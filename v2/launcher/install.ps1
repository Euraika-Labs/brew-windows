param(
    [string]$Version = "latest",
    [string]$Prefix,
    [string]$PayloadUrl,
    [string]$PayloadSha256,
    [switch]$SkipRuntimeBootstrap
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$Script:LauncherVersion = "0.1.0-dev"

function Write-Step {
    param([string]$Message)
    Write-Host "==> $Message"
}

function New-Directory {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        New-Item -ItemType Directory -Force -Path $Path | Out-Null
    }
}

function Resolve-Prefix {
    param([string]$RequestedPrefix)

    if (-not [string]::IsNullOrWhiteSpace($RequestedPrefix)) {
        return [System.IO.Path]::GetFullPath($RequestedPrefix)
    }
    if (-not [string]::IsNullOrWhiteSpace($env:HOMEBREW_PREFIX)) {
        return [System.IO.Path]::GetFullPath($env:HOMEBREW_PREFIX)
    }
    return [System.IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA "Homebrew"))
}

function Path-Contains {
    param(
        [string]$PathValue,
        [string]$Entry
    )

    if ([string]::IsNullOrWhiteSpace($PathValue)) {
        return $false
    }

    $needle = [System.IO.Path]::GetFullPath($Entry).TrimEnd("\")
    foreach ($segment in $PathValue.Split(";", [System.StringSplitOptions]::RemoveEmptyEntries)) {
        try {
            if ([System.IO.Path]::GetFullPath($segment).TrimEnd("\") -ieq $needle) {
                return $true
            }
        } catch {
        }
    }

    return $false
}

function Add-ToUserPath {
    param([string]$Entry)

    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if (-not (Path-Contains -PathValue $userPath -Entry $Entry)) {
        if ([string]::IsNullOrWhiteSpace($userPath)) {
            [Environment]::SetEnvironmentVariable("Path", $Entry, "User")
        } else {
            [Environment]::SetEnvironmentVariable("Path", "$Entry;$userPath", "User")
        }
        Write-Step "Added $Entry to the User PATH."
    }

    if (-not (Path-Contains -PathValue $env:Path -Entry $Entry)) {
        if ([string]::IsNullOrWhiteSpace($env:Path)) {
            $env:Path = $Entry
        } else {
            $env:Path = "$Entry;$env:Path"
        }
    }
}

function Resolve-GitHubAsset {
    param([string]$RequestedVersion)

    $releaseUri = if ($RequestedVersion -eq "latest") {
        "https://api.github.com/repos/Euraika-Labs/brew-windows/releases/latest"
    } else {
        "https://api.github.com/repos/Euraika-Labs/brew-windows/releases/tags/$RequestedVersion"
    }

    $release = Invoke-RestMethod -Uri $releaseUri
    $asset = $release.assets | Where-Object { $_.name -like "brew-windows-*.zip" } | Select-Object -First 1
    if ($null -eq $asset) {
        throw "Could not find a brew-windows zip asset on release $($release.tag_name)."
    }

    $sha = $null
    $digest = [string]$asset.digest
    if ($digest -match "^sha256:([0-9a-fA-F]{64})$") {
        $sha = $matches[1].ToLowerInvariant()
    }

    return [ordered]@{
        url = $asset.browser_download_url
        sha256 = $sha
        version = $release.tag_name
    }
}

function Assert-Hash {
    param(
        [string]$Path,
        [string]$ExpectedSha256
    )

    if ([string]::IsNullOrWhiteSpace($ExpectedSha256)) {
        throw "The release asset does not expose a SHA256 digest. Refusing unchecked install."
    }

    $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $ExpectedSha256.ToLowerInvariant()) {
        throw "Payload checksum mismatch. Expected $ExpectedSha256 but got $actual."
    }
}

function Save-Payload {
    param(
        [string]$Url,
        [string]$Destination
    )

    if ($Url -match "^https://") {
        Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing
        return
    }

    if ($Url -match "^file://") {
        $uri = [uri]$Url
        Copy-Item -LiteralPath $uri.LocalPath -Destination $Destination -Force
        return
    }

    if (Test-Path -LiteralPath $Url -PathType Leaf) {
        Copy-Item -LiteralPath $Url -Destination $Destination -Force
        return
    }

    throw "Unsupported payload URL. Use HTTPS or a local file path."
}

if ($env:OS -ne "Windows_NT") {
    throw "Brew Windows install.ps1 supports native Windows only."
}

$resolvedPrefix = Resolve-Prefix -RequestedPrefix $Prefix
$binPath = Join-Path $resolvedPrefix "bin"
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("brew-windows-install-" + [System.Guid]::NewGuid().ToString("N"))
$archivePath = Join-Path $tempRoot "brew-windows.zip"
$extractPath = Join-Path $tempRoot "extract"
$backupPath = Join-Path $tempRoot "backup"

if ([string]::IsNullOrWhiteSpace($PayloadUrl)) {
    $asset = Resolve-GitHubAsset -RequestedVersion $Version
    $PayloadUrl = $asset.url
    $PayloadSha256 = $asset.sha256
    $Version = $asset.version
}

try {
    Write-Step "Installing Brew Windows to $resolvedPrefix"
    New-Directory -Path $tempRoot
    New-Directory -Path $extractPath
    New-Directory -Path $backupPath

    Write-Step "Downloading payload"
    Save-Payload -Url $PayloadUrl -Destination $archivePath
    Assert-Hash -Path $archivePath -ExpectedSha256 $PayloadSha256

    Write-Step "Extracting payload"
    Expand-Archive -LiteralPath $archivePath -DestinationPath $extractPath -Force

    New-Directory -Path $resolvedPrefix
    $managedItems = @("bin", "patches", "runtime-manifest.json", "uninstall.ps1", "README.md")
    foreach ($item in $managedItems) {
        $existing = Join-Path $resolvedPrefix $item
        if (Test-Path -LiteralPath $existing) {
            Move-Item -LiteralPath $existing -Destination (Join-Path $backupPath $item)
        }
    }

    try {
        foreach ($item in Get-ChildItem -LiteralPath $extractPath -Force) {
            Move-Item -LiteralPath $item.FullName -Destination (Join-Path $resolvedPrefix $item.Name)
        }
    } catch {
        foreach ($item in $managedItems) {
            $installed = Join-Path $resolvedPrefix $item
            if (Test-Path -LiteralPath $installed) {
                Remove-Item -LiteralPath $installed -Recurse -Force
            }
            $backup = Join-Path $backupPath $item
            if (Test-Path -LiteralPath $backup) {
                Move-Item -LiteralPath $backup -Destination $installed
            }
        }
        throw
    }

    foreach ($dir in @("Cellar", "opt", "var\homebrew", "Cache", "Logs", "Temp", "Library\Taps", "runtime")) {
        New-Directory -Path (Join-Path $resolvedPrefix $dir)
    }

    $manifest = [ordered]@{
        version = $Version
        launcherVersion = $Script:LauncherVersion
        installedAt = [DateTimeOffset]::UtcNow.ToString("o")
        prefix = $resolvedPrefix
        payloadUrl = $PayloadUrl
        payloadSha256 = $PayloadSha256
    }
    $manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $resolvedPrefix "install-manifest.json") -Encoding UTF8

    Add-ToUserPath -Entry $binPath

    $env:HOMEBREW_PREFIX = $resolvedPrefix

    if ($SkipRuntimeBootstrap) {
        Write-Step "Skipping runtime bootstrap (SkipRuntimeBootstrap set)."
    } else {
        Write-Step "Downloading Homebrew runtime (~130 MB)"
        Write-Host "    This is a one-time download. Subsequent brew commands run locally."
        $brewPs1 = Join-Path $binPath "brew.ps1"
        if (-not (Test-Path -LiteralPath $brewPs1 -PathType Leaf)) {
            Write-Host "Launcher script not found at $brewPs1; skipping bootstrap."
        } else {
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $brewPs1 --version
            if ($LASTEXITCODE -ne 0) {
                Write-Host "Runtime bootstrap failed (exit code $LASTEXITCODE). Open a new PowerShell window and run ``brew --version`` to retry."
            }
        }
    }

    Write-Step "Current session command: brew"
    Write-Step "Future PowerShell windows: open a new terminal and run brew"
    Write-Host "Brew Windows installed successfully."
} finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
