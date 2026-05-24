# Brew Windows v2 Patches

This directory holds the unified-diff patches that `Install-Runtime`
applies to the pinned upstream `Homebrew/brew` working tree after the
shallow clone is checked out.

The rationale for shipping patches instead of maintaining a fork is
recorded in
[ADR 0004 (Maintain Patches Against Upstream Homebrew Rather Than A
Fork)](../../docs/adr/0004-maintained-patches-vs-fork.md). Every patch
in this directory is the prototype of an eventual upstream PR against
`Homebrew/brew`.

## Patch Header Convention

Every patch file MUST begin with a comment header that `git apply`
ignores, in the form documented by ADR 0004:

```
# Brew Windows v2 patch
#
# Title:      <short imperative sentence>
# Targets:    <relative paths inside the Homebrew checkout>
# Upstream:   <PR draft URL or "PR candidate, drafted in Phase 5">
# Phase:      <which brew-windows phase introduced or owns this patch>
# Rationale:  <why this patch exists, one or two lines>
# Preserves:  <macOS/Linux behavior guarantees>
```

The header is the human-readable card for the patch. It must be
accurate; reviewers rely on `Title` and `Targets` when bumping the
upstream commit pin.

## Manifest Linkage

Each patch is referenced from `v2/launcher/runtime-manifest.json` as an
entry in the top-level `patches` array:

```json
{
  "path": "patches/windows-os-detection.patch",
  "sha256": "<64 hex chars>",
  "appliesTo": "homebrew"
}
```

- `path` is relative to the launcher release zip root (and to this
  `launcher/` source directory).
- `sha256` is the SHA-256 of the patch file as shipped. It is computed
  by `v2/scripts/pin-runtime.ps1` (Wave 1.C).
- `appliesTo` is currently always `"homebrew"`. Future runtimes may
  define other targets.

Patches are applied in array order. `Install-Runtime` runs
`git apply --check <patch>` first; any failure aborts the install
before mutating the working tree.

## Current Patch Set

| File                              | Targets                                                | Purpose                                                |
| --------------------------------- | ------------------------------------------------------ | ------------------------------------------------------ |
| `windows-os-detection.patch`      | `Library/Homebrew/brew.sh`, `Library/Homebrew/os.rb`, `Library/Homebrew/extend/os/windows/.keep` | Adds `OS.windows?`, OSTYPE branch, extension dir.      |

The Windows link strategy patch (`windows-link-strategy.patch`) is
documented in [LINK_STRATEGY.md](../../docs/LINK_STRATEGY.md) and lands
in Wave 1.D; it is not yet present in this directory.

## Adding A New Patch

1. Write the patch file in this directory. Start with the header
   block above (verbatim except for the field values).
2. Add a new entry to the `patches` array in
   `v2/launcher/runtime-manifest.json` with a placeholder SHA-256
   (`"0" * 64`) and `appliesTo: "homebrew"`.
3. Set `placeholdersFilled` to `false` at the top of the manifest if
   it was `true`.
4. Run `v2/scripts/pin-runtime.ps1` to recompute SHA-256 values across
   the manifest. The script flips `placeholdersFilled` to `true` once
   every placeholder has been filled.
5. Verify the patch applies cleanly:
   ```powershell
   # In a fresh upstream checkout pinned to runtime-manifest.json's ref:
   git apply --check v2/launcher/patches/<new-patch>.patch
   ```
6. Add or update tests under `v2/tests/` that exercise the patched
   behavior. Keep the patch scoped tightly enough that a single test
   case covers it.

## Patch Scope Rules

- Patches must be small (target < 200 LOC of diff, hard ceiling 400
  LOC). A patch that grows past 400 LOC is a sign it should be split.
- Patches must not change macOS or Linux behavior. CI runs upstream's
  test suite against the patched tree on those platforms.
- Patches must be drafted as upstream PR candidates. If a change is
  not believable as an upstream PR, it does not belong here; consider
  whether it belongs in the launcher (`brew.ps1`) instead.
