#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
PKG="Package.swift"

try_open_app() {
  local app="$1"
  [[ -d "$app" ]] || return 1
  open -a "$app" "$PKG"
  return 0
}

# 任意: export STILLMD_XCODE_APP="/Applications/Xcode-beta.app"
if [[ -n "${STILLMD_XCODE_APP:-}" ]]; then
  try_open_app "$STILLMD_XCODE_APP" && exit 0
fi

for candidate in \
  "/Applications/Xcode.app" \
  "/Applications/Xcode-beta.app"; do
  try_open_app "$candidate" && exit 0
done

# Spotlight で Xcode を探す（名前が違う配置でも拾える）
while IFS= read -r found; do
  try_open_app "$found" && exit 0
done < <(mdfind "kMDItemCFBundleIdentifier == 'com.apple.dt.Xcode'" 2>/dev/null | head -5)

# xcode-select が Xcode を指していれば xed が使える
if command -v xed >/dev/null 2>&1; then
  if xed "$PKG" 2>/dev/null; then
    exit 0
  fi
fi

echo "stillmd: Xcode が見つかりません。" >&2
echo "  • Mac App Store から「Xcode」をインストールする" >&2
echo "  • または Xcode-beta の場合: export STILLMD_XCODE_APP=\"/Applications/Xcode-beta.app\"" >&2
echo "  • インストール済みなら: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" >&2
exit 1
