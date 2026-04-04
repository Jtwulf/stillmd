#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
VERSION="${1:-dev}"
APP_DIR="$PROJECT_DIR/build/stillmd.app"
DIST_DIR="$PROJECT_DIR/dist"
ARCHIVE_BASENAME="stillmd-${VERSION}-macos"
ZIP_PATH="$DIST_DIR/${ARCHIVE_BASENAME}.zip"
SHA_PATH="$DIST_DIR/${ARCHIVE_BASENAME}.sha256"

"$SCRIPT_DIR/build-app.sh" --release

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

if [[ ! -d "$APP_DIR" ]]; then
    echo "Expected app bundle not found at $APP_DIR" >&2
    exit 1
fi

(
    cd "$PROJECT_DIR/build"
    COPYFILE_DISABLE=1 zip -qryX "$ZIP_PATH" "stillmd.app"
)
(
    cd "$DIST_DIR"
    shasum -a 256 "$(basename "$ZIP_PATH")"
) > "$SHA_PATH"

echo "Created release archive: $ZIP_PATH"
echo "Created checksum: $SHA_PATH"
