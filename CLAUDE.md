# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Project Is

Brew Windows is research toward a native Windows port of Homebrew. The repository
now hosts two design generations:

- **`v1/`** - the original PowerShell-native MVP. Working `brew install codex`
  pipeline with a JSON formula catalog, Cellar layout, SHA256-verified
  downloads, and shim-based linking. Archived after Homebrew maintainer
  feedback ([discussion 6860](https://github.com/orgs/Homebrew/discussions/6860))
  established that any upstreamable native Windows path must use bash + Ruby
  + curl, not a parallel PowerShell reimplementation. See `v1/README.md` and
  `v1/docs/`.

- **`v2/`** - the current design generation (in progress). A small
  Windows-native launcher (`brew.cmd` + `brew.ps1`) that bootstraps upstream
  `Homebrew/brew` itself on first run using native Win32 bash (MinGit) +
  Ruby (RubyInstaller) + the system curl that ships with Windows 10+. The
  user-facing front door stays `brew` in PowerShell; the runtime underneath
  is Homebrew's real Ruby/bash codebase. See `v2/README.md` and
  `v2/docs/ARCHITECTURE.md`.

The Windows-side primitives v1 proved (per-user `%LOCALAPPDATA%\Homebrew`
prefix, `.ps1` + `.cmd` shims for restricted-execution-policy environments,
no-elevation install, SHA256-everything, PATH management without profile
edits) carry forward into v2's design unchanged.

## Determining Which Generation You're Working In

- If the user mentions formula JSON, catalog sync, `sync-homebrew-catalog.ps1`,
  `brew.ps1` dispatch logic, `Install-Formula`, or anything about the manifest
  schema - that's v1 (`v1/`). v1 is archived; only touch it for bug fixes,
  documentation corrections, or historical research.
- If the user mentions the bootstrap launcher, MinGit, RubyInstaller, fetching
  upstream Homebrew, or the new architecture - that's v2 (`v2/`).
- If unclear, ask which generation. Don't reflexively edit v1.

## Project-Level Documents (Apply to Both Generations)

- `BREW_WINDOWS_UPSTREAM_ARCHITECTURE.md` - long-form vision document.
- `docs/UPSTREAM_DOSSIER.md` - upstream Homebrew evidence package and reality
  check.
- `docs/UPSTREAM_DISCUSSION_DRAFT.md` - the draft that became discussion 6860.
- `docs/UPSTREAM_MAINTAINER_PACKET.md` - condensed packet for maintainers.
- `docs/UPSTREAM_PR_SEQUENCE.md` - the originally proposed PR sequence
  (largely superseded by maintainer feedback, but retained as record).
- `docs/adr/0005-upstream-discussion-first.md` - durable decision to discuss
  before opening upstream PRs.

## v1 Quick Reference (Archived)

v1 has its own CLAUDE-style notes in `v1/docs/ARCHITECTURE.md`. The key
v1 commands all moved under `v1/`:

```powershell
# Run v1 against an in-tree prefix
$env:HOMEBREW_PREFIX = "$env:LOCALAPPDATA\Homebrew-dev"
$env:HOMEBREW_TAP_PATHS = (Resolve-Path .\v1\Library\Taps\euraika-labs\homebrew-core\Formula).Path
.\v1\bin\brew.ps1 --version

# Full v1 validation
powershell -NoProfile -ExecutionPolicy Bypass -File .\v1\scripts\validate.ps1
```

v1 design tour: `v1/docs/ARCHITECTURE.md`. v1 ADRs (native-only, prefix,
catalog, Codex source): `v1/docs/adr/0001`-`0004`.

## v2 (Current)

v2 design lives in `v2/docs/ARCHITECTURE.md`. v2 ADRs live in `v2/docs/adr/`
and renumber from 0001 - they are about v2's choices, not extensions of v1's
ADRs. v2 ADR 0001 explicitly supersedes v1 ADR 0001 (the "native-only"
position is preserved but clarified to allow vendoring native Win32 binaries
the user never types into).

## Conventions (Apply Everywhere)

- **PowerShell style**: `Set-StrictMode -Version 2.0` + `$ErrorActionPreference = "Stop"` at the top of every script. Use `-LiteralPath` for filesystem operations - paths can contain `[`, `]`, spaces, etc.
- **No emojis** anywhere in code, docs, or commit messages (matches upstream Homebrew style).
- **ASCII-only** for `Write-Host` / log output. Some downstream consumers run under Windows PowerShell 5.1 which mishandles UTF-8 without BOM.
- **Conventional commits**: `feat:`, `fix:`, `docs:`, `chore:`, `test:`, `refactor:`. See the parent workspace `CLAUDE.md` (`../CLAUDE.md`).
- **Don't copy code from `upstream-brew/`** - that directory is a read-only checkout of `Homebrew/brew` for reference. v2 will *invoke* upstream Homebrew at runtime, never embed its source.

## CI & Quality Gates

`.github/workflows/ci.yml` currently runs v1's validation under PowerShell 7
and Windows PowerShell 5.1, plus PSScriptAnalyzer at Error severity over v1's
PowerShell sources, plus JSON parsing, actionlint, and zizmor. v2 will add
its own jobs to the same workflow once it has executable code.

CI runs with `permissions: contents: read` and `actions/checkout` uses
`persist-credentials: false`. Don't relax these defaults without a threat
model update.
