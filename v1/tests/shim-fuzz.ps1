Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$BrewScript = Join-Path $RepoRoot "bin\brew.ps1"

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

function New-ArgvFixture {
    param(
        [string]$Root,
        [string]$TapFormulaDir
    )

    $payloadRoot = Join-Path $Root "payload"
    $payloadBin = Join-Path $payloadRoot "bin"
    New-Item -ItemType Directory -Force -Path $payloadBin | Out-Null

    $argvScript = @'
$payload = [ordered]@{
    count = $args.Count
    args = @($args)
}

if (-not [string]::IsNullOrWhiteSpace($env:BREW_WINDOWS_ARGV_CAPTURE)) {
    $payload | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $env:BREW_WINDOWS_ARGV_CAPTURE -Encoding UTF8
}

$exitCode = 0
if (-not [string]::IsNullOrWhiteSpace($env:BREW_WINDOWS_ARGV_EXIT_CODE)) {
    $exitCode = [int]$env:BREW_WINDOWS_ARGV_EXIT_CODE
}

exit $exitCode
'@
    Set-Content -LiteralPath (Join-Path $payloadBin "argv-target.ps1") -Value $argvScript -Encoding ASCII

    $archivePath = Join-Path $Root "argv-1.0.0.zip"
    Compress-Archive -Path (Join-Path $payloadRoot "*") -DestinationPath $archivePath -Force
    $sha = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()

    $manifest = [ordered]@{
        schemaVersion = "0"
        name = "argv"
        version = "1.0.0"
        description = "Fixture CLI package for Brew Windows shim fuzz tests."
        homepage = "https://example.invalid/argv"
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
                name = "argv"
                path = "bin/argv-target.ps1"
            }
        )
        resources = @()
        conflicts = @()
        test = [ordered]@{
            command = "argv smoke"
            match = ""
        }
        livecheck = [ordered]@{
            type = "none"
        }
    }

    New-Item -ItemType Directory -Force -Path $TapFormulaDir | Out-Null
    $manifest | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath (Join-Path $TapFormulaDir "argv.json") -Encoding UTF8
}

function Invoke-ShimAndReadCapture {
    param(
        [string]$ShimPath,
        [string[]]$Arguments,
        [string]$CapturePath,
        [int]$ExpectedExitCode
    )

    Remove-Item -LiteralPath $CapturePath -Force -ErrorAction SilentlyContinue
    $env:BREW_WINDOWS_ARGV_CAPTURE = $CapturePath
    $env:BREW_WINDOWS_ARGV_EXIT_CODE = [string]$ExpectedExitCode
    try {
        if ($ShimPath.EndsWith(".ps1", [System.StringComparison]::OrdinalIgnoreCase)) {
            & $PowerShellExe -NoProfile -ExecutionPolicy Bypass -File $ShimPath @Arguments 2>&1 | Out-Null
        } else {
            $quotedArgs = @('"' + $ShimPath + '"')
            foreach ($argument in $Arguments) {
                $quotedArgs += '"' + $argument.Replace('"', '\"') + '"'
            }
            & cmd.exe /d /s /c ($quotedArgs -join " ") 2>&1 | Out-Null
        }
        $exitCode = $LASTEXITCODE
    } finally {
        Remove-Item Env:\BREW_WINDOWS_ARGV_CAPTURE -ErrorAction SilentlyContinue
        Remove-Item Env:\BREW_WINDOWS_ARGV_EXIT_CODE -ErrorAction SilentlyContinue
    }

    Assert-True -Condition ($exitCode -eq $ExpectedExitCode) -Message "$ShimPath returned $exitCode instead of $ExpectedExitCode"
    Assert-True -Condition (Test-Path -LiteralPath $CapturePath -PathType Leaf) -Message "$ShimPath did not write capture file"
    return (Get-Content -LiteralPath $CapturePath -Raw | ConvertFrom-Json)
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("brew-windows-shim-fuzz-" + [System.Guid]::NewGuid().ToString("N"))
$prefix = Join-Path $tempRoot "Homebrew Shim Prefix"
$tapFormulaDir = Join-Path $tempRoot "tap\Formula"

try {
    New-ArgvFixture -Root $tempRoot -TapFormulaDir $tapFormulaDir

    $oldPrefix = $env:HOMEBREW_PREFIX
    $oldTapPaths = $env:HOMEBREW_TAP_PATHS
    $oldPath = $env:Path
    $env:HOMEBREW_PREFIX = $prefix
    $env:HOMEBREW_TAP_PATHS = $tapFormulaDir
    $env:Path = "$(Join-Path $prefix "bin");$env:Path"

    try {
        Invoke-Brew -Arguments @("install", "argv") | Out-Null

        $expectedArgs = @(
            "plain",
            "with spaces",
            "symbols-._=+,",
            "paren(value)",
            "bracket[1]",
            "amp&value",
            "caret^value",
            "single'quote",
            "path C:\Temp\Brew Windows"
        )

        $ps1Shim = Join-Path $prefix "bin\argv.ps1"
        $cmdShim = Join-Path $prefix "bin\argv.cmd"
        $ps1Capture = Join-Path $tempRoot "ps1-capture.json"
        $cmdCapture = Join-Path $tempRoot "cmd-capture.json"

        $ps1Result = Invoke-ShimAndReadCapture -ShimPath $ps1Shim -Arguments $expectedArgs -CapturePath $ps1Capture -ExpectedExitCode 37
        Assert-StringArrayEqual -Actual @($ps1Result.args) -Expected $expectedArgs -Message "PowerShell shim argument preservation failed."

        $cmdResult = Invoke-ShimAndReadCapture -ShimPath $cmdShim -Arguments $expectedArgs -CapturePath $cmdCapture -ExpectedExitCode 42
        Assert-StringArrayEqual -Actual @($cmdResult.args) -Expected $expectedArgs -Message "cmd shim argument preservation failed."

        Invoke-Brew -Arguments @("uninstall", "argv") | Out-Null
    } finally {
        $env:HOMEBREW_PREFIX = $oldPrefix
        $env:HOMEBREW_TAP_PATHS = $oldTapPaths
        $env:Path = $oldPath
    }

    Write-Host "Shim fuzz tests passed."
} finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
