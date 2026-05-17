param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$BrewArgs
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$Script:BrewVersion = "0.1.0-dev"
$Script:JsonMode = $false

function Resolve-BrewPrefix {
    if (-not [string]::IsNullOrWhiteSpace($env:HOMEBREW_PREFIX)) {
        return [System.IO.Path]::GetFullPath($env:HOMEBREW_PREFIX)
    }

    $scriptPath = if ($PSCommandPath) { $PSCommandPath } else { $MyInvocation.MyCommand.Path }
    $binDir = Split-Path -Parent $scriptPath
    return [System.IO.Path]::GetFullPath((Split-Path -Parent $binDir))
}

$Script:Prefix = Resolve-BrewPrefix
$Script:Paths = [ordered]@{
    Prefix = $Script:Prefix
    Bin = Join-Path $Script:Prefix "bin"
    Cellar = Join-Path $Script:Prefix "Cellar"
    Opt = Join-Path $Script:Prefix "opt"
    Library = Join-Path $Script:Prefix "Library"
    Taps = Join-Path $Script:Prefix "Library\Taps"
    Var = Join-Path $Script:Prefix "var\homebrew"
    Cache = Join-Path $Script:Prefix "Cache"
    Logs = Join-Path $Script:Prefix "Logs"
    Temp = Join-Path $Script:Prefix "Temp"
    Receipts = Join-Path $Script:Prefix "var\homebrew\receipts"
}

function ConvertTo-BrewJson {
    param([object]$Value)
    $Value | ConvertTo-Json -Depth 40
}

function Write-BrewObject {
    param([object]$Value)
    if ($Script:JsonMode) {
        ConvertTo-BrewJson $Value
    } else {
        $Value
    }
}

function Write-BrewError {
    param(
        [string]$Message,
        [int]$ExitCode = 1
    )

    if ($Script:JsonMode) {
        ConvertTo-BrewJson ([ordered]@{
            ok = $false
            error = [ordered]@{
                message = $Message
                code = $ExitCode
            }
        })
        exit $ExitCode
    }

    Write-Error $Message
    exit $ExitCode
}

function New-BrewDirectory {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        New-Item -ItemType Directory -Force -Path $Path | Out-Null
    }
}

function Initialize-BrewPrefix {
    foreach ($path in $Script:Paths.Values) {
        New-BrewDirectory -Path $path
    }
}

function Get-CanonicalPath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path).TrimEnd("\")
}

function Assert-PathUnderPrefix {
    param([string]$Path)

    $prefix = (Get-CanonicalPath $Script:Prefix) + "\"
    $full = (Get-CanonicalPath $Path) + "\"
    if (-not $full.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
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

function Get-ManifestFiles {
    $files = New-Object System.Collections.Generic.List[string]

    if (-not [string]::IsNullOrWhiteSpace($env:HOMEBREW_TAP_PATHS)) {
        foreach ($tapPath in $env:HOMEBREW_TAP_PATHS.Split(";", [System.StringSplitOptions]::RemoveEmptyEntries)) {
            if (Test-Path -LiteralPath $tapPath -PathType Leaf) {
                if ($tapPath.EndsWith(".json", [System.StringComparison]::OrdinalIgnoreCase)) {
                    $files.Add((Get-CanonicalPath $tapPath))
                }
            } elseif (Test-Path -LiteralPath $tapPath -PathType Container) {
                Get-ChildItem -LiteralPath $tapPath -Recurse -Filter "*.json" -File |
                    ForEach-Object { $files.Add($_.FullName) }
            }
        }
    }

    if (Test-Path -LiteralPath $Script:Paths.Taps -PathType Container) {
        Get-ChildItem -LiteralPath $Script:Paths.Taps -Recurse -Filter "*.json" -File |
            ForEach-Object { $files.Add($_.FullName) }
    }

    return $files | Sort-Object -Unique
}

function Read-Manifest {
    param([string]$Path)

    $manifest = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    $manifest | Add-Member -NotePropertyName "__path" -NotePropertyValue $Path -Force
    return $manifest
}

function Get-Manifests {
    $items = @()
    foreach ($file in Get-ManifestFiles) {
        try {
            $items += Read-Manifest -Path $file
        } catch {
            throw "Invalid manifest $file`: $($_.Exception.Message)"
        }
    }

    return $items | Sort-Object name
}

function Find-Manifest {
    param([string]$Name)

    $matches = @(Get-Manifests | Where-Object { $_.name -ieq $Name })
    if ($matches.Count -eq 0) {
        throw "No formula found for '$Name'."
    }
    if ($matches.Count -gt 1) {
        throw "Formula '$Name' is ambiguous across tap paths."
    }

    return $matches[0]
}

function Get-ManifestVariant {
    param([object]$Manifest)

    if ($null -eq $Manifest.platforms -or $null -eq $Manifest.platforms.windows) {
        throw "Formula '$($Manifest.name)' does not support Windows."
    }

    $arch = Get-WindowsArchitectureKey
    $arches = $Manifest.platforms.windows.arches
    $property = $arches.PSObject.Properties[$arch]
    if ($null -eq $property) {
        throw "Formula '$($Manifest.name)' does not support Windows architecture '$arch'."
    }

    return [ordered]@{
        architecture = $arch
        value = $property.Value
    }
}

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

function Save-Artifact {
    param(
        [string]$Url,
        [string]$Destination
    )

    if (-not (Test-HttpsOrLocalUri -Url $Url)) {
        throw "Only HTTPS and local file artifacts are supported: $Url"
    }

    New-BrewDirectory -Path (Split-Path -Parent $Destination)

    if ($Url -match "^https://") {
        Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing
        return
    }

    if ($Url -match "^file://") {
        $uri = [uri]$Url
        Copy-Item -LiteralPath $uri.LocalPath -Destination $Destination -Force
        return
    }

    Copy-Item -LiteralPath $Url -Destination $Destination -Force
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

function Expand-Artifact {
    param(
        [string]$ArchivePath,
        [string]$Destination,
        [string]$Type
    )

    New-BrewDirectory -Path $Destination
    switch ($Type) {
        "zip" {
            Expand-Archive -LiteralPath $ArchivePath -DestinationPath $Destination -Force
        }
        "tgz" {
            & tar.exe -xzf $ArchivePath -C $Destination
            if ($LASTEXITCODE -ne 0) {
                throw "tar.exe failed to extract $ArchivePath"
            }
        }
        "tar.gz" {
            & tar.exe -xzf $ArchivePath -C $Destination
            if ($LASTEXITCODE -ne 0) {
                throw "tar.exe failed to extract $ArchivePath"
            }
        }
        default {
            throw "Unsupported archive type '$Type'."
        }
    }
}

function Copy-PayloadFiles {
    param(
        [string]$SourceRoot,
        [string]$StageRoot,
        [object]$InstallSpec
    )

    New-BrewDirectory -Path $StageRoot

    if ($null -ne $InstallSpec -and $null -ne $InstallSpec.files) {
        foreach ($fileMap in $InstallSpec.files) {
            $from = Join-Path $SourceRoot $fileMap.from
            $to = Join-Path $StageRoot $fileMap.to
            if (-not (Test-Path -LiteralPath $from -PathType Leaf)) {
                throw "Expected payload file is missing: $from"
            }
            New-BrewDirectory -Path (Split-Path -Parent $to)
            Copy-Item -LiteralPath $from -Destination $to -Force
        }
        return
    }

    Get-ChildItem -LiteralPath $SourceRoot -Force | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $StageRoot -Recurse -Force
    }
}

function Get-ManifestBins {
    param([object]$Manifest)

    if ($null -eq $Manifest.bin) {
        return @()
    }

    if ($Manifest.bin -is [array]) {
        return $Manifest.bin
    }

    return @($Manifest.bin)
}

function New-Shim {
    param(
        [string]$Name,
        [string]$TargetPath
    )

    $ps1Path = Join-Path $Script:Paths.Bin "$Name.ps1"
    $cmdPath = Join-Path $Script:Paths.Bin "$Name.cmd"
    $escapedTarget = $TargetPath.Replace("'", "''")

    $ps1 = @"
# Generated by Brew Windows. Do not edit.
`$ErrorActionPreference = "Stop"
`$target = '$escapedTarget'
& `$target @args
exit `$LASTEXITCODE
"@

    $cmd = @"
@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0$Name.ps1" %*
exit /b %ERRORLEVEL%
"@

    Set-Content -LiteralPath $ps1Path -Value $ps1 -Encoding UTF8
    Set-Content -LiteralPath $cmdPath -Value $cmd -Encoding ASCII
}

function Remove-Shim {
    param([string]$Name)

    foreach ($extension in @(".ps1", ".cmd")) {
        $path = Join-Path $Script:Paths.Bin "$Name$extension"
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            Remove-Item -LiteralPath $path -Force
        }
    }
}

function Get-ReceiptPath {
    param([string]$Name)
    return Join-Path $Script:Paths.Receipts "$Name.json"
}

function Read-Receipt {
    param([string]$Name)

    $path = Get-ReceiptPath -Name $Name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return $null
    }

    return Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
}

function Write-Receipt {
    param(
        [object]$Manifest,
        [object]$Variant,
        [string]$CellarPath
    )

    $bins = @()
    foreach ($bin in Get-ManifestBins -Manifest $Manifest) {
        $bins += [ordered]@{
            name = $bin.name
            path = $bin.path
        }
    }

    $receipt = [ordered]@{
        name = $Manifest.name
        version = $Manifest.version
        architecture = $Variant.architecture
        installedAt = [DateTimeOffset]::UtcNow.ToString("o")
        manifestPath = $Manifest.__path
        cellarPath = $CellarPath
        bins = $bins
    }

    New-BrewDirectory -Path $Script:Paths.Receipts
    ConvertTo-BrewJson $receipt | Set-Content -LiteralPath (Get-ReceiptPath -Name $Manifest.name) -Encoding UTF8
}

function Install-Formula {
    param(
        [string]$Name,
        [bool]$Force
    )

    Initialize-BrewPrefix
    $manifest = Find-Manifest -Name $Name
    $variantInfo = Get-ManifestVariant -Manifest $manifest
    $variant = $variantInfo.value
    $cellarParent = Join-Path $Script:Paths.Cellar $manifest.name
    $cellarPath = Join-Path $cellarParent $manifest.version

    if ((Test-Path -LiteralPath $cellarPath -PathType Container) -and -not $Force) {
        $message = "$($manifest.name) $($manifest.version) is already installed."
        if ($Script:JsonMode) {
            Write-BrewObject ([ordered]@{ ok = $true; changed = $false; message = $message })
        } else {
            Write-Host $message
        }
        return
    }

    $assetName = Split-Path -Leaf $variant.url
    $archivePath = Join-Path $Script:Paths.Cache $assetName
    $workRoot = Join-Path $Script:Paths.Temp ("install-" + $manifest.name + "-" + [System.Guid]::NewGuid().ToString("N"))
    $extractRoot = Join-Path $workRoot "extract"
    $stageRoot = Join-Path $workRoot "stage"

    try {
        Save-Artifact -Url $variant.url -Destination $archivePath
        Assert-FileHash -Path $archivePath -ExpectedSha256 $variant.sha256

        $archiveType = $variant.extract.type
        Expand-Artifact -ArchivePath $archivePath -Destination $extractRoot -Type $archiveType

        $sourceRoot = $extractRoot
        $sourcePathProperty = $variant.extract.PSObject.Properties["sourcePath"]
        if ($null -ne $sourcePathProperty -and -not [string]::IsNullOrWhiteSpace($sourcePathProperty.Value)) {
            $sourceRoot = Join-Path $extractRoot $sourcePathProperty.Value
        }
        if (-not (Test-Path -LiteralPath $sourceRoot -PathType Container)) {
            throw "Archive source root does not exist: $sourceRoot"
        }

        $installSpec = $null
        $installProperty = $variant.PSObject.Properties["install"]
        if ($null -ne $installProperty) {
            $installSpec = $installProperty.Value
        }
        Copy-PayloadFiles -SourceRoot $sourceRoot -StageRoot $stageRoot -InstallSpec $installSpec

        foreach ($bin in Get-ManifestBins -Manifest $manifest) {
            $target = Join-Path $stageRoot $bin.path
            if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
                throw "Formula '$($manifest.name)' did not install expected binary: $($bin.path)"
            }
        }

        New-BrewDirectory -Path $cellarParent
        if (Test-Path -LiteralPath $cellarPath) {
            Assert-PathUnderPrefix -Path $cellarPath
            Remove-Item -LiteralPath $cellarPath -Recurse -Force
        }
        Move-Item -LiteralPath $stageRoot -Destination $cellarPath

        foreach ($bin in Get-ManifestBins -Manifest $manifest) {
            New-Shim -Name $bin.name -TargetPath (Join-Path $cellarPath $bin.path)
        }

        Write-Receipt -Manifest $manifest -Variant $variantInfo -CellarPath $cellarPath

        if ($Script:JsonMode) {
            Write-BrewObject ([ordered]@{
                ok = $true
                changed = $true
                name = $manifest.name
                version = $manifest.version
                cellarPath = $cellarPath
            })
        } else {
            Write-Host "Installed $($manifest.name) $($manifest.version)"
        }
    } finally {
        if (Test-Path -LiteralPath $workRoot) {
            Assert-PathUnderPrefix -Path $workRoot
            Remove-Item -LiteralPath $workRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Uninstall-Formula {
    param([string]$Name)

    Initialize-BrewPrefix
    $receipt = Read-Receipt -Name $Name
    if ($null -eq $receipt) {
        throw "Formula '$Name' is not installed."
    }

    foreach ($bin in $receipt.bins) {
        Remove-Shim -Name $bin.name
    }

    if (Test-Path -LiteralPath $receipt.cellarPath) {
        Assert-PathUnderPrefix -Path $receipt.cellarPath
        Remove-Item -LiteralPath $receipt.cellarPath -Recurse -Force
    }

    $receiptPath = Get-ReceiptPath -Name $Name
    if (Test-Path -LiteralPath $receiptPath) {
        Remove-Item -LiteralPath $receiptPath -Force
    }

    $cellarParent = Join-Path $Script:Paths.Cellar $Name
    if ((Test-Path -LiteralPath $cellarParent -PathType Container) -and
        $null -eq (Get-ChildItem -LiteralPath $cellarParent -Force | Select-Object -First 1)) {
        Remove-Item -LiteralPath $cellarParent -Force
    }

    if ($Script:JsonMode) {
        Write-BrewObject ([ordered]@{ ok = $true; changed = $true; name = $Name })
    } else {
        Write-Host "Uninstalled $Name"
    }
}

function Get-InstalledReceipts {
    Initialize-BrewPrefix
    if (-not (Test-Path -LiteralPath $Script:Paths.Receipts -PathType Container)) {
        return @()
    }

    return @(Get-ChildItem -LiteralPath $Script:Paths.Receipts -Filter "*.json" -File | ForEach-Object {
        Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json
    } | Sort-Object name)
}

function Show-Help {
    @"
Brew Windows $Script:BrewVersion

Usage:
  brew <command> [options]

Commands:
  --version              Print Brew Windows version
  --prefix               Print HOMEBREW_PREFIX
  --cellar               Print HOMEBREW_CELLAR
  config                 Print native Windows configuration
  doctor                 Diagnose the current prefix
  search [text]          Search formula manifests
  info <name>            Show formula metadata
  install <name>         Install a formula
  uninstall <name>       Uninstall a formula
  list                   List installed formulae
  update                 Refresh local metadata placeholder
  upgrade [name]         Reinstall installed formulae from current manifests
  self-uninstall         Run the Brew Windows uninstaller

Global options:
  --json                 Emit machine-readable JSON where supported
"@
}

function Show-Config {
    Initialize-BrewPrefix
    $config = [ordered]@{
        version = $Script:BrewVersion
        system = "windows"
        processor = Get-WindowsArchitectureKey
        prefix = $Script:Paths.Prefix
        cellar = $Script:Paths.Cellar
        repository = $Script:Paths.Prefix
        library = $Script:Paths.Library
        cache = $Script:Paths.Cache
        temp = $Script:Paths.Temp
        logs = $Script:Paths.Logs
        tapPaths = @(Get-ManifestFiles | ForEach-Object { Split-Path -Parent $_ } | Sort-Object -Unique)
    }

    if ($Script:JsonMode) {
        Write-BrewObject $config
    } else {
        foreach ($key in $config.Keys) {
            $value = $config[$key]
            if ($value -is [array]) {
                $value = $value -join ";"
            }
            Write-Host ("{0}: {1}" -f $key, $value)
        }
    }
}

function Invoke-Doctor {
    Initialize-BrewPrefix
    $warnings = New-Object System.Collections.Generic.List[string]

    if ($env:OS -ne "Windows_NT") {
        $warnings.Add("This prototype supports native Windows only.")
    }

    if (-not (Test-PathListContains -PathValue $env:Path -Entry $Script:Paths.Bin)) {
        $warnings.Add("$($Script:Paths.Bin) is not on the current process PATH.")
    }

    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if (-not (Test-PathListContains -PathValue $userPath -Entry $Script:Paths.Bin)) {
        $warnings.Add("$($Script:Paths.Bin) is not on the User PATH.")
    }

    foreach ($receipt in Get-InstalledReceipts) {
        foreach ($bin in $receipt.bins) {
            $shimPath = Join-Path $Script:Paths.Bin "$($bin.name).cmd"
            if (-not (Test-Path -LiteralPath $shimPath -PathType Leaf)) {
                $warnings.Add("Missing shim for installed formula '$($receipt.name)': $shimPath")
            }
            $command = Get-Command $bin.name -ErrorAction SilentlyContinue
            if ($null -ne $command -and -not $command.Source.StartsWith($Script:Paths.Bin, [System.StringComparison]::OrdinalIgnoreCase)) {
                $warnings.Add("Command '$($bin.name)' is shadowed by $($command.Source).")
            }
        }
    }

    $policies = @()
    try {
        $policies = @(Get-ExecutionPolicy -List | ForEach-Object {
            [ordered]@{ scope = $_.Scope.ToString(); policy = $_.ExecutionPolicy.ToString() }
        })
    } catch {
        $warnings.Add("Could not read PowerShell execution policies: $($_.Exception.Message)")
    }

    $result = [ordered]@{
        ok = ($warnings.Count -eq 0)
        prefix = $Script:Paths.Prefix
        warnings = @($warnings)
        executionPolicies = $policies
    }

    if ($Script:JsonMode) {
        Write-BrewObject $result
    } else {
        if ($warnings.Count -eq 0) {
            Write-Host "Your system is ready to brew on native Windows."
        } else {
            Write-Host "Brew Windows found $($warnings.Count) warning(s):"
            foreach ($warning in $warnings) {
                Write-Host "- $warning"
            }
        }
    }
}

function Search-Formulae {
    param([string]$Query)

    $items = @(Get-Manifests | Where-Object {
        [string]::IsNullOrWhiteSpace($Query) -or
        $_.name -like "*$Query*" -or
        $_.description -like "*$Query*"
    } | ForEach-Object {
        [ordered]@{
            name = $_.name
            version = $_.version
            description = $_.description
        }
    })

    if ($Script:JsonMode) {
        Write-BrewObject $items
    } else {
        foreach ($item in $items) {
            Write-Host ("{0} {1} - {2}" -f $item.name, $item.version, $item.description)
        }
    }
}

function Show-FormulaInfo {
    param([string]$Name)

    $manifest = Find-Manifest -Name $Name
    $variant = Get-ManifestVariant -Manifest $manifest
    $info = [ordered]@{
        name = $manifest.name
        version = $manifest.version
        description = $manifest.description
        homepage = $manifest.homepage
        license = $manifest.license
        type = $manifest.type
        manifestPath = $manifest.__path
        architecture = $variant.architecture
        url = $variant.value.url
        sha256 = $variant.value.sha256
        installed = ($null -ne (Read-Receipt -Name $manifest.name))
    }

    if ($Script:JsonMode) {
        Write-BrewObject $info
    } else {
        Write-Host "$($info.name): $($info.version)"
        Write-Host $info.description
        Write-Host "Homepage: $($info.homepage)"
        Write-Host "License: $($info.license)"
        Write-Host "Architecture: $($info.architecture)"
        Write-Host "Installed: $($info.installed)"
    }
}

function List-Installed {
    $receipts = @(Get-InstalledReceipts)
    if ($Script:JsonMode) {
        Write-BrewObject $receipts
    } else {
        foreach ($receipt in $receipts) {
            Write-Host $receipt.name
        }
    }
}

function Invoke-Upgrade {
    param([string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) {
        $receipts = @(Get-InstalledReceipts)
        foreach ($receipt in $receipts) {
            Install-Formula -Name $receipt.name -Force $true
        }
        return
    }

    Install-Formula -Name $Name -Force $true
}

function Invoke-SelfUninstall {
    $uninstaller = Join-Path $Script:Prefix "uninstall.ps1"
    if (-not (Test-Path -LiteralPath $uninstaller -PathType Leaf)) {
        throw "Could not find Brew Windows uninstaller at $uninstaller"
    }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $uninstaller
    exit $LASTEXITCODE
}

function Normalize-Arguments {
    param([string[]]$InputArgs)

    $remaining = New-Object System.Collections.Generic.List[string]
    foreach ($arg in $InputArgs) {
        if ($arg -eq "--json") {
            $Script:JsonMode = $true
        } else {
            $remaining.Add($arg)
        }
    }

    return @($remaining)
}

try {
    $normalizedArgs = @(Normalize-Arguments -InputArgs $BrewArgs)
    if ($normalizedArgs.Count -eq 0) {
        Show-Help
        exit 0
    }

    $command = $normalizedArgs[0]
    $rest = @()
    if ($normalizedArgs.Count -gt 1) {
        $rest = @($normalizedArgs[1..($normalizedArgs.Count - 1)])
    }

    switch ($command) {
        "--version" { Write-Host "Brew Windows $Script:BrewVersion" }
        "-v" { Write-Host "Brew Windows $Script:BrewVersion" }
        "help" { Show-Help }
        "--help" { Show-Help }
        "-h" { Show-Help }
        "--prefix" { Write-Host $Script:Paths.Prefix }
        "--cellar" { Write-Host $Script:Paths.Cellar }
        "--repository" { Write-Host $Script:Paths.Prefix }
        "config" { Show-Config }
        "doctor" { Invoke-Doctor }
        "search" { Search-Formulae -Query ($rest -join " ") }
        "info" {
            if ($rest.Count -lt 1) { throw "Usage: brew info <name>" }
            Show-FormulaInfo -Name $rest[0]
        }
        "install" {
            $force = $false
            $names = @()
            foreach ($item in $rest) {
                if ($item -eq "--force") { $force = $true } else { $names += $item }
            }
            if ($names.Count -ne 1) { throw "Usage: brew install [--force] <name>" }
            Install-Formula -Name $names[0] -Force $force
        }
        "uninstall" {
            if ($rest.Count -ne 1) { throw "Usage: brew uninstall <name>" }
            Uninstall-Formula -Name $rest[0]
        }
        "list" { List-Installed }
        "update" {
            $result = [ordered]@{ ok = $true; changed = $false; message = "Brew Windows uses local release metadata in this prototype." }
            if ($Script:JsonMode) { Write-BrewObject $result } else { Write-Host $result.message }
        }
        "upgrade" { Invoke-Upgrade -Name ($rest -join "") }
        "self-uninstall" { Invoke-SelfUninstall }
        default { throw "Unknown command '$command'. Run 'brew help'." }
    }
} catch {
    Write-BrewError -Message $_.Exception.Message
}
