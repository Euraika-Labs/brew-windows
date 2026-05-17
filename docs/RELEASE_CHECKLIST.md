# Release Checklist

Use this checklist before publishing a release that exposes the README one-line
installer.

## Build

- Run `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\validate.ps1`.
- Run `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-release.ps1 -Version <version>`.
- Upload `install.ps1` as a release asset.
- Upload `dist\brew-windows-<version>.zip` as a release asset.
- Upload or publish the SHA256 value for the payload zip.

## Security

- Confirm package artifacts have SHA256 values.
- Confirm the release payload has a SHA256 digest.
- Confirm no workflow uses `pull_request_target`.
- Confirm GitHub Actions permissions are least privilege.
- Confirm no profile edits are required by default.

## Acceptance

- Fresh Windows 11 Terminal install succeeds:

  ```powershell
  irm https://github.com/Euraika-Labs/brew-windows/releases/latest/download/install.ps1 | iex
  ```

- `brew doctor` completes.
- `brew install codex` succeeds.
- `codex --version` prints a `codex-cli` version.
- `brew uninstall codex` removes the Codex shims and Cellar entry.
- `brew self-uninstall` removes the prefix and User PATH entry.
