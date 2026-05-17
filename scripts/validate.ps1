Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))

& (Join-Path $repoRoot "tests\run.ps1")
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

$jsonFiles = git -C $repoRoot ls-files --cached --others --exclude-standard -- "*.json"
foreach ($jsonFile in $jsonFiles) {
    Get-Content -LiteralPath (Join-Path $repoRoot $jsonFile) -Raw | ConvertFrom-Json | Out-Null
}

Write-Host "Validation passed."
