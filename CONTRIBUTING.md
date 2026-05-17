# Contributing

Thank you for your interest in Brew Windows. This project exists to develop a
credible upstream path for Windows-related Homebrew improvements.

## Principles

- Prefer upstreamable design over local hacks.
- Keep changes small, reviewable, and well documented.
- Avoid breaking macOS and Linux assumptions unless the change introduces a
  clear abstraction.
- Treat native Windows support as experimental until Homebrew maintainers accept
  a support model.
- Do not copy Homebrew code into this repository unless the license and purpose
  are clear.

## Before Opening an Issue

Please check whether your idea belongs in one of these categories:

- WSL, PowerShell, or Windows Terminal integration.
- Native Windows bootstrap or path handling.
- Keg linking, shims, or executable resolution.
- Bottle tags, binary inspection, or dependency scanning.
- Upstream pull request planning.

If the issue is about normal Homebrew usage, open it in the appropriate
Homebrew repository or discussion forum instead.

## Pull Request Guidelines

Pull requests should:

- Be written in English.
- Include a concise explanation of the problem and solution.
- Reference the related issue or architecture section when possible.
- Include tests or validation steps when behavior changes.
- Avoid unrelated formatting churn.
- Keep generated files out of the repository.

## AI-Assisted Contributions

AI-assisted work is allowed if the contributor:

- Reviews and understands the generated content.
- Discloses the tool or model used when opening the pull request.
- Can respond to review feedback without relying on maintainers to fix the work.

This mirrors the expectations used by the Homebrew project.

## Local Validation

For documentation-only changes:

```sh
git diff --check
```

For future code changes, add project-specific validation commands to this file
as the implementation grows.
