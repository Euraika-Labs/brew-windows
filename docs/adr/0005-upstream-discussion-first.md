# ADR 0005: Upstream Discussion Before Homebrew Pull Requests

Date: 2026-05-22

## Status

Accepted

## Context

Brew Windows has a working native Windows prototype and a public release path,
but Homebrew upstream currently documents macOS, Linux, and WSL 2 rather than
native Windows. The prior native Windows support issue in `Homebrew/brew` was
closed, and the core concern was the scale of Unix and Bash assumptions in the
codebase.

A large pull request that attempts to add native Windows support would likely
consume maintainer time without first answering whether native Windows belongs
in Homebrew's support model at all.

## Decision

Before opening any pull request against `Homebrew/brew`, this project will open
a maintainer discussion with:

- a working native Windows prototype;
- release and CI evidence;
- a clear non-WSL scope;
- known compatibility gaps;
- a small proposed pull request sequence;
- explicit non-goals and stop conditions.

Any future upstream pull request must preserve current macOS/Linux behavior and
must be limited to abstractions, tests, or documentation unless Homebrew
maintainers explicitly invite Windows-specific runtime code.

## Consequences

- The project will not open a large "Windows support" pull request.
- The first upstream ask is guidance, not acceptance.
- Windows bottle tags, formula migration, PE/COFF inspection, and installer
  changes remain deferred.
- If maintainers say native Windows is out of scope, Brew Windows can continue
  as a separate compatibility-oriented project, but upstream integration stops
  being the next milestone.
