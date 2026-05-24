# Compliance With Homebrew Maintainer Feedback

This document maps each requirement and constraint surfaced in
[Homebrew discussion 6860](https://github.com/orgs/Homebrew/discussions/6860)
to where v2 satisfies it. The goal is to make compliance traceable -
anyone can open this document and see exactly which decision satisfies
which requirement.

## Source Quotes (Summary)

The full discussion is public. Summarized maintainer positions:

### p-linnane (Maintainer)

> "Native Windows is firmly out of scope for Homebrew/brew, and
> Chocolatey, Scoop, or WinGet are better fits."
>
> "Windows breaks nearly all Unix assumptions simultaneously, unlike
> Linuxbrew."
>
> "Even inert abstractions carry permanent maintenance and test burden
> for an unsupported target."
>
> Recommendation: stay independent.

### MikeMcQuaid (Maintainer)

> Not categorically excluded long-term if it includes bash, Ruby,
> and curl.
>
> "Complete a full Windows port independently first, then submit
> small (<500 line) incremental PRs."
>
> "Actual CI, binary packages, and non-author users are required."
>
> Unsupported / Tier 3 experimental status is how any future support
> would begin.
>
> Most new functionality (bottle tags, shim strategies,
> `Library/Homebrew/os/windows.rb`) could eventually merge - **except
> extended PowerShell support initially**.

### MikeMcQuaid (Reconsidered)

> Pivoted toward making Homebrew-under-WSL better interact with
> Windows systems (e.g., `winget` for `brew bundle`, displaying
> Windows build config on WSL).
>
> Concrete PRs referenced: #22397, #22398.

## Requirements Table

| # | Requirement | Source | Where v2 Satisfies It | Status |
| --- | --- | --- | --- | --- |
| 1 | Use bash + Ruby + curl as the runtime | MikeMcQuaid | [ADR 0003](adr/0003-runtime-composition.md) - MinGit bash, RubyInstaller Ruby, system curl | Satisfied by design |
| 2 | Complete the full external port before approaching upstream | MikeMcQuaid | [PHASE_PLAN.md](PHASE_PLAN.md) - Phases 1-4 produce a working port before Phase 5 | Satisfied by phasing |
| 3 | Small (<500 line) incremental PRs | MikeMcQuaid | [LINK_STRATEGY.md](LINK_STRATEGY.md) - first patch is ~180 lines; Phase 5 PRs are each scoped <500 | Satisfied by design |
| 4 | Actual CI on the external project | MikeMcQuaid | [PHASE_PLAN.md](PHASE_PLAN.md) - Phase 1-4 CI; existing `.github/workflows/ci.yml` already exercises v1, will be expanded for v2 | Satisfied by phasing |
| 5 | Binary packages (signed, attested release artifacts) | MikeMcQuaid | Release workflow (Phase 4) - SHA256 sidecars, GitHub artifact attestation, same model as v1 | Satisfied by Phase 4 |
| 6 | Non-author users actually running the project | MikeMcQuaid | [PHASE_PLAN.md](PHASE_PLAN.md) - Phase 4 exit criterion requires 3+ non-author users | Satisfied by Phase 4 |
| 7 | Tier 3 / unsupported / experimental positioning | MikeMcQuaid | [ADR 0001](adr/0001-bootstrap-upstream-homebrew.md) - explicit non-claim of Tier 1 support; Phase 5 PRs gate Windows behind unsupported flag | Satisfied by design |
| 8 | No "extended PowerShell support" in initial upstream PRs | MikeMcQuaid | [PHASE_PLAN.md](PHASE_PLAN.md) - Phase 5 PR sequence is `OS.windows?`, extension point, link strategy. No PowerShell-specific PR is in the first sequence. | Satisfied by design |
| 9 | Stay independent if upstream remains unwilling | p-linnane | v2 functions without any upstream merge. Phase 5 is the upstream-merge phase; Phases 1-4 produce a working independent project. | Satisfied by design |
| 10 | Preserve macOS / Linux behavior in any upstream PR | Implied by both | [ADR 0004](adr/0004-maintained-patches-vs-fork.md), [LINK_STRATEGY.md](LINK_STRATEGY.md) - patches are additive, guarded by `OS.windows?`. PRs 1-3 in Phase 5 are useful or inert on macOS/Linux. | Satisfied by design |
| 11 | Maintenance and test burden minimized | p-linnane | [LINK_STRATEGY.md](LINK_STRATEGY.md) + [HOMEBREW_INTEGRATION.md](HOMEBREW_INTEGRATION.md) - we patch as little as possible; the Phase 5 PR sequence specifically extracts abstractions that benefit macOS/Linux readability. | Mitigated by design; ultimately maintainer judgment |

## Specific Non-Asks

To make compliance unambiguous, v2 **does not ask for**:

- Tier 1 Windows support.
- Official Windows bottles.
- A `homebrew/core` campaign to add Windows support to existing formulae.
- A formula DSL change such as `on_windows do ... end`.
- Native PowerShell `brew` (the launcher is in PowerShell but the
  internal runtime is bash + Ruby).
- Any change to upstream's existing macOS or Linux behavior.
- Maintainer time for review before Phase 4 is complete.
- A support promise to end users from upstream.

These are explicitly out of scope. They were out of scope in v1's
`docs/UPSTREAM_DOSSIER.md` and remain out of scope in v2.

## Constraint Mapping To Architecture

### "bash + Ruby + curl"

| Tool | v2 source | Distribution shape |
| --- | --- | --- |
| bash | MinGit (`git-for-windows/git` GitHub Releases) | Native Win32 .exe |
| Ruby | RubyInstaller (`oneclick/rubyinstaller2` GitHub Releases) | Native Win32 .exe |
| curl | `C:\Windows\System32\curl.exe` | Microsoft-supplied since Win10 1803 |

All three are native Win32 executables. None require WSL, MSYS2 as a
shell environment, or any non-Windows runtime layer.

### "Complete the port externally first"

[PHASE_PLAN.md](PHASE_PLAN.md) is the explicit plan. Phases 1-4 build
a working external project. Phase 5 begins upstream conversation.

The phase boundary is the compliance gate. Phase 5 is not started
until Phase 4 produces real CI + binary packages + non-author user
evidence.

### "Small (<500 LOC) PRs"

Target sizes per [PHASE_PLAN.md](PHASE_PLAN.md) Phase 5:

- PR 1 (`OS.windows?`): ~30 LOC
- PR 2 (`extend/os/windows/` skeleton): ~20 LOC
- PR 3 (Keg link strategy extraction): ~150 LOC
- PR 4 (Windows shim link strategy): ~150 LOC

Each is well under 500. Each is independently mergeable.

### "CI"

v1 already has a Windows CI matrix that runs on every push and PR
([ci.yml](../../.github/workflows/ci.yml)). v2 will add jobs to the
same workflow once it has executable code.

CI coverage by phase:

- Phase 1: install.ps1 happy path, bootstrap failure paths.
- Phase 2: doctor checks, brew config output.
- Phase 3: full install / uninstall cycle, argument fuzz tests.
- Phase 4: upgrade paths, restricted-execution-policy paths, prefix
  with spaces, simulated MITM (corrupted SHA256), simulated upstream
  history rewrite.

### "Binary packages"

v1's release workflow ([release.yml](../../.github/workflows/release.yml))
already produces:

- Release zip with SHA256 sidecar
- GitHub artifact attestation
- Signed, named release on GitHub

v2 inherits the same release pipeline shape with a different payload.
Same attestation model, smaller zip.

### "Non-author users"

Phase 4 exit criterion. Documented in [PHASE_PLAN.md](PHASE_PLAN.md).

Recruitment plan (best-effort, Phase 4 work):

- Follow-up comment on the existing Homebrew discussion 6860 once v2
  ships its first release.
- Windows developer communities (PowerShell subreddit, Hacker News
  Show, dev.to writeup).
- Direct outreach to v1 users who tried `brew install codex`.

A non-author user counts when they:

- Ran `irm install.ps1 | iex` on their own machine.
- Successfully completed `brew install <formula>` and got working
  output from the installed CLI.
- Publicly confirmed it on the project's issue tracker or discussion.

### "Tier 3 / unsupported"

v2's positioning is explicit:

- The launcher's User-Agent string identifies as "Brew Windows v2
  (experimental)".
- The Phase 5 Windows link strategy PR is guarded by an explicit
  `HOMEBREW_EXPERIMENTAL_WINDOWS_SUPPORT` opt-in initially.
- The README, install message, and `brew doctor` output all describe
  v2 as experimental.

No claim of supported tier appears anywhere in v2 documentation or
runtime output.

### "No extended PowerShell support initially"

The Phase 5 PR sequence does not include:

- A native PowerShell `brew` reimplementation (we do not have one;
  the launcher is the only PS, and it stays in the v2 repo).
- A PowerShell-specific `brew shellenv` improvement beyond what
  already merged (PR #19407).
- Any PowerShell completion changes beyond what already merged.

What we may submit later, post-Phase 5, depending on maintainer
appetite:

- A `brew shellenv pwsh` improvement if Phase 2 surfaces a bug.
- A Windows-aware path resolver helper if a Phase 5 review surfaces
  one as useful for all platforms.

Both deferred until invited.

## Compliance Audit Checklist

When preparing the Phase 5 upstream conversation, run this checklist:

- [ ] v2 has shipped a public release (not just a tag).
- [ ] Release artifacts have SHA256 sidecars and GitHub attestation.
- [ ] CI matrix is green and exercises the install / install / uninstall
  / corrupted-runtime cycle.
- [ ] At least three non-author users have publicly confirmed working
  installs.
- [ ] The Phase 5 PR drafts are each under 500 LOC.
- [ ] Each PR has tests proving macOS/Linux behavior is unchanged.
- [ ] No PR claims a support tier.
- [ ] No PR depends on a later PR to be useful.
- [ ] The compliance table above is current.

When every box is checked, Phase 5 is appropriate.

## What Compliance Does Not Mean

Compliance with the maintainer feedback does not mean upstream will
merge anything. Both maintainer positions in discussion 6860 are
contingent:

- p-linnane explicitly said no, even to inert abstractions.
- MikeMcQuaid said maybe, conditional on Phase 1-4 evidence.

Phase 5 is the test of which position prevails. v2 is built to be
viable regardless: it functions as a complete external project, and
the upstream PRs are bonus value.

If upstream rejects every Phase 5 PR, v2 still works. v2's existence
does not depend on upstream acceptance.
