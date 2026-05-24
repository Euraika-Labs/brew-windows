# v2 ADR 0001: Bootstrap Upstream Homebrew Instead Of Reimplementing It

Date: 2026-05-24

## Status

Accepted. Supersedes v1 ADR 0001 ("Native Windows Only").

## Context

v1 implemented a PowerShell-native package manager that preserved
Homebrew's mental model but used none of Homebrew's actual code. v1 ADR
0001 was explicit: WSL, MSYS2, and Linux compatibility layers were not
implementation strategies; the default runtime was PowerShell.

In May 2026, [Homebrew discussion 6860](https://github.com/orgs/Homebrew/discussions/6860)
established the upstream-merge prerequisite: any path that could
eventually land in `Homebrew/brew` must use **bash + Ruby + curl**.
PowerShell-only implementations would not be reviewed for upstream
inclusion.

The v1 position - "no compatibility layers" - was correct against WSL,
correct against MSYS2 as a runtime identity, and correct against
pretending Windows is Linux. But it conflated two different things:

1. **Runtime identity**: what the user types, what shell they are in,
   what platform conventions their commands obey.
2. **Implementation language**: what code runs underneath.

(1) must be Windows: PowerShell, Windows Terminal, semicolons in PATH,
`.exe` suffixes, NTFS, no `/bin/sh` symlinks. (2) is invisible to the
user.

bash, Ruby, and curl all have credible native-Windows distributions
that satisfy (1):

- MinGit ships a native Win32 `bash.exe`. Microsoft-signed installer.
  Runs without WSL.
- RubyInstaller ships a native Win32 `ruby.exe`. Signed installer.
  Runs without WSL.
- `curl.exe` is in the Windows base image since Windows 10 1803.

Vendoring these as private binaries that the user never types into is
not the same as making MSYS2 or WSL the user's runtime identity.

## Decision

v2 of Brew Windows wraps and bootstraps upstream `Homebrew/brew` rather
than reimplementing Homebrew in PowerShell.

A small Windows-native launcher (`brew.cmd` + `brew.ps1`) does two
things and only two things:

1. Ensures a private runtime directory contains MinGit, RubyInstaller,
   and a pinned clone of `Homebrew/brew`. Downloads them on first use
   if missing.
2. Sets the `HOMEBREW_*` environment contract and execs `bash.exe
   bin/brew <args>` from the cloned Homebrew repository.

Everything else - formula resolution, dependency solving, downloads,
extraction, linking, receipts, `brew search`, `brew info`, `brew update`,
`brew upgrade` - is upstream Homebrew's code, unchanged where possible.

The "native Windows only" position from v1 ADR 0001 is preserved with
one clarification: vendoring native Win32 binaries that the user never
types into is allowed and explicitly does not count as a compatibility
layer. WSL is still out of scope. MSYS2 as the user's shell environment
is still out of scope.

## Consequences

- The PowerShell `brew` runtime (`v1/bin/brew.ps1`) is retired.
- The JSON manifest schema, formula catalog, and catalog sync pipeline
  are retired. Homebrew's existing Ruby formula DSL replaces them.
- The release zip shrinks dramatically. Most of v1's mass is the
  catalog and the PowerShell runtime.
- The Codex formula is rewritten as a Ruby formula in a Windows tap.
  The Windows-side install mechanics are unchanged (official OpenAI
  release bundle, SHA256 verified, shimmed onto PATH).
- The upstream PR sequence proposed pre-discussion
  (`docs/UPSTREAM_PR_SEQUENCE.md`) is retired. v2 follows the route
  MikeMcQuaid described: complete external port -> non-author users +
  CI -> small (<500 LOC) PRs.
- v2 inherits the deployment problem of upstream Homebrew on Windows -
  primarily, that Homebrew's link step assumes symlinks. v2 likely
  carries a maintained patch / fork that swaps in a Windows-safe shim
  strategy until upstream accepts the abstraction.
- Existing PowerShell completion support in upstream Homebrew (merged
  in PR 19407) becomes more useful, since the user is in PowerShell.

## Rejected Alternative: Stay Independent Forever

The other path consistent with one of the two maintainer responses
(p-linnane: "stay independent") is to continue v1's approach. This was
rejected because:

- The project's stated long-term goal is upstream Homebrew compatibility,
  documented in `BREW_WINDOWS_UPSTREAM_ARCHITECTURE.md` since the start.
  Permanent independence contradicts that.
- v1's runtime had to reimplement every Homebrew feature one at a time
  (`brew search`, `brew info`, `brew install`, `brew uninstall`,
  `brew list`, then `brew upgrade`, `brew update`, `brew tap`,
  `brew deps`, `brew uses`, ...). v2 inherits all of these for free.
- The catalog sync pipeline was a perpetual cost - keeping a Windows
  manifest catalog in sync with Homebrew formula updates is work that
  v2 doesn't need to do.

The cost of v2's path is real (130 MB first-use download, an
upstream-Homebrew dependency, a maintained Windows-link-strategy
patch) but it is bounded and well-understood.
