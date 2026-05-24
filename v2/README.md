# Brew Windows v2

v2 is the current design generation: a small Windows-native launcher
that bootstraps upstream `Homebrew/brew` itself on first run.

The user-facing experience is still:

```powershell
irm https://github.com/Euraika-Labs/brew-windows/releases/latest/download/install.ps1 | iex
brew install codex
codex --version
```

The runtime *underneath* the `brew` command is no longer a PowerShell
reimplementation. It is upstream Homebrew's real bash + Ruby code,
executed by a native Win32 bash (MinGit), a native Win32 Ruby
(RubyInstaller), and the `curl.exe` that ships with Windows 10 1803
and later.

## Why This Shape

Two things changed between v1 and v2:

1. **Homebrew maintainer feedback**
   ([discussion 6860](https://github.com/orgs/Homebrew/discussions/6860))
   established that any path that could eventually merge upstream must
   use bash + Ruby + curl. A PowerShell-only reimplementation cannot.
2. **All three dependencies have credible native-Windows distributions**
   that do not require WSL or MSYS2 as a runtime identity: MinGit ships
   a working Win32 bash, RubyInstaller ships a portable Ruby, and
   `curl.exe` has been part of the Windows base image since 2018.

So v2's design rule is: ship a tiny launcher in the release zip, fetch
the real runtime on first use, and from then on delegate to upstream
Homebrew.

## Status

Design only. No executable code in this directory yet.

## Document Map

Start with the architecture document, then drill down as needed.

### Master Documents

- [ARCHITECTURE.md](docs/ARCHITECTURE.md) - master overview: goals,
  non-goals, layered shape, prefix layout, lifecycle, links to all
  other documents.
- [COMPLIANCE.md](docs/COMPLIANCE.md) - explicit mapping of every
  Homebrew maintainer requirement from discussion 6860 to where v2
  satisfies it.
- [PHASE_PLAN.md](docs/PHASE_PLAN.md) - 5-phase implementation
  plan with deliverables, exit criteria, and risk per phase.

### Subsystem Specifications

- [LAUNCHER.md](docs/LAUNCHER.md) - `brew.cmd`, `brew.ps1`,
  `install.ps1`, `uninstall.ps1` specs and pseudocode.
- [BOOTSTRAP.md](docs/BOOTSTRAP.md) - `Install-Runtime` flow,
  `runtime-manifest.json` schema, atomicity policy.
- [HOMEBREW_INTEGRATION.md](docs/HOMEBREW_INTEGRATION.md) - the full
  `HOMEBREW_*` environment contract; what we set and why; how the
  launcher hands off to bash.
- [LINK_STRATEGY.md](docs/LINK_STRATEGY.md) - the most
  upstream-relevant patch: `.cmd` + `.ps1` shim pairs replacing
  symlinks on Windows.
- [THREAT_MODEL.md](docs/THREAT_MODEL.md) - assets, trust
  boundaries, primary threats, mitigations, compared to v1.

### Architecture Decision Records

- [ADR 0001](docs/adr/0001-bootstrap-upstream-homebrew.md) - bootstrap
  upstream Homebrew instead of reimplementing it.
- [ADR 0002](docs/adr/0002-fetch-runtime-on-first-run.md) - small
  release zip; runtime downloaded on first use.
- [ADR 0003](docs/adr/0003-runtime-composition.md) - MinGit bash +
  RubyInstaller Ruby + system curl.
- [ADR 0004](docs/adr/0004-maintained-patches-vs-fork.md) - small
  patches against upstream rather than a fork.
- [ADR 0005](docs/adr/0005-windows-link-strategy.md) - `.cmd` +
  `.ps1` shim pairs as the Windows link strategy.
- [ADR 0006](docs/adr/0006-brew-update-semantics.md) - `brew update`
  intercepted by the launcher; updates happen via launcher releases.
- [ADR 0007](docs/adr/0007-windows-only-tap-first.md) - no taps
  installed by default; Windows-only tap for v2-era formulae.
- [ADR 0008](docs/adr/0008-path-management.md) - User PATH only, no
  Machine PATH, no profile edits.

## What v2 Inherits From v1

v1 proved several Windows-side primitives that v2 carries forward
unchanged. See [`../v1/README.md`](../v1/README.md) for the list.

## What v2 Retires From v1

- The PowerShell `brew` runtime (`v1/bin/brew.ps1`, ~850 lines).
- The manifest schema and JSON formula catalog
  (`v1/schema/`, `v1/Library/`).
- The Homebrew -> Windows manifest sync pipeline
  (`v1/scripts/sync-homebrew-catalog.ps1`).
- The candidate report (`v1/catalog/windows-candidates.json`).

These are replaced by upstream Homebrew's existing Ruby formula DSL
and its existing `brew install` pipeline.

## What Lives Where (When v2 Has Code)

```
v2/
+-- README.md                          # this file
+-- docs/                              # design docs (current)
|   +-- ARCHITECTURE.md
|   +-- LAUNCHER.md
|   +-- BOOTSTRAP.md
|   +-- HOMEBREW_INTEGRATION.md
|   +-- LINK_STRATEGY.md
|   +-- THREAT_MODEL.md
|   +-- PHASE_PLAN.md
|   +-- COMPLIANCE.md
|   +-- adr/
|       +-- 0001-bootstrap-upstream-homebrew.md
|       +-- 0002-fetch-runtime-on-first-run.md
|       +-- 0003-runtime-composition.md
|       +-- 0004-maintained-patches-vs-fork.md
|       +-- 0005-windows-link-strategy.md
|       +-- 0006-brew-update-semantics.md
|       +-- 0007-windows-only-tap-first.md
|       +-- 0008-path-management.md
+-- launcher/                          # (Phase 1) launcher source
|   +-- bin/brew.cmd
|   +-- bin/brew.ps1
|   +-- install.ps1
|   +-- uninstall.ps1
|   +-- runtime-manifest.json
|   +-- patches/
|   |   +-- windows-os-detection.patch
|   |   +-- windows-link-strategy.patch
|   +-- README.md
+-- schema/                            # (Phase 1) manifest schemas
|   +-- runtime-manifest.v0.schema.json
+-- scripts/                           # (Phase 1) build + validate
|   +-- build-release.ps1
|   +-- validate.ps1
+-- tests/                             # (Phase 1+) test harness
    +-- install-runtime.ps1
    +-- launcher-smoke.ps1
    +-- shim-fuzz.ps1                  # ported from v1
```

The `launcher/`, `schema/`, `scripts/`, and `tests/` subdirectories
are created during Phase 1 implementation.

## Status Tracker

- [x] v1 archived; restructure complete.
- [x] v2 architecture documented.
- [x] Phase 1 - Launcher + Bootstrap proof (verified end-to-end:
  PortableGit + RubyInstaller + patched upstream Homebrew produce
  a working `brew --version` from a clean test prefix)
- [ ] Phase 2 - Doctor parity (in progress)
- [ ] Phase 3 - First formula install
- [ ] Phase 4 - Non-author users + CI maturity
- [ ] Phase 5 - Upstream PR sequence

See [PHASE_PLAN.md](docs/PHASE_PLAN.md) for each phase's deliverables
and exit criteria.

### Phase 1 substatus

- [x] Wave 1.B: launcher core (`brew.cmd`, `brew.ps1`, `install.ps1`, `uninstall.ps1`, `runtime-manifest.json`, schema, `windows-os-detection.patch`)
- [x] Wave 1.C: real `Install-Runtime` + scripts (`validate.ps1`, `build-release.ps1`, `pin-runtime.ps1`)
- [x] Wave 1.D: Phase 1 tests + user guide ([`docs/USER_GUIDE.md`](docs/USER_GUIDE.md))
- [x] Wave 1.E: CI integration (`.github/workflows/ci.yml` gets v2 jobs)
- [x] Phase 1 end-to-end verification: pinned the manifest (`pin-runtime.ps1`), ran the launcher against a clean test prefix, the full bootstrap chain produced `brew --version` output from upstream Homebrew. R2 (MinGit lacks bash) surfaced and was resolved by switching to PortableGit; R1 and R3 did not surface.
