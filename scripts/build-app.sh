#!/bin/bash
set -euo pipefail

# Build stillmd.app bundle from Swift Package Manager project
# Usage: ./scripts/build-app.sh [--release]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_NAME="stillmd"
BUNDLE_ID="com.jtwulf.stillmd"
ICON_SOURCE="$PROJECT_DIR/assets/app-icon/stillmd-icon.png"
ICON_NAME="AppIcon"

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
    BINARY_PATH=".build/release/MarkdownPreviewer"
else
    swift build
    BINARY_PATH=".build/debug/MarkdownPreviewer"
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

# Copy Info.plist and add bundle metadata
cat > "$CONTENTS_DIR/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>stillmd</string>
    <key>CFBundleIconFile</key>
    <string>$ICON_NAME</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.5</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>UTImportedTypeDeclarations</key>
    <array>
        <dict>
            <key>UTTypeIdentifier</key>
            <string>net.daringfireball.markdown</string>
            <key>UTTypeDescription</key>
            <string>Markdown Document</string>
            <key>UTTypeConformsTo</key>
            <array>
                <string>public.plain-text</string>
            </array>
            <key>UTTypeTagSpecification</key>
            <dict>
                <key>public.filename-extension</key>
                <array>
                    <string>md</string>
                    <string>markdown</string>
                </array>
            </dict>
        </dict>
    </array>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>Markdown Document</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSHandlerRank</key>
            <string>Default</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>net.daringfireball.markdown</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
PLIST

# Copy SPM resource bundle (contains marked.js, highlight.js, preview.css)
RESOURCE_BUNDLE=$(find .build -name "MarkdownPreviewer_MarkdownPreviewer.bundle" -type d 2>/dev/null | head -1)
if [[ -n "$RESOURCE_BUNDLE" ]]; then
    cp -R "$RESOURCE_BUNDLE" "$RESOURCES_DIR/"
    echo "  Copied resource bundle: $(basename "$RESOURCE_BUNDLE")"
else
    echo "  WARNING: Resource bundle not found. Resources may not load at runtime."
fi

echo ""
echo "=== Build complete ==="
echo "  App: $APP_DIR"
echo ""
echo "To install:"
echo "  cp -R \"$APP_DIR\" /Applications/"
echo ""
echo "To run:"
echo "  open \"$APP_DIR\""
