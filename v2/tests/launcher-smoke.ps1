Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# ---------------------------------------------------------------------------
# Launcher smoke tests for Brew Windows v2.
#
# Exercises the command-dispatch paths in v2/launcher/bin/brew.ps1 that do
# NOT require a real runtime install. Every test creates a throwaway prefix
# under $env:TEMP, copies in just enough of the launcher payload to exercise
# the path under test, invokes brew.ps1 in a fresh PowerShell child process,
# and asserts on the exit code and output stream.
# ---------------------------------------------------------------------------

$RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
$LauncherRoot = Join-Path $RepoRoot "v2\launcher"
$BrewScriptSource = Join-Path $LauncherRoot "bin\brew.ps1"
$BrewCmdSource = Join-Path $LauncherRoot "bin\brew.cmd"

if ($PSVersionTable.PSEdition -eq "Core") {
    $PowerShellExe = Join-Path $PSHOME "pwsh.exe"
} else {
    $PowerShellExe = Join-Path $PSHOME "powershell.exe"
}

# ---------------------------------------------------------------------------
# Assertion helpers (lifted verbatim from v1/tests/shim-fuzz.ps1:14-40).
# ---------------------------------------------------------------------------

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )
    if (-not $Condition) {
        throw $Message
    }
}

function Assert-StringArrayEqual {
    param(
        [string[]]$Actual,
        [string[]]$Expected,
        [string]$Message
    )

    if ($Actual.Count -ne $Expected.Count) {
        throw "$Message Count mismatch. Expected $($Expected.Count), got $($Actual.Count). Actual: $($Actual -join "|")"
    }

    for ($index = 0; $index -lt $Expected.Count; $index += 1) {
        if ($Actual[$index] -cne $Expected[$index]) {
            throw "$Message Mismatch at index $index. Expected '$($Expected[$index])', got '$($Actual[$index])'."
        }
    }
}

# ---------------------------------------------------------------------------
# Local helpers.
# ---------------------------------------------------------------------------

function New-TestPrefix {
    param([string]$Root, [string]$Name)

    $prefix = Join-Path $Root $Name
    New-Item -ItemType Directory -Force -Path (Join-Path $prefix "bin") | Out-Null
    Copy-Item -LiteralPath $BrewScriptSource -Destination (Join-Path $prefix "bin\brew.ps1") -Force
    Copy-Item -LiteralPath $BrewCmdSource -Destination (Join-Path $prefix "bin\brew.cmd") -Force
    return $prefix
}

function New-PlaceholderManifest {
    param([string]$Prefix)

    # Tests construct their own placeholder manifest rather than copying the
    # shipped runtime-manifest.json, so the test suite remains decoupled from
    # whatever pins the shipped manifest currently carries. The shipped
    # manifest is pinned with real SHA256s once pin-runtime.ps1 has run.
    $manifest = [ordered]@{
        schemaVersion      = "0"
        launcherVersion    = "0.1.0-dev"
        generatedAt        = "2026-05-24T15:30:00Z"
        placeholdersFilled = $false
        components = [ordered]@{
            mingit = [ordered]@{
                version       = "2.49.0"
                url           = "https://example.invalid/mingit.zip"
                sha256        = ("0" * 64)
                extract       = "zip"
                stripTopLevel = $false
            }
            ruby = [ordered]@{
                version       = "3.3.6-1"
                url           = "https://example.invalid/ruby.7z"
                sha256        = ("0" * 64)
                extract       = "7z"
                stripTopLevel = $true
            }
            homebrew = [ordered]@{
                ref            = ("0" * 40)
                url            = "https://example.invalid/brew.git"
                expectedTreeId = ("0" * 40)
            }
        }
        patches = @(
            [ordered]@{
                path      = "patches/windows-os-detection.patch"
                sha256    = ("0" * 64)
                appliesTo = "homebrew"
            }
        )
    }
    $manifest | ConvertTo-Json -Depth 10 |
        Set-Content -LiteralPath (Join-Path $Prefix "runtime-manifest.json") -Encoding UTF8
}

function New-FakeRuntime {
    param([string]$Prefix)

    # Place fake runtime directories. The launcher's Test-RuntimeReady only
    # checks for the *directory* existence and a pins.json that matches the
    # placeholder hashes already in the manifest - it does NOT validate the
    # contents of the runtime tree. This is exactly what we need to exercise
    # the post-bootstrap dispatch paths without a real 130 MB download.
    #
    # Pair this with New-PlaceholderManifest so the placeholder hashes in
    # the manifest match the placeholder hashes in pins.json.
    foreach ($component in @("mingit", "ruby", "homebrew")) {
        New-Item -ItemType Directory -Force -Path (Join-Path $Prefix "runtime\$component") | Out-Null
    }

    $pins = [ordered]@{
        schemaVersion = "0"
        installedAt = "2026-05-24T00:00:00Z"
        launcherVersion = "0.1.0-dev"
        components = [ordered]@{
            mingit = [ordered]@{ version = "2.49.0"; sha256 = ("0" * 64) }
            ruby = [ordered]@{ version = "3.3.6-1"; sha256 = ("0" * 64) }
            homebrew = [ordered]@{ ref = ("0" * 40); treeId = ("0" * 40) }
        }
        patchesApplied = @()
    }
    $pins | ConvertTo-Json -Depth 10 |
        Set-Content -LiteralPath (Join-Path $Prefix "runtime\pins.json") -Encoding UTF8
}

function Invoke-LauncherIsolated {
    param(
        [string]$Prefix,
        [string[]]$Arguments
    )

    $brewPs1 = Join-Path $Prefix "bin\brew.ps1"

    # Build an inline expression that clears HOMEBREW_PREFIX so the launcher
    # resolves the prefix from the script's grandparent directory. This keeps
    # each test isolated from any HOMEBREW_PREFIX the harness inherited.
    $argLiterals = @()
    foreach ($a in $Arguments) {
        $argLiterals += ("'" + $a.Replace("'", "''") + "'")
    }
    $argList = if ($argLiterals.Count -gt 0) { $argLiterals -join "," } else { "" }

    $command = "`$env:HOMEBREW_PREFIX = `$null; & '" + $brewPs1.Replace("'", "''") + "'"
    if ($argList) {
        $command += " " + $argList
    }
    $command += "; exit `$LASTEXITCODE"

    # Use System.Diagnostics.Process so the child's stderr is captured as
    # plain text rather than wrapped in PowerShell ErrorRecord objects (which
    # under StrictMode + $ErrorActionPreference=Stop would terminate the
    # harness on the first Write-Error from the launcher's catch block).
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $PowerShellExe
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true

    $psi.Arguments = '-NoProfile -ExecutionPolicy Bypass -Command "' + $command.Replace('"', '\"') + '"'

    $proc = [System.Diagnostics.Process]::Start($psi)
    $stdout = $proc.StandardOutput.ReadToEnd()
    $stderr = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()

    return [ordered]@{
        ExitCode = $proc.ExitCode
        Output = ($stdout + $stderr)
    }
}

# ---------------------------------------------------------------------------
# Test driver.
# ---------------------------------------------------------------------------

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("brew-windows-v2-test-" + [System.Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null

$savedPrefix = $env:HOMEBREW_PREFIX
$savedProcessor = $env:HOMEBREW_PROCESSOR

try {
    # ----- Test 1: self-update + self-uninstall intercept fire pre-runtime -

    Write-Host "==> Test 1: self-update and self-uninstall intercepts work without runtime"
    $prefix1 = New-TestPrefix -Root $tempRoot -Name "t1-bare"
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $prefix1 "runtime-manifest.json"))) `
        "Test 1 setup: runtime-manifest.json must NOT be present in the bare prefix."

    $r = Invoke-LauncherIsolated -Prefix $prefix1 -Arguments @("self-update")
    Assert-True ($r.ExitCode -eq 0) "Test 1: brew self-update should exit 0 (stub). Got $($r.ExitCode). Output: $($r.Output)"
    Assert-True ($r.Output -match "self-update") "Test 1: self-update output should mention self-update. Got: $($r.Output)"

    $r = Invoke-LauncherIsolated -Prefix $prefix1 -Arguments @("self-uninstall")
    Assert-True ($r.ExitCode -ne 0) "Test 1: brew self-uninstall should fail (no uninstall.ps1). Got exit 0."
    Assert-True ($r.Output -match "uninstall") "Test 1: self-uninstall error should mention 'uninstall'. Got: $($r.Output)"
    Assert-True ($r.Output -notmatch "runtime-manifest.json") `
        "Test 1: self-uninstall must fail BEFORE the runtime check. Got: $($r.Output)"
    Write-Host "Test 1 passed."

    # ----- Test 2: Missing runtime-manifest.json -----------------------------

    Write-Host "==> Test 2: Missing runtime-manifest.json fails cleanly"
    $prefix2 = New-TestPrefix -Root $tempRoot -Name "t2-no-manifest"

    $r = Invoke-LauncherIsolated -Prefix $prefix2 -Arguments @("--version")
    Assert-True ($r.ExitCode -ne 0) "Test 2: brew --version should fail when runtime-manifest.json is missing. Got exit 0."
    Assert-True ($r.Output -match "runtime-manifest.json") `
        "Test 2: error should mention runtime-manifest.json. Got: $($r.Output)"
    Write-Host "Test 2 passed."

    # ----- Test 3: Manifest present, runtime absent (placeholders not filled)

    Write-Host "==> Test 3: Runtime not bootstrapped triggers placeholders abort"
    $prefix3 = New-TestPrefix -Root $tempRoot -Name "t3-manifest-no-runtime"
    New-PlaceholderManifest -Prefix $prefix3

    $r = Invoke-LauncherIsolated -Prefix $prefix3 -Arguments @("--version")
    Assert-True ($r.ExitCode -ne 0) "Test 3: brew --version should fail when runtime is not pinned. Got exit 0."
    Assert-True (($r.Output -match "placeholdersFilled") -or ($r.Output -match "pin-runtime.ps1")) `
        "Test 3: error should mention placeholdersFilled or pin-runtime.ps1. Got: $($r.Output)"
    Write-Host "Test 3 passed."

    # ----- Test 4: brew update intercept fires when runtime is "ready" -------

    Write-Host "==> Test 4: brew update intercept message points to brew self-update"
    $prefix4 = New-TestPrefix -Root $tempRoot -Name "t4-update-intercept"
    New-PlaceholderManifest -Prefix $prefix4
    New-FakeRuntime -Prefix $prefix4

    $r = Invoke-LauncherIsolated -Prefix $prefix4 -Arguments @("update")
    Assert-True ($r.ExitCode -eq 0) "Test 4: brew update should exit 0 (intercepted). Got $($r.ExitCode). Output: $($r.Output)"
    Assert-True ($r.Output -match "brew self-update") `
        "Test 4: update intercept should redirect to brew self-update. Got: $($r.Output)"
    Write-Host "Test 4 passed."

    # ----- Test 5: An exec-attempting command fails when bash.exe is absent --

    Write-Host "==> Test 5: brew config exec fails cleanly when MinGit bash is absent"
    $prefix5 = New-TestPrefix -Root $tempRoot -Name "t5-config-noexec"
    New-PlaceholderManifest -Prefix $prefix5
    New-FakeRuntime -Prefix $prefix5
    # We deliberately do NOT create runtime/mingit/usr/bin/bash.exe; the
    # launcher should fall through Test-RuntimeReady (dirs + matching pins.json)
    # then Set-HomebrewEnvironment then Invoke-UpstreamBrew, which checks for
    # bash.exe and throws a specific message before attempting the exec.

    $r = Invoke-LauncherIsolated -Prefix $prefix5 -Arguments @("config")
    Assert-True ($r.ExitCode -ne 0) "Test 5: brew config should fail when bash.exe is missing. Got exit 0."
    Assert-True ($r.Output -match "MinGit bash not found") `
        "Test 5: error should mention 'MinGit bash not found'. Got: $($r.Output)"
    Write-Host "Test 5 passed."

    # ----- Test 6: Prefix containing spaces ---------------------------------

    Write-Host "==> Test 6: Prefix with spaces round-trips through launcher path handling"
    $prefix6 = New-TestPrefix -Root $tempRoot -Name "Homebrew V2 Test Prefix"
    New-PlaceholderManifest -Prefix $prefix6
    Assert-True ($prefix6 -match " ") "Test 6 setup: prefix must contain a space. Got: $prefix6"

    $r = Invoke-LauncherIsolated -Prefix $prefix6 -Arguments @("--version")
    Assert-True ($r.ExitCode -ne 0) "Test 6: brew --version should fail (placeholders still present). Got exit 0."
    Assert-True (($r.Output -match "placeholdersFilled") -or ($r.Output -match "pin-runtime.ps1")) `
        "Test 6: error should mention placeholdersFilled or pin-runtime.ps1. Got: $($r.Output)"
    # The "Homebrew V2 Test Prefix" substring is the round-trip evidence: if the
    # launcher mangled the path (e.g. lost the spaces, or only quoted part of
    # it), this assertion would fail. Install-Runtime prints the prefix in its
    # opening "Bootstrapping Homebrew runtime..." block and the manifest path
    # in the placeholders-filled error message - either path includes the
    # prefix verbatim.
    #
    # Windows PowerShell wraps Write-Error output at $Host.UI.RawUI.BufferSize
    # (default 80 columns under -NonInteractive). That can split the path
    # substring across a newline mid-word ("Homebrew V2 Test\nPrefix\..."),
    # which makes a literal regex match miss. Collapse all whitespace runs
    # to a single space before checking; the round-trip evidence (no chars
    # dropped, no chars added) is still preserved.
    $outputCollapsed = ($r.Output -replace "\s+", " ")
    Assert-True ($outputCollapsed -match [regex]::Escape("Homebrew V2 Test Prefix")) `
        "Test 6: error or status output should contain the prefix path with spaces preserved. Got: $($r.Output)"
    Write-Host "Test 6 passed."

    Write-Host ""
    Write-Host "All launcher-smoke tests passed."
} finally {
    $env:HOMEBREW_PREFIX = $savedPrefix
    $env:HOMEBREW_PROCESSOR = $savedProcessor
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
