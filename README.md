# Brew Windows

Brew Windows brings the Homebrew experience to Windows 11 Terminal and
PowerShell natively - no WSL, no MSYS2 as your shell, no Administrator
prompts, no edits to `$PROFILE`. You type `brew install <formula>` and
get a working executable on your PATH.

The runtime underneath the `brew` command is upstream Homebrew's real
bash + Ruby code, executed by a native Win32 bash (MinGit) and Ruby
(RubyInstaller) that the launcher fetches on first run. v1's
PowerShell-native reimplementation has been archived in favor of this
shape after maintainer feedback in
[Homebrew discussion 6860](https://github.com/orgs/Homebrew/discussions/6860).

## Status

**v2 Phases 1, 2, and 3 are complete and verified end-to-end on a clean
Windows 11 host.** The full sequence works today:

```powershell
brew --version                                # Homebrew >=4.3.0
brew config                                   # full Windows config
brew doctor                                   # 2 legitimate warnings only
brew tap euraika-labs/windows file:///<tap>   # 1 formula tapped
brew install euraika-labs/windows/ripgrep     # built in 3 seconds
rg --version                                  # ripgrep 15.1.0
brew list                                     # ripgrep
brew uninstall ripgrep                        # clean reverse
```

The runtime carries 20 narrowly scoped patches against upstream Homebrew
([`v2/launcher/patches/`](v2/launcher/patches/)), all guarded by
`RbConfig host_os` so macOS/Linux behavior is untouched. Phase 4
(release pipeline + non-author users) and Phase 5 (upstream PR sequence)
are not yet started - so the current install path runs against the
locally-built launcher zip, not a published GitHub release. See
[v2/docs/PHASE_PLAN.md](v2/docs/PHASE_PLAN.md) for the full plan.

## Requirements

- Windows 10 1803 (April 2018) or later, Windows 11 supported.
- PowerShell 5.1 or PowerShell 7+. Windows Terminal recommended but not required.
- Internet access on first run (to download MinGit, RubyInstaller, and
  the upstream Homebrew clone - about 130 MB total, one time, cached
  under your prefix).
- No Administrator account needed. No Developer Mode toggle needed.
- No existing Homebrew, WSL, MSYS2, Git for Windows, Ruby, or Python
  installation required - the launcher vendors everything it needs into
  `%LOCALAPPDATA%\Homebrew` and never touches anything else on your system.

## Install

### Option A: Build the launcher zip locally and install it (recommended today)

This is the path that works right now, before Phase 4 ships GitHub
releases.

```powershell
# 1. Clone the repo
git clone https://github.com/Euraika-Labs/brew-windows.git
cd brew-windows

# 2. Compute SHA256s for the manifest (one-off; commits the launcher
#    to specific MinGit / Ruby / Homebrew versions)
powershell -NoProfile -ExecutionPolicy Bypass -File .\v2\scripts\pin-runtime.ps1

# 3. Build the launcher release zip
powershell -NoProfile -ExecutionPolicy Bypass -File .\v2\scripts\build-release.ps1 -Version dev

# 4. Install from the built zip
$payload   = Resolve-Path .\v2\dist\brew-windows-v2-dev.zip
$sha256    = (Get-FileHash $payload -Algorithm SHA256).Hash
powershell -NoProfile -ExecutionPolicy Bypass -File .\v2\launcher\install.ps1 `
    -PayloadUrl $payload `
    -PayloadSha256 $sha256
```

What `install.ps1` does:

- Resolves the prefix (`%LOCALAPPDATA%\Homebrew` by default; override
  with `-Prefix` or `$env:HOMEBREW_PREFIX`).
- Verifies the payload SHA256, extracts the launcher under
  `<prefix>\bin\`.
- Adds `<prefix>\bin` to your User PATH via
  `HKCU\Environment\Path` (no edits to `$PROFILE` or system PATH).
- Eagerly runs the bootstrap, fetching MinGit + RubyInstaller + the
  pinned upstream Homebrew commit into `<prefix>\runtime\` and
  verifying every download against the manifest's SHA256s.

Close PowerShell and open a new window so the User PATH update is
visible to the new shell.

### Option B: First-class one-liner (Phase 4, not yet shipped)

```powershell
irm https://github.com/Euraika-Labs/brew-windows/releases/latest/download/install.ps1 | iex
```

This is the long-term install story. It will work once Phase 4 publishes
a tagged release with the launcher zip + SHA256 sidecar attached. Track
[PHASE_PLAN.md](v2/docs/PHASE_PLAN.md) for status.

## First-run verification

In a fresh PowerShell window:

```powershell
brew --version           # should print "Homebrew >=4.3.0 ..."
brew config              # full Windows-aware config dump
brew doctor              # should print at most two informational warnings
```

`brew doctor` may report:

- `Suspicious Git newline settings found. core.autocrlf = true` -
  reflects your global gitconfig; harmless for brew but worth reviewing
  if you don't intentionally have it set.
- `<prefix>\bin is not on your User PATH` - only if you skipped
  `install.ps1` or you're testing from a custom prefix. The normal
  install adds it; open a new PowerShell window.

Anything beyond those is a real issue - file it on the project's
[issue tracker](https://github.com/Euraika-Labs/brew-windows/issues).

## Daily usage

```powershell
brew search <name>       # search homebrew/core + tapped taps
brew info <formula>      # show formula metadata, deps, URL, SHA256
brew install <formula>   # install into Cellar, link shims into <prefix>\bin
brew list                # list installed formulae
brew uninstall <formula> # remove shims + Cellar entry
brew help <command>      # per-command help, lifted verbatim from upstream
```

### Installing a formula (current state)

The ecosystem story: Brew Windows can install **Windows-shaped
formulae** - formulae that point at prebuilt Windows binary zips and do
`bin.install "foo.exe"` in their install block. macOS / Linux formulae
in `homebrew/core` typically assume a working clang/gcc toolchain and
POSIX paths and will not currently build on Windows.

The project ships one example Windows-shaped tap at
[`v2/tap/`](v2/tap/) (one formula: `ripgrep`):

```powershell
# Tap the local Windows-only formula directory
brew tap euraika-labs/windows file:///C:/Users/<you>/path/to/brew-windows/v2/tap

brew install euraika-labs/windows/ripgrep
rg --version                                  # ripgrep 15.1.0
```

Behind the scenes:

1. The pinned BurntSushi/ripgrep Windows zip is downloaded and
   SHA256-verified.
2. The formula's `install` method (`bin.install "rg.exe"`) copies the
   executable into the keg at
   `<prefix>\Cellar\ripgrep\15.1.0\bin\rg.exe`.
3. A `.cmd` + `.ps1` shim pair is generated at `<prefix>\bin\rg.cmd`
   and `<prefix>\bin\rg.ps1` pointing at the keg-installed binary.
   Both shims forward every argument and the exit code through
   transparently.

`brew uninstall <formula>` reverses cleanly: the shim pair is removed
from `<prefix>\bin\` and the keg is removed from `Cellar\`.

Adding more formulae is a matter of authoring more `.rb` files in a
Windows-only tap. See
[`v2/docs/USER_GUIDE.md`](v2/docs/USER_GUIDE.md) for an end-to-end
walkthrough.

## Updating

`brew update` is intercepted by the launcher with a message pointing at
`brew self-update` (which doesn't exist yet - Phase 4 ships it). For
now, update by rebuilding the launcher from a fresh checkout:

```powershell
cd brew-windows
git pull
powershell -NoProfile -ExecutionPolicy Bypass -File .\v2\scripts\pin-runtime.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\v2\scripts\build-release.ps1 -Version dev
# Reinstall using Option A above; the runtime is re-bootstrapped if pins changed.
```

## Uninstalling

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\v2\launcher\uninstall.ps1
```

This removes the prefix directory and reverses the User PATH entry. No
system-wide cleanup is required because nothing system-wide was
installed.

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| `brew: command not found` in a new shell | User PATH wasn't refreshed | Open a new PowerShell window after running `install.ps1`. |
| `Bootstrapping Homebrew runtime under ...` then long pause | First-run runtime download (~130 MB) | Wait for it to finish. The runtime is cached after the first run. |
| `runtime-manifest.json still contains placeholder SHA256s` | The launcher payload was built without `pin-runtime.ps1` | Run `v2\scripts\pin-runtime.ps1` then rebuild and reinstall. |
| `Permission denied` writing to `<prefix>\runtime\...` | Antivirus locking a file mid-extract | Re-run `brew --version` - the bootstrap is idempotent and re-tries from a clean staging dir. |
| `brew doctor` Tier 3 warning about prefix | Informational - Windows is Tier 3 by Homebrew's support model | Safe to ignore. The actual readiness check is `check_runtime_integrity`. |

If something else is off, run `brew doctor` first - the diagnostic
checks under [`v2/launcher/patches/windows-diagnostics.patch`](v2/launcher/patches/windows-diagnostics.patch)
cover the most common Windows-specific footguns.

## Repository layout

```
brew-windows/
+-- v1/                  # Archived: PowerShell-native MVP
+-- v2/                  # Current architecture
|   +-- launcher/        # brew.cmd, brew.ps1, install.ps1, runtime-manifest.json
|   |   +-- patches/     # 20 small patches against upstream Homebrew
|   +-- scripts/         # validate.ps1, build-release.ps1, pin-runtime.ps1
|   +-- schema/          # JSON schema for runtime-manifest
|   +-- tests/           # Launcher smoke tests + doctor + shim fuzz
|   +-- tap/             # Local Windows-only tap (ripgrep formula)
|   +-- docs/            # ARCHITECTURE, BOOTSTRAP, LINK_STRATEGY, ADRs, etc.
+-- docs/                # Project-level upstream dossier + ADRs
+-- BREW_WINDOWS_UPSTREAM_ARCHITECTURE.md
```

## Documentation

### v2 user-facing docs

- [v2/README.md](v2/README.md) - the v2-specific overview.
- [v2/docs/USER_GUIDE.md](v2/docs/USER_GUIDE.md) - install + first
  install walkthrough.
- [v2/docs/ARCHITECTURE.md](v2/docs/ARCHITECTURE.md) - master design
  document.
- [v2/docs/BOOTSTRAP.md](v2/docs/BOOTSTRAP.md) - what `Install-Runtime`
  does and what gets written where.
- [v2/docs/PHASE_PLAN.md](v2/docs/PHASE_PLAN.md) - current status per
  phase + what each phase delivers.
- [v2/launcher/patches/README.md](v2/launcher/patches/README.md) - the
  20 patches indexed by phase, with rationale per file.

### Upstream conversation

- Project vision: [BREW_WINDOWS_UPSTREAM_ARCHITECTURE.md](BREW_WINDOWS_UPSTREAM_ARCHITECTURE.md)
- Upstream dossier: [docs/UPSTREAM_DOSSIER.md](docs/UPSTREAM_DOSSIER.md)
- Discussion draft: [docs/UPSTREAM_DISCUSSION_DRAFT.md](docs/UPSTREAM_DISCUSSION_DRAFT.md)
- Maintainer packet: [docs/UPSTREAM_MAINTAINER_PACKET.md](docs/UPSTREAM_MAINTAINER_PACKET.md)
- Proposed PR sequence (pre-feedback): [docs/UPSTREAM_PR_SEQUENCE.md](docs/UPSTREAM_PR_SEQUENCE.md)
- Discussion-first ADR: [docs/adr/0005-upstream-discussion-first.md](docs/adr/0005-upstream-discussion-first.md)

## Non-goals

- Implementing Brew Windows through WSL.
- Wrapping `wsl.exe`.
- Becoming a WinGet, Scoop, Chocolatey, npm, or MSYS2 wrapper.
- Promising official Homebrew Windows support before maintainers accept
  a support model.

## Community

- [CONTRIBUTING.md](CONTRIBUTING.md)
- [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)
- [SECURITY.md](SECURITY.md)
- [SUPPORT.md](SUPPORT.md)

## License

BSD 2-Clause. See [LICENSE](LICENSE).
