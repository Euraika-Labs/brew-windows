# Brew Windows

Brew Windows is a native-Windows-first research and prototype project for
bringing Homebrew to Windows as a real Windows package manager experience, not
as a wrapper around WSL.

The long-term goal is to contribute practical, reviewable pull requests to the
real [Homebrew/brew](https://github.com/Homebrew/brew) project. The short-term
goal is to prove the native Windows architecture in this repository: a
PowerShell bootstrap, Windows path handling, executable shims, Windows-aware keg
linking, and eventually Windows bottle support.

## Position

This project is not about simulating Homebrew through WSL.

WSL is an existing workaround for users who want Linux Homebrew on a Windows
machine. It is not the product vision here. Brew Windows targets Windows itself:
PowerShell, Windows Terminal, NTFS, Windows process execution, Windows path
semantics, and native Windows binaries.

## Vision

Homebrew should be able to grow from macOS and Linux into a credible native
Windows developer package manager while preserving the upstream Homebrew model:

- formula-style package definitions;
- a Cellar-style install layout;
- reproducible package metadata;
- safe linking into a user-facing prefix;
- checksum-verified downloads;
- small, reviewable upstream changes.

The native Windows implementation should feel like Homebrew, but it must respect
Windows instead of pretending Windows is Unix.

## Current Scope

- Native `brew.ps1` bootstrap design.
- Windows-native environment and path handling.
- PowerShell and Windows Terminal integration for native Windows.
- Executable shims and junction/link strategy.
- Native Windows package install prototype for portable CLI tools.
- Windows bottle tag and binary-format research.
- Upstream pull request planning for `Homebrew/brew`.

## Non-goals

- Using WSL as the implementation strategy.
- Wrapping `wsl.exe` and calling that native Windows support.
- Replacing WinGet, Scoop, or Chocolatey.
- Maintaining a permanent incompatible Homebrew fork.
- Rewriting `homebrew/core` for Windows in one step.
- Promising official Homebrew native Windows support before Homebrew
  maintainers accept a support model.

## Roadmap

1. Build a native Windows proof in this repository.
2. Implement a PowerShell launcher that can run read-only Homebrew commands.
3. Add native Windows platform detection and path abstractions.
4. Add a Windows shim/link strategy for installed executables.
5. Install and uninstall a small portable CLI package on Windows.
6. Add Windows CI for the prototype.
7. Use the working prototype to open an upstream Homebrew discussion.
8. Propose small upstream pull requests only after the native behavior is proven.

The architecture document explains the design in detail:

- [BREW_WINDOWS_UPSTREAM_ARCHITECTURE.md](BREW_WINDOWS_UPSTREAM_ARCHITECTURE.md)

## Repository Layout

```text
.
|-- .github/                 GitHub community templates
|-- BREW_WINDOWS_UPSTREAM_ARCHITECTURE.md
|-- CODE_OF_CONDUCT.md
|-- CONTRIBUTING.md
|-- LICENSE
|-- README.md
|-- SECURITY.md
`-- SUPPORT.md
```

## Development Status

This repository is in the native Windows architecture and prototype phase. Code
should be added when it validates one of the core native Windows design
decisions: bootstrap, paths, shims, linking, package installation, binary
inspection, or CI.

## Community

Please read:

- [CONTRIBUTING.md](CONTRIBUTING.md)
- [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)
- [SECURITY.md](SECURITY.md)
- [SUPPORT.md](SUPPORT.md)

## License

This project is licensed under the BSD 2-Clause License. See [LICENSE](LICENSE).
