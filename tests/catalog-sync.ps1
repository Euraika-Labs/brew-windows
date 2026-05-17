Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$SyncScript = Join-Path $RepoRoot "scripts\sync-homebrew-catalog.ps1"
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

function New-DemoArchive {
    param(
        [string]$Root,
        [string]$Version,
        [string]$Target
    )

    $payloadRoot = Join-Path $Root "payload-$Target"
    $archiveRoot = Join-Path $payloadRoot "demo-$Version-$Target"
    New-Item -ItemType Directory -Force -Path $archiveRoot | Out-Null

    $demoCmd = @"
@echo off
echo demo $Version %*
"@
    Set-Content -LiteralPath (Join-Path $archiveRoot "demo.exe") -Value $demoCmd -Encoding ASCII

    $archivePath = Join-Path $Root "demo-$Version-$Target.zip"
    Compress-Archive -Path (Join-Path $payloadRoot "*") -DestinationPath $archivePath -Force
    return [ordered]@{
        path = $archivePath
        sha256 = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
        size = (Get-Item -LiteralPath $archivePath).Length
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

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("brew-windows-catalog-sync-test-" + [System.Guid]::NewGuid().ToString("N"))

try {
    $fixtureDir = Join-Path $tempRoot "fixtures"
    $releaseFixtureDir = Join-Path $fixtureDir "github"
    $formulaPath = Join-Path $fixtureDir "formula.json"
    $candidatePath = Join-Path $tempRoot "windows-candidates.json"
    $manifestDir = Join-Path $tempRoot "Formula"
    $cacheDir = Join-Path $tempRoot "cache"
    $prefix = Join-Path $tempRoot "Homebrew Prefix"
    New-Item -ItemType Directory -Force -Path $releaseFixtureDir | Out-Null

    $x64Archive = New-DemoArchive -Root $tempRoot -Version "1.2.3" -Target "x86_64-pc-windows-msvc"
    $arm64Archive = New-DemoArchive -Root $tempRoot -Version "1.2.3" -Target "aarch64-pc-windows-msvc"
    $badArchivePath = Join-Path $tempRoot "odd-1.0.0-x86_64-pc-windows-msvc.zip"
    Set-Content -LiteralPath $badArchivePath -Value "not a zip archive" -Encoding ASCII
    $badArchiveSha256 = (Get-FileHash -LiteralPath $badArchivePath -Algorithm SHA256).Hash.ToLowerInvariant()
    $badArchiveSize = (Get-Item -LiteralPath $badArchivePath).Length

    $formula = @(
        [ordered]@{
            name = "demo"
            full_name = "demo"
            tap = "homebrew/core"
            desc = "Demo CLI used by catalog sync tests"
            license = "MIT"
            homepage = "https://github.com/example/demo"
            versions = [ordered]@{
                stable = "1.2.3"
                bottle = $true
            }
            urls = [ordered]@{
                stable = [ordered]@{
                    url = "https://github.com/example/demo/archive/refs/tags/v1.2.3.tar.gz"
                    checksum = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
                }
            }
            disabled = $false
            deprecated = $false
            dependencies = @()
            executables = @("demo")
            ruby_source_path = "Formula/d/demo.rb"
            ruby_source_checksum = [ordered]@{
                sha256 = "fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210"
            }
        },
        [ordered]@{
            name = "odd"
            full_name = "odd"
            tap = "homebrew/core"
            desc = "Malformed archive used by catalog sync tests"
            license = "MIT"
            homepage = "https://github.com/example/odd"
            versions = [ordered]@{
                stable = "1.0.0"
                bottle = $true
            }
            urls = [ordered]@{
                stable = [ordered]@{
                    url = "https://github.com/example/odd/archive/refs/tags/v1.0.0.tar.gz"
                    checksum = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
                }
            }
            disabled = $false
            deprecated = $false
            dependencies = @()
            executables = @("odd")
            ruby_source_path = "Formula/o/odd.rb"
            ruby_source_checksum = [ordered]@{
                sha256 = "abcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcd"
            }
        }
    )
    $formula | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $formulaPath -Encoding UTF8

    $release = [ordered]@{
        tag_name = "v1.2.3"
        assets = @(
            [ordered]@{
                name = "demo-1.2.3-x86_64-pc-windows-msvc.zip"
                browser_download_url = $x64Archive.path
                digest = "sha256:$($x64Archive.sha256)"
                size = $x64Archive.size
            },
            [ordered]@{
                name = "demo-1.2.3-aarch64-pc-windows-msvc.zip"
                browser_download_url = $arm64Archive.path
                digest = "sha256:$($arm64Archive.sha256)"
                size = $arm64Archive.size
            }
        )
    }
    $release | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $releaseFixtureDir "example__demo.json") -Encoding UTF8
    $badRelease = [ordered]@{
        tag_name = "v1.0.0"
        assets = @(
            [ordered]@{
                name = "odd-1.0.0-x86_64-pc-windows-msvc.zip"
                browser_download_url = $badArchivePath
                digest = "sha256:$badArchiveSha256"
                size = $badArchiveSize
            }
        )
    }
    $badRelease | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $releaseFixtureDir "example__odd.json") -Encoding UTF8

    & $PowerShellExe -NoProfile -ExecutionPolicy Bypass -File $SyncScript `
        -HomebrewFormulaPath $formulaPath `
        -GitHubReleaseFixturesDir $releaseFixtureDir `
        -CandidateOutputPath $candidatePath `
        -ManifestOutputDir $manifestDir `
        -CacheDir $cacheDir `
        -GenerateManifests `
        -FailOnNoCandidates | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "catalog sync script failed"
    }

    $candidateReport = Get-Content -LiteralPath $candidatePath -Raw | ConvertFrom-Json
    Assert-True -Condition ($candidateReport.candidates.Count -eq 2) -Message "expected two candidates"
    $demoCandidate = $candidateReport.candidates | Where-Object { $_.name -eq "demo" } | Select-Object -First 1
    $oddCandidate = $candidateReport.candidates | Where-Object { $_.name -eq "odd" } | Select-Object -First 1
    Assert-True -Condition ($demoCandidate.promotable -eq $true) -Message "demo candidate was not promotable"
    Assert-True -Condition ($oddCandidate.promotable -eq $false) -Message "malformed archive candidate should not be promotable"
    Assert-True -Condition ($oddCandidate.reason -eq "archive-layout-not-promotable") -Message "malformed archive rejection reason was not preserved"

    $manifestPath = Join-Path $manifestDir "demo.json"
    Assert-True -Condition (Test-Path -LiteralPath $manifestPath -PathType Leaf) -Message "demo manifest was not generated"
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    Assert-True -Condition ($manifest.platforms.windows.arches.x64.extract.sourcePath -match "x86_64-pc-windows-msvc") -Message "x64 sourcePath not detected"
    Assert-True -Condition ($manifest.platforms.windows.arches.arm64.extract.sourcePath -match "aarch64-pc-windows-msvc") -Message "arm64 sourcePath not detected"
    Assert-True -Condition ($manifest.bin[0].path -eq "demo.exe") -Message "demo executable path was not normalized"

    $oldPrefix = $env:HOMEBREW_PREFIX
    $oldTapPaths = $env:HOMEBREW_TAP_PATHS
    $oldPath = $env:Path
    $env:HOMEBREW_PREFIX = $prefix
    $env:HOMEBREW_TAP_PATHS = $manifestDir
    $env:Path = "$(Join-Path $prefix "bin");$env:Path"
    try {
        Invoke-Brew -Arguments @("install", "demo") | Out-Null
        Assert-True -Condition (Test-Path -LiteralPath (Join-Path $prefix "Cellar\demo\1.2.3\demo.exe")) -Message "generated demo formula did not install"
        Invoke-Brew -Arguments @("uninstall", "demo") | Out-Null
    } finally {
        $env:HOMEBREW_PREFIX = $oldPrefix
        $env:HOMEBREW_TAP_PATHS = $oldTapPaths
        $env:Path = $oldPath
    }

    Write-Host "Catalog sync tests passed."
} finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
