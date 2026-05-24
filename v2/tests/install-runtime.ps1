Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# ---------------------------------------------------------------------------
# Install-Runtime unit tests for Brew Windows v2.
#
# These tests exercise the bootstrap helpers in v2/launcher/bin/brew.ps1 in
# isolation - no network, no real archives, no MinGit/Ruby/Homebrew. We do
# this by loading brew.ps1 with its "# Main dispatch" tail block neutralised,
# then calling the helper functions directly.
#
# This is a deliberate test-only pattern. We do NOT modify the launcher
# source; we transform a copy in memory, write it to a temp file, and
# dot-source the temp file. The trade-off is that any helper rename in
# brew.ps1 will surface here as a clear failure ("function X not found").
# ---------------------------------------------------------------------------

$RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
$LauncherRoot = Join-Path $RepoRoot "v2\launcher"
$BrewScript = Join-Path $LauncherRoot "bin\brew.ps1"

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

function Assert-Throws {
    param(
        [ScriptBlock]$Action,
        [string]$MessagePattern,
        [string]$Context
    )

    $caught = $false
    $message = ""
    try {
        & $Action
    } catch {
        $caught = $true
        $message = [string]$_.Exception.Message
    }

    if (-not $caught) {
        throw "${Context}: expected an exception but the action completed without error."
    }
    if (-not ($message -match $MessagePattern)) {
        throw "${Context}: exception message did not match /$MessagePattern/. Got: $message"
    }
}

# ---------------------------------------------------------------------------
# Test-harness pattern: load brew.ps1 functions without main dispatch.
# ---------------------------------------------------------------------------

function Get-TestableBrewScript {
    param([string]$BrewPs1)

    $content = Get-Content -LiteralPath $BrewPs1 -Raw
    $marker = '# Main dispatch'
    $idx = $content.IndexOf($marker)
    if ($idx -lt 0) {
        throw "Main dispatch marker not found in $BrewPs1. The test harness needs the '$marker' comment to know where to truncate."
    }
    return $content.Substring(0, $idx) + "`nreturn`n"
}

function New-TestableBrewFile {
    param([string]$TempRoot)

    $testableContent = Get-TestableBrewScript -BrewPs1 $BrewScript
    $testableScript = Join-Path $TempRoot "brew-testable.ps1"
    # The truncated copy is a .ps1 with no `param([Parameter(...)])` consumer
    # for $args - dot-sourcing it as a function body is fine.
    Set-Content -LiteralPath $testableScript -Value $testableContent -Encoding UTF8
    return $testableScript
}

# Build the truncated file once and dot-source it into THIS scope so every
# test below can call Install-Runtime, Test-RuntimeReady, Assert-FileHash,
# Assert-PathUnderPrefix, Move-RuntimeItem, and Get-DownloadedRuntimeArtifact
# directly.
$harnessRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("brew-windows-v2-test-" + [System.Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $harnessRoot | Out-Null

$savedPrefix = $env:HOMEBREW_PREFIX
$savedProcessor = $env:HOMEBREW_PROCESSOR

try {
    $testableScript = New-TestableBrewFile -TempRoot $harnessRoot
    . $testableScript

    # Sanity-check the harness loaded everything we need.
    foreach ($fn in @(
        "Install-Runtime", "Test-RuntimeReady", "Read-RuntimeManifest",
        "Assert-FileHash", "Assert-PathUnderPrefix", "Move-RuntimeItem",
        "Get-DownloadedRuntimeArtifact"
    )) {
        Assert-True ($null -ne (Get-Command -Name $fn -ErrorAction SilentlyContinue)) `
            "Harness: required function $fn was not exposed after dot-sourcing $testableScript."
    }

    # -----------------------------------------------------------------------
    # Helpers for manifest fixtures.
    # -----------------------------------------------------------------------

    function New-PlaceholderManifest {
        param([string]$Prefix)

        $manifest = [ordered]@{
            schemaVersion = "0"
            launcherVersion = "0.1.0-dev"
            generatedAt = "2026-05-24T15:30:00Z"
            placeholdersFilled = $false
            components = [ordered]@{
                mingit = [ordered]@{
                    version = "2.49.0"
                    url = "https://example.invalid/mingit.zip"
                    sha256 = ("0" * 64)
                    extract = "zip"
                    stripTopLevel = $false
                }
                ruby = [ordered]@{
                    version = "3.3.6-1"
                    url = "https://example.invalid/ruby.7z"
                    sha256 = ("0" * 64)
                    extract = "7z"
                    stripTopLevel = $true
                }
                homebrew = [ordered]@{
                    ref = ("0" * 40)
                    url = "https://github.com/Homebrew/brew.git"
                    expectedTreeId = ("0" * 40)
                }
            }
            patches = @()
        }
        $manifest | ConvertTo-Json -Depth 10 |
            Set-Content -LiteralPath (Join-Path $Prefix "runtime-manifest.json") -Encoding UTF8
    }

    function New-FilledManifest {
        param(
            [string]$Prefix,
            [string]$MingitSha,
            [string]$RubySha,
            [string]$HomebrewTreeId
        )

        $manifest = [ordered]@{
            schemaVersion = "0"
            launcherVersion = "0.1.0-dev"
            generatedAt = "2026-05-24T15:30:00Z"
            placeholdersFilled = $true
            components = [ordered]@{
                mingit = [ordered]@{
                    version = "2.49.0"
                    url = "https://example.invalid/mingit.zip"
                    sha256 = $MingitSha
                    extract = "zip"
                    stripTopLevel = $false
                }
                ruby = [ordered]@{
                    version = "3.3.6-1"
                    url = "https://example.invalid/ruby.7z"
                    sha256 = $RubySha
                    extract = "7z"
                    stripTopLevel = $true
                }
                homebrew = [ordered]@{
                    ref = ("d" * 40)
                    url = "https://github.com/Homebrew/brew.git"
                    expectedTreeId = $HomebrewTreeId
                }
            }
            patches = @()
        }
        $manifest | ConvertTo-Json -Depth 10 |
            Set-Content -LiteralPath (Join-Path $Prefix "runtime-manifest.json") -Encoding UTF8
    }

    function Write-PinsFile {
        param(
            [string]$Prefix,
            [string]$MingitSha,
            [string]$RubySha,
            [string]$HomebrewTreeId
        )

        $pins = [ordered]@{
            schemaVersion = "0"
            installedAt = "2026-05-24T00:00:00Z"
            launcherVersion = "0.1.0-dev"
            components = [ordered]@{
                mingit = [ordered]@{ version = "2.49.0"; sha256 = $MingitSha }
                ruby = [ordered]@{ version = "3.3.6-1"; sha256 = $RubySha }
                homebrew = [ordered]@{ ref = ("d" * 40); treeId = $HomebrewTreeId }
            }
            patchesApplied = @()
        }
        New-Item -ItemType Directory -Force -Path (Join-Path $Prefix "runtime") | Out-Null
        $pins | ConvertTo-Json -Depth 10 |
            Set-Content -LiteralPath (Join-Path $Prefix "runtime\pins.json") -Encoding UTF8
    }

    function New-FakeRuntimeDirs {
        param([string]$Prefix)
        foreach ($component in @("mingit", "ruby", "homebrew")) {
            New-Item -ItemType Directory -Force -Path (Join-Path $Prefix "runtime\$component") | Out-Null
        }
    }

    function New-CleanPrefix {
        param([string]$Root, [string]$Name)
        $prefix = Join-Path $Root $Name
        New-Item -ItemType Directory -Force -Path $prefix | Out-Null
        return $prefix
    }

    # -----------------------------------------------------------------------
    # Test 1: Install-Runtime aborts when placeholdersFilled is false.
    # -----------------------------------------------------------------------

    Write-Host "==> Test 1: Install-Runtime refuses a placeholder manifest"
    $p1 = New-CleanPrefix -Root $harnessRoot -Name "t1-placeholders"
    New-PlaceholderManifest -Prefix $p1

    Assert-Throws -Context "Test 1" -MessagePattern "placeholdersFilled|pin-runtime\.ps1" -Action {
        Install-Runtime -Prefix $p1
    }
    Write-Host "Test 1 passed."

    # -----------------------------------------------------------------------
    # Test 2: Test-RuntimeReady returns false when runtime/ is missing.
    # -----------------------------------------------------------------------

    Write-Host "==> Test 2: Test-RuntimeReady is false when runtime/ is absent"
    $p2 = New-CleanPrefix -Root $harnessRoot -Name "t2-no-runtime-dir"
    New-PlaceholderManifest -Prefix $p2

    $ready = Test-RuntimeReady -Prefix $p2
    Assert-True (-not $ready) "Test 2: Test-RuntimeReady should return `$false when runtime/ does not exist."
    Write-Host "Test 2 passed."

    # -----------------------------------------------------------------------
    # Test 3: Test-RuntimeReady detects pins.json drift.
    # -----------------------------------------------------------------------

    Write-Host "==> Test 3: Test-RuntimeReady detects pins.json hash drift"
    $p3 = New-CleanPrefix -Root $harnessRoot -Name "t3-pins-drift"
    $manifestSha = "a" * 64
    $manifestSha2 = "b" * 64
    $manifestTree = "c" * 40
    New-FilledManifest -Prefix $p3 -MingitSha $manifestSha -RubySha $manifestSha2 -HomebrewTreeId $manifestTree
    New-FakeRuntimeDirs -Prefix $p3
    # pins.json carries DIFFERENT hashes -> drift detected.
    Write-PinsFile -Prefix $p3 -MingitSha ("1" * 64) -RubySha ("2" * 64) -HomebrewTreeId ("3" * 40)

    $ready = Test-RuntimeReady -Prefix $p3
    Assert-True (-not $ready) "Test 3: Test-RuntimeReady should return `$false on pins.json drift."
    Write-Host "Test 3 passed."

    # -----------------------------------------------------------------------
    # Test 4: Test-RuntimeReady returns true when pins match.
    # -----------------------------------------------------------------------

    Write-Host "==> Test 4: Test-RuntimeReady is true when pins match the manifest"
    $p4 = New-CleanPrefix -Root $harnessRoot -Name "t4-pins-match"
    New-FilledManifest -Prefix $p4 -MingitSha $manifestSha -RubySha $manifestSha2 -HomebrewTreeId $manifestTree
    New-FakeRuntimeDirs -Prefix $p4
    Write-PinsFile -Prefix $p4 -MingitSha $manifestSha -RubySha $manifestSha2 -HomebrewTreeId $manifestTree

    $ready = Test-RuntimeReady -Prefix $p4
    Assert-True $ready "Test 4: Test-RuntimeReady should return `$true when pins.json hashes match the manifest."
    Write-Host "Test 4 passed."

    # -----------------------------------------------------------------------
    # Test 5: Get-DownloadedRuntimeArtifact rejects non-HTTPS URLs.
    # -----------------------------------------------------------------------

    Write-Host "==> Test 5: Get-DownloadedRuntimeArtifact rejects http:// (non-HTTPS) URLs"
    $p5 = New-CleanPrefix -Root $harnessRoot -Name "t5-non-https"
    $cacheDir = Join-Path $p5 "Cache"
    New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null
    $logPath = Join-Path $p5 "test.log"

    Assert-Throws -Context "Test 5" -MessagePattern "(?i)https|non-HTTPS" -Action {
        Get-DownloadedRuntimeArtifact `
            -Url "http://example.invalid/foo.zip" `
            -ExpectedSha256 ("a" * 64) `
            -CacheDir $cacheDir `
            -ComponentName "test" `
            -LogPath $logPath
    }
    Write-Host "Test 5 passed."

    # -----------------------------------------------------------------------
    # Test 6: Assert-FileHash flags a checksum mismatch.
    # -----------------------------------------------------------------------

    Write-Host "==> Test 6: Assert-FileHash throws on checksum mismatch"
    $p6 = New-CleanPrefix -Root $harnessRoot -Name "t6-hash-mismatch"
    $sample = Join-Path $p6 "sample.txt"
    Set-Content -LiteralPath $sample -Value "Brew Windows v2 test fixture content." -Encoding UTF8

    # Compute the real hash so the test self-documents the "good" path:
    # this is exactly the comparison Assert-FileHash performs.
    $actualHash = (Get-FileHash -LiteralPath $sample -Algorithm SHA256).Hash.ToLowerInvariant()
    Assert-True (-not [string]::IsNullOrWhiteSpace($actualHash)) "Test 6 setup: failed to compute sample hash."

    Assert-Throws -Context "Test 6" -MessagePattern "Checksum mismatch" -Action {
        Assert-FileHash -Path $sample -ExpectedSha256 ("0" * 64)
    }

    # Good-path sanity check: the same call with the real hash must NOT throw.
    Assert-FileHash -Path $sample -ExpectedSha256 $actualHash
    Write-Host "Test 6 passed."

    # -----------------------------------------------------------------------
    # Test 7: Assert-PathUnderPrefix refuses an out-of-prefix path.
    # -----------------------------------------------------------------------

    Write-Host "==> Test 7: Assert-PathUnderPrefix refuses paths outside the prefix"
    $p7 = New-CleanPrefix -Root $harnessRoot -Name "t7-path-guard"

    Assert-Throws -Context "Test 7" -MessagePattern "HOMEBREW_PREFIX" -Action {
        Assert-PathUnderPrefix -Path "C:\Windows\System32" -Prefix $p7
    }

    # Good-path sanity check: a path inside the prefix must NOT throw.
    Assert-PathUnderPrefix -Path (Join-Path $p7 "Cache\thing") -Prefix $p7
    Write-Host "Test 7 passed."

    # -----------------------------------------------------------------------
    # Test 8: Move-RuntimeItem successfully relocates a file.
    # -----------------------------------------------------------------------

    Write-Host "==> Test 8: Move-RuntimeItem swap moves source to destination"
    $p8 = New-CleanPrefix -Root $harnessRoot -Name "t8-move"
    $src = Join-Path $p8 "src.txt"
    $dst = Join-Path $p8 "dst.txt"
    Set-Content -LiteralPath $src -Value "movable" -Encoding UTF8
    Assert-True (Test-Path -LiteralPath $src) "Test 8 setup: source file missing."

    Move-RuntimeItem -LiteralSource $src -LiteralDestination $dst
    Assert-True (Test-Path -LiteralPath $dst) "Test 8: destination should exist after Move-RuntimeItem."
    Assert-True (-not (Test-Path -LiteralPath $src)) "Test 8: source should no longer exist after Move-RuntimeItem."
    Write-Host "Test 8 passed."

    Write-Host ""
    Write-Host "All install-runtime tests passed."
} finally {
    $env:HOMEBREW_PREFIX = $savedPrefix
    $env:HOMEBREW_PROCESSOR = $savedProcessor
    Remove-Item -LiteralPath $harnessRoot -Recurse -Force -ErrorAction SilentlyContinue
}
