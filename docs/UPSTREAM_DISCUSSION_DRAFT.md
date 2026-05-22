# Homebrew Discussion Draft

This draft is ready to paste into `Homebrew/discussions` under "Tap maintenance
and Homebrew development" after project owner approval.

## Title

Native Windows Brew prototype: request for guidance on small upstreamable abstractions

## Body

Hello Homebrew maintainers,

I am working on a native Windows prototype that tries to preserve Homebrew
concepts while running directly in Windows Terminal and PowerShell. This is not
a WSL bridge, not an MSYS2 runtime identity, and not a wrapper around WinGet,
Scoop, Chocolatey, npm, or `wsl.exe`.

I am not asking Homebrew to accept native Windows support today. I am asking
whether maintainers would consider a small sequence of no-behavior-change
abstractions that could make a future native Windows experiment reviewable
without disturbing current macOS/Linux behavior.

Prototype repo:

<https://github.com/Euraika-Labs/brew-windows>

Current release:

<https://github.com/Euraika-Labs/brew-windows/releases/tag/v0.2.3>

The current public demo path is:

```powershell
irm https://github.com/Euraika-Labs/brew-windows/releases/latest/download/install.ps1 | iex
brew install codex
codex --version
```

What exists in the prototype today:

- per-user prefix at `%LOCALAPPDATA%\Homebrew`;
- PowerShell-native installer and runtime;
- Cellar-style package layout;
- checksum-verified downloads;
- `.cmd` and `.ps1` shims;
- generic package catalog;
- Windows CI for Windows PowerShell and PowerShell 7;
- release payload SHA256 and artifact attestation;
- a real `codex` package using official OpenAI Windows release assets.

I have read the prior native Windows issue:

<https://github.com/Homebrew/brew/issues/14197>

The concern about Unix/Bash assumptions is valid. The prototype was built to
gather evidence before asking for any upstream changes.

The proposed first PR sequence would be deliberately narrow:

1. Document and test the launcher-to-`brew.sh` environment contract.
2. Add inert Windows host detection without enabling Windows support.
3. Extract path-list and executable-resolution helpers while preserving current
   Unix behavior.
4. Extract shellenv rendering so PowerShell output can be added narrowly.
5. Extract keg linking behind a strategy interface before discussing Windows
   shims.

The full dossier and PR sequence are here:

- <https://github.com/Euraika-Labs/brew-windows/blob/main/docs/UPSTREAM_DOSSIER.md>
- <https://github.com/Euraika-Labs/brew-windows/blob/main/docs/UPSTREAM_PR_SEQUENCE.md>
- <https://github.com/Euraika-Labs/brew-windows/blob/main/docs/UPSTREAM_MAINTAINER_PACKET.md>

Questions:

- Is native Windows categorically out of scope for Homebrew?
- If not, which no-behavior-change abstraction would be the least objectionable
  first PR?
- Would any Windows-related code need to stay outside `Homebrew/brew` until a
  much later milestone?
- Would an unsupported or Tier 3 experimental path still create too much
  maintenance burden?
- Are Windows bottle tags, shim link strategies, or PowerShell shellenv changes
  out of bounds?

I am happy to keep this as a separate prototype if that is the right answer. I
would rather ask early and avoid wasting maintainer review time than open a
large "Windows support" PR.
