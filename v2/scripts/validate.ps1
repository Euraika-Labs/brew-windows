Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

# v2Root is the v2/ tree; this script validates only v2 sources.
# Mirrors v1/scripts/validate.ps1 but skips test files that are not yet
# present (Wave 1.D introduces them).
$v2Root = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))

function Write-Step {
    param([string]$Message)
    Write-Host "==> $Message"
}

$tests = @(
    "tests\launcher-smoke.ps1",
    "tests\install-runtime.ps1"
)

foreach ($test in $tests) {
    $path = Join-Path $v2Root $test
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Write-Warning "Test not yet present, skipping: $path"
        continue
    }
    Write-Step "Running $test"
    # Reset $LASTEXITCODE before each invocation so StrictMode does not
    # trip on the variable being unset before the test script has had a
    # chance to call exit. Scripts that complete normally (no exit call)
    # leave $LASTEXITCODE at whatever its previous value was; we treat
    # that as success.
    $global:LASTEXITCODE = 0
    & $path
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
}

Write-Step "Parsing JSON files under v2/"
$jsonFiles = Get-ChildItem -LiteralPath $v2Root -Recurse -Filter "*.json" -File |
    Where-Object {
        # Skip the lazy-fetched runtime tree if present; only validate source JSON.
        $_.FullName -notlike (Join-Path $v2Root "runtime\*")
    }

foreach ($jsonFile in $jsonFiles) {
    Get-Content -LiteralPath $jsonFile.FullName -Raw | ConvertFrom-Json | Out-Null
}

Write-Host "Validation passed."
