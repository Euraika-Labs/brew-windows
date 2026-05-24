param([Parameter(ValueFromRemainingArguments = $true)][string[]]$BrewArgs)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$Script:LauncherVersion = "0.1.0-dev"

# ---------------------------------------------------------------------------
# Prefix resolution
# ---------------------------------------------------------------------------

function Resolve-BrewPrefix {
    if (-not [string]::IsNullOrWhiteSpace($env:HOMEBREW_PREFIX)) {
        return [System.IO.Path]::GetFullPath($env:HOMEBREW_PREFIX)
    }

    $scriptPath = if ($PSCommandPath) { $PSCommandPath } else { $MyInvocation.MyCommand.Path }
    $binDir = Split-Path -Parent $scriptPath
    return [System.IO.Path]::GetFullPath((Split-Path -Parent $binDir))
}

# ---------------------------------------------------------------------------
# Filesystem helpers (lifted verbatim from v1/bin/brew.ps1)
# ---------------------------------------------------------------------------

function New-BrewDirectory {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        New-Item -ItemType Directory -Force -Path $Path | Out-Null
    }
}

function Get-CanonicalPath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path).TrimEnd("\")
}

function Assert-PathUnderPrefix {
    param([string]$Path, [string]$Prefix)

    $prefixCanon = (Get-CanonicalPath $Prefix) + "\"
    $full = (Get-CanonicalPath $Path) + "\"
    if (-not $full.StartsWith($prefixCanon, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to modify path outside HOMEBREW_PREFIX: $Path"
    }
}

function Test-PathListContains {
    param(
        [string]$PathValue,
        [string]$Entry
    )

    if ([string]::IsNullOrWhiteSpace($PathValue)) {
        return $false
    }

    $needle = (Get-CanonicalPath $Entry)
    foreach ($segment in $PathValue.Split(";", [System.StringSplitOptions]::RemoveEmptyEntries)) {
        try {
            if ((Get-CanonicalPath $segment) -ieq $needle) {
                return $true
            }
        } catch {
        }
    }

    return $false
}

# ---------------------------------------------------------------------------
# Architecture detection
# ---------------------------------------------------------------------------

function Get-WindowsArchitectureKey {
    $arch = $env:PROCESSOR_ARCHITEW6432
    if ([string]::IsNullOrWhiteSpace($arch)) {
        $arch = $env:PROCESSOR_ARCHITECTURE
    }

    switch -Regex ($arch) {
        "ARM64" { return "arm64" }
        "AMD64|x86_64" { return "x64" }
        default { return ($arch.ToLowerInvariant()) }
    }
}

function Get-HomebrewProcessor {
    # Returns the value expected by HOMEBREW_PROCESSOR: Homebrew names,
    # not Windows names. See HOMEBREW_INTEGRATION.md.
    $arch = $env:PROCESSOR_ARCHITEW6432
    if ([string]::IsNullOrWhiteSpace($arch)) {
        $arch = $env:PROCESSOR_ARCHITECTURE
    }

    switch -Regex ($arch) {
        "ARM64" { return "arm64" }
        "AMD64|x86_64" { return "x86_64" }
        default { return ($arch.ToLowerInvariant()) }
    }
}

# ---------------------------------------------------------------------------
# URL and hash helpers (lifted verbatim from v1/bin/brew.ps1)
# ---------------------------------------------------------------------------

function Test-HttpsOrLocalUri {
    param([string]$Url)

    if ($Url -match "^https://") {
        return $true
    }
    if ($Url -match "^file://") {
        return $true
    }
    if (Test-Path -LiteralPath $Url) {
        return $true
    }

    return $false
}

function Assert-FileHash {
    param(
        [string]$Path,
        [string]$ExpectedSha256
    )

    $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $ExpectedSha256.ToLowerInvariant()) {
        throw "Checksum mismatch for $Path. Expected $ExpectedSha256 but got $actual."
    }
}

# ---------------------------------------------------------------------------
# Runtime manifest + pins
# ---------------------------------------------------------------------------

function Read-RuntimeManifest {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "runtime-manifest.json not found at $Path. The launcher payload looks incomplete; re-run install.ps1."
    }

    try {
        $manifest = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    } catch {
        throw "runtime-manifest.json at $Path is not valid JSON: $($_.Exception.Message)"
    }

    if ($null -eq $manifest.schemaVersion -or $manifest.schemaVersion -ne "0") {
        throw "runtime-manifest.json at $Path has unsupported schemaVersion '$($manifest.schemaVersion)'. Expected '0'."
    }

    if ($null -eq $manifest.components) {
        throw "runtime-manifest.json at $Path is missing the 'components' object."
    }

    return $manifest
}

function Read-RuntimePins {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $null
    }

    try {
        return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    } catch {
        return $null
    }
}

function Get-ComponentProperty {
    param(
        [object]$Container,
        [string]$Name
    )

    if ($null -eq $Container) {
        return $null
    }

    $prop = $Container.PSObject.Properties[$Name]
    if ($null -eq $prop) {
        return $null
    }

    return $prop.Value
}

function Get-ExpectedComponentHash {
    param([object]$Component)

    if ($null -eq $Component) {
        return $null
    }

    $sha = Get-ComponentProperty -Container $Component -Name "sha256"
    if (-not [string]::IsNullOrWhiteSpace($sha)) {
        return $sha
    }

    # The Homebrew component records its working-tree hash rather than an
    # archive sha256. See BOOTSTRAP.md.
    return Get-ComponentProperty -Container $Component -Name "expectedTreeSha256"
}

function Get-PinnedComponentHash {
    param([object]$Pin)

    if ($null -eq $Pin) {
        return $null
    }

    $sha = Get-ComponentProperty -Container $Pin -Name "sha256"
    if (-not [string]::IsNullOrWhiteSpace($sha)) {
        return $sha
    }

    return Get-ComponentProperty -Container $Pin -Name "treeSha256"
}

function Test-RuntimeReady {
    param([string]$Prefix)

    $manifestPath = Join-Path $Prefix "runtime-manifest.json"
    $pinsPath = Join-Path $Prefix "runtime\pins.json"

    $expected = Read-RuntimeManifest -Path $manifestPath
    $pins = Read-RuntimePins -Path $pinsPath

    foreach ($component in @("mingit", "ruby", "homebrew")) {
        $componentDir = Join-Path $Prefix "runtime\$component"
        if (-not (Test-Path -LiteralPath $componentDir -PathType Container)) {
            return $false
        }

        if ($null -eq $pins) {
            return $false
        }

        $expectedComponent = Get-ComponentProperty -Container $expected.components -Name $component
        $pinnedComponent = Get-ComponentProperty -Container $pins.components -Name $component

        $expectedHash = Get-ExpectedComponentHash -Component $expectedComponent
        $pinnedHash = Get-PinnedComponentHash -Component $pinnedComponent

        if ([string]::IsNullOrWhiteSpace($expectedHash) -or [string]::IsNullOrWhiteSpace($pinnedHash)) {
            return $false
        }

        if (-not $expectedHash.Equals($pinnedHash, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $false
        }
    }

    return $true
}

# ---------------------------------------------------------------------------
# Environment contract
# ---------------------------------------------------------------------------

function Set-HomebrewEnvironment {
    param([string]$Prefix)

    $env:HOMEBREW_BREW_FILE       = Join-Path $Prefix "runtime\homebrew\bin\brew"
    $env:HOMEBREW_PREFIX          = $Prefix
    $env:HOMEBREW_REPOSITORY      = Join-Path $Prefix "runtime\homebrew"
    $env:HOMEBREW_LIBRARY         = Join-Path $Prefix "runtime\homebrew\Library"
    $env:HOMEBREW_CELLAR          = Join-Path $Prefix "Cellar"
    $env:HOMEBREW_CACHE           = Join-Path $Prefix "Cache"
    $env:HOMEBREW_TEMP            = Join-Path $Prefix "Temp"
    $env:HOMEBREW_LOGS            = Join-Path $Prefix "Logs"
    $env:HOMEBREW_SYSTEM          = "Windows"
    $env:HOMEBREW_PROCESSOR       = (Get-HomebrewProcessor)
    $env:HOMEBREW_NO_ANALYTICS    = "1"
    $env:HOMEBREW_NO_AUTO_UPDATE  = "1"

    # Force UTF-8 for both PowerShell host streams and the bash subprocess.
    # See HOMEBREW_INTEGRATION.md "Locale, Encoding, And Code Pages".
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
    $env:LANG   = "C.UTF-8"
    $env:LC_ALL = "C.UTF-8"

    # Prepend the vendored runtime to PATH for the bash invocation only.
    # The persisted User PATH still only carries <prefix>\bin.
    $env:PATH = (Join-Path $Prefix "runtime\mingit\usr\bin") + ";" +
                (Join-Path $Prefix "runtime\ruby\bin")       + ";" +
                $env:PATH
}

# ---------------------------------------------------------------------------
# Exec strategy
# ---------------------------------------------------------------------------

function Invoke-UpstreamBrew {
    param(
        [string]$Prefix,
        [string[]]$Arguments
    )

    $bash = Join-Path $Prefix "runtime\mingit\usr\bin\bash.exe"
    if (-not (Test-Path -LiteralPath $bash -PathType Leaf)) {
        throw "MinGit bash not found at $bash. Runtime appears broken; delete <prefix>\runtime and re-run brew."
    }

    $brewScript = Join-Path $Prefix "runtime\homebrew\bin\brew"
    if (-not (Test-Path -LiteralPath $brewScript -PathType Leaf)) {
        throw "Upstream Homebrew bin/brew not found at $brewScript. Runtime appears broken; delete <prefix>\runtime and re-run brew."
    }

    # bash on Windows parses C:\foo as drive C followed by \foo. Use forward
    # slashes for the script path. HOMEBREW_* values stay as native Windows
    # paths because Homebrew's Ruby code expects that. See LAUNCHER.md
    # "Path handling notes".
    $brewScriptUnix = $brewScript.Replace("\", "/")

    if ($null -eq $Arguments) {
        $Arguments = @()
    }

    & $bash $brewScriptUnix @Arguments
    exit $LASTEXITCODE
}

# ---------------------------------------------------------------------------
# Intercepted commands
# ---------------------------------------------------------------------------

function Invoke-SelfUninstall {
    param([string]$Prefix)

    $uninstaller = Join-Path $Prefix "uninstall.ps1"
    if (-not (Test-Path -LiteralPath $uninstaller -PathType Leaf)) {
        throw "Could not find Brew Windows uninstaller at $uninstaller"
    }

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $uninstaller
    exit $LASTEXITCODE
}

function Invoke-SelfUpdate {
    param([string]$Prefix)

    # STUB: real implementation lands in a later wave. For now we print a
    # clear notice and exit 0 so callers can scaffold around the command.
    Write-Host "brew self-update will download the latest Brew Windows release,"
    Write-Host "verify its SHA256, and swap in the new launcher files."
    Write-Host ""
    Write-Host "Not implemented in this build."
    exit 0
}

function Invoke-UpdateInterception {
    param([string]$Prefix)

    # Message text mirrors v2/docs/adr/0006-brew-update-semantics.md.
    Write-Host "brew update is not used in Brew Windows v2."
    Write-Host ""
    Write-Host "Brew Windows v2 pins the Homebrew runtime and formula sources to a"
    Write-Host "specific version. To get newer formulae, update the launcher:"
    Write-Host ""
    Write-Host "    brew self-update"
    Write-Host ""
    Write-Host "This downloads the latest Brew Windows release, which advances the"
    Write-Host "pinned Homebrew commit to a tested version."
    exit 0
}

# ---------------------------------------------------------------------------
# Install-Runtime stub (real implementation lands in Wave 1.C)
# ---------------------------------------------------------------------------

function Install-Runtime {
    param([string]$Prefix)
    throw "Install-Runtime not yet implemented (stub in Wave 1.B). The real implementation lands in Wave 1.C."
}

# ---------------------------------------------------------------------------
# Main dispatch
# ---------------------------------------------------------------------------

try {
    if ($null -eq $BrewArgs) {
        $BrewArgs = @()
    }

    $prefix = Resolve-BrewPrefix

    # Intercepted commands that do not require a working runtime.
    if ($BrewArgs.Count -gt 0) {
        switch ($BrewArgs[0]) {
            "self-uninstall" { Invoke-SelfUninstall -Prefix $prefix; return }
            "self-update"    { Invoke-SelfUpdate -Prefix $prefix;   return }
        }
    }

    if (-not (Test-RuntimeReady -Prefix $prefix)) {
        Install-Runtime -Prefix $prefix
    }

    Set-HomebrewEnvironment -Prefix $prefix

    # `brew update` is intercepted after env is set so that future variants
    # of the message can reference HOMEBREW_* values if needed.
    if ($BrewArgs.Count -gt 0 -and $BrewArgs[0] -eq "update") {
        Invoke-UpdateInterception -Prefix $prefix
        return
    }

    Invoke-UpstreamBrew -Prefix $prefix -Arguments $BrewArgs
} catch {
    Write-Error $_.Exception.Message
    exit 1
}
