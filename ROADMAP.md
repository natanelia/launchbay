# Roadmap

The order below favors reliable daily workflows over feature-count parity with mature commercial products.

## Near term

- Stream logs instead of fetching a fixed tail.
- Add container inspect JSON with environment, mounts, networks, and process details.
- Add volume and network management screens.
- Add image prune and system disk-usage views.
- Add registry sign-in/sign-out surfaces without persisting credentials in the app.
- Add configurable default CPU, memory, platform, and host bind address.
- Add native notifications for completed pulls and builds.
- Add signed and notarized release automation.

## Developer workflows

- Compose-compatible project runner backed by explicit `container` operations.
- Project presets stored in user-owned files.
- Build progress parsing and structured build logs.
- Container exec panel and terminal integration.
- Open exposed HTTP ports directly from the container detail view.
- Import/export image archives.

## Observability

- Periodic CPU and memory statistics.
- Disk and image-layer usage.
- Network throughput and published-port health.
- Retained local activity history with opt-in persistence and bounded storage.

## Compatibility

- Capability detection by CLI version instead of assuming every command flag exists.
- Fixture tests against multiple supported Apple `container` releases.
- Migration guidance when upstream JSON or commands change.

## Explicit non-goals for now

- Reimplementing Apple's virtualization runtime.
- Shipping a privileged kernel or network extension.
- Pretending to be a Docker Engine socket before compatibility is complete and testable.
- Storing registry passwords or cloud credentials in application preferences.
