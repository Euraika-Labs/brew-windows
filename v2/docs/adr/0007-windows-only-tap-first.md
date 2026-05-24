# v2 ADR 0007: Windows-Only Tap First, Not homebrew/core

Date: 2026-05-24

## Status

Accepted.

## Context

Upstream Homebrew ships with one tap installed by default:
`homebrew/core`. That tap contains thousands of formulae targeting
macOS and Linux. Almost none of them work on Windows today:

- Many depend on macOS or Linux libraries.
- Many ship Mach-O / ELF bottles.
- Many have build steps that rely on Unix-specific tooling.

If v2 inherits `homebrew/core` automatically:

- `brew search` returns thousands of formulae that cannot install.
- `brew install <random-formula>` fails in confusing ways.
- The user's mental model gets damaged before the first success.

Three options:

1. **Ship `homebrew/core` enabled by default.** Accept that almost
   every formula will fail. Document this as "expected."
2. **Ship `homebrew/core` enabled but filter to Windows-capable
   formulae.** Requires a per-formula Windows-support flag upstream,
   which does not exist.
3. **Ship no tap by default.** Maintain a Windows-only tap (e.g.
   `Euraika-Labs/homebrew-windows`) with a curated set of formulae
   known to work on Windows. Users can `brew tap` it explicitly, or
   the launcher can pre-tap it during Phase 3+.

Options 1 and 2 both leave the user in a bad starting state. Option
3 is what every nascent Homebrew-derivative does
(`homebrew/cask`, `homebrew/portable-ruby`, etc.).

## Decision

v2 ships with **no taps installed by default**.

The launcher's `install.ps1` does **not** run `brew tap` for any
tap. After install, `brew search` returns nothing useful (no tap to
search).

v2 maintains a Windows-only tap, initially at
`Euraika-Labs/homebrew-windows`, with formulae known to work on
Windows.

During Phase 3, when the first formula install is implemented:

- The user explicitly runs `brew tap Euraika-Labs/homebrew-windows`
  before `brew install <name>`.
- OR the launcher offers an opt-in convenience: a one-time prompt
  during `install.ps1` asking whether to enable the Windows tap.
  Default: no (explicit user action required).

At Phase 4, the project's user-facing documentation walks the user
through tapping the Windows tap on first use.

The launcher itself never auto-taps. Auto-tapping crosses a trust
boundary (an internet-fetched git repository whose contents we did
not pin in `runtime-manifest.json`).

## Consequences

### User experience

- A clean install does nothing useful until the user taps a tap.
- This is documented prominently in the user guide and in
  `brew doctor`'s "no taps installed" warning.
- The user is never confused by `homebrew/core` formulae failing.

### Tap content scope

`Euraika-Labs/homebrew-windows` (initial scope):

- Phase 3: `codex` (re-written as Ruby formula targeting Windows
  release URLs).
- Phase 4: `ripgrep`, `fd`, `bat`, `gh`, `eza` - the v1
  catalog winners. Each ported to a Ruby formula. Each known to work
  with the v2 link strategy.
- Beyond Phase 4: any Windows-portable CLI tool with an official
  Windows release archive and a SHA256.

Tap contents are formulae we have hand-verified install on Windows.
No speculative additions.

### Long term

If upstream Homebrew eventually accepts the link strategy patch and
adds Windows-aware `on_windows` blocks to `homebrew/core`, individual
formulae in `homebrew/core` may start declaring Windows support. At
that point v2 may add a `brew tap homebrew/core` step on opt-in -
but `brew install <random-formula>` from `homebrew/core` will still
fail on most things, because most formulae won't have Windows blocks.

The Windows-only tap remains the primary source of v2-installable
formulae for the foreseeable future.

### Compatibility with the upstream PR sequence

[COMPLIANCE.md](../COMPLIANCE.md) requirement 10 says v2 must not ask
for changes in `homebrew/core` or in the formula DSL. Shipping a
separate tap is exactly how a Windows port stays out of
`homebrew/core` - the tap is our content, not upstream's.

## Rejected Alternative: Default to homebrew/core

Rejected because:

- It positions v2 as broken-by-default. Most `brew install` attempts
  would fail.
- It would put pressure on upstream `homebrew/core` to accept
  Windows-related changes prematurely. That contradicts
  [ADR 0005](0005-windows-link-strategy.md) and
  [COMPLIANCE.md](../COMPLIANCE.md).
- It would make v2 search results misleading
  (`brew search ffmpeg` returns a formula that does not install).

## Rejected Alternative: Auto-Tap Windows Tap

Rejected because:

- An auto-tap during `install.ps1` adds a network operation that the
  user did not authorize.
- The tap's contents are not SHA256-pinned in
  `runtime-manifest.json` (that would make the tap part of the
  release zip, defeating tap separation).
- A compromised tap repository could affect every Brew Windows
  install at the moment of `install.ps1`. By making the user
  explicitly type `brew tap`, we make the trust decision explicit.
- Documented opt-in convenience (a prompt during install.ps1) is
  acceptable. Documented auto-tap is not.

## Rejected Alternative: Filter homebrew/core to Windows-Capable

Rejected because:

- There is no Windows-capable flag in homebrew/core formulae today.
- Adding such a flag is exactly the kind of upstream change v2's
  COMPLIANCE.md explicitly does not ask for.
- Per-formula filtering on the client side would parse every formula
  to decide if it is Windows-capable - heavy and brittle.

## Tap Versioning And Pinning

The Windows-only tap follows the same model as any Homebrew tap:

- It is a git repository.
- Users run `brew tap <owner>/<tap>` to clone it.
- Users run `git pull` (manually, given
  [ADR 0006](0006-brew-update-semantics.md)) or wait for a launcher
  release that automates tap updates.
- The launcher does not pin tap contents to a specific commit
  (taps are user-owned).

Phase 4 may introduce optional tap pinning (a `brew-windows-tap-pin`
mechanism) if non-author user feedback indicates it's needed for
reproducibility.

## CI Coverage

CI must verify:

- A clean install of the launcher has no taps installed.
- `brew tap Euraika-Labs/homebrew-windows` succeeds.
- After tapping, `brew install codex` works.
- `brew untap Euraika-Labs/homebrew-windows` removes the tap.
- `brew doctor` reports correctly on tap state.
