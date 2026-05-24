# Brew Windows v2 Phase Plan

Implementation is staged in five phases. Each phase produces something
demonstrable and verifiable, and each one is exit-criteria gated.

The phase plan is calibrated to MikeMcQuaid's feedback in
[discussion 6860](https://github.com/orgs/Homebrew/discussions/6860):

> Complete the full Windows port independently first, then submit
> small (<500 line) incremental PRs ... actual CI, binary packages,
> and non-author users are required.

Phase 5 is the upstream-PR phase. Phases 1-4 produce what MikeMcQuaid
asked for before Phase 5 is appropriate.

## Current Status (2026-05-24)

| Phase | Status |
| --- | --- |
| Phase 1 - Launcher + Bootstrap Proof | **Complete** |
| Phase 2 - Doctor Parity + Diagnostics | **Complete** |
| Phase 3 - First Formula Install | **Complete** |
| Phase 4 - Non-Author Users + CI Maturity | Not started |
| Phase 5 - Upstream PR Sequence | Not started |

Phase 3's exit criterion is met against the test prefix on this PC:
`brew install euraika-labs/windows/ripgrep` produces a working
`rg --version` from a generated `.cmd` + `.ps1` shim pair, and
`brew uninstall` reverses cleanly. Phase 3 required nine new patches
beyond the originally planned `windows-link-strategy.patch`; see
[`launcher/patches/`](../launcher/patches/) for the inventory and
each patch's own header for the rationale.

## Phase 1: Launcher + Bootstrap Proof

**Goal:** From a clean Windows 11 box, `irm install.ps1 | iex` produces
a working `brew --version` in a fresh PowerShell window.

**Deliverables:**

- `v2/launcher/bin/brew.cmd`
- `v2/launcher/bin/brew.ps1` (~250 lines including `Install-Runtime`)
- `v2/launcher/install.ps1`
- `v2/launcher/uninstall.ps1`
- `v2/launcher/runtime-manifest.json` pinning the first MinGit,
  RubyInstaller, and Homebrew versions
- `v2/launcher/patches/windows-os-detection.patch`
- `v2/scripts/build-release.ps1` (analogous to v1's, but smaller payload)
- `v2/scripts/validate.ps1`
- `v2/tests/install-runtime.ps1` - exercises bootstrap end-to-end
- `v2/tests/launcher-smoke.ps1` - launcher entry + exit code paths

**Exit criteria:**

1. On a clean `windows-latest` GitHub runner:
   - `install.ps1` completes in under 5 minutes including the
     ~130 MB runtime download.
   - `brew --version` exits 0 and prints a Homebrew version string.
   - `brew help` returns upstream Homebrew's help text.
2. `Install-Runtime` aborts cleanly on:
   - Network failure (CI inserts a bad URL).
   - SHA256 mismatch (CI corrupts a downloaded archive).
   - Missing patch file.
3. Lazy bootstrap works: delete `runtime/`, run `brew --version`,
   bootstrap re-runs, command succeeds.
4. Hash-drift detection works: corrupt a runtime file, run `brew
   --version`, runtime is re-installed.

**Risks:**

- MinGit's bash may be missing utilities Homebrew's `brew.sh` needs.
  Mitigation: a small probe step in Phase 1 lists every external
  command `brew.sh` invokes and verifies presence in MinGit.
- RubyInstaller's 7z archive may be awkward to extract. Mitigation:
  documented fallback path (system `tar.exe`, then bundled 7z).
- Upstream Homebrew's `brew.sh` may have a path it cannot handle on
  Windows. Mitigation: scope the patch in
  `windows-os-detection.patch` to the minimum needed, document each
  workaround.

**Estimated effort:** 1-2 weeks of focused work.

## Phase 2: Doctor Parity And Diagnostics

**Goal:** `brew config`, `brew doctor`, `brew --prefix`, `brew
--cellar`, `brew --repository`, `brew shellenv` all work via upstream
code and produce Windows-meaningful output.

**Deliverables:**

- Windows-aware checks added to `brew doctor` (long-path policy,
  execution policy, antivirus locking probes, PATH conflicts).
- Implementation: a Phase 2 patch that extends
  `Library/Homebrew/diagnostic.rb` with `OS.windows?` checks.
- `brew shellenv pwsh` validated against the v2 prefix.
- v2 CI matrix expanded:
  - PowerShell 7 + Windows PowerShell 5.1 (v1 parity)
  - clean install
  - upgrade-from-Phase-1
  - corrupted-runtime recovery

**Exit criteria:**

1. `brew config` prints Windows system information correctly:
   `HOMEBREW_PREFIX`, `HOMEBREW_CELLAR`, OS version, processor,
   Ruby version, git version.
2. `brew doctor` reports a clean machine on a fresh CI runner.
3. `brew doctor` correctly warns on a deliberately-broken machine:
   missing `<prefix>\bin` from PATH, shadowed `brew.cmd`, restricted
   execution policy, missing long-path policy.
4. `brew shellenv pwsh` output is identical to upstream's pwsh output
   for an equivalent prefix.

**Risks:**

- Upstream's `diagnostic.rb` may be tightly coupled to macOS/Linux
  assumptions. Mitigation: extend, do not rewrite. Each Windows check
  is an additive method.
- Long-path policy detection requires reading a specific registry
  key. PowerShell sidecar function reachable from Ruby via
  `system('powershell.exe ...')` if needed.

**Estimated effort:** 1 week.

## Phase 3: First Formula Install

**Goal:** `brew install codex` installs the official OpenAI Windows
release bundle, `codex --version` works from a new PowerShell window,
`brew uninstall codex` cleans up.

**Deliverables:**

- `v2/launcher/patches/windows-link-strategy.patch` -
  ~150 line patch implementing the `.cmd` + `.ps1` shim link
  strategy. See [LINK_STRATEGY.md](LINK_STRATEGY.md).
- A Codex formula written in Ruby targeting a Windows-only tap
  (`Euraika-Labs/homebrew-windows`). The formula uses the same
  upstream OpenAI release URLs and SHA256s that v1's
  `codex.json` used.
- A second formula chosen for variety (probably `ripgrep` because
  it's the cleanest Windows portable archive).
- `brew install`, `brew list`, `brew uninstall` smoke tests in CI.
- Argument fuzz tests ported from v1's `shim-fuzz.ps1`, run against
  shims that the patched Homebrew produces.

**Exit criteria:**

1. `brew install codex` works end to end:
   - Download Windows archive from OpenAI's GitHub release.
   - SHA256 verify.
   - Extract to `Cellar/codex/<ver>/`.
   - Generate `<prefix>\bin\codex.cmd` and `<prefix>\bin\codex.ps1`.
   - Receipt written to `var/homebrew/receipts/codex.json`.
2. `codex --version` works from a new PowerShell window.
3. `brew uninstall codex` removes shims and the Cellar entry.
4. `shim-fuzz` tests pass against the generated shims.
5. `brew install ripgrep` works (same flow with a different formula).

**Risks:**

- Upstream's tap loading may have macOS/Linux assumptions that affect
  our Windows-only tap. Mitigation: a Windows-only tap is just a git
  repo; Phase 3 surfaces any quirks early.
- Homebrew's keg-link conflict detection may behave unexpectedly with
  shims. Mitigation: tests cover the conflict path explicitly
  (existing `gh.cmd` from outside brew should make `brew install gh`
  fail with a clear message).
- The Codex formula uses an `npm`-packaged tgz with multiple
  binaries that need to be placed in specific locations. v1's
  `install.files` mapping handled that. Phase 3 verifies upstream's
  Ruby formula DSL has equivalent expressiveness (resources or
  layered `install` blocks).

**Estimated effort:** 2-3 weeks.

## Phase 4: Non-Author Users + CI Maturity

**Goal:** v2 is something a non-author user can install and use to
do real work. CI exercises every code path. Public documentation
exists.

**Deliverables:**

- v2 release pipeline (analogous to v1's `release.yml`):
  - Builds the launcher zip.
  - SHA256 + attestation.
  - GitHub Release with `install.ps1` and the launcher zip.
- Public install URL working: `irm https://github.com/Euraika-Labs/brew-windows/releases/latest/download/install.ps1 | iex`.
- User guide: `v2/docs/USER_GUIDE.md` documenting install, common
  commands, troubleshooting.
- Contributor guide: `v2/docs/CONTRIBUTOR_GUIDE.md` documenting
  development setup, how to add a patch, how to run tests locally.
- At least three non-author users have completed a `brew install`
  cycle and reported back. Issues opened, fixed, closed.
- A small Windows-only tap (`Euraika-Labs/homebrew-windows`)
  publicly available with 3-5 working formulae.
- CI exercises:
  - install
  - install with restricted execution policy
  - install on path-with-spaces
  - install + uninstall + reinstall cycle
  - upgrade across launcher versions
  - simulated MITM (bad SHA256) abort behavior
  - simulated upstream history rewrite abort behavior

**Exit criteria:**

1. Three or more non-author users have publicly confirmed working
   installs.
2. CI matrix is green for all defined cases.
3. Public release v2.0.0 with attested artifacts.
4. User guide and contributor guide are written.
5. Documented `brew-windows-update` flow (or equivalent) exists for
   bumping the runtime pin without re-running `install.ps1`.

**Risks:**

- Finding three non-author Windows users with the patience to run a
  prototype is the real bottleneck. Mitigation: a small write-up
  about v2 to the same Homebrew discussion thread as a follow-up;
  Windows developer subreddits as channels.
- A formula in the Windows-only tap may break on a future launcher
  release. Mitigation: CI tests run against the tap on every
  launcher-source change.

**Estimated effort:** 4-6 weeks calendar (because non-author users
take wall-clock time to recruit and respond).

## Phase 5: Upstream PR Sequence (Revised)

**Goal:** Begin the upstream conversation MikeMcQuaid sketched, now
backed by real evidence from Phase 1-4. Submit small, focused PRs
against `Homebrew/brew`.

This phase replaces the originally-proposed sequence in
`docs/UPSTREAM_PR_SEQUENCE.md`. The new sequence is shorter and
respects MikeMcQuaid's <500 LOC target.

**Proposed PRs in order:**

1. **`OS.windows?` predicate.** ~30 lines. Inert: returns
   false on macOS and Linux, makes the host detectable on Windows.
   No code path changes. Tests verify macOS/Linux predicates are
   unchanged.
2. **`Library/Homebrew/extend/os/windows/` directory.** Adds the
   directory and a minimum-viable extension module that exists but
   does nothing yet. ~20 lines. Establishes the extension point.
3. **Keg link strategy extraction.** Moves the existing symlink
   logic into a default `PosixSymlinkStrategy` class. No behavior
   change. ~150 lines including tests. Useful on macOS/Linux too:
   makes the link step easier to read and test.
4. **Windows shim link strategy.** Uses the hook from PR 3. Guarded
   by `OS.windows?`. Behind an explicit experimental flag initially.
   ~150 lines. This is the patch we have been maintaining locally
   since Phase 3.

PRs 1-3 are useful even if Windows support never lands. They clarify
upstream code, add tests, and are independently mergeable. PR 4 is
the actual Windows enablement.

**Exit criteria:**

1. PR 1 merged or has explicit maintainer feedback documenting
   why not.
2. PR 2 merged or explicit feedback.
3. PR 3 merged or explicit feedback.
4. PR 4 has a maintainer response (merged, deferred to experimental
   tier, or explicit rejection).

**Risks:**

- Maintainer position changes at any step. The v2 architecture must
  not require any of these PRs to merge - v2 already works as an
  external project.
- A maintainer review surfaces a structural issue with our patch
  approach. Mitigation: maintain dialog, iterate the patches in
  response.

**Estimated effort:** Months calendar time. PR review cycles dominate.

## Stop Conditions

Stop and reassess if:

- Maintainers explicitly say PR 1 (`OS.windows?` predicate) is not
  acceptable. This signals the upstream path is closed even for
  inert abstractions.
- A Phase 1-3 blocker proves the bash + Ruby + curl prerequisite
  cannot be met in practice on Windows (e.g., MinGit's bash is
  insufficient for Homebrew's bootstrap and no alternative exists).
  v2 may need to retreat to a smaller goal or accept independence.
- A critical security finding in MinGit or RubyInstaller that we
  cannot pin around. Mitigation already in design: we pin specific
  versions, so a known-bad version is just a pin bump.

If a stop condition triggers, v2 continues as an external project
without the upstream-merge goal.

## What Does Not Happen In Phase 1-4

Deferred until after Phase 5 outcomes are known:

- Windows bottle tags. Source-build is the Windows default during
  Phase 1-4.
- PE/COFF binary inspection and DLL dependency scanning.
- Authenticode signature verification for downloaded `.exe` files.
- A `homebrew/core` Windows enablement campaign.
- A Windows-aware formula DSL (`on_windows do ... end`). If needed,
  this is post-Phase 5 work.
- MSI / EXE installer support.
- GUI app (Cask-style) support on Windows.

These are documented as "later" in the original
`BREW_WINDOWS_UPSTREAM_ARCHITECTURE.md` and remain deferred.
