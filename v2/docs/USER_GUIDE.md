# Brew Windows User Guide

Brew Windows is a Windows-native launcher that lets you run upstream
[Homebrew](https://brew.sh) on a stock Windows 11 machine. There is no
WSL, no MSYS2, no admin rights, and no shell profile editing. The whole
thing installs into your user profile in one line of PowerShell, and
from then on you type `brew <command>` exactly as you would on macOS or
Linux.

## Status

Brew Windows v2 is currently in Phase 1 (launcher + bootstrap proof). The
launcher installs cleanly but actual formula installs are not yet available -
that lands in Phase 3. See [`PHASE_PLAN.md`](PHASE_PLAN.md) for the current
state and what each phase delivers.

## Install

Open Windows Terminal (or any PowerShell 5.1 / 7+ session) and run:

```powershell
irm https://github.com/Euraika-Labs/brew-windows/releases/latest/download/install.ps1 | iex
```

What that one line does:

- Downloads `install.ps1` from the latest GitHub release and pipes it
  to `Invoke-Expression`.
- Resolves the matching release zip, verifies its SHA256, and extracts
  the launcher into `%LOCALAPPDATA%\Homebrew` (your per-user prefix).
- Adds `%LOCALAPPDATA%\Homebrew\bin` to your **User** `PATH` (never the
  Machine `PATH`).
- Eagerly downloads the runtime - MinGit, RubyInstaller, and a shallow
  clone of `Homebrew/brew` - to `%LOCALAPPDATA%\Homebrew\runtime`. This
  is a one-time ~130 MB download.
- Writes `install-manifest.json` recording the launcher version.

No elevation is required at any point. If your execution policy is
restricted, the `brew.cmd` front door still works - the launcher invokes
PowerShell with `-ExecutionPolicy Bypass` for its own scripts only and
does not modify machine policy.

## First Run

Close and reopen your terminal so the new `PATH` entry is picked up.
Then:

```powershell
brew --version
```

You should see the upstream Homebrew version string printed by
`runtime/homebrew/bin/brew`. If the runtime was bootstrapped eagerly by
`install.ps1`, this call returns immediately. If for any reason the
runtime is missing (you copied the prefix, deleted `runtime/`, or
upgraded the launcher), the launcher detects the mismatch and runs
`Install-Runtime` lazily on this first call.

## What You Can Do Today (Phase 1)

The following commands are wired through the launcher today:

| Command | Behavior |
| --- | --- |
| `brew --version` | Prints the upstream Homebrew version. |
| `brew help` | Forwards to upstream's help. |
| `brew self-uninstall` | Intercepted; removes the prefix and User PATH entry. |
| `brew self-update` | Intercepted; bumps the launcher and re-runs `Install-Runtime`. |

The following commands will work once Phase 2 / Phase 3 land. They are
listed here only so you know what to expect:

- `brew install <formula>` (Phase 3)
- `brew uninstall <formula>` (Phase 3)
- `brew tap <owner>/<repo>` (Phase 3)
- `brew doctor` (Phase 2)
- `brew config` (Phase 2)
- `brew --prefix` (Phase 2)

Running any of these today forwards them to upstream Homebrew, which
will currently complain that pieces of the Windows port are not in
place yet. That is expected for Phase 1.

## Uninstall

The supported uninstall paths are:

```powershell
brew self-uninstall
```

or, if `brew` itself is broken, run the installer's sibling directly:

```powershell
& "$env:LOCALAPPDATA\Homebrew\uninstall.ps1"
```

Either path removes `%LOCALAPPDATA%\Homebrew\bin` from your User PATH
and deletes the entire prefix directory. The uninstaller refuses to
delete a directory that does not look like a Brew Windows prefix (no
`install-manifest.json`, no `runtime/`).

## Troubleshooting

This section is intentionally short for Phase 1. It will grow as more
real failure modes show up in Phase 2+.

- **`brew` is not recognized after install.** Close and reopen your
  terminal. `install.ps1` updates the User `PATH` in the registry, but
  already-open processes still see the old value.
- **`Install-Runtime` fails with a SHA256 mismatch.** Delete
  `%LOCALAPPDATA%\Homebrew\Cache` and re-run `install.ps1`. The cached
  archive was corrupted in transit.
- **`Install-Runtime` fails with a sharing violation while moving
  `runtime/mingit/`.** This is usually antivirus or EDR holding a
  handle on a just-extracted executable. Retry after a few seconds, or
  add `%LOCALAPPDATA%\Homebrew` to your AV exclusion list.

## Configuration

Phase 1 supports one configuration knob:

- `HOMEBREW_PREFIX` - override the install prefix. If set in your
  environment before running `install.ps1`, the launcher installs there
  instead of `%LOCALAPPDATA%\Homebrew`. The launcher itself honors this
  variable on every invocation.

Once `brew config` works in Phase 2, the full upstream `HOMEBREW_*`
environment contract becomes available. See
[`HOMEBREW_INTEGRATION.md`](HOMEBREW_INTEGRATION.md) for the contract
the launcher sets for upstream Homebrew today.

## Reporting Issues

Brew Windows is experimental software. The runtime is upstream
Homebrew; the launcher is a thin Windows-native wrapper around it. Bugs
in either layer are very much expected.

Open issues against the project tracker:

  https://github.com/Euraika-Labs/brew-windows/issues

When filing a bug, please include:

- Output of `brew --version`.
- Contents of `%LOCALAPPDATA%\Homebrew\install-manifest.json`.
- Contents of `%LOCALAPPDATA%\Homebrew\runtime\pins.json` (if it
  exists).
- The exact command you ran and the full error message.
