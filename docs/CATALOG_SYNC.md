# Catalog Sync

Brew Windows uses Homebrew as an upstream metadata source, but not as a Windows
binary source.

The sync pipeline reads Homebrew formula metadata, checks whether the upstream
project publishes Windows-native release archives, verifies SHA256 digests from
GitHub Releases, inspects archive layout, and generates Brew Windows manifests
only for packages that can be installed as portable Windows CLI tools.

## Sources

- Homebrew formula metadata: `https://formulae.brew.sh/api/formula.json`
- Individual formula metadata: `https://formulae.brew.sh/api/formula/<name>.json`
- GitHub release metadata: `https://api.github.com/repos/<owner>/<repo>/releases/latest`

Homebrew bottles are not used for Windows installs because current Homebrew
bottles target macOS and Linux.

## Promotion Policy

A formula is promoted automatically only when all of these are true:

- Formula is not disabled.
- Formula is not deprecated.
- Formula declares executables.
- A GitHub repository can be detected from Homebrew metadata.
- Latest GitHub release version matches Homebrew stable version.
- A Windows x64 archive asset exists.
- Every selected asset exposes a `sha256:` digest.
- Archive type is supported by Brew Windows.
- Archive inspection finds all declared executables.
- Architecture layouts agree on relative executable paths.

ARM64 is added when a matching Windows ARM64 archive exists.

Packages that fail one of these checks remain in
`catalog/windows-candidates.json` with a rejection reason and are not converted
to installable manifests.

## Manual Run

Generate candidates and manifests for selected packages:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\sync-homebrew-catalog.ps1 `
  -PackageName ripgrep,fd,bat,gh `
  -GenerateManifests `
  -FailOnNoCandidates
```

Scan a broader slice of Homebrew:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\sync-homebrew-catalog.ps1 `
  -Limit 200 `
  -GenerateManifests `
  -FailOnNoCandidates
```

Then validate:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\validate.ps1
```

## Automation

`.github/workflows/catalog-sync.yml` runs weekly and can also be triggered
manually. It creates or updates an `automation/catalog-sync` pull request when
the generated catalog changes.

The workflow does not merge automatically. A maintainer should review generated
packages, especially new command names and archive layouts.

## Current Limits

- Installer formats such as MSI, MSIX, and GUI EXE installers are excluded.
- Bare single-file `.exe` assets are excluded until the manifest schema supports
  non-archive payloads.
- Dependency graph solving is still primitive; promoted packages should be
  portable CLIs.
- Archive inspection currently promotes zip layouts. Other archive types can be
  listed as candidates but need layout support before automatic manifest
  generation.
