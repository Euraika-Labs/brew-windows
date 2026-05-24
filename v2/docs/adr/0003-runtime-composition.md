# v2 ADR 0003: Runtime Composition

Date: 2026-05-24

## Status

Accepted.

## Context

v2 ADR 0001 requires bash + Ruby + curl to be available to the launcher.
v2 ADR 0002 requires those to be downloadable from pinned URLs with
SHA256 verification. This ADR picks specific distributions.

The constraints:

- **Native Win32 builds only.** No WSL. No MSYS2 as runtime identity.
- **Signed, predictable release URLs.** We need to pin specific
  versions + SHA256 hashes.
- **Smallest reasonable footprint** that still covers what upstream
  `Homebrew/brew` actually needs.
- **No mandatory developer prerequisites.** A user with a stock Windows
  11 install should be able to run `irm install.ps1 | iex` and end up
  with a working `brew`.

## Decision

### bash: MinGit

Use **MinGit** (`MinGit-X.Y.Z-64-bit.zip` or
`MinGit-X.Y.Z-busybox-64-bit.zip`) from the `git-for-windows/git`
GitHub Releases.

Rationale:

- MinGit ships a working `usr/bin/bash.exe` and the minimal POSIX
  environment (`coreutils`, `sed`, `awk`, `grep`, `find`) that
  Homebrew's `brew.sh` bootstrap actually uses.
- Microsoft-signed installer / archive.
- Stable predictable URL pattern.
- ~50 MB compressed - acceptable for first-run.
- Same MinGit is what most Windows developers already have via Git for
  Windows. We pin our own copy so the user's installed version cannot
  break us.

The MinGit "busybox" variant is smaller (~25 MB) but ships busybox
utilities instead of full coreutils. We start with the full MinGit; if
Homebrew's bash bootstrap doesn't touch the differences, we can switch
to busybox in a later launcher version to halve the footprint.

### Ruby: RubyInstaller (Without DevKit / MSYS2 Sidecar)

Use **RubyInstaller for Windows**, specifically the "Ruby" archive
distribution (not the installer EXE, not the "Ruby + Devkit"
variant). Available from `oneclick/rubyinstaller2` GitHub Releases as
`rubyinstaller-X.Y.Z-N-x64.7z`.

Rationale:

- Native PE Ruby for Windows.
- ~30 MB compressed.
- DevKit / MSYS2 toolchain is *only* needed for compiling native gems
  from source. Homebrew itself doesn't compile native gems from
  `brew install` - so DevKit is not a runtime requirement.
- Signed, predictable releases.

The archive format is 7z, so the launcher needs a 7z extractor. PowerShell
5.1+ does not have native 7z support; we will either:

- ship a tiny 7z extraction library, or
- prefer the `.exe` self-extracting variant where available, or
- shell out to `tar.exe` (Windows 10 1803+) which can read some 7z
  variants.

Decision deferred to Phase 1 implementation. If 7z is awkward, falling
back to a custom RubyInstaller zip mirror hosted on this project's
release storage is an acceptable last resort.

### curl: System curl

Use `C:\Windows\System32\curl.exe`.

Rationale:

- Shipped with Windows 10 1803 (April 2018) and every Windows version
  since. Available in every supported Windows install we target.
- Microsoft-maintained and Microsoft-signed.
- Zero download cost. Zero update responsibility for us.
- `brew doctor` verifies presence and prints a clear error if not
  found (e.g. on a Windows 10 version older than 1803).

### Homebrew: Shallow Git Clone, Pinned Commit SHA

Clone `https://github.com/Homebrew/brew.git` into `runtime/homebrew/`
with `--depth=1` at a specific commit SHA recorded in
`runtime-manifest.json`.

Rationale:

- Pinning to a SHA (not a branch) eliminates the "what Homebrew version
  did I get?" question and makes the launcher reproducible.
- Shallow clone keeps the on-disk size around ~50 MB instead of the
  ~150 MB a full clone produces.
- Updating Homebrew is a launcher version bump: `runtime-manifest.json`
  gets a new SHA, the next launcher upgrade triggers a re-clone.
- This also means `brew update` (which upstream defines as
  `git pull origin master` inside the Homebrew repo) does not behave
  the same way. We will likely intercept `brew update` in `brew.ps1`
  and have it check for a new launcher version instead.

## Consequences

- Cold-install on-disk footprint: ~130 MB total
  (50 MinGit + 30 Ruby + 50 Homebrew).
- Bandwidth on first run: ~130 MB combined download.
- We become responsible for tracking three upstream release feeds:
  Git for Windows, RubyInstaller, and Homebrew commit pins. A simple
  automation (similar in spirit to v1's catalog sync) will check for
  new upstream versions and propose a `runtime-manifest.json` bump.
- The launcher needs a working 7z extractor for RubyInstaller. Phase 1
  decides whether to ship one, use tar.exe, or mirror as zip.
- Homebrew's existing `brew update` command needs special handling.
  Designing that is deferred to Phase 4.

## Rejected Alternatives

- **WSL bash**: ruled out by v2 ADR 0001 and v1 ADR 0001. WSL is not
  a runtime identity.
- **Cygwin**: produces a Cygwin runtime identity that surfaces
  through error messages and file paths. We want users to never see
  a Unix path.
- **MSYS2 standalone (not via MinGit)**: too much surface area. MinGit
  already vendors the MSYS2 bits Homebrew needs.
- **Build our own Ruby + bash**: enormous maintenance cost.
  RubyInstaller and MinGit are mature and well-maintained.
- **Use Ruby from any installed source (system, RubyInstaller already
  on PATH)**: removes our version control. We need pinned versions.
- **Use Git for Windows full install instead of MinGit**: ~250 MB,
  bundles git GUI tools and Perl, far more than we need.
