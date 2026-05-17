Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$BrewScript = Join-Path $RepoRoot "bin\brew.ps1"
$CodexTap = Join-Path $RepoRoot "Library\Taps\euraika-labs\homebrew-core\Formula"

if ($PSVersionTable.PSEdition -eq "Core") {
    $PowerShellExe = Join-Path $PSHOME "pwsh.exe"
} else {
    $PowerShellExe = Join-Path $PSHOME "powershell.exe"
}

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )
    if (-not $Condition) {
        throw $Message
    }
}

function Invoke-Brew {
    param(
        [string[]]$Arguments,
        [int]$ExpectedExitCode = 0
    )

    $output = & $PowerShellExe -NoProfile -ExecutionPolicy Bypass -File $BrewScript @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne $ExpectedExitCode) {
        throw "brew $($Arguments -join ' ') exited $exitCode, expected $ExpectedExitCode.`n$output"
    }
    return ($output -join [Environment]::NewLine)
}

function New-HelloFixture {
    param(
        [string]$Root,
        [string]$TapFormulaDir
    )

    $payloadRoot = Join-Path $Root "payload"
    $payloadBin = Join-Path $payloadRoot "bin"
    New-Item -ItemType Directory -Force -Path $payloadBin | Out-Null

    $helloCmd = @"
@echo off
echo hello 1.0 %*
"@
    Set-Content -LiteralPath (Join-Path $payloadBin "hello.cmd") -Value $helloCmd -Encoding ASCII

    $archivePath = Join-Path $Root "hello-1.0.0.zip"
    Compress-Archive -Path (Join-Path $payloadRoot "*") -DestinationPath $archivePath -Force
    $sha = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()

    $manifest = [ordered]@{
        schemaVersion = "0"
        name = "hello"
        version = "1.0.0"
        description = "Fixture CLI package for Brew Windows tests."
        homepage = "https://example.invalid/hello"
        license = "BSD-2-Clause"
        type = "portable-cli"
        platforms = [ordered]@{
            windows = [ordered]@{
                arches = [ordered]@{
                    x64 = [ordered]@{
                        url = $archivePath
                        sha256 = $sha
                        extract = [ordered]@{
                            type = "zip"
                        }
                    }
                    arm64 = [ordered]@{
                        url = $archivePath
                        sha256 = $sha
                        extract = [ordered]@{
                            type = "zip"
                        }
                    }
                }
            }
        }
        bin = @(
            [ordered]@{
                name = "hello"
                path = "bin/hello.cmd"
            }
        )
        resources = @()
        conflicts = @()
        test = [ordered]@{
            command = "hello world"
            match = "^hello 1.0 world"
        }
        livecheck = [ordered]@{
            type = "none"
        }
    }

    New-Item -ItemType Directory -Force -Path $TapFormulaDir | Out-Null
    $manifest | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath (Join-Path $TapFormulaDir "hello.json") -Encoding UTF8

    $bad = $manifest.PSObject.Copy()
    $bad.name = "bad-hash"
    $bad.platforms.windows.arches.x64.sha256 = ("0" * 64)
    $bad.platforms.windows.arches.arm64.sha256 = ("0" * 64)
    $bad | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath (Join-Path $TapFormulaDir "bad-hash.json") -Encoding UTF8
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("brew-windows-test-" + [System.Guid]::NewGuid().ToString("N"))
$prefix = Join-Path $tempRoot "Homebrew Test Prefix"
$tapFormulaDir = Join-Path $tempRoot "tap\Formula"

try {
    New-HelloFixture -Root $tempRoot -TapFormulaDir $tapFormulaDir

    $oldPrefix = $env:HOMEBREW_PREFIX
    $oldTapPaths = $env:HOMEBREW_TAP_PATHS
    $oldPath = $env:Path
    $env:HOMEBREW_PREFIX = $prefix
    $env:HOMEBREW_TAP_PATHS = "$tapFormulaDir;$CodexTap"
    $env:Path = "$(Join-Path $prefix "bin");$env:Path"

    try {
        $version = Invoke-Brew -Arguments @("--version")
        Assert-True -Condition ($version -match "Brew Windows") -Message "version output did not mention Brew Windows"

        $configJson = Invoke-Brew -Arguments @("--json", "config")
        $config = $configJson | ConvertFrom-Json
        Assert-True -Condition ($config.prefix -eq $prefix) -Message "config prefix mismatch"

        $search = Invoke-Brew -Arguments @("search", "hello")
        Assert-True -Condition ($search -match "hello 1.0.0") -Message "search did not find hello fixture"

        $codexInfoJson = Invoke-Brew -Arguments @("--json", "info", "codex")
        $codexInfo = $codexInfoJson | ConvertFrom-Json
        Assert-True -Condition ($codexInfo.name -eq "codex") -Message "codex manifest was not readable"
        Assert-True -Condition ($codexInfo.url -match "codex-npm-win32") -Message "codex manifest does not use Windows npm bundle"

        $badOutput = Invoke-Brew -Arguments @("--json", "install", "bad-hash") -ExpectedExitCode 1
        Assert-True -Condition ($badOutput -match "Checksum mismatch") -Message "bad hash install did not fail with checksum mismatch"

        Invoke-Brew -Arguments @("install", "hello") | Out-Null
        Assert-True -Condition (Test-Path -LiteralPath (Join-Path $prefix "Cellar\hello\1.0.0\bin\hello.cmd")) -Message "hello keg was not installed"
        Assert-True -Condition (Test-Path -LiteralPath (Join-Path $prefix "bin\hello.ps1")) -Message "hello PowerShell shim missing"
        Assert-True -Condition (Test-Path -LiteralPath (Join-Path $prefix "bin\hello.cmd")) -Message "hello cmd shim missing"

        $helloOutput = & $PowerShellExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $prefix "bin\hello.ps1") "world" 2>&1
        Assert-True -Condition (($helloOutput -join " ") -match "hello 1.0 world") -Message "hello shim did not run correctly"

        $list = Invoke-Brew -Arguments @("list")
        Assert-True -Condition ($list -match "hello") -Message "list did not show installed hello"

        $doctorJson = Invoke-Brew -Arguments @("--json", "doctor")
        $doctor = $doctorJson | ConvertFrom-Json
        Assert-True -Condition ($null -ne $doctor.prefix) -Message "doctor did not emit JSON"

        Invoke-Brew -Arguments @("uninstall", "hello") | Out-Null
        Assert-True -Condition (-not (Test-Path -LiteralPath (Join-Path $prefix "bin\hello.ps1"))) -Message "hello shim remained after uninstall"
    } finally {
        $env:HOMEBREW_PREFIX = $oldPrefix
        $env:HOMEBREW_TAP_PATHS = $oldTapPaths
        $env:Path = $oldPath
    }

    Write-Host "Brew Windows tests passed."
} finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
