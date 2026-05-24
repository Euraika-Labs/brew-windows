# Homebrew Integration

This document defines how v2's launcher hands control to upstream
`Homebrew/brew` and what contract the two sides agree on.

The headline rule: **the launcher is the only thing between the user
and upstream Homebrew.** Once the launcher has set up the environment
and exec'd bash, Homebrew runs unmodified except for the small patches
documented in [LINK_STRATEGY.md](LINK_STRATEGY.md) and
[ADR 0004](adr/0004-maintained-patches-vs-fork.md).

## Environment Variable Contract

Upstream Homebrew's `Library/Homebrew/brew.sh` reads a defined set of
environment variables to bootstrap itself. v2 sets every relevant one
explicitly. Setting things explicitly is deliberate: it makes the
contract testable and prevents bug-by-side-effect.

### Variables We Set

| Variable | Value | Rationale |
| --- | --- | --- |
| `HOMEBREW_BREW_FILE` | `<prefix>\runtime\homebrew\bin\brew` | Path Homebrew uses to re-invoke itself. Must exist. |
| `HOMEBREW_PREFIX` | `<prefix>` | The install prefix. Same as v1: `%LOCALAPPDATA%\Homebrew` by default. |
| `HOMEBREW_REPOSITORY` | `<prefix>\runtime\homebrew` | Path to the Homebrew git checkout. Used by `brew update`. |
| `HOMEBREW_LIBRARY` | `<prefix>\runtime\homebrew\Library` | Path to Homebrew's Ruby library directory. |
| `HOMEBREW_CELLAR` | `<prefix>\Cellar` | Where Homebrew installs kegs. |
| `HOMEBREW_CACHE` | `<prefix>\Cache` | Where Homebrew caches downloaded archives. |
| `HOMEBREW_TEMP` | `<prefix>\Temp` | Where Homebrew stages downloads + extractions. |
| `HOMEBREW_LOGS` | `<prefix>\Logs` | Where Homebrew writes per-formula install logs. |
| `HOMEBREW_SYSTEM` | `Windows` | Tells Homebrew what host OS this is. Requires the os/windows patch to be meaningful. |
| `HOMEBREW_PROCESSOR` | `x86_64` or `arm64` | From `PROCESSOR_ARCHITEW6432` (WoW64-aware) or `PROCESSOR_ARCHITECTURE`. |
| `HOMEBREW_NO_ANALYTICS` | `1` | Opt out of analytics by default in v2. Upstream Homebrew's analytics endpoints are not expected to handle our system tag anyway. |
| `HOMEBREW_NO_AUTO_UPDATE` | `1` | Prevents upstream Homebrew from doing its own `git pull` on each command. We pin via `runtime-manifest.json` (see [ADR 0006](adr/0006-brew-update-semantics.md)). |

### Variables We Do Not Set

These exist in upstream Homebrew but v2 does not touch them. Defaults
or upstream-defined behavior applies.

- `HOMEBREW_BOTTLE_DOMAIN`, `HOMEBREW_BOTTLE_DEFAULT_DOMAIN`. No Windows
  bottles exist; bottle behavior on a Windows-only tap is "build from
  source, fail loudly if not possible".
- `HOMEBREW_ARTIFACT_DOMAIN`, `HOMEBREW_API_DOMAIN`. Defaults apply.
- `HOMEBREW_DEVELOPER`, `HOMEBREW_VERBOSE`, `HOMEBREW_DEBUG`. User-set
  variables; we pass them through.
- `HOMEBREW_GITHUB_API_TOKEN`. If the user sets it, we pass it
  through.

### PATH Prepend

The launcher prepends `runtime\mingit\usr\bin` and `runtime\ruby\bin`
to `PATH` **only for the bash invocation**. The User PATH (persisted)
is unchanged - only `<prefix>\bin` is on the User PATH (added by
`install.ps1`).

This means:

- The user types `brew` and gets our launcher.
- Inside upstream Homebrew, `bash`, `ruby`, and POSIX utilities
  resolve to the vendored runtime.
- The user does not get a global `bash`, `ruby`, or `make` on their
  shell PATH outside the brew context.

Avoiding pollution of the user's PATH is intentional. It is the v1 ADR
0002 promise carried forward.

## What Upstream Homebrew Sees

After the launcher has set environment and exec'd:

```
bash.exe /c/Users/.../Homebrew/runtime/homebrew/bin/brew install codex
```

From Homebrew's perspective:

- `$0` is `/c/Users/.../Homebrew/runtime/homebrew/bin/brew` (forward slashes,
  the bash representation).
- `$@` is `install codex`.
- `$HOMEBREW_PREFIX` etc. are all set.
- `$OSTYPE` is something MinGit's bash reports - typically
  `msys` or `cygwin`. **This is the field where Homebrew's
  platform detection currently fails on Windows.** See [LINK_STRATEGY.md](LINK_STRATEGY.md)
  and the v2 patch set.

Homebrew's `brew.sh` proceeds with:

1. Read the environment.
2. Locate the Ruby interpreter (we put it on PATH).
3. Exec Ruby against `Library/Homebrew/brew.rb`.

From here it is unmodified upstream code, with our patches applied.

## Patch Strategy In Brief

See [ADR 0004](adr/0004-maintained-patches-vs-fork.md) for the full
patches-vs-fork decision. Summary:

- Patches live in `v2/patches/*.patch` in the launcher source.
- `runtime-manifest.json` lists each patch with its SHA256.
- `Install-Runtime` applies patches after the Homebrew checkout
  completes.
- Each patch is small (target <100 lines) and tightly scoped to one
  upstream-reviewable abstraction.

Initial patch set (Phase 1-3):

- `patches/windows-os-detection.patch` (~30 lines). Teaches
  `brew.sh` and `Library/Homebrew/os.rb` to recognize Windows.
- `patches/windows-link-strategy.patch` (~150 lines). Adds a
  Windows-specific code path in the keg link step that emits `.cmd` +
  `.ps1` shims instead of symlinks.
- `patches/no-auto-update.patch` (~10 lines, only if upstream's
  `HOMEBREW_NO_AUTO_UPDATE` check has a gap on Windows).

Each patch is the candidate for a small upstream PR once Phase 4
produces non-author users and CI evidence.

## What v2 Does Not Touch

- Formula DSL. We do not patch formula loading, parsing, or evaluation.
  A Ruby formula is a Ruby formula.
- Bottle metadata. Bottles are deferred. Source-build is the Windows
  default.
- Dependency solver. Standard upstream behavior.
- Tap loading. Standard upstream behavior.
- `brew search`, `brew info`, `brew list`, `brew uses`, `brew deps`,
  `brew leaves`. All standard upstream behavior.
- Download mechanism. Homebrew uses `curl` from PATH. On Windows that
  resolves to `C:\Windows\System32\curl.exe` (Microsoft-supplied).

This minimalism is the whole point of v2. The smaller our footprint
in Homebrew code, the smaller the upstream PR sequence at Phase 5.

## Forwarding Stdin, Stdout, Stderr

The launcher uses PowerShell's call operator (`&`) to exec bash. This
preserves:

- stdin (pipe-in works: `echo y | brew install something-that-prompts`).
- stdout / stderr (separate streams, interactive `brew` commands work).
- Console attachment (no detached process; Ctrl+C in PowerShell sends
  to the bash child).

We do **not** use `Start-Process`, `Invoke-Expression`, or `cmd /c`.
Each has at least one buffer-or-detachment problem that would degrade
the interactive experience.

## TTY And Color Output

When run from Windows Terminal, PowerShell, or cmd.exe console host:

- `bash.exe`'s stdout/stderr are connected to the parent console.
- Homebrew detects TTY correctly and emits ANSI color sequences.
- Modern Windows console handles ANSI sequences natively (Windows 10
  1607+). No `ANSICON` or `colorama` needed.

When run from PowerShell ISE or a CI runner without a TTY, Homebrew
falls back to non-color output as it does on macOS/Linux.

## Locale, Encoding, And Code Pages

Homebrew internally assumes UTF-8. Windows PowerShell 5.1 defaults to
the system code page (often `Windows-1252`) for stdout encoding,
which is wrong for Homebrew's output.

The launcher sets:

```powershell
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
```

before execing bash. This makes Homebrew's UTF-8 output render
correctly in both PowerShell 5.1 and PowerShell 7+. Setting these on
PowerShell 7 is a no-op (it's already UTF-8) but harmless.

We also set `$env:LANG = "C.UTF-8"` and `$env:LC_ALL = "C.UTF-8"` for
the bash subprocess.

## Long Path Support

Some Homebrew formulae produce file paths longer than 260 characters.
Windows historically capped paths at MAX_PATH=260 but supports longer
paths if:

- Windows 10 1607+ with the "Enable Win32 long paths" group policy or
  registry setting enabled.
- Process manifest declares `longPathAware`.

`brew doctor` checks the group policy setting and warns if disabled.
Phase 2 owns this check.

## Working Directory

The launcher does not `cd` before exec'ing bash. Homebrew's bash
bootstrap is robust to the caller's CWD - it uses `$0` to find
itself. We pass `$0` as an absolute (forward-slash) path, which is
correct.

## Exit Codes

- Launcher returns whatever bash returns. bash returns whatever
  Homebrew returns. No translation.
- `brew install` exit codes match upstream Homebrew behavior on
  macOS/Linux.
- Launcher-level errors (e.g. failed `Install-Runtime`, runtime
  integrity check) exit with code 1 and an explicit error message.

## Open Integration Questions

These resolve during Phase 1-3 implementation:

1. **Does MinGit's bash provide everything `brew.sh` needs?** Most
   likely yes (MinGit includes coreutils, sed, grep, find). Phase 1
   verifies.
2. **Does MinGit ship `git` such that Homebrew's `brew update` and
   tap operations work?** Yes - MinGit *is* git plus a minimal POSIX
   environment. Phase 2 verifies.
3. **Is RubyInstaller's Ruby ABI-compatible with Homebrew's gem
   expectations?** Homebrew uses very few gems internally and bundles
   them. Phase 1 verifies on `brew --version`.
4. **Does upstream Homebrew assume forward-slash paths anywhere
   that would break with our backslash `HOMEBREW_*` values?**
   Phase 1-2 surface this. Mitigation: convert to forward slashes for
   any HOMEBREW_* values that Homebrew passes back to bash.
