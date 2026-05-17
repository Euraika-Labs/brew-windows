# Brew Windows

Brew Windows is a native Windows prototype for bringing the Homebrew experience
to Windows 11 Terminal and PowerShell.

It is not a WSL wrapper, not an MSYS2 shortcut, and not a fake alias around
another package manager. The default install is per-user at:

```text
%LOCALAPPDATA%\Homebrew
```

## Target Experience

The intended public install path is:

```powershell
irm https://github.com/Euraika-Labs/brew-windows/releases/latest/download/install.ps1 | iex
brew install codex
codex --version
```

The current repository implements the first native MVP:

- PowerShell-native `brew` runtime.
- Generic JSON formula catalog.
- Cellar-style package layout.
- SHA256-verified package downloads.
- `.ps1` and `.cmd` executable shims.
- A real `codex` formula using official OpenAI Windows release assets.
- Windows CI for PowerShell 7 and Windows PowerShell.

## Status

This is experimental research and prototype code. Do not treat it as official
Homebrew support for Windows.

The long-term goal is to use this repository as evidence for small, reviewable
upstream discussions and pull requests against
[Homebrew/brew](https://github.com/Homebrew/brew).

## Install From Source

Until a release is published, run the prototype from a local checkout:

```powershell
$env:HOMEBREW_PREFIX = "$env:LOCALAPPDATA\Homebrew-dev"
$env:HOMEBREW_TAP_PATHS = (Resolve-Path .\Library\Taps\euraika-labs\homebrew-core\Formula).Path
.\bin\brew.ps1 --version
.\bin\brew.ps1 doctor
.\bin\brew.ps1 info codex
```

To build the release payload that `install.ps1` expects:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-release.ps1 -Version 0.1.0
```

The release should upload both:

- `install.ps1`
- `dist\brew-windows-0.1.0.zip`

## Commands

```powershell
brew --version
brew config
brew doctor
brew search codex
brew info codex
brew install codex
brew list
brew upgrade codex
brew uninstall codex
brew self-uninstall
```

Most read commands support `--json`:

```powershell
brew --json config
brew --json doctor
brew --json info codex
```

## Manifest Model

Formulae are JSON files under:

```text
Library\Taps\<owner>\<tap>\Formula\<name>.json
```

The manifest schema is documented in:

- [schema/manifest.v0.schema.json](schema/manifest.v0.schema.json)

The first real formula is:

- [Library/Taps/euraika-labs/homebrew-core/Formula/codex.json](Library/Taps/euraika-labs/homebrew-core/Formula/codex.json)

Codex is installed from OpenAI GitHub release bundles, not by shelling out to
`npm install -g`.

## Repository Layout

```text
.
|-- bin\                         brew.cmd and brew.ps1
|-- docs\                        architecture, ADRs, sprint plan, threat model
|-- Library\Taps\                built-in formula catalog
|-- schema\                      manifest schema
|-- scripts\                     validation and release payload tooling
|-- tests\                       native Windows smoke tests
|-- install.ps1                  release installer entrypoint
`-- uninstall.ps1                prefix uninstaller
```

## Validate

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\validate.ps1
```

## Roadmap

The sprint plan is tracked in:

- [docs/SPRINT_PLAN.md](docs/SPRINT_PLAN.md)

The upstream strategy is tracked in:

- [BREW_WINDOWS_UPSTREAM_ARCHITECTURE.md](BREW_WINDOWS_UPSTREAM_ARCHITECTURE.md)
- [docs/UPSTREAM_DOSSIER.md](docs/UPSTREAM_DOSSIER.md)

## Non-goals

- Implementing Brew Windows through WSL.
- Wrapping `wsl.exe`.
- Becoming a WinGet, Scoop, Chocolatey, npm, or MSYS2 wrapper.
- Promising official Homebrew Windows support before maintainers accept a
  support model.

## Community

Please read:

- [CONTRIBUTING.md](CONTRIBUTING.md)
- [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)
- [SECURITY.md](SECURITY.md)
- [SUPPORT.md](SUPPORT.md)

## License

This project is licensed under the BSD 2-Clause License. See [LICENSE](LICENSE).
