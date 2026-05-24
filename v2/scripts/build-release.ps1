param(
    [string]$Version = "dev",
    [string]$OutputDir = "dist"
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# v2Root is the v2/ tree. Output dir resolves under v2/ (default v2/dist/).
$v2Root = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$launcherRoot = Join-Path $v2Root "launcher"
$resolvedOutput = [System.IO.Path]::GetFullPath((Join-Path $v2Root $OutputDir))

function Write-Step {
    param([string]$Message)
    Write-Host "==> $Message"
}

if (-not (Test-Path -LiteralPath $launcherRoot -PathType Container)) {
    throw "Launcher directory not found: $launcherRoot"
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("brew-windows-v2-release-" + [System.Guid]::NewGuid().ToString("N"))
$payloadRoot = Join-Path $tempRoot "payload"

try {
    Write-Step "Staging payload at $payloadRoot"
    New-Item -ItemType Directory -Force -Path $payloadRoot | Out-Null

    # Directories that must exist in the release zip.
    foreach ($dir in @("bin", "patches")) {
        $src = Join-Path $launcherRoot $dir
        if (-not (Test-Path -LiteralPath $src -PathType Container)) {
            throw "Required directory missing from launcher: $src"
        }
        Copy-Item -LiteralPath $src -Destination (Join-Path $payloadRoot $dir) -Recurse -Force
    }

    # Required top-level files. install.ps1 is uploaded as a sibling asset,
    # so it is intentionally NOT placed inside the zip payload.
    foreach ($file in @("runtime-manifest.json", "uninstall.ps1")) {
        $src = Join-Path $launcherRoot $file
        if (-not (Test-Path -LiteralPath $src -PathType Leaf)) {
            throw "Required file missing from launcher: $src"
        }
        Copy-Item -LiteralPath $src -Destination (Join-Path $payloadRoot $file) -Force
    }

    # Optional README.md.
    $optionalReadme = Join-Path $launcherRoot "README.md"
    if (Test-Path -LiteralPath $optionalReadme -PathType Leaf) {
        Copy-Item -LiteralPath $optionalReadme -Destination (Join-Path $payloadRoot "README.md") -Force
    }

    # install.ps1 is required as a sibling asset.
    $installSrc = Join-Path $launcherRoot "install.ps1"
    if (-not (Test-Path -LiteralPath $installSrc -PathType Leaf)) {
        throw "install.ps1 missing from launcher: $installSrc"
    }

    Write-Step "Creating output directory $resolvedOutput"
    New-Item -ItemType Directory -Force -Path $resolvedOutput | Out-Null

    $zipName = "brew-windows-v2-$Version.zip"
    $zipPath = Join-Path $resolvedOutput $zipName
    if (Test-Path -LiteralPath $zipPath) {
        Remove-Item -LiteralPath $zipPath -Force
    }

    Write-Step "Compressing payload to $zipPath"
    Compress-Archive -Path (Join-Path $payloadRoot "*") -DestinationPath $zipPath -Force

    $sha = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
    Set-Content -LiteralPath "$zipPath.sha256" -Value "$sha  $zipName" -Encoding ASCII

    # Copy install.ps1 as a sibling release asset so the pipeline can upload
    # both the zip and install.ps1.
    $installDest = Join-Path $resolvedOutput "install.ps1"
    Copy-Item -LiteralPath $installSrc -Destination $installDest -Force

    Write-Host "Created $zipPath"
    Write-Host "SHA256 $sha"
    Write-Host "install.ps1 $installDest"
} finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
