# Architecture

## Goals

LaunchBay is a thin, auditable desktop control plane for Apple's `container` runtime. Its primary goals are:

1. Preserve Apple's runtime and isolation model instead of reimplementing a daemon or VM manager.
2. Expose common container workflows through a native macOS interface.
3. Keep all command execution observable, testable, and resistant to shell injection.
4. Tolerate additive changes in Apple's machine-readable output.
5. Avoid importing unstable implementation packages from the upstream repository.

## Modules

### `LaunchBayCore`

A platform-neutral Swift library containing:

- Domain models for containers, images, system status, run configuration, and build configuration.
- `ContainerCLI`, an actor that serializes executable configuration and maps app operations to CLI commands.
- `ProcessCommandExecutor`, which launches direct executable/argument vectors and captures output through private temporary files.
- `ContainerJSONParser`, a tolerant parser for the CLI's JSON list and status output.
- Validation and executable discovery.

The library has no third-party package dependencies.

### `LaunchBay`

A macOS SwiftUI executable containing:

- A navigation-based dashboard.
- Container and image master-detail screens.
- Run, pull, and build sheets.
- System status, settings, logs, and activity output.
- `AppModel`, a `@MainActor` state coordinator around the `ContainerCLI` actor.

On non-macOS hosts the target compiles to a small explanatory command-line stub. This lets the whole Swift package build during cross-platform core verification while keeping AppKit and SwiftUI isolated behind `#if os(macOS)`.

## Command boundary

All operations are represented by `CommandInvocation`:

- Absolute executable URL.
- Separate argument array.
- Optional current directory.
- Explicit timeout.

No operation goes through `/bin/sh -c`. This avoids shell metacharacter interpretation, quoting ambiguity, and accidental command composition. The display form is generated only for inspection/copying and redacts known secret-bearing options.

Long-running commands use larger explicit timeouts:

- System lifecycle: 180 seconds.
- Image pull and container run: 1,800 seconds.
- Image build: 3,600 seconds.

## JSON compatibility strategy

Apple's current list commands expose `--format json`. LaunchBay parses only fields needed by the UI and ignores unknown fields.

Required invariants are intentionally narrow:

- A container must have an identity.
- An image must have an identity or digest.
- Top-level list output must remain an array.
- System status output must remain an object.

Compatibility aliases are accepted for a few historically common spellings, such as `hostIP`/`hostIp`, `guestPort`, and `args`. A malformed payload is surfaced as an error rather than silently inventing a resource.

## Concurrency model

- UI state is isolated to `@MainActor`.
- `ContainerCLI` is an actor.
- The process executor performs blocking process and file operations in a detached task.
- Container and image refreshes are requested concurrently after the system is confirmed running.
- Mutating operations are serialized in the UI through `activeOperation`.
- Automatic refresh is suspended while a mutation is active.

## Runtime ownership

The application does not own Apple's launchd services, VM data, registry authentication, networks, or root filesystem storage. It asks the CLI to perform operations and reports the CLI's stdout, stderr, and exit code.

This means command-line and GUI workflows remain interoperable: a resource created in either surface appears in the other on refresh.

## Packaging

The repository uses Swift Package Manager rather than an Xcode project. `scripts/build-app.sh`:

1. Builds an arm64 release executable.
2. Creates a standard `.app` layout.
3. Copies `Info.plist`.
4. Produces an `.icns` icon from the checked-in 1024-pixel source image when macOS icon tools are available.
5. Applies ad-hoc code signing.
6. Creates a ZIP archive with resource forks preserved.

A production release should replace ad-hoc signing with Developer ID Application signing and Apple notarization.
