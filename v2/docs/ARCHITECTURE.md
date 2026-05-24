# Brew Windows v2 Architecture

Date: 2026-05-24
Status: Design draft. No executable code yet.

This is the master architecture document. It states v2's goals, shape,
and high-level decisions, then points to the detail documents for each
subsystem.

## Goals

- Run `brew install <name>` from PowerShell or Windows Terminal on a
  stock Windows 11 machine that has never heard of WSL or MSYS2.
- Use upstream `Homebrew/brew`'s real bash + Ruby code as the runtime,
  unmodified where possible, patched narrowly where Windows requires it.
- Keep the release zip small (target: under 2 MB). Fetch the real
  runtime on first use.
- Preserve every Windows-side primitive v1 proved: per-user prefix,
  no-elevation install, `.cmd` + `.ps1` shims, SHA256-everything, no
  shell-profile edits.
- Stay on a credible long-term path toward small, reviewable upstream
  PRs against `Homebrew/brew`. v2 is calibrated to MikeMcQuaid's
  feedback in [discussion 6860](https://github.com/orgs/Homebrew/discussions/6860).
  See [COMPLIANCE.md](COMPLIANCE.md) for the exact mapping.

## Non-Goals

- WSL bridge, WSL-aware install, or any reliance on `wsl.exe`.
- MSYS2 as the user's runtime identity. Vendoring a native Win32 bash
  binary that the user never types into is **not** "MSYS2 as runtime
  identity" - see [v2 ADR 0001](adr/0001-bootstrap-upstream-homebrew.md).
- Reimplementing Homebrew commands in PowerShell.
- Replacing the JSON manifest catalog with anything else. The catalog
  is retired; Homebrew's Ruby DSL replaces it.
- Promising official Homebrew Windows support before maintainers
  accept a support model.
- Officially supporting machine-wide installs. v2 is per-user.

## Layered Shape

```
+---------------------------------------------------------------+
|  USER                                                         |
|    types `brew install codex` in PowerShell                   |
+----------------------------+----------------------------------+
                             |
                             v
+---------------------------------------------------------------+
|  LAUNCHER  (in release zip, ~2 MB total)                      |
|    bin\brew.cmd           - .cmd front door                   |
|    bin\brew.ps1           - presence check, env, exec         |
|    install.ps1            - first-time install + bootstrap    |
|    uninstall.ps1          - reverse of install.ps1            |
|    runtime-manifest.json  - pinned URLs + SHA256              |
+----------------------------+----------------------------------+
                             |
                             v
+---------------------------------------------------------------+
|  RUNTIME  (fetched on first use, ~130 MB on disk)             |
|    runtime\mingit\        - Win32 bash + minimal POSIX env    |
|    runtime\ruby\          - RubyInstaller portable Ruby       |
|    runtime\homebrew\      - pinned shallow clone of           |
|                             Homebrew/brew, with v2 patches    |
|                             applied                           |
+----------------------------+----------------------------------+
                             |
                             v
+---------------------------------------------------------------+
|  HOMEBREW (upstream, runs unmodified except for the           |
|           small Windows patches we maintain - see              |
|           LINK_STRATEGY.md and ADR 0004)                       |
|    bin\brew                                                   |
|      -> Library\Homebrew\brew.sh (bash)                       |
|         -> Library\Homebrew\brew.rb (Ruby)                    |
|            -> formula resolution, download, install, link     |
+----------------------------+----------------------------------+
                             |
                             v
+---------------------------------------------------------------+
|  PREFIX  (per-user, %LOCALAPPDATA%\Homebrew)                  |
|    bin\<name>.cmd, bin\<name>.ps1   - generated shims         |
|    Cellar\<name>\<version>\         - installed payloads      |
|    opt\<name>                       - Homebrew's opt links    |
|    Library\Taps\<owner>\<tap>\      - tap clones              |
|    var\homebrew\                    - Homebrew state          |
|    Cache\, Logs\, Temp\             - support directories     |
+---------------------------------------------------------------+
```

Each layer has a clear contract with the layer above and below. The
launcher's only job is to make sure the runtime exists and to hand
control to upstream Homebrew with the right environment. Everything
else is upstream Homebrew's problem - which is the point.

## Component Responsibilities

| Layer | Responsibility | Detail Doc |
| --- | --- | --- |
| `brew.cmd` | Universal front door. Survives restricted PowerShell execution policy. | [LAUNCHER.md](LAUNCHER.md) |
| `brew.ps1` | Resolve prefix. Verify runtime presence and integrity. Set `HOMEBREW_*` env. Exec bash. Propagate exit code. | [LAUNCHER.md](LAUNCHER.md) |
| `install.ps1` | First-time install: extract launcher to prefix, add prefix\bin to User PATH, call `Install-Runtime`. | [LAUNCHER.md](LAUNCHER.md) |
| `uninstall.ps1` | Reverse of install. Removes prefix and User PATH entry. | [LAUNCHER.md](LAUNCHER.md) |
| `runtime-manifest.json` | Pinned versions + SHA256 for MinGit, RubyInstaller, Homebrew commit. | [BOOTSTRAP.md](BOOTSTRAP.md) |
| `Install-Runtime` (function in `brew.ps1`) | Download, verify, extract, and stage each runtime component. Apply v2 patches to the Homebrew clone. | [BOOTSTRAP.md](BOOTSTRAP.md) |
| HOMEBREW_* env contract | The environment variables upstream Homebrew expects. We set every one explicitly. | [HOMEBREW_INTEGRATION.md](HOMEBREW_INTEGRATION.md) |
| v2 Homebrew patches | Minimal Ruby patches that make Homebrew's link step work on Windows. | [LINK_STRATEGY.md](LINK_STRATEGY.md) + [ADR 0004](adr/0004-maintained-patches-vs-fork.md) |
| Shim generation | `.cmd` + `.ps1` pair per linked executable. | [LINK_STRATEGY.md](LINK_STRATEGY.md) + [ADR 0005](adr/0005-windows-link-strategy.md) |
| `brew update` interception | Intercepted by `brew.ps1`. Pinned Homebrew commit is not advanced by `brew update`. | [ADR 0006](adr/0006-brew-update-semantics.md) |
| Tap policy | No taps installed by default. Windows-only tap for v2-era formulae. | [ADR 0007](adr/0007-windows-only-tap-first.md) |
| PATH management | User PATH only, never machine PATH, no profile edits. | [ADR 0008](adr/0008-path-management.md) |

## Prefix Layout

```
%LOCALAPPDATA%\Homebrew\
+-- bin\                     # user PATH entry; shims live here
+-- Cellar\<name>\<ver>\     # Homebrew-managed kegs
+-- opt\                     # Homebrew-managed opt prefix
+-- Library\
|   +-- Taps\                # `brew tap` writes here
+-- var\
|   +-- homebrew\            # Homebrew-managed state
+-- Cache\                   # download cache
+-- Logs\
+-- Temp\
+-- runtime\                 # NEW in v2 - private to our launcher
|   +-- mingit\              # MinGit; provides usr\bin\bash.exe
|   +-- ruby\                # RubyInstaller portable Ruby
|   +-- homebrew\            # shallow git clone of Homebrew/brew
|   +-- pins.json            # exact installed versions + SHA256
+-- runtime-manifest.json    # desired versions + SHA256 (from release zip)
+-- install-manifest.json    # written by install.ps1; carries launcher version
```

`runtime/` is owned by the launcher; Homebrew should never write into it.
`bin/`, `Cellar/`, `opt/`, `Library/`, `var/`, `Cache/`, `Logs/`,
`Temp/` are all the same paths Homebrew uses elsewhere - upstream's
existing code handles them. The only new thing in the prefix is the
`runtime/` directory and two small metadata files.

## Lifecycle Summary

### First-time install

1. User runs `irm https://github.com/Euraika-Labs/brew-windows/releases/latest/download/install.ps1 | iex`.
2. `install.ps1` resolves a release zip URL, verifies its SHA256, and extracts the launcher payload to `%LOCALAPPDATA%\Homebrew\`.
3. `install.ps1` adds `%LOCALAPPDATA%\Homebrew\bin` to the **User** PATH.
4. `install.ps1` writes `install-manifest.json` recording the launcher version.
5. `install.ps1` invokes `Install-Runtime` eagerly. User sees one progress indicator: "Downloading Homebrew runtime, ~130 MB, one-time download...".
6. `Install-Runtime` downloads MinGit, RubyInstaller, and Homebrew, SHA256-verifies each, extracts them into `runtime/`, applies v2 patches to the Homebrew clone, writes `runtime/pins.json`.
7. User opens a new PowerShell window. `brew --version` works.

### First formula install

1. User runs `brew install codex`.
2. `brew.cmd` execs `brew.ps1`.
3. `brew.ps1` confirms `runtime/` is present and matches `runtime-manifest.json`. (Lazy bootstrap fallback: if missing or stale, calls `Install-Runtime`.)
4. `brew.ps1` sets `HOMEBREW_BREW_FILE`, `HOMEBREW_PREFIX`, ..., adds `runtime/mingit/usr/bin` and `runtime/ruby/bin` to PATH.
5. `brew.ps1` execs `runtime/mingit/usr/bin/bash.exe runtime/homebrew/bin/brew install codex`.
6. Upstream Homebrew resolves the formula, downloads, SHA256-verifies, extracts to `Cellar/codex/<ver>/`.
7. Homebrew's link step (patched: see [LINK_STRATEGY.md](LINK_STRATEGY.md)) generates `bin/codex.cmd` and `bin/codex.ps1` pointing at `Cellar/codex/<ver>/bin/codex.exe`.
8. User opens a new PowerShell window. `codex --version` works.

### Upgrade

1. User runs `irm install.ps1 | iex` again with a newer launcher version.
2. `install.ps1` recognizes an existing install (sees `install-manifest.json`), backs up the launcher files, writes the new ones, writes a new `install-manifest.json`.
3. The new `runtime-manifest.json` may pin new versions. Next `brew` invocation detects the mismatch between `runtime/pins.json` and `runtime-manifest.json` and re-runs `Install-Runtime`.
4. Already-installed formulae in `Cellar/` are untouched. They keep working until the user runs `brew upgrade`.

### Uninstall

1. User runs `brew self-uninstall` (intercepted by `brew.ps1`) or invokes `uninstall.ps1` directly.
2. `uninstall.ps1` removes the prefix entry from User PATH.
3. `uninstall.ps1` removes the entire prefix directory.

## What's Preserved From v1

These v1 decisions cross over unchanged:

- Per-user prefix at `%LOCALAPPDATA%\Homebrew`. No elevation, no machine PATH writes. ([ADR 0008](adr/0008-path-management.md), originally v1 ADR 0002.)
- `.cmd` + `.ps1` front-door shims. Same rationale - works under restricted PowerShell execution policies without modifying machine policy. ([LINK_STRATEGY.md](LINK_STRATEGY.md), [ADR 0005](adr/0005-windows-link-strategy.md).)
- SHA256-everything threat model. HTTPS-or-local URL allowlist. ([THREAT_MODEL.md](THREAT_MODEL.md).)
- `Assert-PathUnderPrefix` style canonicalization checks before any destructive filesystem write.
- User PATH management without shell-profile edits.
- Windows CI matrix: PowerShell 7 + Windows PowerShell 5.1.
- Shim argument and exit-code fuzz tests (`v1/tests/shim-fuzz.ps1`) - these define the expected behavior for v2's link strategy patch and any future upstream PR.

## What's Retired From v1

- The ~850-line PowerShell runtime (`v1/bin/brew.ps1`).
- The JSON manifest schema (`v1/schema/manifest.v0.schema.json`).
- The formula catalog (`v1/Library/Taps/.../*.json`).
- The Homebrew -> Windows manifest sync pipeline (`v1/scripts/sync-homebrew-catalog.ps1`).
- The candidate report (`v1/catalog/windows-candidates.json`).

These are replaced by upstream Homebrew's existing Ruby formula DSL,
existing tap discovery, existing download/extract/install/link pipeline,
and existing `brew search` / `brew info`.

## Phase Plan

Five phases. Each one produces something demonstrable. See
[PHASE_PLAN.md](PHASE_PLAN.md) for full deliverables and exit criteria.

1. **Launcher + Bootstrap proof.** `brew --version` works on a clean box. No formula install.
2. **Doctor parity.** `brew config`, `brew doctor`, `brew --prefix` all work via upstream code.
3. **First formula install.** Windows link strategy patch in place. One formula (probably codex re-written as Ruby) installs end-to-end.
4. **Non-author users + CI.** Real CI runs the full cycle. At least three non-author users have run `brew install`.
5. **Upstream PR sequence (revised).** Only after Phase 4. Small (<500 LOC) PRs against `Homebrew/brew`, starting with the link strategy abstraction.

## Compliance With Maintainer Feedback

See [COMPLIANCE.md](COMPLIANCE.md) for a full requirement-by-requirement
mapping. Summary:

- p-linnane: native Windows is firmly out of scope. v2 respects this
  by remaining an external project, not requesting tier 1 support, and
  not asking for any merge before maintainer position changes.
- MikeMcQuaid: not categorically excluded long-term *if it uses bash +
  Ruby + curl*; complete the port externally first; small PRs only after
  real CI + non-author users. v2 is built to this prescription.

## Threat Model

See [THREAT_MODEL.md](THREAT_MODEL.md). v2 inherits v1's threat model
and adds two new trust boundaries:

- Runtime downloads on first run (MinGit, RubyInstaller, Homebrew clone).
- Upstream Homebrew/brew git history.

Both are mitigated by SHA256 pinning, commit-SHA pinning, and release
artifact attestation.

## Decision Index

| Decision | ADR |
| --- | --- |
| Bootstrap upstream Homebrew instead of reimplementing | [0001](adr/0001-bootstrap-upstream-homebrew.md) |
| Fetch runtime on first run, not bundle | [0002](adr/0002-fetch-runtime-on-first-run.md) |
| MinGit bash + RubyInstaller Ruby + system curl | [0003](adr/0003-runtime-composition.md) |
| Maintained patches against upstream, not a fork | [0004](adr/0004-maintained-patches-vs-fork.md) |
| Windows shim link strategy (`.cmd` + `.ps1`) | [0005](adr/0005-windows-link-strategy.md) |
| `brew update` semantics under a pinned model | [0006](adr/0006-brew-update-semantics.md) |
| Windows-only tap first, not homebrew/core | [0007](adr/0007-windows-only-tap-first.md) |
| User PATH only, no machine PATH, no profile edits | [0008](adr/0008-path-management.md) |
