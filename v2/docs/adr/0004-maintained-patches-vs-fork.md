# v2 ADR 0004: Maintain Patches Against Upstream Homebrew Rather Than A Fork

Date: 2026-05-24

## Status

Accepted.

## Context

v2 ADR 0001 commits v2 to running upstream `Homebrew/brew`'s code as
the runtime. Upstream Homebrew, as of mid-2026, does not work
unmodified on Windows. Specifically:

- `Library/Homebrew/os.rb` knows macOS and Linux; not Windows.
- The keg link step assumes symlinks.
- Some bash bootstrap code in `brew.sh` has `OSTYPE`-based branches
  that fall through to a generic Unix path on Windows, which then
  fails on the symlink call.

v2 needs Homebrew to behave differently in these places. There are
three ways to get that:

1. **Fork**: maintain `Euraika-Labs/brew` (or similar) as a Windows
   fork of `Homebrew/brew`. Pin the launcher to clone from the fork.
2. **Patches**: maintain small patch files in this repo. The launcher
   clones upstream `Homebrew/brew` and applies the patches during
   `Install-Runtime`.
3. **Runtime monkey-patching**: leave the Homebrew clone unmodified;
   inject Ruby code at startup that re-opens classes and changes
   behavior.

Each has trade-offs.

A **fork** is the lowest-effort to integrate but the highest-cost to
maintain. Every upstream change requires a merge. Hidden changes
accumulate. Reviewability of "what does v2 actually change?" is poor.
Worst case, the fork diverges enough that proposing changes back
upstream is no longer believable.

**Runtime monkey-patching** is invisible to upstream and brittle.
Changes in upstream internals silently break Windows behavior. Tests
hide the breakage until a user reports it.

**Patches** sit between the two. Every change is a discrete `.patch`
file with a clear filename, scope, and rationale. The patch set is
the prototype for the eventual upstream PRs.

## Decision

v2 maintains a small set of patches against upstream `Homebrew/brew`.

- Patches live in `v2/launcher/patches/*.patch`.
- Each patch has a SHA256 pinned in `runtime-manifest.json`.
- `Install-Runtime` applies each patch with `git apply --check`
  (dry run) followed by `git apply`, in the order listed in
  `runtime-manifest.json`.
- The patch set is small and tightly scoped. Initial set:
  - `windows-os-detection.patch` (~30 lines): adds `OS.windows?`
    and an `extend/os/windows/` extension point.
  - `windows-link-strategy.patch` (~150 lines): adds the Windows
    keg link strategy.
- Each patch is the prototype of a future upstream PR. If upstream
  accepts the abstraction, the patch is removed from our set and we
  bump the pinned commit SHA past the merge.

We do **not** maintain a fork of `Homebrew/brew`.

## Consequences

### Operational

- Every patch is reviewable in this repository. `git log --
  v2/launcher/patches/` is a complete record of Windows-specific
  changes against upstream Homebrew.
- Pinning the upstream commit SHA means upstream changes do not
  silently disrupt our runtime. A new commit SHA is a deliberate
  bump.
- When upstream changes touch code our patches touch, `git apply
  --check` fails fast during `Install-Runtime`. We see breakage
  before users do.

### Maintenance cost

- Bumping the upstream commit SHA requires re-validating that each
  patch still applies and produces the expected behavior. CI runs
  this on every commit-SHA bump.
- Adding a new patch requires: writing the patch, adding it to
  `runtime-manifest.json`, regenerating SHA256s, updating
  `pins.json` semantics, adding a test case that exercises the
  patched behavior.
- Patch review is now part of our review process. Each patch is its
  own document with a header comment explaining what it does and
  what upstream PR it prototypes.

### Compliance

This decision is what makes [COMPLIANCE.md](../COMPLIANCE.md)
requirements 3 and 10 achievable. Each patch is small (target
<200 LOC), each is independently reviewable, each preserves
macOS/Linux behavior by design.

## Patch Header Convention

Every patch file begins with a header:

```
# Brew Windows v2 patch
#
# Title:      Add OS.windows? predicate and extend/os/windows/ skeleton
# Targets:    Library/Homebrew/os.rb, Library/Homebrew/extend/os/windows/...
# Upstream:   PR candidate for `Homebrew/brew`; PR draft TBD
# Phase:      1 (bootstrap proof) / 5 (upstream PR)
# Rationale:  Native Windows detection without enabling any new code
#             paths; required by subsequent v2 patches.
# Preserved:  All existing OS.mac? / OS.linux? behavior.
```

The header is comment lines that `git apply` ignores, but they make
the patch readable as a standalone artifact.

## Patch Application Failure Policy

If `git apply --check` fails for any patch during `Install-Runtime`:

1. The install aborts with an explicit error naming the patch.
2. The previous runtime (if any) is restored from staging.
3. No partial state is left.

This is the same atomicity policy as the rest of `Install-Runtime`.

In practice, a patch fails to apply only when:

- The pinned upstream commit SHA in `runtime-manifest.json` does not
  match what our patches were written against. This is a manifest
  authoring bug.
- The patch file in the release zip was tampered with. This is the
  scenario [THREAT_MODEL.md](../THREAT_MODEL.md) T9 covers.
- An installer was hand-edited.

All three cases warrant aborting.

## Rejected Alternative: Fork

Rejected because:

- A fork's diff against upstream is large and unreadable as a unit.
- A fork hides the boundary between "upstream's behavior" and "v2's
  behavior".
- A fork is harder to translate into upstream PRs - reviewers cannot
  easily see "this is the slice we propose".
- Fork divergence accumulates silently.
- Upstream Homebrew has explicit policy against long-running forks
  ([Homebrew docs](https://docs.brew.sh/)).

## Rejected Alternative: Runtime Monkey-Patching

Rejected because:

- Monkey-patches are invisible in `git diff` against the upstream
  repository.
- Upstream internal changes silently break behavior; we discover it
  by user reports.
- Reviewability is poor. The behavior is in Ruby code that runs at
  startup, not in a discrete patch with a header.
- Translating monkey-patches into upstream PRs is effectively a
  rewrite.

## Migration Path For Each Patch

When upstream accepts a PR that obviates one of our patches:

1. Bump the pinned commit SHA in `runtime-manifest.json` past the
   merge.
2. Remove the patch file from `v2/launcher/patches/`.
3. Remove the patch entry from `runtime-manifest.json`.
4. Test that v2 still works.
5. Cut a new launcher release.

This is straightforward because each patch is a discrete unit.

## CI Coverage

CI must verify on every change:

- Every patch in `runtime-manifest.json` exists in the launcher
  source tree at the listed path.
- Every patch's SHA256 matches the value in `runtime-manifest.json`.
- Every patch applies cleanly against the pinned upstream commit.
- After applying all patches, the resulting Homebrew clone produces
  expected behavior in smoke tests.

A patch that breaks any of these fails the CI build.
