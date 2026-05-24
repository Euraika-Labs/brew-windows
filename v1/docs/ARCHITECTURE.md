# Brew Windows MVP Architecture

Brew Windows is a native Windows package manager prototype that keeps Homebrew's
mental model while using Windows-native behavior.

## Runtime

The MVP runtime is PowerShell:

- `brew.cmd` is the command users run.
- `brew.ps1` is the implementation.
- No shell profile edit is required.
- No administrator rights are required.

The `.cmd` front door lets `brew` work even when local `.ps1` execution is
restricted. The command delegates with process-scoped execution policy only.

## Prefix

Default prefix:

```text
%LOCALAPPDATA%\Homebrew
```

Layout:

```text
%LOCALAPPDATA%\Homebrew\
|-- bin\
|-- Cellar\
|-- opt\
|-- Library\
|   `-- Taps\
|-- var\
|   `-- homebrew\
|       `-- receipts\
|-- Cache\
|-- Logs\
`-- Temp\
```

## Catalog

Formulae are JSON documents under tap folders:

```text
Library\Taps\<owner>\<tap>\Formula\<name>.json
```

The MVP can also load formulae from `HOMEBREW_TAP_PATHS`, separated with `;`.
This keeps tests and local experiments isolated from the built-in tap.

## Install Flow

`brew install <name>`:

1. Resolves a formula by name.
2. Selects the Windows architecture variant.
3. Downloads or copies the artifact into `Cache`.
4. Verifies SHA256.
5. Extracts into `Temp`.
6. Copies declared payload files into a staging directory.
7. Moves the staging directory into `Cellar\<name>\<version>`.
8. Creates `.ps1` and `.cmd` shims in `bin`.
9. Writes a receipt under `var\homebrew\receipts`.

The MVP uses shims instead of symlinks or junctions. That keeps the default
install no-elevation and avoids Developer Mode requirements.

## Codex Formula

The Codex formula uses official OpenAI release bundles:

- `codex-npm-win32-x64-<version>.tgz`
- `codex-npm-win32-arm64-<version>.tgz`

It does not run `npm install -g`. Brew owns the download, verification, layout,
shim, upgrade, and uninstall behavior.
