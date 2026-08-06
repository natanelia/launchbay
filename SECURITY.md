# Security Policy

## Supported versions

Security fixes are applied to the latest commit on `main`. Until the project publishes signed releases, source builds are the supported distribution method.

## Reporting a vulnerability

Please do not open a public issue for a vulnerability that could expose credentials, execute unintended commands, cross a container boundary, or compromise the build/release pipeline.

Report it privately through GitHub's **Security → Report a vulnerability** flow for this repository. Include:

- The affected commit or version.
- Reproduction steps.
- Expected and observed behavior.
- Whether secrets, host files, containers, or the build pipeline are exposed.
- A suggested mitigation, when available.

You should receive an acknowledgment within seven days. No bounty is promised.

## Trust model

LaunchBay is an unsandboxed developer tool because it must launch an external executable and allow user-selected host paths to be bind-mounted. It inherits the privileges of the signed-in macOS user. It does not request root privileges itself.

The application trusts:

- The `container` executable selected or discovered on the host.
- Apple's container services and VM/runtime implementation.
- Image registries and image content chosen by the user.
- Host paths explicitly selected for bind mounts.

The application does **not** treat container images as trusted host code. Apple's runtime isolation remains the security boundary.

## Defensive design

- CLI commands use direct argv execution, not shell interpolation.
- Known secret-bearing arguments are redacted before display or activity recording.
- Command output is displayed as text and is not interpreted as markup or commands.
- No third-party runtime dependencies are linked into the application.
- GitHub Actions are pinned to immutable commit SHAs and receive read-only repository permissions.
- CI never runs container images supplied by pull requests.
- The repository does not include install-time scripts that request elevation.

## Release verification

The current build script performs ad-hoc signing for local use. Ad-hoc signing proves bundle integrity only after creation; it does not establish publisher identity. A future public binary release must use Developer ID signing, notarization, checksums, and provenance before it is described as trusted for general distribution.
