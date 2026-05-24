# ADR 0003: Generic Catalog With Codex First

Date: 2026-05-17

## Decision

The MVP uses a generic JSON manifest catalog. Codex is the first real package,
not a special case in the CLI.

## Rationale

The user-facing demo needs `brew install codex`, but hard-coding Codex would not
prove a package manager. A small generic catalog proves resolution, checksums,
Cellar layout, shims, receipts, uninstall, and future package growth.

## Consequences

- Formulae live under `Library\Taps\<owner>\<tap>\Formula`.
- The manifest schema starts at v0 and is intentionally small.
- Packages must provide SHA256 values.
