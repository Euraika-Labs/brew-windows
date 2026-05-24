# Launcher Specification

The launcher is the only code v2 ships in its release zip. It is
responsible for:

1. Resolving the prefix.
2. Verifying the runtime is present and unmodified.
3. Setting the `HOMEBREW_*` environment contract.
4. Execing bash against upstream Homebrew's `bin/brew`.
5. Propagating the exit code.

That is the whole job. The launcher does not parse formulae, does not
contact the network during normal operation, and does not maintain
state beyond `install-manifest.json` (set at install time) and
`runtime/pins.json` (set by `Install-Runtime`).

Target size: ~250 lines of PowerShell + ~5 lines of cmd. Source is in
`v2/launcher/` once implementation starts.

## `bin\brew.cmd`

Verbatim from v1 with a different path:

```cmd
@echo off
setlocal
set "BREW_BIN=%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%BREW_BIN%brew.ps1" %*
exit /b %ERRORLEVEL%
```

The `.cmd` front door exists because some environments enforce a
restricted PowerShell execution policy on `.ps1` files. Calling
`powershell.exe -ExecutionPolicy Bypass -File brew.ps1` from inside a
`.cmd` does not modify any system-wide policy and works regardless.

## `bin\brew.ps1`

### Top of file (preamble)

```powershell
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$BrewArgs)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$Script:LauncherVersion = "0.1.0-dev"
```

### Prefix resolution

```powershell
function Resolve-BrewPrefix {
    if (-not [string]::IsNullOrWhiteSpace($env:HOMEBREW_PREFIX)) {
        return [System.IO.Path]::GetFullPath($env:HOMEBREW_PREFIX)
    }
    $scriptPath = if ($PSCommandPath) { $PSCommandPath } else { $MyInvocation.MyCommand.Path }
    $binDir = Split-Path -Parent $scriptPath
    return [System.IO.Path]::GetFullPath((Split-Path -Parent $binDir))
}
```

Same approach as v1: `HOMEBREW_PREFIX` env wins, otherwise the script's
grandparent directory (i.e., the prefix that contains `bin\brew.ps1`).

### Runtime presence check

```powershell
function Test-RuntimeReady {
    param([string]$Prefix)

    $expected = Read-RuntimeManifest -Path (Join-Path $Prefix "runtime-manifest.json")
    $pins = Read-RuntimePins -Path (Join-Path $Prefix "runtime\pins.json")

    foreach ($component in @("mingit", "ruby", "homebrew")) {
        $componentDir = Join-Path $Prefix "runtime\$component"
        if (-not (Test-Path -LiteralPath $componentDir -PathType Container)) {
            return $false
        }
        if ($null -eq $pins -or $pins.$component.sha256 -ne $expected.$component.sha256) {
            return $false
        }
    }
    return $true
}
```

If runtime is missing or any component's recorded SHA256 in
`pins.json` doesn't match `runtime-manifest.json`, the runtime is
not ready and `Install-Runtime` is called.

This handles all the unhappy paths: missing `runtime/`, partial
extraction, prefix copied between machines, manual deletion, version
upgrade where `runtime-manifest.json` advanced.

### Environment contract

```powershell
function Set-HomebrewEnvironment {
    param([string]$Prefix)

    $env:HOMEBREW_BREW_FILE       = Join-Path $Prefix "runtime\homebrew\bin\brew"
    $env:HOMEBREW_PREFIX          = $Prefix
    $env:HOMEBREW_REPOSITORY      = Join-Path $Prefix "runtime\homebrew"
    $env:HOMEBREW_LIBRARY         = Join-Path $Prefix "runtime\homebrew\Library"
    $env:HOMEBREW_CELLAR          = Join-Path $Prefix "Cellar"
    $env:HOMEBREW_CACHE           = Join-Path $Prefix "Cache"
    $env:HOMEBREW_TEMP            = Join-Path $Prefix "Temp"
    $env:HOMEBREW_LOGS            = Join-Path $Prefix "Logs"
    $env:HOMEBREW_SYSTEM          = "Windows"
    $env:HOMEBREW_PROCESSOR       = (Get-HomebrewProcessor)
    $env:HOMEBREW_NO_ANALYTICS    = "1"   # opt out, see HOMEBREW_INTEGRATION.md
    $env:HOMEBREW_NO_AUTO_UPDATE  = "1"   # we pin via runtime-manifest, see ADR 0006

    # Prepend our runtime to PATH for the bash invocation only
    $env:PATH = (Join-Path $Prefix "runtime\mingit\usr\bin") + ";" +
                (Join-Path $Prefix "runtime\ruby\bin")       + ";" +
                $env:PATH
}
```

Full justification for each variable: [HOMEBREW_INTEGRATION.md](HOMEBREW_INTEGRATION.md).

### Intercepted commands

A short list of commands the launcher intercepts instead of forwarding
to upstream Homebrew:

| Command | Reason | Behavior |
| --- | --- | --- |
| `brew self-uninstall` | Removes our launcher state, not just the prefix | Execs `uninstall.ps1` |
| `brew self-update` | Bumps the launcher version + re-runs `Install-Runtime` | Downloads latest release, validates SHA256, swaps launcher files |
| `brew update` | Pinned commit model conflicts with upstream's `git pull` | Prints a message pointing at `brew self-update` (see [ADR 0006](adr/0006-brew-update-semantics.md)) |

All other commands forward to upstream Homebrew transparently.

### Main dispatch

```powershell
try {
    $prefix = Resolve-BrewPrefix

    # Intercepted commands (no runtime needed)
    if ($BrewArgs.Count -gt 0) {
        switch ($BrewArgs[0]) {
            "self-uninstall" { Invoke-SelfUninstall -Prefix $prefix; return }
            "self-update"    { Invoke-SelfUpdate -Prefix $prefix;   return }
        }
    }

    if (-not (Test-RuntimeReady -Prefix $prefix)) {
        Install-Runtime -Prefix $prefix
    }

    Set-HomebrewEnvironment -Prefix $prefix

    # Intercepted commands (after env set, before exec)
    if ($BrewArgs.Count -gt 0 -and $BrewArgs[0] -eq "update") {
        Invoke-UpdateInterception -Prefix $prefix
        return
    }

    Invoke-UpstreamBrew -Prefix $prefix -Arguments $BrewArgs
} catch {
    Write-Error $_.Exception.Message
    exit 1
}
```

### Exec strategy

```powershell
function Invoke-UpstreamBrew {
    param([string]$Prefix, [string[]]$Arguments)

    $bash = Join-Path $Prefix "runtime\mingit\usr\bin\bash.exe"
    $brewScript = Join-Path $Prefix "runtime\homebrew\bin\brew"

    # bash requires forward slashes for the script path
    $brewScriptUnix = $brewScript.Replace("\", "/")

    & $bash $brewScriptUnix @Arguments
    exit $LASTEXITCODE
}
```

We use `&` (call operator) rather than `Start-Process` so stdout, stderr,
stdin, and the exit code propagate naturally. PowerShell's `&` does
not buffer output, which matters for `brew install` progress lines.

### Path handling notes

Bash on Windows accepts both `C:\foo\bar` and `/c/foo/bar` style paths.
MinGit's bash internally translates drive-letter paths. We pass
`HOMEBREW_*` values in their natural Windows form (`C:\Users\...`)
because that's what Homebrew's Ruby code actually does inside.

The single exception is the script path argument to `bash.exe` - bash
parses `C:\path\to\script` as `C:` followed by `\path\...` and fails.
We convert to forward slashes for that one call.

## `install.ps1`

Largely the same shape as v1's `install.ps1`. Different in:

- Extracts only the launcher (bin, *.ps1, runtime-manifest.json,
  optional docs subset). No `Library/`, no `schema/`, no `tests/`.
- Calls `Install-Runtime` as its final step.
- Records the launcher version in `install-manifest.json`.
- Adds **only** `%LOCALAPPDATA%\Homebrew\bin` to User PATH. Does not
  add `runtime\mingit\usr\bin` or `runtime\ruby\bin` - those are
  internal and reached via `brew.ps1` only.

## `uninstall.ps1`

Same as v1's `uninstall.ps1`. Removes:

- `%LOCALAPPDATA%\Homebrew\bin` from User PATH.
- The entire prefix directory.

Refuses to delete a prefix that does not look like a brew-windows
prefix (missing `install-manifest.json` and `runtime/` simultaneously).

## Failure Modes

| Failure | Where | Behavior |
| --- | --- | --- |
| Network failure during `Install-Runtime` | Phase 1 install | Throws. No partial runtime/. Re-run install.ps1 to retry. |
| SHA256 mismatch during `Install-Runtime` | Phase 1 install | Throws with explicit message. Refuses to proceed. |
| `runtime-manifest.json` missing or malformed | `brew.ps1` startup | Throws. Almost always means corrupted release zip. |
| `runtime/` partially extracted | `brew.ps1` startup | Detected by `Test-RuntimeReady`. Triggers full re-install. |
| MinGit bash exits with code 127 (command not found) | After exec | Forwarded as-is. Usually means missing utility in MinGit; recorded as an issue, never silently swallowed. |
| User runs from a path containing characters bash can't represent | After exec | Caught early by `Test-PrefixBashCompatible` (a new check added in Phase 1 once we know what bash chokes on). |

## CI Coverage Of The Launcher

Phase 1 CI must exercise:

- `brew --version` from a fresh prefix (triggers eager bootstrap via install.ps1).
- `brew --version` from an existing prefix (no bootstrap).
- `brew --version` after `runtime/` is manually deleted (triggers lazy bootstrap).
- Hash mismatch by corrupting a runtime component file (`brew.ps1` must refuse to run).
- Exit code propagation (`brew nonexistent-subcommand` returns the same code upstream does).
- Path-with-spaces prefix.
- Argument preservation through the bash call (using a fixture similar to v1's `tests/shim-fuzz.ps1`).

Full CI plan: section in [PHASE_PLAN.md](PHASE_PLAN.md).
