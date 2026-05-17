param(
    [string]$Version = "dev",
    [string]$OutputDir = "dist"
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$resolvedOutput = [System.IO.Path]::GetFullPath((Join-Path $repoRoot $OutputDir))
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("brew-windows-release-" + [System.Guid]::NewGuid().ToString("N"))
$payloadRoot = Join-Path $tempRoot "payload"

try {
    New-Item -ItemType Directory -Force -Path $payloadRoot | Out-Null
    foreach ($item in @("bin", "Library", "schema", "docs")) {
        Copy-Item -LiteralPath (Join-Path $repoRoot $item) -Destination (Join-Path $payloadRoot $item) -Recurse -Force
    }
    Copy-Item -LiteralPath (Join-Path $repoRoot "uninstall.ps1") -Destination (Join-Path $payloadRoot "uninstall.ps1") -Force

    New-Item -ItemType Directory -Force -Path $resolvedOutput | Out-Null
    $zipPath = Join-Path $resolvedOutput "brew-windows-$Version.zip"
    if (Test-Path -LiteralPath $zipPath) {
        Remove-Item -LiteralPath $zipPath -Force
    }

    Compress-Archive -Path (Join-Path $payloadRoot "*") -DestinationPath $zipPath -Force
    $sha = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
    Set-Content -LiteralPath "$zipPath.sha256" -Value "$sha  $(Split-Path -Leaf $zipPath)" -Encoding ASCII

    Write-Host "Created $zipPath"
    Write-Host "SHA256 $sha"
} finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
