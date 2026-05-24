# Brew Windows

Brew Windows is research toward bringing the Homebrew experience to Windows 11
Terminal and PowerShell, natively, without WSL.

## Status

The repository now hosts two design generations in parallel:

- [v1/](v1/) - the PowerShell-native MVP. Fully working `brew install codex`
  flow with a JSON formula catalog, Cellar layout, SHA256-verified downloads,
  and shim-based package linking. Archived after upstream Homebrew maintainer
  feedback ([Homebrew discussion 6860](https://github.com/orgs/Homebrew/discussions/6860))
  established that any upstreamable native Windows path must use bash, Ruby,
  and curl rather than a parallel PowerShell reimplementation.
- [v2/](v2/) - the new architecture. A small Windows-native launcher that
  bootstraps upstream `Homebrew/brew` itself on first run using native Win32
  bash (MinGit) + Ruby (RubyInstaller) + the curl that ships with Windows. The
  user-facing front door stays `brew` in PowerShell; the runtime underneath is
  Homebrew's real codebase.

v1 stays in the tree as evidence and as a reference for the Windows-side
primitives (prefix layout, shims, no-elevation install) that v2 still relies on.

## Background

- Project vision: [BREW_WINDOWS_UPSTREAM_ARCHITECTURE.md](BREW_WINDOWS_UPSTREAM_ARCHITECTURE.md)
- Upstream dossier: [docs/UPSTREAM_DOSSIER.md](docs/UPSTREAM_DOSSIER.md)
- Upstream discussion draft: [docs/UPSTREAM_DISCUSSION_DRAFT.md](docs/UPSTREAM_DISCUSSION_DRAFT.md)
- Upstream maintainer packet: [docs/UPSTREAM_MAINTAINER_PACKET.md](docs/UPSTREAM_MAINTAINER_PACKET.md)
- Proposed upstream PR sequence (pre-feedback): [docs/UPSTREAM_PR_SEQUENCE.md](docs/UPSTREAM_PR_SEQUENCE.md)
- Discussion-first ADR: [docs/adr/0005-upstream-discussion-first.md](docs/adr/0005-upstream-discussion-first.md)

## Non-goals

- Implementing Brew Windows through WSL.
- Wrapping `wsl.exe`.
- Becoming a WinGet, Scoop, Chocolatey, npm, or MSYS2 wrapper.
- Promising official Homebrew Windows support before maintainers accept a
  support model.

## Community

- [CONTRIBUTING.md](CONTRIBUTING.md)
- [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)
- [SECURITY.md](SECURITY.md)
- [SUPPORT.md](SUPPORT.md)

## License

BSD 2-Clause. See [LICENSE](LICENSE).
