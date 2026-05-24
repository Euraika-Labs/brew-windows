param(
    [string]$Prefix,
    [switch]$Force
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

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

function Remove-PathEntry {
    param(
        [string]$PathValue,
        [string]$Entry
    )

    if ([string]::IsNullOrWhiteSpace($PathValue)) {
        return ""
    }

    $needle = [System.IO.Path]::GetFullPath($Entry).TrimEnd("\")
    $kept = New-Object System.Collections.Generic.List[string]
    foreach ($segment in $PathValue.Split(";", [System.StringSplitOptions]::RemoveEmptyEntries)) {
        try {
            if ([System.IO.Path]::GetFullPath($segment).TrimEnd("\") -ieq $needle) {
                continue
            }
        } catch {
        }
        $kept.Add($segment)
    }

    return ($kept -join ";")
}

$resolvedPrefix = Resolve-Prefix -RequestedPrefix $Prefix
$binPath = Join-Path $resolvedPrefix "bin"

if (-not (Test-Path -LiteralPath $resolvedPrefix -PathType Container)) {
    Write-Host "Brew Windows is not installed at $resolvedPrefix."
    exit 0
}

$marker = Join-Path $resolvedPrefix "install-manifest.json"
$brewScript = Join-Path $resolvedPrefix "bin\brew.ps1"
if (-not (Test-Path -LiteralPath $marker -PathType Leaf) -and -not (Test-Path -LiteralPath $brewScript -PathType Leaf)) {
    throw "Refusing to uninstall because $resolvedPrefix does not look like a Brew Windows prefix."
}

if (-not $Force) {
    $answer = Read-Host "Remove Brew Windows from $resolvedPrefix? [y/N]"
    if ($answer -notmatch "^(?i:y|yes)$") {
        Write-Host "Aborted."
        exit 1
    }
}

$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
[Environment]::SetEnvironmentVariable("Path", (Remove-PathEntry -PathValue $userPath -Entry $binPath), "User")
$env:Path = Remove-PathEntry -PathValue $env:Path -Entry $binPath

Remove-Item -LiteralPath $resolvedPrefix -Recurse -Force
Write-Host "Brew Windows uninstalled."
