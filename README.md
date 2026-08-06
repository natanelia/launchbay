# LaunchBay

A native macOS desktop client for [Apple's `container`](https://github.com/apple/container) runtime.

LaunchBay gives Apple silicon Macs a focused, visual workflow for OCI/Docker images without installing or managing a separate Linux VM appliance. It uses Apple's own `container` command-line interface as the stable process boundary and presents container lifecycle, images, logs, builds, and system state in SwiftUI.

> [!IMPORTANT]
> This project is an independent open-source client. It is not affiliated with Apple, Docker, or OrbStack. “Apple”, “Docker”, and “OrbStack” are trademarks of their respective owners.

## What works

- Start and stop the Apple container system.
- List running and stopped containers.
- Start, stop, and delete containers.
- Inspect image, command, ports, addresses, CPU, memory, and timestamps.
- Read workload and boot logs.
- Copy an interactive shell command for a running container.
- Pull OCI/Docker images, including an optional platform override.
- List and delete local images.
- Build an image from a Dockerfile or Containerfile.
- Run a container with ports, bind mounts, environment variables, CPU and memory limits, Rosetta, minimal init, read-only root filesystems, and automatic removal.
- Discover the `container` executable automatically or use a custom path.
- Record a local in-memory activity trail with exact commands, output, duration, and exit code. Environment values are redacted.
- Refresh automatically without blocking manual operations.

## Requirements

- Apple silicon Mac.
- macOS 26 or newer.
- Apple's [`container`](https://github.com/apple/container) CLI installed from an official signed release.
- The container system initialized with `container system start` at least once, or started from the app.

The app deliberately does not bundle Apple's runtime, request administrator access, or download privileged components.

## Build and run

```bash
git clone https://github.com/natanelia/launchbay.git
cd launchbay
swift test
swift run LaunchBay
```

Create a distributable, ad-hoc-signed Apple silicon application bundle:

```bash
./scripts/build-app.sh
open "dist/LaunchBay.app"
```

The script also creates `dist/LaunchBay.zip`.

## How it works

```text
SwiftUI views
    ↓
@MainActor AppModel
    ↓
ContainerCLI actor
    ↓
ProcessCommandExecutor (direct argv, no shell)
    ↓
/usr/local/bin/container
    ↓
Apple container services and per-container Linux VMs
```

The integration uses the CLI's machine-readable JSON output instead of linking Apple's internal Swift packages. That boundary is intentional: Apple currently warns that minor `container` releases may include breaking changes. The parser accepts additive fields and a small set of compatible key variants while still rejecting malformed or identity-less records.

See [Architecture](docs/ARCHITECTURE.md) for the design and [Security](SECURITY.md) for the trust model.

## Safety and privacy

- Commands are launched with `Process` and an argument array, never by interpolating a shell command.
- Environment variable values and registry passwords are redacted in displayed command history.
- Activity history is held in memory only and is cleared when the app exits.
- No analytics, telemetry, account, network proxy, or background updater is included.
- The app does not hold Docker credentials itself; registry authentication remains owned by Apple's CLI.
- Destructive actions require an explicit UI confirmation.

## Current scope

This is a useful desktop MVP, not an implementation of OrbStack's proprietary engine. It does not yet provide:

- Docker Engine API or `/var/run/docker.sock` compatibility.
- Docker Compose orchestration.
- Kubernetes.
- Live CPU, memory, disk, or network charts.
- A built-in terminal emulator.
- Automatic runtime installation or privileged networking setup.
- Signed/notarized release binaries.

Those are tracked as follow-on areas in [ROADMAP.md](ROADMAP.md). The architecture keeps these additions separable from the core CLI adapter.

## Development

```bash
./scripts/check.sh
```

The check script formats and lints Swift, runs all tests, builds a release binary, and syntax-checks the macOS sources. CI performs the same tests on a macOS runner and packages the `.app` bundle.

The core module is intentionally platform-neutral, so command construction and parsing can be tested on Linux as well as macOS. The native executable presents the SwiftUI application only on macOS.

## License

MIT. See [LICENSE](LICENSE).
