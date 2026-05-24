# Runtime Bootstrap Specification

`Install-Runtime` is the function in `brew.ps1` (also reachable from
`install.ps1`) that materializes the contents of `runtime/`. It runs
in two situations:

- **Eager**: called from `install.ps1` immediately after the launcher
  files are placed. User sees one progress indicator.
- **Lazy**: called from `brew.ps1` when `Test-RuntimeReady` reports
  missing or stale components. Acts as a safety net for prefix copies,
  manual deletion, or version upgrades.

Both call paths are the same function, the same network operations,
and the same verification. The only difference is who initiates it.

## `runtime-manifest.json`

`runtime-manifest.json` is shipped in the release zip. It pins every
external dependency the runtime needs.

```json
{
  "schemaVersion": "0",
  "launcherVersion": "0.1.0",
  "generatedAt": "2026-05-24T13:00:00Z",
  "components": {
    "mingit": {
      "version": "2.49.0",
      "url": "https://github.com/git-for-windows/git/releases/download/v2.49.0.windows.1/MinGit-2.49.0-64-bit.zip",
      "sha256": "<64 hex chars>",
      "extract": "zip",
      "stripTopLevel": false
    },
    "ruby": {
      "version": "3.3.6-1",
      "url": "https://github.com/oneclick/rubyinstaller2/releases/download/RubyInstaller-3.3.6-1/rubyinstaller-3.3.6-1-x64.7z",
      "sha256": "<64 hex chars>",
      "extract": "7z",
      "stripTopLevel": true
    },
    "homebrew": {
      "ref": "<40 hex chars - upstream commit SHA>",
      "url": "https://github.com/Homebrew/brew.git",
      "expectedTreeId": "<40 hex chars - git tree object id, see note below>"
    }
  },
  "patches": [
    {
      "path": "patches/windows-link-strategy.patch",
      "sha256": "<64 hex chars>",
      "appliesTo": "homebrew"
    }
  ]
}
```

Fields:

- `launcherVersion`: the launcher release this manifest was generated
  with. Used to detect "user upgraded the launcher, runtime is now
  stale" by comparing against `install-manifest.json`.
- `components.<name>.sha256`: required for every downloaded artifact.
  No SHA256 means refuse to install.
- `components.homebrew.ref`: a full 40-character commit SHA. Never a
  branch name. Never a tag.
- `components.homebrew.expectedTreeId`: the git tree object id (SHA-1,
  40 hex chars) reachable from the pinned commit, computed via
  `git rev-parse <ref>^{tree}`. Belt-and-braces protection against
  history rewrites on the Homebrew GitHub repository. The schema v0
  uses git's native tree id rather than a recursive SHA256; v1 of the
  schema may switch to a full content hash if the tree id ever proves
  insufficient.
- `patches[]`: ordered list of patches to apply to the Homebrew
  working tree after checkout. Stored in the launcher release zip
  under `patches/` and referenced by relative path here.

The schema lives at `v2/schema/runtime-manifest.v0.schema.json`
(to be written alongside the first launcher implementation).

## `runtime/pins.json`

Written by `Install-Runtime` after each component installs successfully.
Records the version + SHA256 that was actually placed on disk.

```json
{
  "schemaVersion": "0",
  "installedAt": "2026-05-24T13:30:42Z",
  "launcherVersion": "0.1.0",
  "components": {
    "mingit":   { "version": "2.49.0",  "sha256": "<64 hex>" },
    "ruby":     { "version": "3.3.6-1", "sha256": "<64 hex>" },
    "homebrew": { "ref": "<40 hex>",    "treeId": "<40 hex>" }
  },
  "patchesApplied": [
    { "path": "patches/windows-link-strategy.patch", "sha256": "<64 hex>" }
  ]
}
```

`Test-RuntimeReady` reads both `runtime-manifest.json` and `runtime/pins.json`
and compares them. Any mismatch -> `Install-Runtime` is called.

## Install-Runtime Flow

For each component in order: `mingit`, `ruby`, `homebrew`.

### Common prelude

1. Create `<prefix>/Cache/` if missing.
2. Create `<prefix>/runtime/` if missing.
3. Create a fresh staging directory: `<prefix>/Temp/runtime-stage-<guid>/`.
   Cleaned up in a `finally` block.

### MinGit

1. Download the URL into `<prefix>/Cache/<basename>` using `Invoke-WebRequest`.
   Reject anything that is not HTTPS.
2. SHA256 verify the cached file against `components.mingit.sha256`.
   Mismatch -> throw.
3. `Expand-Archive` into `<staging>/mingit/`.
4. If `runtime/mingit/` exists, move it to `<staging>/mingit-old/` first.
5. Move `<staging>/mingit/` to `<prefix>/runtime/mingit/`.
6. If step 5 succeeded, delete `<staging>/mingit-old/` (the previous version).
7. If step 5 failed, restore `<staging>/mingit-old/` to `<prefix>/runtime/mingit/`.

The pattern is: stage everything in `Temp/`, swap atomically (or as
atomically as the Windows filesystem allows), only delete the previous
version after the new one is committed.

### Ruby

Same flow as MinGit. The wrinkle is the 7z archive format.

PowerShell 5.1+ does not have native 7z extraction. Options, in
preference order:

1. **`tar.exe` from Windows 10 1803+**. `tar.exe -xf rubyinstaller.7z`
   works in current Windows versions thanks to bundled libarchive.
2. **Bundled 7z extractor**. Ship a small standalone `7z.exe` in the
   release zip (~300 KB).
3. **Mirror RubyInstaller as zip**. Host a re-archived `.zip` on this
   project's release storage. Adds one more SHA256 pin.

Phase 1 picks one. The current expectation is (1): `tar.exe` should
work, and falls back to (2) if not. (3) is a last resort.

### Homebrew

Different flow because this is git, not an archive.

1. Check if `<prefix>/runtime/homebrew/` is an existing valid git
   repository at the expected commit SHA. If yes and tree-sha matches,
   nothing to do.
2. Otherwise: shallow-clone into `<staging>/homebrew/`:
   ```
   git clone --depth=1 --no-tags --no-checkout \
     https://github.com/Homebrew/brew.git <staging>/homebrew
   cd <staging>/homebrew
   git fetch --depth=1 origin <commit-sha>
   git checkout <commit-sha>
   ```
3. Compute the working tree id via `git rev-parse <ref>^{tree}` (the
   git tree object SHA-1) and compare to
   `components.homebrew.expectedTreeId`.
4. Apply each patch in `patches[]`:
   ```
   git apply --check <staging>/homebrew/path/to/patch
   git apply <patch>
   ```
   The `--check` first means a bad patch fails before we modify anything.
5. Move `<staging>/homebrew/` to `<prefix>/runtime/homebrew/` with the
   same swap-and-cleanup pattern as MinGit.

Git itself is provided by MinGit, which was installed in the previous
step. We invoke MinGit's git: `<prefix>/runtime/mingit/cmd/git.exe`.

### Finalize

After all three components succeed:

1. Write `<prefix>/runtime/pins.json` reflecting what was installed.
2. Delete the staging directory.
3. Return success.

If any step fails:

1. Restore the previous `runtime/<component>/` from `<staging>/<component>-old/`
   if it existed.
2. Delete the staging directory.
3. Re-throw the error.

The user is left with either the new runtime fully installed or the
previous runtime intact. Never a partial state.

## Atomicity Notes

Windows filesystem operations are not as atomic as POSIX. A
`Move-Item` of a directory across the same volume is a rename and is
near-atomic. Across volumes it's a copy + delete. The prefix and
`Temp/` are in the same volume by construction (both under
`%LOCALAPPDATA%`), so the rename path applies.

Antivirus and EDR products on Windows can hold open handles on
just-extracted executables. If a move fails with ERROR_SHARING_VIOLATION,
the bootstrap retries with a short backoff (up to 5 seconds total).
If still failing, it throws with a message naming antivirus as the
likely cause.

## Bandwidth And Disk Footprint

| Component | Cold download | Extracted on disk |
| --- | --- | --- |
| MinGit | ~50 MB | ~120 MB |
| RubyInstaller | ~30 MB | ~70 MB |
| Homebrew shallow clone | ~50 MB | ~50 MB |
| **Total** | **~130 MB** | **~240 MB** |

The cache (`Cache/`) keeps the downloaded archives so a re-run of
`Install-Runtime` does not re-download if the cache is intact. The
release-zip launcher itself is well under 2 MB.

## Offline / Air-Gapped Install

`Install-Runtime` does not support an offline mode in Phase 1-3. Users
on air-gapped machines have two options:

1. Run `install.ps1` on a connected machine, then copy
   `%LOCALAPPDATA%\Homebrew\` to the target machine. The next `brew`
   invocation will verify pins and run.
2. (Future, Phase 4+) Add an `Install-Runtime` `-FromCache <path>`
   parameter that reads pre-staged archives from a local directory
   instead of HTTPS.

## Updating The Runtime

Bumping any pinned version is a launcher release. The flow:

1. Maintainer updates `runtime-manifest.json` in the launcher source.
2. New launcher version is built, signed, attested, published.
3. User runs `brew self-update` (or re-runs `install.ps1`).
4. Launcher files are replaced. `runtime-manifest.json` now pins new
   versions.
5. Next `brew` invocation detects mismatch with `runtime/pins.json`,
   re-runs `Install-Runtime`.
6. Old runtime components are replaced with the new ones.

This is the same mechanism whether the bump is MinGit, Ruby, or the
Homebrew pin. It is also the mechanism for `brew update` semantics
(see [ADR 0006](adr/0006-brew-update-semantics.md)).

## Validation In CI

Phase 1 CI runs `Install-Runtime` from scratch on a clean Windows
runner. The cycle is:

1. Fresh prefix.
2. Run `install.ps1` -> triggers eager `Install-Runtime`.
3. Verify `runtime/` is fully populated.
4. Verify `runtime/pins.json` matches `runtime-manifest.json`.
5. Run `brew --version` -> exits 0, prints upstream Homebrew version.
6. Manually delete `runtime/mingit/` and re-run `brew --version`
   (exercises lazy bootstrap).
7. Manually corrupt `runtime/ruby/bin/ruby.exe` and re-run `brew --version`
   (`Test-RuntimeReady` should detect the sha256 drift).

Failure of any step fails the CI job.
