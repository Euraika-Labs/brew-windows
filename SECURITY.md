# Security Policy

## Supported Versions

This repository is currently in the research and prototype phase. No production
release is supported yet.

| Version | Supported |
| ------- | --------- |
| main    | Best-effort review only |

## Reporting a Vulnerability

Please do not report security vulnerabilities in public issues.

Use GitHub's private vulnerability reporting feature if it is enabled for this
repository. If private reporting is not available, contact the repository owner
through the organization's preferred private channel.

Please include:

- A clear description of the vulnerability.
- Steps to reproduce.
- Affected files, commands, or workflows.
- Potential impact.
- Any suggested mitigation.

## Security Goals

The project should preserve Homebrew's trust model wherever possible:

- Verify downloads with strong checksums.
- Avoid automatic elevation.
- Avoid writing to shell profiles without explicit user consent.
- Keep shims quote-safe.
- Treat installer execution and native Windows package installation as
  high-risk areas.
