# Native Brew Windows Sprint Plan

This plan turns the native Windows architecture into a working MVP and then an
upstream-ready evidence package.

## Sprint 0: Research Lock

Status: complete for the first implementation pass.

Decisions:

- Native Windows only. WSL is prior art, not an implementation path.
- Default prefix is `%LOCALAPPDATA%\Homebrew`.
- The README install command uses a GitHub Release `install.ps1` asset.
- The first real package is `codex`, installed from official OpenAI GitHub
  release assets.
- The MVP uses a generic JSON catalog so Codex is not hard-coded.

## Sprint 1: Bootstrap

Implemented in this repository:

- `install.ps1` resolves a release payload, verifies SHA256, extracts it, writes
  `install-manifest.json`, and updates the User PATH.
- `bin/brew.cmd` is the stable command front door for restricted PowerShell
  systems.
- `bin/brew.ps1` implements `--version`, `config`, `doctor`, `--prefix`,
  `--cellar`, and `--repository`.
- `uninstall.ps1` removes the prefix and User PATH entry after confirmation.

## Sprint 2: Generic Catalog Core

Implemented in this repository:

- Manifest schema v0 in `schema/manifest.v0.schema.json`.
- Tap discovery from `Library\Taps` and optional `HOMEBREW_TAP_PATHS`.
- Manifest commands: `search`, `info`, `install`, `uninstall`, and `list`.
- SHA256 verification for every downloaded or local package artifact.
- Zip and tar.gz extraction.
- Cellar receipts under `var\homebrew\receipts`.

## Sprint 3: Codex Vertical Slice

Implemented in this repository:

- `Library\Taps\euraika-labs\homebrew-core\Formula\codex.json`.
- x64 and arm64 Windows variants from official `openai/codex` GitHub releases.
- Direct bundle layout preservation for `codex.exe`, command runner, sandbox
  setup, and bundled `rg.exe`.
- Generated `.ps1` and `.cmd` shims.

Validated in public releases:

- `v0.2.1` and later validate the public GitHub Release installer path.
- `brew install codex` installs official OpenAI Windows release assets.
- Codex output matches `^codex-cli\s+\d+\.\d+\.\d+`.

## Sprint 4: Lifecycle

Partially implemented:

- `brew update` is currently a local metadata placeholder.
- `brew upgrade` reinstalls installed packages from the current manifests.

Next:

- Add GitHub release livecheck for Codex.
- Add registry update metadata.
- Add rollback for package upgrades.
- Add cache pruning.

## Sprint 5: Security And CI

Implemented in this repository:

- Windows CI for Windows PowerShell and PowerShell 7.
- Checksum failure test.
- Path-with-spaces test prefix.
- PSScriptAnalyzer error gate.
- JSON manifest parse gate.
- actionlint workflow syntax gate.
- zizmor GitHub Actions security gate.
- SHA256 verification for downloaded CI linter binaries.
- Dependabot for GitHub Actions.
- Dependabot cooldown for GitHub Actions updates.
- Manual release workflow with release payload validation.
- GitHub artifact attestations for release assets.
- Shim argument and exit-code fuzz tests for generated `.ps1` and `.cmd`
  launchers.

Next:

- Add Authenticode checks for future installer-style packages.

## Sprint 6: Upstream Dossier

Implemented in this repository:

- Upstream architecture document.
- Initial upstream dossier with staged PR direction.

Next:

- Attach CI evidence from the first public release.
- Open a Homebrew discussion before proposing code.
- Keep upstream PRs limited to abstractions that preserve macOS and Linux
  behavior.
