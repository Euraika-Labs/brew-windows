# Brew Windows v2 Threat Model

v2 inherits v1's threat model (`v1/docs/THREAT_MODEL.md`) and adds new
trust boundaries that come from bootstrapping upstream Homebrew and
its dependencies.

## Assets

- User PATH and current shell environment.
- `%LOCALAPPDATA%\Homebrew` prefix:
  - `bin/` (User PATH entry).
  - `Cellar/` (installed package payloads).
  - `runtime/` (vendored bash + Ruby + Homebrew clone).
  - `install-manifest.json` and `runtime/pins.json` (integrity ledgers).
- Downloaded archives in `Cache/`.
- The launcher's release zip and SHA256 sidecar.

## Trust Boundaries

| Boundary | What crosses it | Mitigation |
| --- | --- | --- |
| The user's machine vs the launcher's release | GitHub Release zip downloaded by `install.ps1` | Pinned URL, SHA256 verification, GitHub artifact attestation. |
| The launcher vs MinGit | `MinGit-X.Y.Z-64-bit.zip` from `git-for-windows/git` releases | SHA256 pinned in `runtime-manifest.json`. URL constrained to `github.com`. |
| The launcher vs RubyInstaller | `rubyinstaller-X.Y.Z-N-x64.7z` from `oneclick/rubyinstaller2` releases | SHA256 pinned in `runtime-manifest.json`. URL constrained to `github.com`. |
| The launcher vs upstream Homebrew | Shallow git clone of `Homebrew/brew` at a specific commit SHA | Commit SHA pinned (not a branch). Working tree SHA256 verified after checkout. |
| The launcher vs v2 patches | Patches in `v2/patches/` shipped in the release zip | SHA256 pinned per patch in `runtime-manifest.json`. |
| Upstream Homebrew vs formula registries | curl downloads of formula source/bottle archives | Inherits upstream Homebrew's own SHA256 verification per formula. |
| Upstream Homebrew vs taps | git clones of tap repositories | Inherits upstream Homebrew's behavior. Each tap is the user's explicit `brew tap` decision. |
| The user's shell vs installed binaries | Generated shims under `<prefix>\bin\` | Shim generation refuses to overwrite non-brew files. `Assert-PathUnderPrefix` style guards before any destructive write. |

## Primary Threats

### T1: Remote artifact substitution at install time

An attacker MITMs the install pipeline and substitutes a malicious
launcher, MinGit, RubyInstaller, or Homebrew clone.

**Mitigations:**
- HTTPS only. The launcher refuses `http://` URLs.
- SHA256 pinned in `runtime-manifest.json` for every download.
- The launcher zip itself has a SHA256 sidecar and GitHub artifact
  attestation.
- The Homebrew clone is pinned to a specific commit SHA, not a branch.

**Residual risk:** if an attacker compromises both our release pipeline
(to produce a malicious launcher zip with a matching SHA256 sidecar)
AND the GitHub attestation system, install can be subverted. This is
the same residual risk every signed-installer model has.

### T2: Hash mismatch silently ignored

A bug in the launcher fails to abort on SHA256 mismatch and proceeds
to install a tampered runtime.

**Mitigations:**
- `Install-Runtime` throws on hash mismatch and does not catch it
  except to clean up staging directories.
- CI exercises the failure path (corrupt a component archive, confirm
  `Install-Runtime` aborts).
- The launcher writes `runtime/pins.json` only after all components
  install successfully, so a partial-then-killed install leaves
  `runtime/pins.json` absent and is detected as "not ready" on next
  `brew` invocation.

### T3: PATH hijacking or command shadowing

An attacker plants a malicious `brew.cmd` earlier in PATH so the user
runs attacker code instead of our launcher.

**Mitigations:**
- `brew doctor` (Phase 2) checks that `brew.cmd` and `brew.ps1`
  resolve to the prefix and warns if shadowed.
- Same check for every receipt-tracked shim. If `gh.cmd` resolves to
  something other than `<prefix>\bin\gh.cmd`, doctor warns.
- v1's command-shadow check (`v1/bin/brew.ps1` line ~660) is the
  reference behavior. Port to the new doctor.

### T4: Shim argument parsing bug

A user invokes a brew-installed CLI with crafted arguments and the
shim mis-parses them, leading to argument injection or quote
stripping.

**Mitigations:**
- The Windows link strategy patch ([LINK_STRATEGY.md](LINK_STRATEGY.md))
  must pass v1's full `shim-fuzz.ps1` test suite. Those tests are
  preserved and re-run in v2 CI.
- Shim format is fixed and minimal. No interpolation of user input
  into the shim body.

### T5: Accidental elevation or machine-wide mutation

The launcher attempts a write that requires admin rights and either
fails or prompts UAC.

**Mitigations:**
- Default prefix `%LOCALAPPDATA%\Homebrew` is user-writable.
- `install.ps1` writes only to User PATH, never Machine PATH.
- The launcher does not create symlinks (would otherwise require
  `SeCreateSymbolicLink` or Developer Mode).
- All `Install-Runtime` writes are inside the prefix.

### T6: Prefix deletion outside the expected install root

A bug causes `uninstall.ps1` or a shim-cleanup path to remove a
directory other than the prefix.

**Mitigations:**
- `Assert-PathUnderPrefix` style canonicalization on every destructive
  write. Refuses to operate on paths that do not canonicalize to a
  child of `HOMEBREW_PREFIX`.
- `uninstall.ps1` additionally requires either `install-manifest.json`
  or `runtime/` to exist in the target directory before agreeing to
  remove it.

### T7: Compromised CI workflow permissions

An attacker exploits an over-broad CI permission to publish a
malicious release.

**Mitigations:**
- `.github/workflows/*.yml` use `permissions: contents: read` by
  default.
- `actions/checkout` uses `persist-credentials: false`.
- Release workflow is `workflow_dispatch` only (manual trigger by a
  maintainer).
- Release workflow writes `contents: write`, `id-token: write`,
  `attestations: write` only when actually publishing a release.
- Pinned action SHAs (we already pin `actions/checkout` and
  `actions/attest`).

### T8: Upstream Homebrew history rewrite

The pinned commit SHA disappears from the upstream `Homebrew/brew`
repository (force-push, branch deletion, repo transfer).

**Mitigations:**
- `Install-Runtime` checks both the commit SHA and a working-tree
  SHA256 (`components.homebrew.expectedTreeId`). If the commit
  resolves but the tree contents have changed, the install aborts.
- If the commit SHA does not exist anymore, the install aborts with
  a clear error.
- A new launcher release with a new pinned commit is the path
  forward.

### T9: Malicious patch in v2/patches/

An attacker substitutes a patch file in the release zip to inject
code into the Homebrew clone.

**Mitigations:**
- Each patch has a SHA256 pinned in `runtime-manifest.json`.
- `runtime-manifest.json` is part of the release zip and is covered
  by the release artifact attestation.
- The launcher refuses to apply a patch whose SHA256 does not match.

### T10: User-installed formula with malicious post-install behavior

The user installs a formula that exploits Homebrew's `install`
machinery to run arbitrary code as the current user.

**Mitigations:**
- This is upstream Homebrew's threat model. v2 inherits it without
  amendment. Per-user prefix means the blast radius is the user's
  account, not the machine.
- Default tap policy is "no taps installed" ([ADR 0007](adr/0007-windows-only-tap-first.md)).
  Users opt in explicitly.

## Compared To v1

v1 owned the entire install pipeline directly: JSON manifest -> URL
+ SHA256 -> download -> extract -> shim. The threat surface was
narrow.

v2 delegates to upstream Homebrew. New surface:

- Trust in upstream Homebrew's own install machinery (already widely
  audited).
- Trust in MinGit / RubyInstaller release signatures (mitigated by
  SHA256 pinning at the launcher level).
- Trust in the upstream `Homebrew/brew` git history (mitigated by
  commit-SHA + working-tree-hash pinning).

What's no longer in our threat surface:

- Manifest schema vulnerabilities (we no longer have one).
- Catalog sync pipeline vulnerabilities (retired).
- Per-formula download URL allowlist (delegated to upstream).
- Per-formula install scripting bugs (delegated to upstream).

Net: smaller code we maintain, slightly broader trust set we depend on,
all pinned by SHA256.

## Required Before First Public v2 Release

- `Install-Runtime` failure-path CI test (corrupt archive -> abort).
- `Assert-PathUnderPrefix` style guard on every write in the launcher.
- v1's `shim-fuzz.ps1` ported to v2 testing of the link-strategy patch.
- GitHub artifact attestation on the v2 release zip and
  `runtime-manifest.json`.
- A short "What v2 sends over the network" appendix in the user-facing
  install documentation (URLs, sizes).

## Audit Trail

- Every `Install-Runtime` writes a structured log line to
  `<prefix>/Logs/install-runtime.log` per component, recording:
  source URL, downloaded SHA256, install timestamp, success/failure.
- Every shim is generated with a fixed marker (`Generated by Brew
  Windows`) so doctor can distinguish brew-managed from user-placed
  files.
