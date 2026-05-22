# Native Windows Brew Maintainer Packet

Last verified: 2026-05-22.

This packet is the short version to share with Homebrew maintainers after the
project has merged Sprint 6 documentation.

## Request

We are not asking Homebrew to accept a native Windows port today.

We are asking whether maintainers would consider a sequence of small,
no-behavior-change abstractions that could make a native Windows experiment
reviewable later while preserving current macOS/Linux behavior.

## Working Prototype

Brew Windows is a native Windows prototype:

- no WSL implementation path;
- no MSYS2 runtime identity;
- no wrapper around WinGet, Scoop, Chocolatey, npm, or `wsl.exe`;
- per-user prefix at `%LOCALAPPDATA%\Homebrew`;
- PowerShell-native installer and runtime;
- Cellar-style package layout;
- checksum-verified package artifacts;
- `.cmd` and `.ps1` shims;
- generic JSON catalog;
- automated catalog sync from Homebrew formula metadata for packages with
  verified Windows release assets.

Public install path:

```powershell
irm https://github.com/Euraika-Labs/brew-windows/releases/latest/download/install.ps1 | iex
brew install codex
codex --version
```

Current release:

- <https://github.com/Euraika-Labs/brew-windows/releases/tag/v0.2.3>

## Evidence Already Available

- Release payload includes SHA256 sidecar.
- GitHub artifact attestation exists for the release payload.
- Windows CI validates Windows PowerShell and PowerShell 7.
- Static checks include PSScriptAnalyzer, actionlint, and zizmor.
- Tests cover checksum failure, prefix paths with spaces, catalog sync, install
  receipts, uninstall behavior, and shim argument/exit-code preservation.
- `brew install codex` installs official OpenAI Windows release assets and
  preserves the native `codex.exe` bundle.

## Upstream Reality We Are Respecting

- Homebrew currently documents macOS, Linux, and WSL 2 usage, not native
  Windows.
- Support tiers currently define Tier 1 for macOS and Linux.
- `Homebrew/brew#14197` was closed with clear maintainer concern about Unix and
  Bash dependencies.
- Existing upstream structure has Bash bootstrap, macOS/Linux OS modules,
  symlink-oriented keg linking, and Mach-O/ELF binary inspection.

## Proposed First Upstream Ask

Would maintainers be open to reviewing one of these small first steps?

1. Document and test the launcher-to-`brew.sh` environment contract.
2. Add an inert Windows host predicate that does not enable support.
3. Extract path-list and executable-resolution helpers while preserving Unix
   behavior.
4. Extract shellenv rendering so PowerShell output can be added narrowly.
5. Extract keg linking behind a strategy interface before any Windows shim work.

The full sequence is in
[docs/UPSTREAM_PR_SEQUENCE.md](UPSTREAM_PR_SEQUENCE.md).

## Non-Goals

- No request for Tier 1 Windows support.
- No official Windows bottles.
- No formula migration.
- No Homebrew installer changes.
- No WSL-based implementation.
- No support promise to end users.

## Questions For Maintainers

- Is native Windows categorically out of scope?
- If not, which no-op abstraction would be least objectionable as a first PR?
- Should any Windows-specific code stay outside `Homebrew/brew` until a separate
  prototype reaches more milestones?
- Would an unsupported or Tier 3 experimental mode be acceptable, or would that
  still create too much maintenance burden?
- Are Windows bottle tags, link strategies, or PowerShell shellenv changes
  considered out of bounds?
