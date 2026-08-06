# Changelog

All notable changes will be documented here.

## [Unreleased]

### Added

- Native SwiftUI dashboard for Apple's `container` runtime.
- Container list, lifecycle, logs, deletion, and shell-command copying.
- Image list, pull, build, and deletion workflows.
- Configurable container run form for ports, volumes, environment, resources, Rosetta, init, and filesystem isolation.
- Automatic CLI discovery and system lifecycle controls.
- Redacted in-memory command activity trail.
- Forward-tolerant JSON parsing and core tests.
- Reproducible app packaging, CI, security policy, and contribution guidance.
- Warm command execution in an existing running container through the typed core adapter.
- A performance-engineering plan covering small files, filesystem events, VM reuse, networking, and trusted service grouping.

### Changed

- Coalesce concurrent read requests and cache low-volatility CLI results with mutation-aware invalidation.
- Adapt automatic refresh cadence to active, idle, stopped, and background application states.
