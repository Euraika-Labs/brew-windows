# Brew Windows Threat Model

## Assets

- User PATH and current shell environment.
- `%LOCALAPPDATA%\Homebrew` prefix.
- Download cache and extracted package payloads.
- Generated shims in `bin`.
- Package receipts and manifest metadata.

## Trust Boundaries

- GitHub release API and release assets.
- Package artifact URLs.
- Local tap paths supplied through `HOMEBREW_TAP_PATHS`.
- PowerShell execution from Windows Terminal.
- User PATH resolution.

## Primary Threats

- Remote artifact substitution.
- Hash mismatch ignored by mistake.
- PATH hijacking or command shadowing.
- Shim argument parsing bugs.
- Accidental elevation or machine-wide mutation.
- Prefix deletion outside the expected install root.
- Compromised CI workflow permissions.

## Current Mitigations

- Every package artifact requires SHA256.
- `install.ps1` refuses release payloads without SHA256 metadata.
- The default prefix is per-user and does not require administrator rights.
- Runtime commands assert destructive package paths are under
  `HOMEBREW_PREFIX`.
- `brew doctor` warns on PATH and shim problems.
- CI runs with `contents: read` by default.
- `actions/checkout` uses `persist-credentials: false`.

## Required Before First Public Release

- Real clean-machine `brew install codex` validation.
- Expanded shim quoting tests for spaces, quotes, `%`, `&`, `^`, and
  parentheses.
- Release artifact SHA256 manifest.
- GitHub artifact attestation for the payload zip.
- Release checklist approval.
