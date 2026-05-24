# v2 ADR 0006: `brew update` Is Intercepted By The Launcher

Date: 2026-05-24

## Status

Accepted.

## Context

Upstream Homebrew's `brew update` command does, roughly:

1. `git -C $HOMEBREW_REPOSITORY pull` to advance the Homebrew clone.
2. `git pull` for every installed tap.
3. Refreshes some cached metadata.

This works on macOS and Linux because Homebrew is a moving target -
the clone tracks `master` (or `main`) and each `update` advances it.

v2 explicitly pins the Homebrew clone to a specific commit SHA
recorded in `runtime-manifest.json` (see
[ADR 0003](0003-runtime-composition.md) and
[BOOTSTRAP.md](../BOOTSTRAP.md)). A `git pull` would un-pin the
clone, breaking the SHA verification on next `Install-Runtime` and
defeating the reproducibility guarantee.

Three options:

1. **Let `brew update` run.** Accept that the clone advances; treat
   the pinned SHA as a starting point, not a fixed point.
2. **Disable `brew update` upstream via env.** Set
   `HOMEBREW_NO_AUTO_UPDATE=1` and rely on upstream's own checks to
   skip auto-update. Manual `brew update` still works.
3. **Intercept `brew update` in the launcher.** Detect the command
   before exec'ing bash, print a message explaining the v2 model,
   and refuse to run the upstream code.

Option 1 contradicts ADR 0003's pinning rationale. Option 2 only
blocks auto-update, not user-initiated `brew update`. Option 3
addresses both.

A separate question: how does the user update Homebrew formulae?
Upstream's answer is "run `brew update`". v2 needs a different
answer.

## Decision

`brew.ps1` intercepts the `update` subcommand before exec'ing bash.

When the user runs `brew update`:

- The launcher prints a short message explaining the v2 model.
- The launcher does **not** exec upstream Homebrew.
- Exit code is 0 (no error - the user did nothing wrong; the
  command just means something different in v2).

The user-facing message:

```
brew update is not used in Brew Windows v2.

Brew Windows v2 pins the Homebrew runtime and formula sources to a
specific version. To get newer formulae, update the launcher:

    brew self-update

This downloads the latest Brew Windows release, which advances the
pinned Homebrew commit to a tested version.
```

`HOMEBREW_NO_AUTO_UPDATE=1` is also set in the environment contract
([HOMEBREW_INTEGRATION.md](../HOMEBREW_INTEGRATION.md)) as a
belt-and-braces guard against upstream's own auto-update logic.

## How Users Actually Get Updates

The v2 update model is launcher-version-bump:

1. The maintainer regularly updates `runtime-manifest.json` to a
   newer pinned Homebrew commit (and possibly newer MinGit / Ruby
   pins).
2. The maintainer publishes a new launcher release.
3. The user runs `brew self-update` (or re-runs
   `irm install.ps1 | iex`).
4. The new launcher's `runtime-manifest.json` has a different
   Homebrew SHA than the user's `runtime/pins.json`.
5. Next `brew` invocation detects the mismatch, calls
   `Install-Runtime`, re-clones Homebrew at the new commit, applies
   patches, updates `pins.json`.
6. The user now has the new Homebrew version, with all formulae
   it includes.

`brew self-update` is a launcher command (intercepted by the
launcher, not forwarded to upstream). It:

1. Resolves the latest Brew Windows release via the GitHub API.
2. Downloads the launcher zip, verifies its SHA256.
3. Backs up the current launcher files.
4. Extracts the new launcher into the prefix.
5. Triggers `Install-Runtime` (lazy) on the next `brew` invocation.

This mirrors how `rustup self update` works and is well-understood by
Windows developers.

## Consequences

### User experience

- Formula updates happen on a slower cadence (launcher releases) than
  upstream Homebrew (continuous on master). Trade-off accepted: a
  cadence of ~monthly launcher releases is reasonable for a Windows
  CLI tool consumer.
- Users cannot "follow Homebrew master" on v2. If they want to track
  a specific Homebrew commit, they can fork the launcher and ship
  their own `runtime-manifest.json`. We document this in
  [CONTRIBUTOR_GUIDE.md](../CONTRIBUTOR_GUIDE.md) when it exists.
- Users do not have to `brew update` before installing - the
  pinned model means the formula they see is the formula they get.
  No stale-cache surprises.

### Reproducibility

- Two users at the same launcher version are guaranteed to be
  running identical bash, Ruby, Homebrew, and patches.
- A bug report can reference the launcher version and be exactly
  reproducible.
- A CI run is deterministic in what version of upstream Homebrew it
  exercises.

### Tap updates

`brew update` also pulls user-installed taps. v2's interception means
tap updates do not happen automatically.

Two paths considered:

- **Tap updates piggy-back on launcher updates.** The launcher
  records the desired tap state somewhere; `Install-Runtime` or a
  separate step fetches the latest of each tap.
- **Tap updates are explicit.** A separate `brew-windows tap-update`
  command or equivalent.

Decision deferred to Phase 4 when actual tap usage exists.

For now, when the user runs `brew tap <owner>/<tap>`, Homebrew clones
the tap as it normally does. The clone tracks the tap's default
branch. The user can manually run `git -C <prefix>/Library/Taps/<owner>/<tap>
pull` if they want updates between launcher releases.

### Operational

- Launcher releases need a clear release cadence to avoid lagging
  upstream too far. Target: ~monthly during Phase 1-4, faster if
  upstream has a Windows-relevant change.
- A `brew-windows-update.ps1` automation in Phase 4+ can check for
  new upstream versions and propose `runtime-manifest.json` bumps
  via PR.

## Rejected Alternative: Let `brew update` Run

Rejected because it defeats the pin model. Once `git pull` runs, the
checked-out tree no longer matches `expectedTreeSha256` in
`runtime-manifest.json`. Either:

- We weaken the integrity check (bad - removes a defense layer).
- We don't check after `brew update` (bad - inconsistent).
- We re-clone after `brew update` (bad - the user just `update`d,
  this would feel wrong).

Better to intercept.

## Rejected Alternative: Disable Only Auto-Update

`HOMEBREW_NO_AUTO_UPDATE=1` alone would allow user-initiated `brew
update`, which then runs `git pull` and breaks the pin. Same problem,
just less frequent.

We set the env var anyway as defense in depth, but it is not the
primary mechanism.

## Rejected Alternative: Patch `brew update`

A Ruby patch could change `brew update` behavior to a no-op or to a
launcher-update prompt. Rejected because:

- The patch would have to live in our patch set and be maintained
  across upstream changes.
- The launcher already does this check before exec - simpler to
  intercept there.
- Phase 5 doesn't propose this patch upstream anyway (upstream wants
  `brew update` to work as it does for them).

## Future: A Real `brew update` On Windows

Once v2 has matured (post-Phase 4) and the upstream PR sequence is
underway, the v2 update model can be relaxed. Possible futures:

- `brew update` re-implemented in the launcher to update the pinned
  Homebrew commit to a known-tested newer version without a full
  launcher release. This requires a manifest service (a published
  JSON document listing tested upstream commits we vouch for).
- `brew update --force` allows the user to advance the upstream
  commit without going through us. Documented as experimental.
- A flag on the launcher (`brew-windows --track <branch>`) for
  power users who want to live on upstream master.

None of these are Phase 1-4 work.

## CI Coverage

CI must verify:

- `brew update` is intercepted (does not invoke upstream).
- `brew self-update --dry-run` shows the right intended actions.
- After a simulated launcher upgrade (manually overwriting the
  launcher files and `runtime-manifest.json`), next `brew --version`
  triggers `Install-Runtime` and the user ends up on the new pin.
