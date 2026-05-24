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
    return Get-ComponentProperty -Container $Component -Name "expectedTreeId"
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

    return Get-ComponentProperty -Container $Pin -Name "treeId"
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
        $pinnedHash = Get-PinnedComponentHash -Pin $pinnedComponent

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
    # Upstream's brew.sh rewrites HOMEBREW_PREFIX in some code paths to
    # match HOMEBREW_REPOSITORY (because on macOS/Linux they're typically
    # equal). Stash the real Brew Windows prefix in a separate variable
    # so Windows-aware diagnostic checks (check_runtime_integrity,
    # check_path_brew_windows) can recover it.
    $env:HOMEBREW_WINDOWS_PREFIX  = $Prefix
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

    # Point Homebrew at our vendored toolchain rather than letting it search
    # PATH and version-check whatever it finds. Required for any command path
    # that triggers Homebrew's "validate the system toolchain" branch (e.g.
    # `brew doctor`, `brew install`). `brew --version` has a faster path that
    # works without these but everything else needs them set.
    # Use forward slashes - bash shims under Library/Homebrew/shims/shared/
    # parse these paths with POSIX ${var%/*}/ patterns which only strip
    # forward-slash separators. A backslash path leaves the parameter
    # expansion empty and the shim ends up calling `cd <full-path>/`,
    # which fails with "Error: failed to cd to <full-path>/".
    $env:HOMEBREW_GIT_PATH        = (Join-Path $Prefix "runtime\mingit\cmd\git.exe").Replace('\','/')
    $env:HOMEBREW_RUBY_PATH       = (Join-Path $Prefix "runtime\ruby\bin\ruby.exe").Replace('\','/')
    $env:HOMEBREW_CURL_PATH       = (Join-Path $env:WINDIR "System32\curl.exe").Replace('\','/')

    # Skip the boot-time bundler-gems install. Upstream's
    # standalone/init.rb attempts Process.fork + exec("bundle install")
    # when our Ruby's MAJOR.MINOR does not match Homebrew's vendored
    # version label ("4.0"). Process.fork is unimplemented on Windows.
    # Setting this routes the early init past the fork call. The
    # vendored gems shipped in runtime/homebrew/Library/Homebrew/vendor/bundle/
    # remain available for commands that need them.
    $env:HOMEBREW_SKIP_INITIAL_GEM_INSTALL = "1"

    # Upstream's utils/ruby.sh exports HOMEBREW_BUNDLER_VERSION before
    # invoking ruby. The build child spawned via Utils.safe_fork
    # (Process.spawn under windows-fork-stub.patch) inherits env from
    # the parent Ruby. Set it here so a child Ruby that runs without
    # going through bash again (e.g. build.rb) finds the var on its
    # first read at standalone/init.rb:61. Keep in sync with the
    # vendored ruby.sh value.
    $env:HOMEBREW_BUNDLER_VERSION = "4.0.10"

    # Bypass Hardware::CPU.cores (which uses fork-based IO.popen via
    # Utils.popen) by setting concrete concurrency values. Auto-detection
    # would call getconf via IO.popen("-", mode) - the fork-myself idiom
    # that Windows Ruby does not implement.
    $env:HOMEBREW_DOWNLOAD_CONCURRENCY = "4"
    $env:HOMEBREW_MAKE_JOBS = "4"

    # Skip the API-prefetch step. Homebrew uses a fork-based parallel
    # DownloadQueue (Ruby Process.fork) for prefetching formula/cask JSON
    # APIs. Fork is unimplemented on Windows; downloads error out. The
    # API is only required for some install paths anyway. Doctor and
    # config do not need it.
    $env:HOMEBREW_NO_INSTALL_FROM_API = "1"

    # Force UTF-8 for both PowerShell host streams and the bash subprocess.
    # See HOMEBREW_INTEGRATION.md "Locale, Encoding, And Code Pages".
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
    $env:LANG   = "C.UTF-8"
    $env:LC_ALL = "C.UTF-8"

    # Prepend the vendored runtime to PATH for the bash invocation only.
    # The persisted User PATH still only carries <prefix>\bin.
    # mingit\cmd contains git.exe (Process.spawn / CreateProcess resolves
    # bare "git" through PATH for upstream calls like `safe_system "git"`).
    # mingit\usr\bin contains bash.exe and the POSIX utilities the shell
    # bootstrap depends on.
    $env:PATH = (Join-Path $Prefix "bin")                    + ";" +
                (Join-Path $Prefix "runtime\mingit\cmd")     + ";" +
                (Join-Path $Prefix "runtime\mingit\usr\bin") + ";" +
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
# Install-Runtime - shared helpers
# ---------------------------------------------------------------------------

function Get-UtcIso8601Timestamp {
    return ([DateTime]::UtcNow).ToString("yyyy-MM-ddTHH:mm:ssZ")
}

function Write-RuntimeLogEntry {
    param(
        [string]$LogPath,
        [string]$Component,
        [string]$State,
        [string]$Details
    )

    $line = "{0} {1} {2} {3}" -f (Get-UtcIso8601Timestamp), $Component, $State, $Details
    Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
}

function Get-FileSha256Lower {
    param([string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Move-RuntimeItem {
    param(
        [string]$LiteralSource,
        [string]$LiteralDestination
    )

    # Move-Item can race with Windows AV / EDR products that hold open
    # handles on freshly-extracted executables. Retry on
    # ERROR_SHARING_VIOLATION (0x80070020) up to 3 times with a 1s gap.
    $attempt = 0
    $maxAttempts = 3
    while ($true) {
        $attempt++
        try {
            Move-Item -LiteralPath $LiteralSource -Destination $LiteralDestination -Force
            return
        } catch [System.IO.IOException] {
            $hresult = $_.Exception.HResult
            if ($hresult -ne -2147024864 -and $hresult -ne 0x80070020) {
                throw
            }

            if ($attempt -ge $maxAttempts) {
                throw "Move-Item failed after $maxAttempts attempts due to a sharing violation. This is typically caused by antivirus or endpoint detection software holding open handles on freshly-extracted files. Source: $LiteralSource. Destination: $LiteralDestination. Original error: $($_.Exception.Message)"
            }

            Start-Sleep -Seconds 1
        }
    }
}

function Remove-RuntimePath {
    param(
        [string]$Path,
        [string]$Prefix
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    Assert-PathUnderPrefix -Path $Path -Prefix $Prefix
    Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
}

function Get-DownloadedRuntimeArtifact {
    param(
        [string]$Url,
        [string]$ExpectedSha256,
        [string]$CacheDir,
        [string]$ComponentName,
        [string]$LogPath
    )

    if (-not (Test-HttpsOrLocalUri -Url $Url)) {
        throw "Refusing to download $ComponentName from non-HTTPS URL: $Url"
    }

    $basename = [System.IO.Path]::GetFileName(([System.Uri]$Url).AbsolutePath)
    if ([string]::IsNullOrWhiteSpace($basename)) {
        throw "Could not determine cache filename for $ComponentName URL: $Url"
    }

    $cachePath = Join-Path $CacheDir $basename

    $needsDownload = $true
    if (Test-Path -LiteralPath $cachePath -PathType Leaf) {
        try {
            $existingHash = Get-FileSha256Lower -Path $cachePath
            if ($existingHash -eq $ExpectedSha256.ToLowerInvariant()) {
                $needsDownload = $false
                Write-RuntimeLogEntry -LogPath $LogPath -Component $ComponentName -State "CACHE_HIT" -Details ("path={0} sha256={1}" -f $cachePath, $existingHash)
            }
        } catch {
            $needsDownload = $true
        }
    }

    if ($needsDownload) {
        Write-RuntimeLogEntry -LogPath $LogPath -Component $ComponentName -State "DOWNLOAD_START" -Details ("url={0}" -f $Url)
        try {
            Invoke-WebRequest -Uri $Url -OutFile $cachePath -UseBasicParsing
        } catch {
            throw "Failed to download $ComponentName from ${Url}: $($_.Exception.Message)"
        }
        $downloadedHash = Get-FileSha256Lower -Path $cachePath
        Write-RuntimeLogEntry -LogPath $LogPath -Component $ComponentName -State "DOWNLOADED" -Details ("url={0} sha256={1}" -f $Url, $downloadedHash)
    }

    Assert-FileHash -Path $cachePath -ExpectedSha256 $ExpectedSha256
    $verifiedHash = Get-FileSha256Lower -Path $cachePath
    Write-RuntimeLogEntry -LogPath $LogPath -Component $ComponentName -State "VERIFIED" -Details ("expected={0} actual={1}" -f $ExpectedSha256.ToLowerInvariant(), $verifiedHash)

    return $cachePath
}

function Resolve-StrippedTopLevel {
    param([string]$ExtractedDir)

    $entries = @(Get-ChildItem -LiteralPath $ExtractedDir -Force)
    if ($entries.Count -ne 1 -or -not $entries[0].PSIsContainer) {
        throw "stripTopLevel was requested but the extracted tree at $ExtractedDir does not have exactly one top-level directory (found $($entries.Count) entries)."
    }
    return $entries[0].FullName
}

function Install-RuntimeComponentSwap {
    param(
        [string]$Prefix,
        [string]$ComponentName,
        [string]$StagedSource,
        [string]$LogPath
    )

    $finalDir = Join-Path $Prefix "runtime\$ComponentName"
    $stageRoot = Split-Path -Parent $StagedSource
    $oldDir = Join-Path $stageRoot ("$ComponentName-old")

    Assert-PathUnderPrefix -Path $finalDir -Prefix $Prefix
    Assert-PathUnderPrefix -Path $oldDir -Prefix $Prefix

    $hadExisting = Test-Path -LiteralPath $finalDir -PathType Container
    if ($hadExisting) {
        Move-RuntimeItem -LiteralSource $finalDir -LiteralDestination $oldDir
    }

    try {
        Move-RuntimeItem -LiteralSource $StagedSource -LiteralDestination $finalDir
    } catch {
        if ($hadExisting -and (Test-Path -LiteralPath $oldDir -PathType Container)) {
            try {
                Move-RuntimeItem -LiteralSource $oldDir -LiteralDestination $finalDir
                Write-RuntimeLogEntry -LogPath $LogPath -Component $ComponentName -State "RESTORED_PREVIOUS" -Details ("path={0}" -f $finalDir)
            } catch {
                # Restoration failed; surface both errors.
                throw "Failed to install $ComponentName and the previous version could not be restored. Original error: $($_.Exception.Message). Restore error: see Logs\install-runtime.log."
            }
        }
        throw
    }

    if ($hadExisting -and (Test-Path -LiteralPath $oldDir -PathType Container)) {
        Remove-RuntimePath -Path $oldDir -Prefix $Prefix
    }

    Write-RuntimeLogEntry -LogPath $LogPath -Component $ComponentName -State "INSTALLED" -Details ("path={0}" -f $finalDir)
}

# ---------------------------------------------------------------------------
# Install-Runtime - per-component sub-functions
# ---------------------------------------------------------------------------

function Install-MinGitComponent {
    param(
        [string]$Prefix,
        [object]$Spec,
        [string]$Stage,
        [string]$LogPath
    )

    $url = Get-ComponentProperty -Container $Spec -Name "url"
    $expectedSha = Get-ComponentProperty -Container $Spec -Name "sha256"
    $extractType = [string](Get-ComponentProperty -Container $Spec -Name "extract")
    $stripTopLevel = [bool](Get-ComponentProperty -Container $Spec -Name "stripTopLevel")

    if ([string]::IsNullOrWhiteSpace($url) -or [string]::IsNullOrWhiteSpace($expectedSha)) {
        throw "MinGit component spec is missing url or sha256."
    }

    $cacheDir = Join-Path $Prefix "Cache"
    $archive = Get-DownloadedRuntimeArtifact -Url $url -ExpectedSha256 $expectedSha -CacheDir $cacheDir -ComponentName "mingit" -LogPath $LogPath

    $extractDir = Join-Path $Stage "mingit-extract"
    New-BrewDirectory -Path $extractDir

    Write-RuntimeLogEntry -LogPath $LogPath -Component "mingit" -State "EXTRACT_START" -Details ("archive={0} type={1}" -f $archive, $extractType)
    try {
        switch ($extractType) {
            "zip" {
                Expand-Archive -LiteralPath $archive -DestinationPath $extractDir -Force
            }
            "7z-sfx" {
                # PortableGit and similar self-extracting 7z archives. The .exe
                # honors -o<dir> and -y to extract non-interactively. We have
                # already SHA256-verified the archive before this point.
                & $archive ("-o" + $extractDir) "-y" | Out-Null
                if ($LASTEXITCODE -ne 0) {
                    throw "Self-extracting 7z archive exited with code $LASTEXITCODE."
                }
            }
            default {
                throw "Unsupported extract type '$extractType' for MinGit component. Expected 'zip' or '7z-sfx'."
            }
        }
    } catch {
        throw "Failed to extract MinGit archive ${archive}: $($_.Exception.Message)"
    }

    $stagedSource = if ($stripTopLevel) {
        Resolve-StrippedTopLevel -ExtractedDir $extractDir
    } else {
        $extractDir
    }

    # Rename the staged directory to a stable name so the swap helper can
    # locate its sibling "-old" location.
    $stagedFinal = Join-Path $Stage "mingit"
    if ($stagedSource -ne $stagedFinal) {
        Move-RuntimeItem -LiteralSource $stagedSource -LiteralDestination $stagedFinal
    }

    Write-RuntimeLogEntry -LogPath $LogPath -Component "mingit" -State "EXTRACTED" -Details ("path={0}" -f $stagedFinal)

    Install-RuntimeComponentSwap -Prefix $Prefix -ComponentName "mingit" -StagedSource $stagedFinal -LogPath $LogPath
}

function Install-RubyComponent {
    param(
        [string]$Prefix,
        [object]$Spec,
        [string]$Stage,
        [string]$LogPath
    )

    $url = Get-ComponentProperty -Container $Spec -Name "url"
    $expectedSha = Get-ComponentProperty -Container $Spec -Name "sha256"
    $stripTopLevel = [bool](Get-ComponentProperty -Container $Spec -Name "stripTopLevel")

    if ([string]::IsNullOrWhiteSpace($url) -or [string]::IsNullOrWhiteSpace($expectedSha)) {
        throw "Ruby component spec is missing url or sha256."
    }

    $cacheDir = Join-Path $Prefix "Cache"
    $archive = Get-DownloadedRuntimeArtifact -Url $url -ExpectedSha256 $expectedSha -CacheDir $cacheDir -ComponentName "ruby" -LogPath $LogPath

    $extractDir = Join-Path $Stage "ruby-extract"
    New-BrewDirectory -Path $extractDir

    Write-RuntimeLogEntry -LogPath $LogPath -Component "ruby" -State "EXTRACT_START" -Details ("archive={0}" -f $archive)

    # tar.exe (libarchive) is the primary 7z extractor on Windows 10 1803+.
    # A bundled-7z fallback is a documented follow-up; for now we throw a
    # clear actionable error if tar.exe cannot extract the archive.
    $tarExe = Join-Path $env:WINDIR "System32\tar.exe"
    if (-not (Test-Path -LiteralPath $tarExe -PathType Leaf)) {
        throw "tar.exe was not found at $tarExe. Brew Windows v2 Phase 1 requires the bundled tar.exe (Windows 10 1803+) to extract the RubyInstaller 7z archive. Please file an issue at https://github.com/Euraika-Labs/brew-windows."
    }

    & $tarExe -xf $archive -C $extractDir
    if ($LASTEXITCODE -ne 0) {
        throw "tar.exe failed to extract the RubyInstaller 7z archive (exit code $LASTEXITCODE). A bundled-7z fallback is not yet implemented; please file an issue at https://github.com/Euraika-Labs/brew-windows so we can prioritise it. Archive: $archive"
    }

    $stagedSource = if ($stripTopLevel) {
        Resolve-StrippedTopLevel -ExtractedDir $extractDir
    } else {
        $extractDir
    }

    $stagedFinal = Join-Path $Stage "ruby"
    if ($stagedSource -ne $stagedFinal) {
        Move-RuntimeItem -LiteralSource $stagedSource -LiteralDestination $stagedFinal
    }

    Write-RuntimeLogEntry -LogPath $LogPath -Component "ruby" -State "EXTRACTED" -Details ("path={0}" -f $stagedFinal)

    Install-RuntimeComponentSwap -Prefix $Prefix -ComponentName "ruby" -StagedSource $stagedFinal -LogPath $LogPath
}

function Install-HomebrewComponent {
    param(
        [string]$Prefix,
        [object]$Spec,
        [object[]]$Patches,
        [string]$Stage,
        [string]$LogPath
    )

    $url = Get-ComponentProperty -Container $Spec -Name "url"
    $ref = Get-ComponentProperty -Container $Spec -Name "ref"
    $expectedTreeHash = Get-ComponentProperty -Container $Spec -Name "expectedTreeId"

    if ([string]::IsNullOrWhiteSpace($url) -or [string]::IsNullOrWhiteSpace($ref) -or [string]::IsNullOrWhiteSpace($expectedTreeHash)) {
        throw "Homebrew component spec is missing url, ref, or expectedTreeId."
    }

    if ($ref -notmatch "^[0-9a-fA-F]{40}$") {
        throw "Homebrew ref '$ref' is not a 40-character commit SHA. runtime-manifest.json must pin a commit SHA, never a branch or tag."
    }

    # MinGit was installed in the previous step; use its git.exe.
    $gitExe = Join-Path $Prefix "runtime\mingit\cmd\git.exe"
    if (-not (Test-Path -LiteralPath $gitExe -PathType Leaf)) {
        throw "MinGit git.exe not found at $gitExe after MinGit install. The runtime is in an inconsistent state; delete <prefix>\runtime and re-run brew."
    }

    $cloneDir = Join-Path $Stage "homebrew"
    if (Test-Path -LiteralPath $cloneDir) {
        Remove-Item -LiteralPath $cloneDir -Recurse -Force
    }

    Write-RuntimeLogEntry -LogPath $LogPath -Component "homebrew" -State "CLONE_START" -Details ("url={0} ref={1}" -f $url, $ref)

    & $gitExe clone --depth=1 --no-tags --no-checkout $url $cloneDir
    if ($LASTEXITCODE -ne 0) {
        throw "git clone of $url failed (exit code $LASTEXITCODE)."
    }

    # Enable long-path support inside this repo so git can write files
    # whose absolute Windows paths exceed MAX_PATH (260 chars). Without
    # this, git silently skips files like
    # ...\concurrent-ruby-1.3.6\lib\concurrent-ruby\concurrent\synchronization\abstract_lockable_object.rb
    # leaving a working tree with missing files that show up as deleted
    # in `git status` later.
    & $gitExe -C $cloneDir config core.longpaths true

    & $gitExe -C $cloneDir fetch --depth=1 origin $ref
    if ($LASTEXITCODE -ne 0) {
        throw "git fetch of commit $ref from $url failed (exit code $LASTEXITCODE)."
    }

    & $gitExe -C $cloneDir checkout $ref
    if ($LASTEXITCODE -ne 0) {
        throw "git checkout of commit $ref failed (exit code $LASTEXITCODE)."
    }

    Write-RuntimeLogEntry -LogPath $LogPath -Component "homebrew" -State "CHECKED_OUT" -Details ("ref={0}" -f $ref)

    # Phase 1 tree-hash: use git's own tree object id (SHA-1, 40 hex chars).
    # The runtime-manifest.json field is named expectedTreeId for forward
    # compatibility with a future recursive SHA256 of the working tree, but
    # the v0 semantics is git's tree object id. See BOOTSTRAP.md and the
    # follow-up note in this function.
    $treeHash = (& $gitExe -C $cloneDir rev-parse "$ref^{tree}") | Out-String
    $treeHash = $treeHash.Trim().ToLowerInvariant()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($treeHash)) {
        throw "git rev-parse failed to compute the tree hash for ref $ref."
    }

    $expectedTreeHashLower = $expectedTreeHash.ToLowerInvariant()
    if (-not $treeHash.Equals($expectedTreeHashLower, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Homebrew tree hash mismatch. Expected $expectedTreeHashLower but got $treeHash. The upstream repository may have been rewritten, or the manifest is out of sync."
    }

    Write-RuntimeLogEntry -LogPath $LogPath -Component "homebrew" -State "TREE_VERIFIED" -Details ("expected={0} actual={1}" -f $expectedTreeHashLower, $treeHash)

    if ($null -ne $Patches) {
        foreach ($patch in $Patches) {
            $patchRelPath = Get-ComponentProperty -Container $patch -Name "path"
            $patchSha = Get-ComponentProperty -Container $patch -Name "sha256"
            $appliesTo = Get-ComponentProperty -Container $patch -Name "appliesTo"

            if ([string]::IsNullOrWhiteSpace($patchRelPath) -or [string]::IsNullOrWhiteSpace($patchSha)) {
                throw "Patch entry is missing path or sha256."
            }

            if (-not [string]::IsNullOrWhiteSpace($appliesTo) -and $appliesTo -ne "homebrew") {
                # Only homebrew-targeted patches are applied here.
                continue
            }

            $patchAbsPath = Join-Path $Prefix $patchRelPath
            if (-not (Test-Path -LiteralPath $patchAbsPath -PathType Leaf)) {
                throw "Patch file not found at $patchAbsPath. The launcher payload looks incomplete; re-run install.ps1."
            }

            Assert-FileHash -Path $patchAbsPath -ExpectedSha256 $patchSha
            $patchActualSha = Get-FileSha256Lower -Path $patchAbsPath

            & $gitExe -C $cloneDir apply --check $patchAbsPath
            if ($LASTEXITCODE -ne 0) {
                throw "git apply --check failed for patch $patchRelPath. The patch does not apply cleanly to the pinned Homebrew commit; the launcher and runtime manifest are out of sync."
            }

            & $gitExe -C $cloneDir apply $patchAbsPath
            if ($LASTEXITCODE -ne 0) {
                throw "git apply failed for patch $patchRelPath after --check succeeded. Working tree may be in a partial state; bootstrap aborted."
            }

            Write-RuntimeLogEntry -LogPath $LogPath -Component "homebrew" -State "PATCH_APPLIED" -Details ("file={0} sha256={1}" -f $patchRelPath, $patchActualSha)
        }
    }

    Install-RuntimeComponentSwap -Prefix $Prefix -ComponentName "homebrew" -StagedSource $cloneDir -LogPath $LogPath

    # The swap (Move-Item of the staging tree) can lose files on very deep
    # paths under certain Windows conditions. Recover by re-checking-out
    # HEAD from the moved git repo (cheap because all blobs are local) and
    # then re-applying the patches against the recovered working tree.
    $installedHomebrew = Join-Path $Prefix "runtime\homebrew"
    # git emits whitespace warnings on stderr; our StrictMode + $ErrorActionPreference="Stop"
    # promotes that to a fatal error. Wrap each native invocation in a
    # try/catch that swallows the wrapped NativeCommandError so long as
    # $LASTEXITCODE indicates success.
    function Invoke-GitQuiet {
        param([string]$Exe, [string[]]$Args, [string]$Cwd)
        try {
            $oldPref = $ErrorActionPreference
            $ErrorActionPreference = "Continue"
            $argv = @("-C", $Cwd) + $Args
            & $Exe @argv 2>&1 | Out-Null
        } finally {
            $ErrorActionPreference = $oldPref
        }
    }

    Invoke-GitQuiet -Exe $gitExe -Args @("reset", "--hard", "HEAD") -Cwd $installedHomebrew
    Invoke-GitQuiet -Exe $gitExe -Args @("clean", "-fdx") -Cwd $installedHomebrew
    if ($null -ne $Patches) {
        foreach ($patch in $Patches) {
            $patchRelPath = Get-ComponentProperty -Container $patch -Name "path"
            $appliesTo = Get-ComponentProperty -Container $patch -Name "appliesTo"
            if (-not [string]::IsNullOrWhiteSpace($appliesTo) -and $appliesTo -ne "homebrew") { continue }
            $patchAbsPath = Join-Path $Prefix $patchRelPath
            Invoke-GitQuiet -Exe $gitExe -Args @("apply", $patchAbsPath) -Cwd $installedHomebrew
        }
    }
    Write-RuntimeLogEntry -LogPath $LogPath -Component "homebrew" -State "POST_SWAP_RECHECKOUT" -Details ("path={0}" -f $installedHomebrew)

    # The symlink repair has to run AFTER the swap so the junctions store
    # absolute paths to the final installed location (NTFS reparse points
    # always resolve relative targets to absolute at creation time).
    Repair-GitSymlinks -RepoDir $installedHomebrew -GitExe $gitExe -LogPath $LogPath

    # Stage and commit the patched + symlink-repaired runtime so the
    # working tree is clean from Homebrew's perspective. Without this,
    # `brew doctor` -> check_git_status sees our intentional patches as
    # uncommitted modifications. Use --no-gpg-sign + --no-verify so the
    # user's global commit signing / hooks do not interfere with the
    # vendored runtime's bootstrap; this commit is purely local and
    # never pushed anywhere.
    # Use a single-token user.name to dodge PowerShell -> cmd.exe argument
    # splitting on spaces. The commit only exists in this local clone and
    # is never pushed; the author identity is informational.
    $oldPref2 = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        & $gitExe -C $installedHomebrew -c "user.name=brew-windows-bootstrap" -c "user.email=bootstrap@brew-windows.invalid" add -A 2>&1 | Out-Null
        $addExit = $LASTEXITCODE
        & $gitExe -C $installedHomebrew -c "user.name=brew-windows-bootstrap" -c "user.email=bootstrap@brew-windows.invalid" commit --no-gpg-sign --no-verify -m "BrewWindows-runtime-patches-applied" 2>&1 | Out-Null
        $commitExit = $LASTEXITCODE
        Write-RuntimeLogEntry -LogPath $LogPath -Component "homebrew" -State "POST_SWAP_COMMIT" -Details ("add_exit={0} commit_exit={1}" -f $addExit, $commitExit)
    } finally {
        $ErrorActionPreference = $oldPref2
    }
    Write-RuntimeLogEntry -LogPath $LogPath -Component "homebrew" -State "POST_SWAP_COMMIT" -Details "patches and symlink repairs committed"
}

function Repair-GitSymlinks {
    param(
        [string]$RepoDir,
        [string]$GitExe,
        [string]$LogPath
    )

    # Git on Windows without admin/Developer Mode writes symbolic-link
    # entries as plain text files containing the link target instead of
    # creating real symlinks. Homebrew's repository ships ~159 such
    # symlinks (notably vendor/gems/<gem> -> <gem>-<version>/) that Ruby
    # code requires via the unsuffixed name. Without repair, every
    # require("vendor/gems/mechanize/...") fails with LoadError and
    # Homebrew.require? silently swallows it - which masquerades as
    # "Unknown command: brew <name>" for any cmd whose load chain touches
    # download_strategy.rb (including brew doctor, brew install, etc.).
    #
    # Resolution without elevation: create NTFS junctions for directory
    # targets and hardlinks for file targets. Both work without admin
    # rights or Developer Mode.

    $entries = & $GitExe -C $RepoDir ls-files --stage
    if ($LASTEXITCODE -ne 0) {
        throw "git ls-files failed while scanning for symlinks (exit $LASTEXITCODE)."
    }

    $repaired = 0
    foreach ($line in $entries) {
        if (-not ($line -match "^120000\s+\S+\s+\S+\s+(.+)$")) {
            continue
        }

        $relPath = $matches[1].Trim()
        $linkFile = Join-Path $RepoDir $relPath
        if (-not (Test-Path -LiteralPath $linkFile -PathType Leaf)) {
            continue
        }

        $targetSpec = (Get-Content -LiteralPath $linkFile -Raw).TrimEnd("`r","`n","/","\")
        if ([string]::IsNullOrWhiteSpace($targetSpec)) {
            continue
        }

        $linkDir = Split-Path -Parent $linkFile
        $targetAbs = [System.IO.Path]::GetFullPath((Join-Path $linkDir $targetSpec))
        if (-not (Test-Path -LiteralPath $targetAbs)) {
            # Dangling symlink in the upstream repo - skip silently.
            continue
        }

        Remove-Item -LiteralPath $linkFile -Force
        if (Test-Path -LiteralPath $targetAbs -PathType Container) {
            # Directory junction. No admin required.
            & cmd.exe /c mklink /J "`"$linkFile`"" "`"$targetAbs`"" 2>$null | Out-Null
        } else {
            # File hardlink. No admin required.
            & cmd.exe /c mklink /H "`"$linkFile`"" "`"$targetAbs`"" 2>$null | Out-Null
        }
        if ($LASTEXITCODE -eq 0) {
            $repaired++
        }
    }

    Write-RuntimeLogEntry -LogPath $LogPath -Component "homebrew" -State "SYMLINKS_REPAIRED" -Details ("count={0}" -f $repaired)
}

# ---------------------------------------------------------------------------
# Install-Runtime - pins writer
# ---------------------------------------------------------------------------

function Write-RuntimePins {
    param(
        [string]$Prefix,
        [object]$Manifest
    )

    $mingit = Get-ComponentProperty -Container $Manifest.components -Name "mingit"
    $ruby = Get-ComponentProperty -Container $Manifest.components -Name "ruby"
    $homebrew = Get-ComponentProperty -Container $Manifest.components -Name "homebrew"

    $patchesApplied = @()
    if ($null -ne $Manifest.PSObject.Properties["patches"] -and $null -ne $Manifest.patches) {
        foreach ($patch in $Manifest.patches) {
            $patchesApplied += [ordered]@{
                path   = (Get-ComponentProperty -Container $patch -Name "path")
                sha256 = (Get-ComponentProperty -Container $patch -Name "sha256")
            }
        }
    }

    $pins = [ordered]@{
        schemaVersion   = "0"
        installedAt     = (Get-UtcIso8601Timestamp)
        launcherVersion = $Script:LauncherVersion
        components      = [ordered]@{
            mingit   = [ordered]@{
                version = (Get-ComponentProperty -Container $mingit -Name "version")
                sha256  = (Get-ComponentProperty -Container $mingit -Name "sha256")
            }
            ruby     = [ordered]@{
                version = (Get-ComponentProperty -Container $ruby -Name "version")
                sha256  = (Get-ComponentProperty -Container $ruby -Name "sha256")
            }
            homebrew = [ordered]@{
                ref        = (Get-ComponentProperty -Container $homebrew -Name "ref")
                treeId = (Get-ComponentProperty -Container $homebrew -Name "expectedTreeId")
            }
        }
        patchesApplied  = $patchesApplied
    }

    $pinsPath = Join-Path $Prefix "runtime\pins.json"
    Assert-PathUnderPrefix -Path $pinsPath -Prefix $Prefix

    $json = $pins | ConvertTo-Json -Depth 10
    # Windows PowerShell 5.1's Set-Content -Encoding UTF8 prepends a
    # UTF-8 BOM that Ruby's JSON.parse rejects with "unexpected character"
    # at column 1. Write a BOM-less UTF-8 file explicitly via .NET. ASCII
    # would also work since pin data is pure JSON, but UTF-8-no-BOM is the
    # safer default if a future pin records, e.g., a UTF-8 patch path.
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($pinsPath, $json, $utf8NoBom)
}

# ---------------------------------------------------------------------------
# Install-Runtime - top-level driver
# ---------------------------------------------------------------------------

function Install-Runtime {
    param([string]$Prefix)

    Write-Host "Bootstrapping Homebrew runtime..."

    $manifestPath = Join-Path $Prefix "runtime-manifest.json"
    $manifest = Read-RuntimeManifest -Path $manifestPath

    $placeholders = $false
    if ($null -ne $manifest.PSObject.Properties["placeholdersFilled"]) {
        $placeholders = -not [bool]$manifest.placeholdersFilled
    } else {
        # Field absent: treat as still-placeholder for safety.
        $placeholders = $true
    }

    if ($placeholders) {
        throw "runtime-manifest.json still contains placeholder SHA256s (placeholdersFilled: false). Re-build the launcher with v2/scripts/pin-runtime.ps1 before running Install-Runtime."
    }

    foreach ($d in @("Cache", "Temp", "runtime", "Logs")) {
        $dir = Join-Path $Prefix $d
        Assert-PathUnderPrefix -Path $dir -Prefix $Prefix
        New-BrewDirectory -Path $dir
    }

    $stage = Join-Path $Prefix ("Temp\runtime-stage-" + [Guid]::NewGuid().ToString("N"))
    Assert-PathUnderPrefix -Path $stage -Prefix $Prefix
    New-BrewDirectory -Path $stage

    $logPath = Join-Path $Prefix "Logs\install-runtime.log"
    Write-RuntimeLogEntry -LogPath $logPath -Component "runtime" -State "BOOTSTRAP_START" -Details ("prefix={0} launcher={1}" -f $Prefix, $Script:LauncherVersion)

    try {
        $mingitSpec = Get-ComponentProperty -Container $manifest.components -Name "mingit"
        $rubySpec = Get-ComponentProperty -Container $manifest.components -Name "ruby"
        $homebrewSpec = Get-ComponentProperty -Container $manifest.components -Name "homebrew"

        if ($null -eq $mingitSpec -or $null -eq $rubySpec -or $null -eq $homebrewSpec) {
            throw "runtime-manifest.json is missing one of: components.mingit, components.ruby, components.homebrew."
        }

        $patches = @()
        if ($null -ne $manifest.PSObject.Properties["patches"] -and $null -ne $manifest.patches) {
            $patches = @($manifest.patches)
        }

        Install-MinGitComponent   -Prefix $Prefix -Spec $mingitSpec   -Stage $stage -LogPath $logPath
        Install-RubyComponent     -Prefix $Prefix -Spec $rubySpec     -Stage $stage -LogPath $logPath
        Install-HomebrewComponent -Prefix $Prefix -Spec $homebrewSpec -Patches $patches -Stage $stage -LogPath $logPath

        Write-RuntimePins -Prefix $Prefix -Manifest $manifest

        Write-RuntimeLogEntry -LogPath $logPath -Component "runtime" -State "BOOTSTRAP_COMPLETE" -Details ("prefix={0}" -f $Prefix)
        Write-Host "Runtime bootstrap complete."
    } finally {
        if (Test-Path -LiteralPath $stage -PathType Container) {
            try {
                Assert-PathUnderPrefix -Path $stage -Prefix $Prefix
                Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
            } catch {
                # Cleanup is best-effort; never mask the original error.
            }
        }
    }
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
