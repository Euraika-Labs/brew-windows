param(
    [string[]]$PackageName = @(),
    [int]$Limit = 100,
    [string]$CandidateOutputPath = "catalog/windows-candidates.json",
    [string]$ManifestOutputDir = "Library/Taps/euraika-labs/homebrew-core/Formula/Generated",
    [string]$CacheDir = ".cache/catalog-sync",
    [string]$HomebrewFormulaPath,
    [string]$GitHubReleaseFixturesDir,
    [switch]$GenerateManifests,
    [switch]$ValidateArchives,
    [switch]$FailOnNoCandidates
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))

function Resolve-ProjectPath {
    param([string]$Path)

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }

    return [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $Path))
}

$ResolvedCandidateOutputPath = Resolve-ProjectPath -Path $CandidateOutputPath
$ResolvedManifestOutputDir = Resolve-ProjectPath -Path $ManifestOutputDir
$ResolvedCacheDir = Resolve-ProjectPath -Path $CacheDir

function New-Directory {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        New-Item -ItemType Directory -Force -Path $Path | Out-Null
    }
}

function ConvertTo-JsonFile {
    param(
        [object]$Value,
        [string]$Path
    )

    New-Directory -Path (Split-Path -Parent $Path)
    $json = ($Value | ConvertTo-Json -Depth 80) + [Environment]::NewLine
    Set-Content -LiteralPath $Path -Encoding UTF8 -NoNewline -Value $json
}

function Get-GitHubToken {
    if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_TOKEN)) {
        return $env:GITHUB_TOKEN
    }

    $gh = Get-Command gh -ErrorAction SilentlyContinue
    if ($null -eq $gh) {
        return $null
    }

    try {
        $token = & gh auth token 2>$null
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($token)) {
            return ($token.Trim())
        }
    } catch {
    }

    return $null
}

function Get-RequestHeaders {
    $headers = @{
        "Accept" = "application/vnd.github+json"
        "User-Agent" = "Euraika-Labs-brew-windows-catalog-sync"
        "X-GitHub-Api-Version" = "2022-11-28"
    }

    $token = Get-GitHubToken
    if (-not [string]::IsNullOrWhiteSpace($token)) {
        $headers["Authorization"] = "Bearer $token"
    }

    return $headers
}

function Invoke-JsonUri {
    param([string]$Uri)

    Invoke-RestMethod -Uri $Uri -Headers (Get-RequestHeaders)
}

function Get-HomebrewFormulae {
    if (-not [string]::IsNullOrWhiteSpace($HomebrewFormulaPath)) {
        $path = Resolve-ProjectPath -Path $HomebrewFormulaPath
        $data = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        return @($data)
    }

    $requestedPackages = @()
    foreach ($entry in $PackageName) {
        $requestedPackages += @(([string]$entry).Split(",", [System.StringSplitOptions]::RemoveEmptyEntries) | ForEach-Object {
            $_.Trim()
        } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }

    if ($requestedPackages.Count -gt 0) {
        $items = @()
        foreach ($name in $requestedPackages) {
            $escaped = [uri]::EscapeDataString($name)
            try {
                $items += Invoke-JsonUri -Uri "https://formulae.brew.sh/api/formula/$escaped.json"
            } catch {
                Write-Warning "Skipping $name because Homebrew formula metadata could not be loaded: $($_.Exception.Message)"
            }
        }
        return @($items)
    }

    try {
        $analytics = Invoke-JsonUri -Uri "https://formulae.brew.sh/api/analytics/install-on-request/30d.json"
        $popularNames = @($analytics.items | Select-Object -First $Limit | ForEach-Object { [string]$_.formula })
        $items = @()
        foreach ($name in $popularNames) {
            try {
                $escaped = [uri]::EscapeDataString($name)
                $items += Invoke-JsonUri -Uri "https://formulae.brew.sh/api/formula/$escaped.json"
            } catch {
                Write-Warning "Skipping $name because Homebrew formula metadata could not be loaded: $($_.Exception.Message)"
            }
        }
        return @($items)
    } catch {
        Write-Warning "Homebrew analytics were not available; falling back to the first $Limit formulae from formula.json."
    }

    $all = @(Invoke-JsonUri -Uri "https://formulae.brew.sh/api/formula.json")
    return @($all | Select-Object -First $Limit)
}

function Get-FormulaString {
    param(
        [object]$Object,
        [string]$Name
    )

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value) {
        return ""
    }

    return [string]$property.Value
}

function Get-GitHubRepository {
    param([object]$Formula)

    $candidates = @(
        (Get-FormulaString -Object $Formula -Name "homepage")
    )

    $stableUrl = ""
    if ($null -ne $Formula.urls -and $null -ne $Formula.urls.stable) {
        $stableUrl = Get-FormulaString -Object $Formula.urls.stable -Name "url"
    }
    $candidates += $stableUrl

    foreach ($candidate in $candidates) {
        if ($candidate -match "github\.com[:/]([^/#?]+)/([^/#?]+)") {
            $owner = $matches[1]
            $repo = ($matches[2] -replace "\.git$", "")
            if (-not [string]::IsNullOrWhiteSpace($owner) -and -not [string]::IsNullOrWhiteSpace($repo)) {
                return "$owner/$repo"
            }
        }
    }

    return $null
}

function Get-FixturePath {
    param([string]$Repository)

    if ([string]::IsNullOrWhiteSpace($GitHubReleaseFixturesDir)) {
        return $null
    }

    $fixtureDir = Resolve-ProjectPath -Path $GitHubReleaseFixturesDir
    $fixtureName = ($Repository -replace "/", "__") + ".json"
    return Join-Path $fixtureDir $fixtureName
}

function Get-GitHubLatestRelease {
    param([string]$Repository)

    $fixturePath = Get-FixturePath -Repository $Repository
    if (-not [string]::IsNullOrWhiteSpace($fixturePath) -and (Test-Path -LiteralPath $fixturePath -PathType Leaf)) {
        return (Get-Content -LiteralPath $fixturePath -Raw | ConvertFrom-Json)
    }

    Invoke-JsonUri -Uri "https://api.github.com/repos/$Repository/releases/latest"
}

function Normalize-Version {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return ""
    }

    $normalized = $Value.Trim().ToLowerInvariant()
    $normalized = $normalized -replace "^release[-_/]", ""
    $normalized = $normalized -replace "^(rust-)?v", ""
    return $normalized
}

function Test-VersionMatches {
    param(
        [string]$FormulaVersion,
        [string]$ReleaseTag
    )

    $formula = Normalize-Version -Value $FormulaVersion
    $tag = Normalize-Version -Value $ReleaseTag
    if ([string]::IsNullOrWhiteSpace($formula) -or [string]::IsNullOrWhiteSpace($tag)) {
        return $false
    }

    return $tag -eq $formula -or $tag.Contains($formula)
}

function Get-AssetSha256 {
    param([object]$Asset)

    $digest = Get-FormulaString -Object $Asset -Name "digest"
    if ($digest -match "^sha256:([0-9a-fA-F]{64})$") {
        return $matches[1].ToLowerInvariant()
    }

    return $null
}

function Get-ArchiveType {
    param([string]$Name)

    if ($Name -match "\.zip$") {
        return "zip"
    }
    if ($Name -match "\.tar\.gz$") {
        return "tar.gz"
    }
    if ($Name -match "\.tgz$") {
        return "tgz"
    }

    return $null
}

function Get-AssetArchitecture {
    param([string]$Name)

    $lower = $Name.ToLowerInvariant()
    if ($lower -match "(i686|386|x86_32)") {
        return $null
    }
    if ($lower -match "(aarch64-pc-windows|windows[-_]?arm64|win32-arm64|arm64.*windows)") {
        return "arm64"
    }
    if ($lower -match "(x86_64-pc-windows|windows[-_]?amd64|windows[-_]?x64|win32-x64|win64|amd64.*windows|x64.*windows)") {
        return "x64"
    }

    return $null
}

function Get-AssetScore {
    param([string]$Name)

    $lower = $Name.ToLowerInvariant()
    $score = 0
    if ($lower -match "msvc") { $score += 50 }
    if ($lower -match "\.zip$") { $score += 20 }
    if ($lower -notmatch "gnu") { $score += 10 }
    if ($lower -match "(portable|standalone)") { $score += 5 }
    return $score
}

function Select-WindowsAssets {
    param([object[]]$Assets)

    $selected = [ordered]@{}
    foreach ($asset in $Assets) {
        $name = Get-FormulaString -Object $asset -Name "name"
        if ([string]::IsNullOrWhiteSpace($name)) {
            continue
        }
        if ($name -match "\.sha256$") {
            continue
        }

        $archiveType = Get-ArchiveType -Name $name
        if ([string]::IsNullOrWhiteSpace($archiveType)) {
            continue
        }

        $architecture = Get-AssetArchitecture -Name $name
        if ([string]::IsNullOrWhiteSpace($architecture)) {
            continue
        }

        $sha256 = Get-AssetSha256 -Asset $asset
        if ([string]::IsNullOrWhiteSpace($sha256)) {
            continue
        }

        $url = Get-FormulaString -Object $asset -Name "browser_download_url"
        if ([string]::IsNullOrWhiteSpace($url)) {
            continue
        }

        $candidate = [ordered]@{
            architecture = $architecture
            name = $name
            url = $url
            sha256 = $sha256
            extractType = $archiveType
            score = Get-AssetScore -Name $name
        }

        if (-not $selected.Contains($architecture) -or $candidate.score -gt $selected[$architecture].score) {
            $selected[$architecture] = $candidate
        }
    }

    return $selected
}

function Save-Asset {
    param(
        [object]$Asset,
        [string]$Destination
    )

    New-Directory -Path (Split-Path -Parent $Destination)
    $url = [string]$Asset.url

    if ($url -match "^https://") {
        Invoke-WebRequest -Uri $url -Headers (Get-RequestHeaders) -OutFile $Destination -UseBasicParsing
        return
    }

    if ($url -match "^file://") {
        $uri = [uri]$url
        Copy-Item -LiteralPath $uri.LocalPath -Destination $Destination -Force
        return
    }

    if (Test-Path -LiteralPath $url -PathType Leaf) {
        Copy-Item -LiteralPath $url -Destination $Destination -Force
        return
    }

    throw "Unsupported asset URL for archive inspection: $url"
}

function Assert-AssetHash {
    param(
        [string]$Path,
        [string]$ExpectedSha256
    )

    $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $ExpectedSha256) {
        throw "Checksum mismatch for $Path. Expected $ExpectedSha256 but got $actual."
    }
}

function Get-ArchiveEntryNames {
    param([string]$ArchivePath)

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead($ArchivePath)
    try {
        return @($zip.Entries | Where-Object { -not [string]::IsNullOrWhiteSpace($_.Name) } | ForEach-Object {
            $_.FullName -replace "\\", "/"
        })
    } finally {
        $zip.Dispose()
    }
}

function Get-CommonDirectoryPrefix {
    param([string[]]$Paths)

    if ($Paths.Count -eq 0) {
        return ""
    }

    $splitPaths = @()
    foreach ($path in $Paths) {
        $splitPaths += ,@($path.Split("/"))
    }
    $prefix = New-Object System.Collections.Generic.List[string]
    $index = 0

    while ($true) {
        $value = $null
        foreach ($parts in $splitPaths) {
            if ($parts.Length -le ($index + 1)) {
                return ($prefix -join "/")
            }
            if ($null -eq $value) {
                $value = $parts[$index]
            } elseif ($parts[$index] -ne $value) {
                return ($prefix -join "/")
            }
        }
        $prefix.Add($value)
        $index += 1
    }
}

function Find-ExecutableEntries {
    param(
        [string[]]$Entries,
        [string[]]$Executables
    )

    $selected = New-Object System.Collections.Generic.List[object]
    foreach ($executable in $Executables) {
        $matches = @($Entries | Where-Object {
            $leaf = Split-Path -Leaf $_
            $leaf -ieq "$executable.exe" -or $leaf -ieq "$executable.cmd" -or $leaf -ieq "$executable.bat"
        } | Sort-Object {
            $leaf = Split-Path -Leaf $_
            if ($leaf -match "\.exe$") { 0 } elseif ($leaf -match "\.cmd$") { 1 } else { 2 }
        }, Length)

        if ($matches.Count -eq 0) {
            return $null
        }

        $selected.Add([ordered]@{
            name = $executable
            entry = $matches[0]
        })
    }

    return $selected.ToArray()
}

function Inspect-AssetLayout {
    param(
        [string]$Package,
        [object]$Asset,
        [string[]]$Executables
    )

    if ($Asset.extractType -ne "zip") {
        return [ordered]@{
            ok = $false
            reason = "archive-inspection-currently-supports-zip-only"
        }
    }

    $safeName = ($Package + "-" + $Asset.architecture + "-" + $Asset.name) -replace "[^A-Za-z0-9._-]", "_"
    $archivePath = Join-Path $ResolvedCacheDir $safeName
    Save-Asset -Asset $Asset -Destination $archivePath
    Assert-AssetHash -Path $archivePath -ExpectedSha256 $Asset.sha256

    $entries = @(Get-ArchiveEntryNames -ArchivePath $archivePath)
    $executableEntries = @(Find-ExecutableEntries -Entries $entries -Executables $Executables)
    if ($null -eq $executableEntries -or $executableEntries.Count -eq 0) {
        return [ordered]@{
            ok = $false
            reason = "declared-executables-not-found-in-archive"
        }
    }

    $sourcePath = Get-CommonDirectoryPrefix -Paths @($executableEntries | ForEach-Object { $_.entry })
    $bins = @()
    foreach ($entry in $executableEntries) {
        $relative = $entry.entry
        if (-not [string]::IsNullOrWhiteSpace($sourcePath)) {
            $relative = $relative.Substring($sourcePath.Length).TrimStart("/")
        }
        $bins += [ordered]@{
            name = $entry.name
            path = $relative
        }
    }

    return [ordered]@{
        ok = $true
        sourcePath = $sourcePath
        bins = $bins
    }
}

function Convert-Dependencies {
    param([object]$Formula)

    $dependencies = @()
    if ($null -ne $Formula.dependencies) {
        $dependencies = @($Formula.dependencies | ForEach-Object { [string]$_ })
    }
    return $dependencies
}

function New-Candidate {
    param([object]$Formula)

    $name = Get-FormulaString -Object $Formula -Name "name"
    if ([string]::IsNullOrWhiteSpace($name)) {
        return $null
    }

    if ($Formula.disabled -eq $true) {
        return [ordered]@{ name = $name; status = "rejected"; reason = "homebrew-formula-disabled" }
    }
    if ($Formula.deprecated -eq $true) {
        return [ordered]@{ name = $name; status = "rejected"; reason = "homebrew-formula-deprecated" }
    }
    if ($null -eq $Formula.executables -or @($Formula.executables).Count -eq 0) {
        return [ordered]@{ name = $name; status = "rejected"; reason = "no-declared-executables" }
    }

    $repository = Get-GitHubRepository -Formula $Formula
    if ([string]::IsNullOrWhiteSpace($repository)) {
        return [ordered]@{ name = $name; status = "rejected"; reason = "no-github-release-repository-detected" }
    }

    try {
        $release = Get-GitHubLatestRelease -Repository $repository
    } catch {
        return [ordered]@{ name = $name; status = "rejected"; reason = "github-release-not-readable"; repository = $repository; error = $_.Exception.Message }
    }

    $version = Get-FormulaString -Object $Formula.versions -Name "stable"
    $tag = Get-FormulaString -Object $release -Name "tag_name"
    if (-not (Test-VersionMatches -FormulaVersion $version -ReleaseTag $tag)) {
        return [ordered]@{
            name = $name
            status = "rejected"
            reason = "github-release-version-does-not-match-homebrew-stable"
            repository = $repository
            homebrewVersion = $version
            latestReleaseTag = $tag
        }
    }

    $assets = Select-WindowsAssets -Assets @($release.assets)
    if ($assets.Count -eq 0 -or -not $assets.Contains("x64")) {
        return [ordered]@{
            name = $name
            status = "rejected"
            reason = "no-sha256-windows-x64-archive-asset"
            repository = $repository
            homebrewVersion = $version
            latestReleaseTag = $tag
        }
    }

    $executables = @($Formula.executables | ForEach-Object { [string]$_ })
    $architectures = [ordered]@{}
    $layoutOk = $true
    $layoutReasons = New-Object System.Collections.Generic.List[string]
    foreach ($architecture in @("x64", "arm64")) {
        if (-not $assets.Contains($architecture)) {
            continue
        }

        $asset = $assets[$architecture]
        try {
            $layout = Inspect-AssetLayout -Package $name -Asset $asset -Executables $executables
        } catch {
            $layout = [ordered]@{
                ok = $false
                reason = "archive-inspection-failed"
                error = $_.Exception.Message
            }
        }
        $architectures[$architecture] = [ordered]@{
            name = $asset.name
            url = $asset.url
            sha256 = $asset.sha256
            extractType = $asset.extractType
            score = $asset.score
            layout = $layout
        }

        if ($layout.ok -ne $true) {
            $layoutOk = $false
            $layoutReasons.Add("$architecture`: $($layout.reason)")
        }
    }

    if ($layoutOk -ne $true) {
        return [ordered]@{
            name = $name
            status = "candidate"
            promotable = $false
            reason = "archive-layout-not-promotable"
            layoutReasons = @($layoutReasons)
            repository = $repository
            homebrewVersion = $version
            latestReleaseTag = $tag
            architectures = $architectures
        }
    }

    $binReference = $null
    foreach ($architecture in $architectures.Keys) {
        $currentBins = $architectures[$architecture].layout.bins
        if ($null -eq $binReference) {
            $binReference = @($currentBins | ForEach-Object { [string]$_.path })
        } else {
            $currentReference = @($currentBins | ForEach-Object { [string]$_.path })
            if (($binReference -join "|") -ne ($currentReference -join "|")) {
                return [ordered]@{
                    name = $name
                    status = "candidate"
                    promotable = $false
                    reason = "architecture-layouts-disagree"
                    repository = $repository
                    homebrewVersion = $version
                    latestReleaseTag = $tag
                    architectures = $architectures
                }
            }
        }
    }

    return [ordered]@{
        name = $name
        status = "candidate"
        promotable = $true
        reason = "sha256-windows-archives-and-layout-validated"
        repository = $repository
        homebrew = [ordered]@{
            tap = Get-FormulaString -Object $Formula -Name "tap"
            sourcePath = Get-FormulaString -Object $Formula -Name "ruby_source_path"
            sourceSha256 = if ($null -ne $Formula.ruby_source_checksum) { Get-FormulaString -Object $Formula.ruby_source_checksum -Name "sha256" } else { "" }
        }
        homebrewVersion = $version
        latestReleaseTag = $tag
        description = Get-FormulaString -Object $Formula -Name "desc"
        homepage = Get-FormulaString -Object $Formula -Name "homepage"
        license = Get-FormulaString -Object $Formula -Name "license"
        executables = $executables
        dependencies = @(Convert-Dependencies -Formula $Formula)
        architectures = $architectures
    }
}

function New-ManifestFromCandidate {
    param([object]$Candidate)

    $arches = [ordered]@{}
    foreach ($architecture in $Candidate.architectures.Keys) {
        $asset = $Candidate.architectures[$architecture]
        $arches[$architecture] = [ordered]@{
            url = $asset.url
            sha256 = $asset.sha256
            extract = [ordered]@{
                type = $asset.extractType
                sourcePath = $asset.layout.sourcePath
            }
        }
    }

    $firstArchitecture = @($Candidate.architectures.Keys)[0]
    $bins = @($Candidate.architectures[$firstArchitecture].layout.bins | ForEach-Object {
        [ordered]@{
            name = $_.name
            path = $_.path
        }
    })

    return [ordered]@{
        schemaVersion = "0"
        name = $Candidate.name
        version = $Candidate.homebrewVersion
        description = $Candidate.description
        homepage = $Candidate.homepage
        license = $Candidate.license
        type = "portable-cli"
        upstream = [ordered]@{
            source = "homebrew-formula-api"
            tap = $Candidate.homebrew.tap
            formulaPath = $Candidate.homebrew.sourcePath
            formulaSha256 = $Candidate.homebrew.sourceSha256
            githubRepository = $Candidate.repository
            githubReleaseTag = $Candidate.latestReleaseTag
        }
        platforms = [ordered]@{
            windows = [ordered]@{
                arches = $arches
            }
        }
        bin = $bins
        resources = @()
        conflicts = @()
        test = [ordered]@{
            command = "$($bins[0].name) --version"
            match = [regex]::Escape($Candidate.homebrewVersion)
        }
        livecheck = [ordered]@{
            type = "github-release"
            repository = $Candidate.repository
        }
    }
}

function Write-Manifests {
    param([object[]]$Candidates)

    New-Directory -Path $ResolvedManifestOutputDir
    Get-ChildItem -LiteralPath $ResolvedManifestOutputDir -Filter "*.json" -File -ErrorAction SilentlyContinue |
        Remove-Item -Force

    foreach ($candidate in $Candidates) {
        if ($candidate.status -ne "candidate" -or $candidate.promotable -ne $true) {
            continue
        }

        $manifest = New-ManifestFromCandidate -Candidate $candidate
        $path = Join-Path $ResolvedManifestOutputDir "$($candidate.name).json"
        ConvertTo-JsonFile -Value $manifest -Path $path
        Write-Host "Generated $path"
    }
}

New-Directory -Path $ResolvedCacheDir

$formulae = @(Get-HomebrewFormulae)
$candidates = @()
$processed = 0
foreach ($formula in $formulae) {
    if ($processed -ge $Limit -and $PackageName.Count -eq 0) {
        break
    }
    $processed += 1
    $candidate = New-Candidate -Formula $formula
    if ($null -ne $candidate) {
        $candidates += $candidate
        if ($candidate.status -eq "candidate" -and $candidate.promotable -eq $true) {
            Write-Host "Promotable: $($candidate.name) $($candidate.homebrewVersion)"
        } else {
            Write-Host "Skipped: $($candidate.name) ($($candidate.reason))"
        }
    }
}

$report = [ordered]@{
    source = [ordered]@{
        homebrewFormulaApi = "https://formulae.brew.sh/api/formula.json"
        githubReleaseApi = "https://docs.github.com/en/rest/releases/releases"
    }
    policy = [ordered]@{
        minimumStatus = "portable Windows CLI archive with SHA256 digest"
        requiresWindowsX64 = $true
        archives = @("zip", "tgz", "tar.gz")
        generatedManifestRequiresZipInspection = $true
    }
    candidates = $candidates
}

ConvertTo-JsonFile -Value $report -Path $ResolvedCandidateOutputPath

if ($GenerateManifests) {
    Write-Manifests -Candidates $candidates
}

$promotableCount = @($candidates | Where-Object { $_.status -eq "candidate" -and $_.promotable -eq $true }).Count
Write-Host "Catalog sync complete. Promotable candidates: $promotableCount"

if ($FailOnNoCandidates -and $promotableCount -eq 0) {
    throw "No promotable Windows candidates were found."
}
