# ADR 0002: Installer, Prefix, And PATH

Date: 2026-05-17

## Decision

The default prefix is `%LOCALAPPDATA%\Homebrew`. The public install experience
is a GitHub Release `install.ps1` one-liner.

## Rationale

`%LOCALAPPDATA%` is writable without administrator rights and is a natural
per-user Windows install location. A release asset gives users a stable URL and
lets the installer verify a versioned payload.

## Consequences

- The installer updates the current process PATH and persists the User PATH.
- No PowerShell profile edit is required.
- Machine-wide installs are out of scope for the MVP.
