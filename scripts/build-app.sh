#!/bin/bash
set -euo pipefail

# Build stillmd.app bundle from Swift Package Manager project
# Usage: ./scripts/build-app.sh [--release]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_NAME="stillmd"
EXECUTABLE_NAME="stillmd"
ICON_SOURCE="$PROJECT_DIR/assets/app-icon/stillmd-icon.png"
ICON_NAME="AppIcon"
INFO_PLIST_SOURCE="$PROJECT_DIR/stillmd/Info.plist"

# Parse args
BUILD_CONFIG="debug"
if [[ "${1:-}" == "--release" ]]; then
    BUILD_CONFIG="release"
fi

echo "=== Building $APP_NAME.app ($BUILD_CONFIG) ==="

# Build the executable
cd "$PROJECT_DIR"
if [[ "$BUILD_CONFIG" == "release" ]]; then
    swift build -c release
    BINARY_PATH=".build/release/$EXECUTABLE_NAME"
else
    swift build
    BINARY_PATH=".build/debug/$EXECUTABLE_NAME"
fi

# Create .app bundle structure
APP_DIR="$PROJECT_DIR/build/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Copy executable
cp "$BINARY_PATH" "$MACOS_DIR/$APP_NAME"

# Build app icon from the source PNG when available
if [[ -f "$ICON_SOURCE" ]]; then
    ICONSET_DIR="$PROJECT_DIR/build/${ICON_NAME}.iconset"
    ICON_ICNS_PATH="$PROJECT_DIR/build/${ICON_NAME}.icns"

    rm -rf "$ICONSET_DIR" "$ICON_ICNS_PATH"
    mkdir -p "$ICONSET_DIR"

    sips -z 16 16     "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
    sips -z 32 32     "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
    sips -z 32 32     "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
    sips -z 64 64     "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
    sips -z 128 128   "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
    sips -z 256 256   "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
    sips -z 256 256   "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
    sips -z 512 512   "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
    sips -z 512 512   "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
    cp "$ICON_SOURCE" "$ICONSET_DIR/icon_512x512@2x.png"

    iconutil -c icns "$ICONSET_DIR" -o "$ICON_ICNS_PATH"
    cp "$ICON_ICNS_PATH" "$RESOURCES_DIR/${ICON_NAME}.icns"
    echo "  Built app icon: ${ICON_NAME}.icns"
else
    echo "  WARNING: Icon source not found at $ICON_SOURCE"
fi

if [[ -f "$INFO_PLIST_SOURCE" ]]; then
    cp "$INFO_PLIST_SOURCE" "$CONTENTS_DIR/Info.plist"
else
    echo "  ERROR: Info.plist source not found at $INFO_PLIST_SOURCE" >&2
    exit 1
fi

# Copy SPM resource bundle (contains marked.js, highlight.js, preview.css)
RESOURCE_BUNDLE="$(
    find .build -name "*.bundle" -type d 2>/dev/null | while read -r bundle; do
        if [[ -n "$(find "$bundle" -name "preview.css" -type f -print -quit 2>/dev/null)" ]]; then
            echo "$bundle"
            break
        fi
    done
)"
if [[ -n "$RESOURCE_BUNDLE" ]]; then
    cp -R "$RESOURCE_BUNDLE" "$RESOURCES_DIR/"
    echo "  Copied resource bundle: $(basename "$RESOURCE_BUNDLE")"
else
    echo "  WARNING: Resource bundle not found. Resources may not load at runtime."
fi

# Sign the assembled bundle ad hoc so macOS can assess the bundle structure
# correctly even when the app is distributed without Developer ID signing.
codesign --force --deep --sign - "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR" >/dev/null
echo "  Ad hoc signed app bundle"

echo ""
echo "=== Build complete ==="
echo "  App: $APP_DIR"
echo ""
echo "To install:"
echo "  cp -R \"$APP_DIR\" /Applications/"
echo ""
echo "To run:"
echo "  open \"$APP_DIR\""
