# Performance engineering

LaunchBay should make Apple's `container` runtime feel fast without claiming ownership of runtime internals it does not control. The application currently uses the public `container` CLI as its process boundary, so this document separates optimizations LaunchBay can ship today from work that requires a lower-level API or upstream runtime support.

## Shipped foundation

### Fewer CLI process launches

Read-only CLI calls use two complementary mechanisms:

- **In-flight coalescing:** concurrent identical reads share one CLI process.
- **Short-lived result caching:** system status, container listings, and image listings use separate time-to-live values based on how quickly each resource normally changes.

Mutating commands invalidate the affected cache after every execution attempt, including nonzero exits and thrown timeout or launch errors. This is deliberate: a failed local CLI result does not prove that the runtime performed no side effect. A manual refresh cancels in-flight reads and clears every completed read cache before querying, so users can always force an authoritative view.

With the default five-second refresh setting, the previous loop launched status, container-list, and image-list processes every cycle: up to 36 CLI processes per minute while the system was running. The cache and cadence configuration produces the following **modeled steady-state process-launch ceilings**:

- 18 CLI processes per minute while one or more containers are active.
- 10 CLI processes per minute while the runtime is running but idle.
- 2 CLI processes per minute while the runtime is stopped.
- No scheduled polling while LaunchBay is inactive.

These are deterministic scheduling calculations, not measured CPU, energy, latency, or UI-throughput results. The focused tests encode the arithmetic so that cache or cadence changes cannot silently invalidate the documented model. Actual launch counts can be lower because each cycle waits for the preceding refresh, or higher because of manual refreshes and user-triggered mutations.

### Adaptive refresh and application lifecycle

The selected interval remains the foreground cadence while one or more containers are running. LaunchBay backs off to:

- 15 seconds while the container system is running but no containers are active.
- 30 seconds while the system is stopped or unavailable.
- No scheduled polling while the application is inactive.

The scheduler uses a cancellable one-shot timer rather than a fixed perpetual loop. A runtime-state or running-container-count change cancels the obsolete sleep and immediately schedules the next cycle with the new cadence. Moving to an inactive scene cancels the timer, cancels in-flight read requests, and terminates their CLI child processes. Returning to the application performs a forced refresh before normal polling resumes.

A user-started runtime mutation is not killed merely because the window becomes inactive; only background read work is cancelled. Once a mutation completes or fails, its affected cache has already been invalidated, and LaunchBay performs a silent reconciliation when the application is active.

### Warm-container execution

`ContainerCLI.execContainer(id:command:timeoutSeconds:)` exposes Apple's `container exec` path through the typed core adapter. Future project runners and development sessions can reuse a running container VM for repeated commands instead of creating and booting a fresh VM for each operation.

This is a foundation, not a general VM pool. LaunchBay does not keep hidden containers alive or alter Apple's lifecycle semantics in this change. An `exec` attempt invalidates the container list because an arbitrary command can terminate PID 1 or otherwise change container state.

## Current evidence and non-claims

This change demonstrates fewer modeled CLI process launches and stronger lifecycle correctness. It does **not** yet demonstrate that a representative development workload builds, starts, or responds faster. In particular:

- No CPU, memory, energy, or wall-clock improvement is claimed.
- The typed `exec` adapter alone is not evidence of a faster development session.
- Small-file, filesystem-event, networking, and shared-VM ideas below remain unimplemented workstreams.

Any future user-facing speedup claim must be supported by the measurement protocol below.

## Measurement protocol

Performance work must include a reproducible baseline and comparison. Record at least:

- Mac model, chip, memory, macOS version, and power mode.
- Apple `container` version and kernel configuration.
- Image reference and immutable digest.
- Cold and warm runs separately.
- Median, p95, minimum, maximum, and sample count.
- Host CPU, memory, and disk pressure during the run.
- Whether data is on a macOS bind mount, a VM-local filesystem, or an image layer.

A result is not comparable when any of those dimensions materially differs. UI responsiveness and CLI process count should be measured separately from guest workload throughput.

## Workstreams

### 1. Small-file performance

Frontend dependency trees and build caches stress metadata operations far more than sequential bandwidth. The next implementation should compare at least these storage modes:

1. Source on a macOS bind mount, dependencies on the bind mount.
2. Source on a macOS bind mount, dependencies and build cache on VM-local storage.
3. Managed source synchronization into VM-local storage.

Measure recursive stat/traversal, package installation, TypeScript compilation, incremental bundling, and deletion of a large dependency tree. LaunchBay can recommend or automate VM-local locations for generated data, but transparent host-file caching or synchronization needs explicit consistency rules and likely lower-level runtime integration.

Correctness requirements:

- Host edits must not be lost or reordered.
- Container writes must have a documented conflict policy.
- Cache invalidation must survive sleep, process crashes, and clock changes.
- Exclusion rules must be inspectable and stored in user-owned project configuration.

### 2. Filesystem-event propagation

Polling file contents faster is not equivalent to forwarding filesystem events. A development-grade implementation should measure host-to-guest and guest-to-host event latency while checking for dropped, duplicated, reordered, and coalesced events.

The target design is an explicit event bridge, such as macOS FSEvents on the host mapped to the guest's native notification mechanism. Before implementation, confirm which public Apple APIs can associate events with a mounted container path. LaunchBay must fall back safely when the bridge is unavailable rather than silently presenting stale state.

Acceptance testing should include:

- At least 10,000 create, modify, rename, and delete operations.
- Atomic-save patterns used by editors.
- Deep directory trees and rapid rename storms.
- Sleep and wake while a watcher is active.
- Vite, webpack, TypeScript, and common test watchers.

### 3. Warm microVM reuse

The first safe reuse primitive is command execution inside an explicitly running container. A future development-session layer can build on it with:

- Named, user-visible session containers.
- Readiness checks before commands are accepted.
- Idle expiration and explicit pinning.
- Image/configuration fingerprints that prevent reuse after incompatible changes.
- Bounded concurrency and per-session resource limits.
- Clear reset and rebuild controls.

Measure fresh `run`, stopped-container `start`, and running-container `exec` separately. Never hide a stale environment behind a faster startup number.

### 4. Container-to-container networking

Benchmark DNS lookup, connection establishment, request latency, throughput, and CPU cost across containers on the same project network. Compare small RPC messages and bulk transfer because they expose different bottlenecks.

Optimization candidates must be selected from measured traces. Possible areas include avoiding redundant host forwarding for guest-to-guest traffic, reusing project networks, reducing proxy copies, and keeping DNS state warm. LaunchBay should not bypass isolation or invent an undocumented networking path merely to improve a synthetic throughput score.

### 5. Trusted service grouping

Grouping multiple trusted services into one VM could amortize kernel and network overhead, but it changes the security boundary from per-container isolation to per-group isolation. It therefore requires a separate architecture decision record before implementation.

The proposal must define:

- An explicit, opt-in trust group in project configuration.
- Which resources are shared: kernel, network namespace, filesystem, process namespace, and caches.
- How secrets and bind mounts remain scoped.
- How one compromised service can affect its peers.
- Upgrade, crash-recovery, and teardown behavior.
- A per-container VM fallback for untrusted workloads.

This likely requires public runtime capabilities below today's CLI surface. Until those capabilities exist and are testable, LaunchBay should preserve Apple's per-container VM model.

## Decision rule

Scheduling and correctness foundations may merge when their deterministic behavior is tested and their claims are explicitly limited to what those tests establish. A user-facing workload-performance change should merge only when it improves a representative workload, preserves correctness and security invariants, and includes enough measurement detail for another contributor to reproduce the result. Lower process count or prettier benchmark output alone is not sufficient evidence of a workload speedup.
