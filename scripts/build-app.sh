#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "build-app.sh requires macOS because it creates and signs a macOS application bundle." >&2
    exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="LaunchBay"
EXECUTABLE_NAME="LaunchBay"
CONFIGURATION="${CONFIGURATION:-release}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/dist}"
APP_DIR="$OUTPUT_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ARCH="${ARCH:-arm64}"

cd "$ROOT_DIR"
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$OUTPUT_DIR"

echo "==> Building $EXECUTABLE_NAME ($CONFIGURATION, $ARCH)"
swift build --configuration "$CONFIGURATION" --arch "$ARCH"
BIN_DIR="$(swift build --configuration "$CONFIGURATION" --arch "$ARCH" --show-bin-path)"
cp "$BIN_DIR/$EXECUTABLE_NAME" "$MACOS_DIR/$EXECUTABLE_NAME"
chmod 755 "$MACOS_DIR/$EXECUTABLE_NAME"
cp "$ROOT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"

if command -v sips >/dev/null 2>&1 && command -v iconutil >/dev/null 2>&1; then
    echo "==> Creating application icon"
    ICON_WORK_DIR="$(mktemp -d)"
    trap 'rm -rf "$ICON_WORK_DIR"' EXIT
    ICONSET="$ICON_WORK_DIR/AppIcon.iconset"
    mkdir -p "$ICONSET"
    SOURCE_ICON="$ROOT_DIR/Resources/AppIcon-1024.png"

    sips -z 16 16 "$SOURCE_ICON" --out "$ICONSET/icon_16x16.png" >/dev/null
    sips -z 32 32 "$SOURCE_ICON" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
    sips -z 32 32 "$SOURCE_ICON" --out "$ICONSET/icon_32x32.png" >/dev/null
    sips -z 64 64 "$SOURCE_ICON" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
    sips -z 128 128 "$SOURCE_ICON" --out "$ICONSET/icon_128x128.png" >/dev/null
    sips -z 256 256 "$SOURCE_ICON" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
    sips -z 256 256 "$SOURCE_ICON" --out "$ICONSET/icon_256x256.png" >/dev/null
    sips -z 512 512 "$SOURCE_ICON" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
    sips -z 512 512 "$SOURCE_ICON" --out "$ICONSET/icon_512x512.png" >/dev/null
    cp "$SOURCE_ICON" "$ICONSET/icon_512x512@2x.png"
    iconutil --convert icns "$ICONSET" --output "$RESOURCES_DIR/AppIcon.icns"
fi

if command -v codesign >/dev/null 2>&1; then
    echo "==> Applying ad-hoc signature"
    codesign --force --deep --sign - --timestamp=none "$APP_DIR"
    codesign --verify --deep --strict "$APP_DIR"
fi

ARCHIVE_PATH="$OUTPUT_DIR/LaunchBay.zip"
rm -f "$ARCHIVE_PATH"
if command -v ditto >/dev/null 2>&1; then
    ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ARCHIVE_PATH"
else
    (cd "$OUTPUT_DIR" && zip -qry "$(basename "$ARCHIVE_PATH")" "$(basename "$APP_DIR")")
fi

printf '\nBuilt:\n  %s\n  %s\n' "$APP_DIR" "$ARCHIVE_PATH"
