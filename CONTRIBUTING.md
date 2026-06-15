# Contributing to ooke

Thanks for your interest in contributing to ooke.

## Getting Started

1. Fork the repository.
2. Clone your fork and create a branch from `main`.
3. Make your changes and ensure `make` builds cleanly.
4. Run `make test` and confirm all tests pass.
5. Open a pull request with a clear description of your changes.

## Language Rule

ooke is written exclusively in toke. Do not add C, Python, JavaScript, or any other language to this repository. If a required capability is missing from the toke standard library, open an issue describing the gap.

## Branch Naming

```
feature/ooke-<component>-<description>
fix/ooke-<component>-<description>
```

## Commit Messages

Follow conventional commit format:

```
feat(ooke/template): implement layout inheritance
fix(ooke/store): handle frontmatter with CRLF line endings
```

## Code Style

- Follow the conventions already established in `src/`.
- Every module should have corresponding tests in `test/`.
- A change is not complete until its tests pass and `make test` is green.

## Reporting Bugs

Open an issue with:

- What you expected to happen.
- What actually happened.
- Steps to reproduce.
- Your platform and toke compiler version.

## Licence

By contributing, you agree that your contributions will be licensed under the MIT licence.
