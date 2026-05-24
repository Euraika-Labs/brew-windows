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

Twenty patches are pinned in `runtime-manifest.json` and applied in
manifest order on every bootstrap. Each patch's own header records
the targets, phase, and rationale; the table below is the index.

### Phase 1 (OS detection)

| File | Purpose |
| --- | --- |
| `windows-os-detection.patch` | Adds `OS.windows?`, OSTYPE branch in `brew.sh`, and the `extend/os/windows/` directory. |

### Phase 2 (boot + doctor parity)

| File | Purpose |
| --- | --- |
| `windows-path-separator.patch` | `split(":")` -> `split(File::PATH_SEPARATOR)` in `Library/Homebrew/utils/gems.rb`. |
| `windows-bundler-lookup.patch` | `find_in_path` extension probe (.bat, .cmd, .exe, .com) for the bundler shim. |
| `windows-system-command.patch` | `SystemCommand#exec3` via `Process.spawn` instead of fork+exec; strips POSIX-only spawn options; routes bash shebang shims through vendored bash.exe. |
| `windows-tty.patch` | Rescue `ENOENT`/`EINVAL` around `/bin/stty` + `/usr/bin/tput` shellouts in `utils/tty.rb`. |
| `windows-python-rescue.patch` | `Language::Python.major_minor_version` rescues `ENOENT` when no python is found. |
| `windows-sandbox-stub.patch` | Skips `require "pty"` and `require "utils/fork"` from `sandbox.rb` on Windows. |
| `windows-utils-popen.patch` | `Utils.popen` uses array-form `IO.popen` (Process.spawn under the hood) instead of the fork-myself idiom; resolves bare `git`/`curl`/`ruby` to `HOMEBREW_GIT_PATH`/`HOMEBREW_CURL_PATH`/`HOMEBREW_RUBY_PATH`. |
| `windows-homebrew-system.patch` | `Homebrew._system` via `Process.spawn` instead of fork+exec; same bare-command and shebang routing. |
| `windows-diagnostics.patch` | Adds Windows-aware doctor checks: `check_long_path_support`, `check_execution_policy`, `check_path_brew_windows` (reads HKCU\\Environment\\Path via reg.exe), `check_path_shadowed_shims`, `check_runtime_integrity`, `check_curl_present`. |
| `windows-doctor-overrides.patch` | No-op overrides on existing checks that assume POSIX: `check_git_newline_settings`, `check_git_status`, `check_for_installed_developer_tools`, `check_homebrew_prefix`, `check_user_path_{1,2,3}`. |

### Phase 3 (formula install)

| File | Purpose |
| --- | --- |
| `windows-which-extensions.patch` | `Kernel#which` probes `.exe`/`.cmd`/`.bat`/`.com` for bare command lookups so `which("unzip")` finds MinGit's `unzip.exe`. |
| `windows-lockfile-unlink-order.patch` | `LockFile#unlock` closes the file handle before `Pathname#unlink` on Windows (no `FILE_SHARE_DELETE` in Ruby's `File.open`). |
| `windows-dev-tools.patch` | `DevelopmentTools.installed?` returns true on Windows so `UnbottledError` doesn't fire for binary-only formulae. |
| `windows-fork-stub.patch` | `Utils.safe_fork` runs the block in-process under a `SafeForkContext` that intercepts `exec(*args)` and converts to `Process.spawn` + `Process.wait`. |
| `windows-build-error-pipe.patch` | `build.rb` skips the UNIXSocket setup on Windows; errors flow back through stderr and exit status. |
| `windows-formulary-drive-path.patch` | `FromURILoader.try_new` rejects `[A-Za-z]:[\\/]` paths early so Windows-absolute formula paths fall through to `FromPathLoader`. |
| `windows-stdenv-compiler.patch` | `Stdenv#setup_build_environment` and `SharedEnvExtension#compiler` return early on Windows when no clang/gcc is available. |
| `windows-atomic-write.patch` | `File.atomic_write` writes via a Tempfile but copies bytes directly to the destination instead of `File.rename` (cross-symlink-Cellar rename fails with ENOENT on Windows). |
| `windows-link-strategy.patch` | `Keg#make_relative_symlink` reroutes `<prefix>/bin` files to `HOMEBREW_WINDOWS_PREFIX/bin` and emits a `.cmd` + `.ps1` shim pair pointing at the keg-installed executable; other files are NTFS-hardlinked (fall back to copy). |

### Archived (no longer in manifest)

`windows-gem-api-version.patch` and `windows-ruby-version.patch` are
kept in this directory for historical reference. They worked around
the Ruby 3.3 / 4.0 vendored-gems mismatch that surfaced before we
upgraded to RubyInstaller 4.0.5-1; they are unused now.

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
