param(
    [string]$ManifestPath = "v2\launcher\runtime-manifest.json"
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# Maintainer utility. Resolves real SHA256s for MinGit + RubyInstaller,
# computes the Homebrew working-tree hash for the maintainer-supplied
# commit SHA, and SHA256s each patch file. Flips placeholdersFilled to
# true and updates generatedAt. Does NOT automatically advance the
# Homebrew ref - that is a maintainer decision.

function Resolve-RepoRoot {
    # Repo root is the parent of v2/.
    return [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
}

function Write-Step {
    param([string]$Message)
    Write-Host "==> $Message"
}

function Assert-HttpsUrl {
    param([string]$Url, [string]$Component)
    if (-not $Url.StartsWith("https://", [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Component '$Component' has non-HTTPS URL: $Url"
    }
}

function Get-FileSha256Lower {
    param([string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

$repoRoot = Resolve-RepoRoot

if ([System.IO.Path]::IsPathRooted($ManifestPath)) {
    $manifestAbs = [System.IO.Path]::GetFullPath($ManifestPath)
} else {
    $manifestAbs = [System.IO.Path]::GetFullPath((Join-Path $repoRoot $ManifestPath))
}

if (-not (Test-Path -LiteralPath $manifestAbs -PathType Leaf)) {
    throw "Manifest not found: $manifestAbs"
}

Write-Step "Reading manifest $manifestAbs"
$manifestText = Get-Content -LiteralPath $manifestAbs -Raw
$manifest = $manifestText | ConvertFrom-Json

# The launcher directory is the parent of the manifest file.
$launcherRoot = [System.IO.Path]::GetDirectoryName($manifestAbs)

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("brew-windows-v2-pin-" + [System.Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null

$summary = New-Object System.Collections.Generic.List[string]

try {
    # ---- MinGit ----
    $mingit = $manifest.components.mingit
    Assert-HttpsUrl -Url $mingit.url -Component "mingit"
    Write-Step "Downloading MinGit from $($mingit.url)"
    $mingitFile = Join-Path $tempRoot "mingit.zip"
    Invoke-WebRequest -Uri $mingit.url -OutFile $mingitFile -UseBasicParsing
    $mingitSha = Get-FileSha256Lower -Path $mingitFile
    $mingit.sha256 = $mingitSha
    $summary.Add("mingit version=$($mingit.version) sha256=$mingitSha")

    # ---- Ruby ----
    $ruby = $manifest.components.ruby
    Assert-HttpsUrl -Url $ruby.url -Component "ruby"
    Write-Step "Downloading RubyInstaller from $($ruby.url)"
    $rubyFile = Join-Path $tempRoot "ruby.7z"
    Invoke-WebRequest -Uri $ruby.url -OutFile $rubyFile -UseBasicParsing
    $rubySha = Get-FileSha256Lower -Path $rubyFile
    $ruby.sha256 = $rubySha
    $summary.Add("ruby version=$($ruby.version) sha256=$rubySha")

    # ---- Homebrew ----
    $homebrew = $manifest.components.homebrew
    Assert-HttpsUrl -Url $homebrew.url -Component "homebrew"
    $placeholderRef = "0000000000000000000000000000000000000000"
    if ($homebrew.ref -eq $placeholderRef -or [string]::IsNullOrWhiteSpace($homebrew.ref)) {
        throw "Set components.homebrew.ref to a real commit SHA before running pin-runtime.ps1"
    }
    if ($homebrew.ref -notmatch '^[0-9a-fA-F]{40}$') {
        throw "components.homebrew.ref must be a full 40-character commit SHA: $($homebrew.ref)"
    }

    Write-Step "Shallow-cloning Homebrew at $($homebrew.ref)"
    $hbDir = Join-Path $tempRoot "homebrew"
    & git clone --no-checkout --filter=blob:none $homebrew.url $hbDir
    if ($LASTEXITCODE -ne 0) {
        throw "git clone failed for $($homebrew.url)"
    }

    Push-Location -LiteralPath $hbDir
    try {
        & git fetch --depth=1 origin $homebrew.ref
        if ($LASTEXITCODE -ne 0) {
            throw "git fetch of $($homebrew.ref) failed"
        }
        & git checkout $homebrew.ref
        if ($LASTEXITCODE -ne 0) {
            throw "git checkout of $($homebrew.ref) failed"
        }
        # The schema v0 stores git's tree object id (SHA-1, 40 hex) here.
        # See BOOTSTRAP.md for the rationale.
        $treeId = (& git rev-parse "HEAD^{tree}").Trim()
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($treeId)) {
            throw "git rev-parse HEAD^{tree} failed"
        }
        $homebrew.expectedTreeId = $treeId
        $summary.Add("homebrew ref=$($homebrew.ref) treeId=$treeId")
    } finally {
        Pop-Location
    }

    # ---- Patches ----
    if ($null -ne $manifest.patches) {
        foreach ($patch in $manifest.patches) {
            $patchAbs = Join-Path $launcherRoot $patch.path
            if (-not (Test-Path -LiteralPath $patchAbs -PathType Leaf)) {
                throw "Patch file missing: $patchAbs"
            }
            $patchSha = Get-FileSha256Lower -Path $patchAbs
            $patch.sha256 = $patchSha
            $summary.Add("patch $($patch.path) sha256=$patchSha")
        }
    }

    # ---- Finalize ----
    $manifest.placeholdersFilled = $true
    $manifest.generatedAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

    Write-Step "Writing manifest $manifestAbs"
    # ConvertTo-Json preserves PSObject property order in PowerShell 5.1+,
    # which matches the order we loaded from disk.
    $json = $manifest | ConvertTo-Json -Depth 10
    Set-Content -LiteralPath $manifestAbs -Value $json -Encoding ASCII

    Write-Host ""
    Write-Host "Pin summary:"
    foreach ($line in $summary) {
        Write-Host "  $line"
    }
} finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
