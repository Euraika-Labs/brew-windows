# v2 ADR 0002: Fetch Runtime On First Run

Date: 2026-05-24

## Status

Accepted.

## Context

v2 ADR 0001 commits v2 to running upstream `Homebrew/brew` underneath a
Windows-native launcher. The runtime that the launcher depends on -
MinGit (~50 MB) + RubyInstaller (~30 MB) + a clone of Homebrew/brew
(~50 MB shallow) - totals ~130 MB on disk.

Two distribution shapes are possible:

1. **Bundle**: ship a 130-200 MB release zip containing the runtime.
2. **Bootstrap**: ship a small launcher (~2 MB) in the release zip;
   download the runtime on first use.

Bundling is simpler but contradicts v1 ADR 0002's small-install promise
and produces a release artifact most users will partially redownload on
upgrades. The bootstrap pattern is also what every comparable Windows
developer-tool installer does today: `rustup`, `mise`, `pyenv-win`,
`volta`, and `nvm-windows` all ship small front doors that fetch their
real runtimes on first use.

## Decision

The Brew Windows v2 release zip contains only the launcher
(`brew.cmd`, `brew.ps1`, `install.ps1`, `uninstall.ps1`,
`runtime-manifest.json`, and minimal docs).

The launcher fetches the rest:

- `Install-Runtime` is called eagerly by `install.ps1` as its last
  step. The user sees one progress indicator: "Downloading Homebrew
  runtime, ~130 MB, one-time download...".
- `Install-Runtime` is also called lazily by `brew.ps1` if it detects
  that `runtime/` is missing or that any component's checksum doesn't
  match `runtime-manifest.json`. This is the safety net for users who
  copy the prefix between machines, delete `runtime/` manually, or
  install from the release zip without running `install.ps1`.

Every component download is HTTPS, pinned to a specific version, and
SHA256-verified against `runtime-manifest.json`. `runtime-manifest.json`
itself is in the release zip and is covered by the release artifact
attestation.

## Consequences

- The release zip stays small. Target: under 2 MB.
- First-run requires network. Offline-only environments need a separate
  documented path (download the runtime archive once on a connected
  machine, drop it into `runtime/` manually, run `brew --version` once
  to verify checksums). This path is not optimized.
- Bumping any component version is a launcher release, not a runtime
  release. `runtime-manifest.json` gets updated; users get the new
  runtime on next launcher upgrade (mechanism for that to be designed
  in Phase 4).
- Eager + lazy duplication is intentional. Eager gives the user a
  predictable one-time wait. Lazy survives weird states (prefix copy,
  manual cleanup, partial install).
- The threat model gains a new boundary: the runtime downloads. Pinned
  HTTPS URLs + SHA256 verification + release attestation on
  `runtime-manifest.json` close that boundary the same way v1 closed
  package artifact downloads.

## Rejected Alternative: Bundle Everything

Considered, rejected. Reasons:

- Contradicts v1 ADR 0002's intent (small per-user install).
- Release zip becomes ~150 MB+, awkward to attest, awkward to download
  from `irm | iex`.
- Upgrades re-download the entire bundle. The bootstrap model
  re-downloads only the changed component.
- Out of step with comparable Windows tooling (rustup et al), which
  primes users to expect first-run downloads.

## Rejected Alternative: Require Pre-Installed Git For Windows + Ruby

Considered, rejected. Reasons:

- Adds prerequisite friction. `irm install.ps1 | iex` no longer "just
  works".
- Removes our control over the exact bash + Ruby versions. The
  bootstrap pattern pins precise versions; relying on the user's
  installation cannot.
- Doesn't actually save much. The bootstrap pattern downloads MinGit
  (~50 MB) which is roughly the same size as a full Git for Windows.
