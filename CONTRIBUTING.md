# Contributing

Thanks for improving LaunchBay.

## Before opening a change

- Keep the app a thin client over Apple's public CLI surface.
- Do not add a shell-command execution path.
- Do not persist secrets in `UserDefaults`, logs, fixtures, or screenshots.
- Prefer capability checks and tolerant parsing over version-string branching.
- Keep third-party dependencies out unless they remove substantial, demonstrated risk or complexity.

## Local checks

```bash
./scripts/check.sh
```

For UI work, also run the application on an Apple silicon Mac with macOS 26 or newer and an official `container` release installed.

## Pull requests

A pull request should include:

- The user problem and the chosen behavior.
- Tests for command construction, validation, parsing, or regressions where applicable.
- Manual verification notes for UI changes.
- Security implications, especially for host paths, environment variables, process execution, registry authentication, or CI.

Keep commits focused and avoid drive-by formatting outside the changed area.

## Upstream compatibility

When adapting to an Apple `container` change, include the upstream release or source reference in the pull request and add a representative fixture test. Avoid depending on an internal upstream Swift package when the CLI can provide a stable process boundary.
