#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "==> Formatting Swift"
swift-format format --in-place --recursive Package.swift Sources Tests

echo "==> Linting Swift"
swift-format lint --strict --recursive Package.swift Sources Tests

echo "==> Running tests"
swift test

echo "==> Building release configuration"
swift build --configuration release

echo "==> Parsing macOS-only sources"
swiftc -frontend -parse \
    -target arm64-apple-macosx26.0 \
    Sources/LaunchBayCore/*.swift \
    Sources/LaunchBay/*.swift \
    -module-name LaunchBaySyntaxCheck

echo "All checks passed."
