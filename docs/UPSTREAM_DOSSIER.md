# Homebrew Upstream Dossier

This repository should not send one large "Windows support" pull request to
Homebrew. The credible path is a sequence of narrow, evidence-backed changes.

## Current Evidence

- Native Windows prefix at `%LOCALAPPDATA%\Homebrew`.
- PowerShell bootstrap without WSL or Bash.
- Generic package metadata and Cellar-style install layout.
- Windows shims instead of privileged symlinks.
- Codex formula based on official OpenAI Windows release assets.
- Windows CI for the prototype.

## Known Upstream Gaps

- `Homebrew/brew` bootstrap is Bash-first.
- The upstream OS model currently centers macOS and Linux.
- Several install/test paths rely on `fork`, Unix sockets, symlinks, and
  Mach-O/ELF assumptions.
- Bottle tags and binary inspection need PE/COFF and DLL support.

## Proposed Discussion Topics

- Whether native Windows belongs in Homebrew's support model.
- Which support tier could apply to an experimental Windows port.
- Whether a PowerShell launcher can prepare the same environment contract as
  the current Bash launcher.
- Which abstractions can be merged without changing macOS/Linux behavior.

## Proposed PR Sequence

1. Refactor launcher assumptions while preserving existing behavior.
2. Add inert Windows OS detection and tests.
3. Add shared path-list and executable-resolution helpers.
4. Add native PowerShell shellenv support.
5. Add link strategy abstraction.
6. Add experimental Windows shim strategy.
7. Add Windows bottle tags only after install semantics are proven.
