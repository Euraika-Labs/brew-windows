# v2 ADR 0008: User PATH Only, No Machine PATH, No Profile Edits

Date: 2026-05-24

## Status

Accepted. Continuation of v1 ADR 0002.

## Context

Installing a CLI tool on Windows is rarely "just put a binary
somewhere." It is "make the binary findable by the shell." Several
Windows install patterns are common:

- **Machine PATH (registry key `HKLM\SYSTEM\...\Environment\Path`)**:
  visible to all users; requires admin to modify.
- **User PATH (registry key `HKCU\Environment\Path`)**: visible to
  the current user; modifiable without admin.
- **Shell profile edits (`$PROFILE` in PowerShell, `~/.bashrc` in
  bash)**: visible only to the current user's interactive shell;
  modifiable without admin but invasive (the user's profile is
  customized by us).
- **Manifest registration (Windows App Execution Aliases, App
  Paths)**: requires installer manifest and specific Windows APIs.

v1 ADR 0002 picked **User PATH only**. The decision rationale:

- No admin required (rules out Machine PATH).
- No invisible mutation of the user's profile (rules out profile
  edits).
- Works in PowerShell, cmd, Windows Terminal, IDE-launched shells -
  anything that reads User PATH.

v2 should not regress on this.

## Decision

v2 continues v1's User-PATH-only model.

- `install.ps1` adds exactly one entry to User PATH:
  `<prefix>\bin`.
- `install.ps1` does **not** write to Machine PATH (registry
  `HKLM\SYSTEM\...`).
- `install.ps1` does **not** modify `$PROFILE` (PowerShell profile),
  `~/.bashrc`, `~/.zshrc`, or any other shell profile.
- `uninstall.ps1` removes only the entry it added.
- The user's existing User PATH is preserved (we prepend, we don't
  replace).

The runtime's internal paths (`runtime\mingit\usr\bin`,
`runtime\ruby\bin`) are **not** added to User PATH. They are only
added to `$env:PATH` for the duration of the bash invocation inside
`brew.ps1`.

## Why Not Add Runtime To User PATH

We could have made bash, Ruby, and the rest of MinGit's utilities
available to the user's shell by adding `runtime\mingit\usr\bin` to
User PATH. We do not, because:

- The user did not ask for a global bash. They asked for `brew`.
- A global bash on PATH would conflict with Git for Windows installs
  the user may already have.
- A global Ruby on PATH would conflict with other Ruby installations.
- We want the User PATH change to be minimal and reversible. One
  entry. One semantic addition: "the `brew` command and the things
  it installed."

If a user wants to invoke MinGit's bash directly, they can:

- Run `<prefix>\runtime\mingit\usr\bin\bash.exe` explicitly.
- Or install a separate Git for Windows; we don't conflict.

## How The PATH Update Works

`install.ps1` reads `[Environment]::GetEnvironmentVariable("Path",
"User")`. If `<prefix>\bin` is not already there, it prepends it
(prepend, not append) and writes the result back via
`[Environment]::SetEnvironmentVariable(..., "User")`.

Prepending puts our shims earlier in the resolution order than
other entries. This is intentional - if the user has another `gh.cmd`
elsewhere, our `gh.cmd` (which they explicitly installed via brew)
wins. Symmetric to how `usr/local/bin` works on macOS.

The current process's `$env:Path` is also updated so the same
PowerShell session sees the change.

Newly-spawned PowerShell windows pick up the User PATH change
naturally - Windows reads HKCU\Environment\Path on shell start.

## Uninstall

`uninstall.ps1` reads User PATH, finds `<prefix>\bin`, removes it,
writes the result back. If `<prefix>\bin` is not in User PATH,
uninstall proceeds anyway and does not warn.

The runtime directory's paths were never in User PATH, so there is
nothing to clean up there.

## Consequences

- No elevation required for install or uninstall.
- The user's shell profile is untouched. The user can customize
  their own profile without v2 interfering.
- The User PATH change is visible from any new shell (PowerShell,
  cmd, Windows Terminal, VSCode integrated terminal, JetBrains
  terminals, etc.).
- The user's existing PATH state is preserved across install and
  uninstall.
- An advanced user who wants brew on Machine PATH can manually add
  it after install. v2 does not actively prevent this; we just
  don't do it by default.

## Failure Modes And Mitigations

### Stale current process PATH

A user installs Brew Windows in a PowerShell window. The User PATH is
updated, but the *current* `$env:Path` of that window may not have
picked up the change automatically.

Mitigation: `install.ps1` explicitly updates `$env:Path` for the
current process. The same window can immediately run `brew`.

### Path length limit

Windows historically limited User PATH to 2047 characters in some
contexts (registry value type quirks). Adding `<prefix>\bin` could
push the user over this limit.

Mitigation: `install.ps1` checks the resulting User PATH length.
If it would exceed 2047 characters, it aborts with a clear error
message asking the user to clean up their PATH first.

### Concurrent PATH edits

If another process is modifying User PATH at the same moment
(`install.ps1` from a different installer running concurrently),
the last write wins.

Mitigation: this is a Windows-level race that no installer
solves robustly. v2 reads-then-writes atomically within the
PowerShell process, which is good enough for normal use.

### User has already added `<prefix>\bin` manually

`install.ps1` checks for the exact entry before adding. If
already present, no PATH change is made.

## What Does Not Happen

v2 does not, under any code path:

- Write to `HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment`.
- Write to `$PROFILE` files (PowerShell or otherwise).
- Modify `.bashrc`, `.zshrc`, `.fish`, or other shell startup
  files.
- Register an App Path under `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths`.
- Create a Windows Service.
- Modify Windows Defender exclusions.
- Modify any Group Policy.
- Install fonts, certificates, drivers, or other system-wide
  artifacts.

These limits are explicit and tested in CI.

## Rejected Alternative: Modify $PROFILE

Rejected because:

- Invisible to the user. They don't expect Brew Windows to be in
  their profile.
- Hard to undo cleanly (`uninstall.ps1` would have to parse and
  edit a file the user may have customized).
- Conflicts with profile-management tools (chezmoi, dotfiles
  repos).
- Doesn't work for non-PowerShell shells.

## Rejected Alternative: Machine PATH

Rejected because:

- Requires admin elevation.
- Affects all users on the machine.
- Inconsistent with per-user install model.

## Rejected Alternative: App Execution Aliases

Rejected because:

- Requires either MSIX packaging or a registry write to
  `HKCU\Software\Microsoft\Windows\CurrentVersion\App Paths`.
- App Paths only work for `start <name>` style invocation, not for
  the user typing `brew` in a shell.
- Adds Windows-specific install surface we don't need.

## CI Coverage

CI must verify on every run:

- After install, User PATH contains `<prefix>\bin`.
- After install, Machine PATH is unchanged.
- After install, `$PROFILE` files are unchanged.
- After uninstall, User PATH no longer contains `<prefix>\bin`.
- Re-running install does not duplicate the PATH entry.

The CI runner has no admin privileges granted to the test job, which
mechanically verifies the no-admin assumption.
