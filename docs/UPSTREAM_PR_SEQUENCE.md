# Proposed Homebrew Pull Request Sequence

Last verified: 2026-05-22.

This sequence is the practical upstream route for Brew Windows. It is not a
promise that Homebrew will accept native Windows support. It is a set of small,
reviewable changes that could be proposed only after a maintainer discussion.

## Rules For Every Upstream Pull Request

- Do not claim Windows support in Homebrew user-facing docs.
- Do not add Windows bottles before maintainers accept the bootstrap and link
  model.
- Preserve current macOS and Linux behavior.
- Keep each pull request independently reviewable.
- Prefer abstractions that improve clarity for existing platforms too.
- Include tests that prove macOS/Linux output is unchanged.
- Mention the Brew Windows prototype as evidence, not as an implementation
  dependency.

## PR 0: Maintainer Discussion

Goal:

Open a discussion in `Homebrew/discussions` under "Tap maintenance and Homebrew
development" asking whether the following sequence is worth preparing.

Artifacts:

- [docs/UPSTREAM_DOSSIER.md](UPSTREAM_DOSSIER.md)
- [docs/UPSTREAM_MAINTAINER_PACKET.md](UPSTREAM_MAINTAINER_PACKET.md)
- [docs/UPSTREAM_DISCUSSION_DRAFT.md](UPSTREAM_DISCUSSION_DRAFT.md)

Exit criteria:

- Maintainers answer whether native Windows is in scope at all.
- Maintainers identify any hard stop areas.
- The first acceptable no-op abstraction PR is selected.

## PR 1: Document And Isolate The Launcher Contract

Candidate upstream files:

- `bin/brew`
- `Library/Homebrew/brew.sh`
- tests around bootstrap environment handling

Goal:

Make the environment contract between the launcher and `brew.sh` explicit:
`HOMEBREW_BREW_FILE`, `HOMEBREW_PREFIX`, `HOMEBREW_REPOSITORY`,
`HOMEBREW_LIBRARY`, `HOMEBREW_CELLAR`, cache/log/temp paths, system, and
processor.

Guardrail:

This PR should be documentation, tests, or small extraction only. It should not
add a Windows launcher.

Why it helps upstream:

The current contract already exists. Naming it makes future launcher work
reviewable without changing runtime behavior.

Exit criteria:

- Existing macOS/Linux tests pass.
- `brew --version`, `brew --prefix`, `brew shellenv`, and normal command
  dispatch behave identically.

## PR 2: Add Inert Windows OS Detection

Candidate upstream files:

- `Library/Homebrew/os.rb`
- `Library/Homebrew/os/windows.rb`
- tests beside existing OS detection tests

Goal:

Add a host predicate equivalent to `OS.windows?`, but keep Windows unsupported
by default.

Guardrail:

The predicate must not route normal Homebrew users into Windows code paths.

Why it helps upstream:

It lets later code discuss Windows explicitly instead of treating it as an
unknown Unix fallback.

Exit criteria:

- macOS/Linux predicates are unchanged.
- Windows detection can be tested through doubles or controlled Ruby
  configuration.
- Running on native Windows still exits clearly unless an experimental gate is
  explicitly set.

## PR 3: Introduce Path List And Executable Resolution Helpers

Candidate upstream files:

- `Library/Homebrew/utils/path.rb`
- `Library/Homebrew/utils/shell.rb`
- command lookup tests

Goal:

Centralize path separator and executable lookup behavior behind helpers that
use the existing Unix behavior for macOS/Linux.

Guardrail:

Do not change command lookup order for current platforms.

Why it helps upstream:

Drive-letter paths, semicolon separators, and executable suffix probing are
Windows-specific pain points. A shared helper prevents platform checks from
spreading through the codebase.

Exit criteria:

- Existing command lookup tests pass.
- New tests prove the helper preserves colon-separated Unix behavior.
- Windows behavior is tested as pure helper logic, not as supported runtime.

## PR 4: Add Shellenv Renderer Abstraction

Candidate upstream files:

- `Library/Homebrew/cmd/shellenv.sh`
- `Library/Homebrew/cmd/shellenv.rb`
- shellenv tests

Goal:

Separate shellenv rendering from platform and shell assumptions. Later this can
support native PowerShell output without touching unrelated bootstrap code.

Guardrail:

Existing Bash, zsh, fish, and csh shellenv output must remain byte-for-byte
equivalent unless maintainers request cleanup.

Why it helps upstream:

PowerShell completion support has already landed upstream. A shellenv renderer
is the next narrow PowerShell-adjacent improvement, and it can be useful without
native Windows support.

Exit criteria:

- Existing shellenv snapshots or tests pass.
- PowerShell output can be added behind an explicit shell selector.
- No profile edits are introduced.

## PR 5: Introduce Link Strategy Boundary

Candidate upstream files:

- `Library/Homebrew/keg.rb`
- `Library/Homebrew/utils/link.rb`
- keg link tests

Goal:

Extract current symlink behavior into a `PosixSymlinkStrategy`-style boundary
without changing default behavior.

Guardrail:

This PR should not introduce Windows shims yet.

Why it helps upstream:

Keg linking is one of the largest native Windows compatibility barriers. A
strategy boundary lets maintainers review the current behavior extraction
before any Windows-specific linking semantics appear.

Exit criteria:

- Current link, unlink, overwrite, dry-run, and conflict behavior is unchanged.
- Tests cover the extracted interface.

## PR 6: Experimental Windows Shim Strategy

Candidate upstream files:

- link strategy implementation files selected in PR 5
- shim generation tests
- unsupported platform guard

Goal:

Add an experimental shim strategy for Windows CLI executables. The prototype
uses `.cmd` and `.ps1` shims that preserve paths, arguments, and exit codes.

Guardrail:

This must be behind an explicit unsupported/experimental gate. It must not be
advertised as general Homebrew support.

Why it helps upstream:

It proves packages can be exposed on PATH without requiring administrator
rights or symlink privileges.

Exit criteria:

- Shim argument and exit code behavior is tested.
- Conflicts are detected before writing shims.
- Existing macOS/Linux linking remains untouched.

## PR 7: Windows Bottle Tag Design

Candidate upstream files:

- bottle tag parsing and display code
- bottle specification tests

Goal:

Discuss and possibly add inert parsing/display support for tags such as
`x86_64_windows` and `arm64_windows`.

Guardrail:

No official Windows bottles are published in this step.

Why it helps upstream:

Bottle tags should not be designed after package installation grows organically.
The tag model needs to be compatible with the existing bottle DSL early.

Exit criteria:

- Tags parse without colliding with macOS/Linux tags.
- No bottle build or publishing path is enabled.

## Deferred Until After Maintainer Buy-In

- Native `install.ps1` in `Homebrew/install`.
- PE/COFF and DLL dependency inspection.
- Windows bottle relocation.
- Formula DSL changes such as `on_windows`.
- Large-scale formula migration.
- GUI app or installer support.
- Any claim of official support tier.
