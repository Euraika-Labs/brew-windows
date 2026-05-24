# Brew Windows v2 Launcher Source

This directory is the **launcher payload**: every file shipped inside
the release zip that a user fetches via `irm install.ps1 | iex`. It is
the only executable code Brew Windows v2 distributes - the actual
Homebrew runtime is downloaded on first use into
`%LOCALAPPDATA%\Homebrew\runtime\` and is not in this directory.

For the design rationale behind each piece below, see
[`../docs/LAUNCHER.md`](../docs/LAUNCHER.md) and
[`../docs/BOOTSTRAP.md`](../docs/BOOTSTRAP.md).

## File-By-File

- `bin/brew.cmd` - the front door. A ~5 line `.cmd` shim that invokes
  `powershell.exe -NoProfile -ExecutionPolicy Bypass -File brew.ps1`.
  Works under restricted PowerShell execution policy without modifying
  machine policy.
- `bin/brew.ps1` - the main launcher. Resolves the prefix, verifies
  the runtime via `Test-RuntimeReady`, calls `Install-Runtime` on first
  use or drift, sets the `HOMEBREW_*` environment contract, and execs
  `runtime/mingit/usr/bin/bash.exe runtime/homebrew/bin/brew <args>`.
- `install.ps1` - the first-time installer. Also shipped as a sibling
  asset on the GitHub release so users can pipe it with `irm | iex`.
  Extracts the launcher, updates User `PATH`, writes
  `install-manifest.json`, and triggers eager `Install-Runtime`.
- `uninstall.ps1` - the reverse of `install.ps1`. Removes the User
  `PATH` entry and deletes the prefix. Refuses to delete a directory
  that does not look like a Brew Windows prefix.
- `runtime-manifest.json` - pinned versions and SHA256s for MinGit,
  RubyInstaller, the upstream Homebrew commit, and every patch in
  `patches/`. Schema lives at
  [`../schema/runtime-manifest.v0.schema.json`](../schema/runtime-manifest.v0.schema.json).
- `patches/` - unified-diff patches against upstream Homebrew applied
  after the shallow clone is checked out. See
  [`patches/README.md`](patches/README.md) for the patch header
  convention and current patch set.

## Release Zip Build

The release zip is produced by
[`../scripts/build-release.ps1`](../scripts/build-release.ps1):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File ..\scripts\build-release.ps1 -Version 0.1.0
```

Output lands in `v2/dist/brew-windows-<version>.zip` with a `.sha256`
sidecar. The zip contains exactly the files in this directory plus
`uninstall.ps1` at the prefix root.

## Pinning The Runtime

SHA256 fields in `runtime-manifest.json` are filled by
[`../scripts/pin-runtime.ps1`](../scripts/pin-runtime.ps1), which
downloads each pinned URL, hashes it, and flips
`placeholdersFilled` to `true` once every component has a real hash.
Do not hand-edit the SHA256 fields.

## Where To Read Next

- [`../docs/ARCHITECTURE.md`](../docs/ARCHITECTURE.md) - the master
  overview of how the launcher fits into the layered design.
- [`../docs/LAUNCHER.md`](../docs/LAUNCHER.md) - per-file launcher
  spec with pseudocode.
- [`../docs/BOOTSTRAP.md`](../docs/BOOTSTRAP.md) - `Install-Runtime`
  flow, atomicity policy, and `runtime-manifest.json` schema notes.
