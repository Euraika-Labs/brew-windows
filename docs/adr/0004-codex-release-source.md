# ADR 0004: Codex Release Source

Date: 2026-05-17

## Decision

The Codex formula installs official OpenAI GitHub release bundles:

- `codex-npm-win32-x64-<version>.tgz`
- `codex-npm-win32-arm64-<version>.tgz`

It does not run `npm install -g @openai/codex`.

## Rationale

Using release bundles keeps Brew Windows responsible for package ownership,
checksums, layout, upgrades, shims, and uninstall. It also avoids making Node or
npm a dependency of Brew Windows.

## Consequences

- The manifest must preserve helper binaries next to Codex.
- The formula tracks OpenAI's `rust-vX.Y.Z` releases.
- User state such as `.codex` remains outside Brew package ownership.
