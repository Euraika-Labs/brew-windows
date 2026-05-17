# ADR 0001: Native Windows Only

Date: 2026-05-17

## Decision

Brew Windows targets native Windows. WSL, MSYS2, and Linux compatibility layers
are not implementation strategies for this project.

## Rationale

The product goal is a Windows Terminal and PowerShell experience where `brew`
installs native Windows command-line tools into a Windows prefix. A WSL wrapper
would not prove Windows path handling, shims, package layout, or upstream
Homebrew compatibility for Windows itself.

## Consequences

- The default runtime is PowerShell.
- Tests must run on native Windows.
- Package artifacts must be native Windows artifacts.
- WSL can be referenced as prior art only.
