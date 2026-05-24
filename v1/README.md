# Brew Windows v1 (Archived)

This directory contains the first design generation of Brew Windows: a
PowerShell-native package manager that implemented the Homebrew mental model
(taps, formulae, Cellar, shims) without WSL or MSYS2.

v1 is **archived**. The runtime, JSON formula catalog, and catalog sync
pipeline are no longer the active design direction. They remain here as:

- evidence of what works natively on Windows without WSL,
- a reference for the Windows-side primitives carried forward into v2
  (prefix layout, shims, no-elevation install, SHA256 verification),
- a working `brew install codex` demo (still runnable from this directory),
- and historical record of the decisions documented in `docs/adr/0001`-`0004`.

## Why It Was Archived

In May 2026 the project opened
[Homebrew discussion 6860](https://github.com/orgs/Homebrew/discussions/6860)
asking maintainers about an upstream path. The substantive feedback was:

- p-linnane: native Windows is firmly out of scope for `Homebrew/brew`.
- MikeMcQuaid: not categorically excluded long-term *if it uses bash + Ruby
  + curl*; complete the external port first; submit small (<500 LOC)
  incremental PRs only after real CI + non-author users exist; extended
  PowerShell support is not the entry path.

A PowerShell-only reimplementation cannot satisfy the bash + Ruby + curl
prerequisite, so the upstream PR sequence v1 was preparing
(`../docs/UPSTREAM_PR_SEQUENCE.md`) was retired. v2 in the sibling `v2/`
directory replaces it with a launcher that bootstraps upstream Homebrew on
first run.

## Still Working

The v1 code still runs end-to-end. To use it from this directory:

```powershell
$env:HOMEBREW_PREFIX = "$env:LOCALAPPDATA\Homebrew-dev"
$env:HOMEBREW_TAP_PATHS = (Resolve-Path .\Library\Taps\euraika-labs\homebrew-core\Formula).Path
.\bin\brew.ps1 --version
.\bin\brew.ps1 doctor
.\bin\brew.ps1 info codex
```

Full validation:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\validate.ps1
```

CI continues to exercise v1 from the v1 paths so the archive does not
silently rot.

## What v2 Reuses

The following v1 decisions are preserved verbatim by v2:

- Per-user prefix at `%LOCALAPPDATA%\Homebrew`. No elevation. No machine
  PATH writes.
- `.cmd` + `.ps1` front-door shims for any installed CLI, so binaries run
  under restricted PowerShell execution policies without modifying machine
  policy.
- SHA256 verification on every downloaded artifact. HTTPS-or-local-only
  URL allowlist.
- `Assert-PathUnderPrefix` style canonicalization checks on destructive
  filesystem operations.
- User PATH management without shell profile edits.
- Windows CI matrix: PowerShell 7 + Windows PowerShell 5.1.
- Shim argument and exit-code fuzz testing (`tests/shim-fuzz.ps1`) - the
  expected behaviour for Homebrew's eventual Windows link strategy.

## v1 Documentation

- `docs/ARCHITECTURE.md` - runtime design.
- `docs/CATALOG_SYNC.md` - Homebrew formula -> Windows manifest pipeline.
- `docs/RELEASE_CHECKLIST.md` - what to verify before publishing a release.
- `docs/SPRINT_PLAN.md` - history of v1's six sprints.
- `docs/THREAT_MODEL.md` - assets, trust boundaries, mitigations.
- `docs/adr/0001`-`0004` - durable v1 decisions (native-only, prefix
  choice, generic catalog, Codex as first formula).
