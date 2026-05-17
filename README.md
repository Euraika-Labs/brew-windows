# Brew Windows

Brew Windows is an upstream-first research and implementation project for
bringing a high-quality Windows experience to Homebrew without fragmenting the
Homebrew ecosystem.

The long-term goal is to contribute practical, reviewable pull requests to the
real [Homebrew/brew](https://github.com/Homebrew/brew) project. The short-term
goal is to define the architecture, prove the risky Windows-specific pieces in
this repository, and keep the upstream maintenance burden low.

## Vision

Homebrew already provides a strong package-management workflow for macOS, Linux,
and Windows users through WSL. This project explores how to make that Windows
story excellent in two stages:

1. Improve the supported Windows-host path: Windows Terminal, PowerShell, and
   Homebrew on WSL2.
2. Prototype native Windows support in a separate repository before proposing
   any native Windows abstractions upstream.

The project is intentionally not a fork that competes with Homebrew. It is a
staging ground for upstreamable design and implementation work.

## Current Scope

- Architecture for an upstream-friendly Windows strategy.
- PowerShell and Windows Terminal integration patterns.
- A WSL-first user experience that can be proposed upstream early.
- Native Windows experiments for bootstrap, path handling, shims, and bottle
  tags.
- Community process, issue templates, and contribution guidelines.

## Non-goals

- Replacing WinGet, Scoop, or Chocolatey.
- Maintaining a permanent incompatible Homebrew fork.
- Rewriting `homebrew/core` for Windows in one step.
- Promising official Homebrew native Windows support before maintainers accept
  a support model.

## Upstream Strategy

The proposed path is deliberately incremental:

1. Submit documentation and small PowerShell improvements for Windows-hosted WSL
   users.
2. Build a native Windows prototype here, outside Homebrew, with its own CI.
3. Open a Homebrew discussion with working evidence and a narrow support model.
4. Propose small upstream pull requests for platform abstractions only after
   maintainers agree that the slice is reviewable.

The architecture document explains the rationale and phases in detail:

- [BREW_WINDOWS_UPSTREAM_ARCHITECTURE.md](BREW_WINDOWS_UPSTREAM_ARCHITECTURE.md)

## Repository Layout

```text
.
|-- .github/                 GitHub workflows and community templates
|-- BREW_WINDOWS_UPSTREAM_ARCHITECTURE.md
|-- CODE_OF_CONDUCT.md
|-- CONTRIBUTING.md
|-- LICENSE
|-- README.md
|-- SECURITY.md
`-- SUPPORT.md
```

## Development Status

This repository is in the research and architecture phase. Code should be added
only when it advances an upstreamable prototype or validates a specific design
decision.

## Community

Please read:

- [CONTRIBUTING.md](CONTRIBUTING.md)
- [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)
- [SECURITY.md](SECURITY.md)
- [SUPPORT.md](SUPPORT.md)

## License

This project is licensed under the BSD 2-Clause License. See [LICENSE](LICENSE).
