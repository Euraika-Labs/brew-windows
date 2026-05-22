# Homebrew Upstream Dossier

Last verified: 2026-05-22.

This dossier explains how Brew Windows should approach `Homebrew/brew`
upstream. It is intentionally conservative: the objective is to earn feedback
on small abstractions before asking maintainers to review any native Windows
implementation.

## Current Upstream Reality

- `Homebrew/brew` latest release observed during this Sprint 6 pass:
  [`5.1.13`](https://github.com/Homebrew/brew/releases/tag/5.1.13), published
  2026-05-21.
- The Homebrew repository description remains "The missing package manager for
  macOS (or Linux)".
- Homebrew documentation says Homebrew may be used on Linux and WSL 2, not
  native Windows:
  <https://docs.brew.sh/Homebrew-on-Linux>.
- The support tier model currently defines Tier 1 for macOS and Linux only:
  <https://docs.brew.sh/Support-Tiers>.
- `Homebrew/brew#14197` ("Windows Support") is closed. The maintainer response
  points users to WSL and calls a native Windows port a large effort because of
  Homebrew's Unix and Bash assumptions:
  <https://github.com/Homebrew/brew/issues/14197>.
- `Homebrew/brew#19407` ("Add PowerShell (pwsh) completion support") was merged
  on 2025-03-03, which is useful evidence that focused PowerShell improvements
  can fit upstream when they do not disturb macOS/Linux behavior:
  <https://github.com/Homebrew/brew/pull/19407>.
- A current GitHub search for open `Homebrew/brew` issues or pull requests with
  "windows" in the title/body returned no active native Windows proposal.

## Prototype Evidence

Brew Windows now has enough native evidence to start an upstream discussion
without asking Homebrew maintainers to accept speculative code.

- Native per-user prefix: `%LOCALAPPDATA%\Homebrew`.
- Release installer entrypoint:

  ```powershell
  irm https://github.com/Euraika-Labs/brew-windows/releases/latest/download/install.ps1 | iex
  ```

- Published release:
  [`v0.2.3`](https://github.com/Euraika-Labs/brew-windows/releases/tag/v0.2.3).
- Release assets:
  - `install.ps1`
  - `brew-windows-v0.2.3.zip`
  - `brew-windows-v0.2.3.zip.sha256`
- Release artifact attestation was verified for `brew-windows-v0.2.3.zip`.
- Windows CI passes on `main`, including Windows PowerShell, PowerShell 7,
  PSScriptAnalyzer, JSON manifest parsing, actionlint, zizmor, catalog sync
  tests, checksum failure tests, and shim argument fuzz tests.
- Native package success path was validated on a real Windows 11 workstation:

  ```powershell
  brew --version
  brew doctor
  brew install codex
  codex --version
  ```

- The Codex package installs official OpenAI Windows release assets instead of
  running `npm install -g`.
- The package catalog sync can derive Windows candidates from official Homebrew
  formula metadata while using Windows-native upstream release assets.

## Compatibility Position

This project should not ask Homebrew to "merge Windows support" in one pull
request. That would be too large, too risky, and inconsistent with Homebrew's
current support model.

The upstream position is:

- Native Windows remains experimental unless Homebrew maintainers say otherwise.
- WSL remains out of scope for this project except as prior art.
- Homebrew concepts should stay recognizable: prefix, cellar, keg, tap,
  formula, bottle, doctor, config, update, upgrade.
- Any upstream pull request must be useful or inert on macOS and Linux.
- No pull request should imply official Windows support before maintainers
  accept a support model.
- Windows bottle tags should be deferred until bootstrap, path handling, link
  strategy, and package installation semantics are proven.

## Gap Map

| Area | Current Homebrew Shape | Native Windows Need | Upstream Approach |
| --- | --- | --- | --- |
| Launcher | `bin/brew` is Bash and re-execs `/bin/bash`. | `brew.ps1` or equivalent native launcher. | First document and isolate the launcher environment contract. |
| Platform detection | `brew.sh` uses `OSTYPE` for Darwin/Linux and generic Unix fallback. | Explicit Windows host detection without pretending it is Linux. | Add inert `OS.windows?` style detection only after discussion. |
| Prefix | Defaults are `/opt/homebrew`, `/usr/local`, and `/home/linuxbrew/.linuxbrew`. | User-writable `%LOCALAPPDATA%\Homebrew` prototype prefix. | Keep prefix policy out of early PRs; treat as support-tier discussion. |
| PATH handling | Unix colon-separated paths and Unix executables are common assumptions. | Semicolon-separated path lists and `.exe`, `.cmd`, `.bat`, `.ps1` resolution. | Add cross-platform path/executable helpers with no behavior change. |
| Shell integration | Bash/zsh/fish are primary; PowerShell completion is merged. | Native PowerShell `shellenv` output and installer behavior. | Start from shellenv rendering, not installer changes. |
| Linking | Keg linking is symlink-oriented. | Shims and carefully chosen junctions/symlinks without admin rights. | Introduce a link strategy interface before any Windows implementation. |
| Binary inspection | Mach-O and ELF are first-class. | PE/COFF and DLL dependency awareness. | Defer until native install and link semantics are reviewed. |
| Support tier | Tier 1 is macOS/Linux; unsupported configurations have strict rules. | Experimental native Windows tier or external prototype. | Ask maintainers which model, if any, is acceptable. |

## Discussion Goals

The first public Homebrew discussion should ask for guidance, not permission to
merge a port.

The discussion should answer:

- Should native Windows support remain permanently outside Homebrew?
- If not, what minimum evidence would make small abstraction PRs reviewable?
- Would maintainers consider inert helpers that preserve current macOS/Linux
  behavior?
- Which support tier, warning model, or unsupported status would be acceptable
  for early native Windows experiments?
- Are there areas maintainers consider out of bounds, such as Windows bottles,
  installer behavior, or formula DSL changes?

The discussion draft is maintained in
[docs/UPSTREAM_DISCUSSION_DRAFT.md](UPSTREAM_DISCUSSION_DRAFT.md).

## Proposed Pull Request Route

The proposed route is documented in
[docs/UPSTREAM_PR_SEQUENCE.md](UPSTREAM_PR_SEQUENCE.md).

The short version:

1. Open a Homebrew discussion with the evidence package.
2. If maintainers are receptive, send only no-behavior-change abstractions
   first.
3. Keep macOS/Linux behavior unchanged and tested.
4. Keep native Windows code behind explicit unsupported/experimental gates.
5. Defer bottles, PE/COFF inspection, and formula migration until the platform
   contract is accepted.

## Stop Conditions

Stop and reassess if maintainers say any of the following:

- Native Windows is out of scope for Homebrew.
- Even inert Windows-related abstractions are unwanted.
- The prototype should remain a separate project or tap indefinitely.
- A specific approach creates unacceptable maintenance burden.

If that happens, Brew Windows can still continue as a compatibility-oriented
native package manager, but it should stop framing the next step as upstream
integration.

## Source Links

- Homebrew on Linux: <https://docs.brew.sh/Homebrew-on-Linux>
- Homebrew Support Tiers: <https://docs.brew.sh/Support-Tiers>
- Homebrew issue 14197, Windows Support:
  <https://github.com/Homebrew/brew/issues/14197>
- Homebrew PR 19407, PowerShell completion:
  <https://github.com/Homebrew/brew/pull/19407>
- Homebrew release 5.1.13:
  <https://github.com/Homebrew/brew/releases/tag/5.1.13>
- Brew Windows release v0.2.3:
  <https://github.com/Euraika-Labs/brew-windows/releases/tag/v0.2.3>
