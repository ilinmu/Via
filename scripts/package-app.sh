#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="AutoWifi"
CONFIGURATION="${CONFIGURATION:-release}"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist}"
APP_DIR="$DIST_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
INFO_PLIST_TEMPLATE="$ROOT_DIR/AutoWifi/Info.plist"
ENTITLEMENTS_PATH="$ROOT_DIR/AutoWifi/AutoWifi.entitlements"
ICON_SOURCE="$ROOT_DIR/AutoWifi/Assets.xcassets/AppIcon.appiconset/icon_1024x1024.png"
BUNDLE_ID="${BUNDLE_ID:-com.linmu.AutoWifi}"
VERSION="${VERSION:-1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
MIN_SYSTEM_VERSION="${MIN_SYSTEM_VERSION:-13.0}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
ZIP_NAME="${ZIP_NAME:-$APP_NAME-macos.zip}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/autowifi-package.XXXXXX")"

cleanup() {
  rm -rf "$TMP_DIR"
}

show_help() {
  cat <<'EOF'
Usage:
  scripts/package-app.sh

Environment variables:
  CONFIGURATION     Build configuration, default: release
  DIST_DIR          Output directory, default: <repo>/dist
  BUNDLE_ID         App bundle identifier, default: com.linmu.AutoWifi
  VERSION           CFBundleShortVersionString, default: 1.0
  BUILD_NUMBER      CFBundleVersion, default: 1
  MIN_SYSTEM_VERSION Minimum macOS version, default: 13.0
  SIGN_IDENTITY     Code signing identity. Default is "-" for ad-hoc signing.
                    Set to an empty string to skip signing.
  ZIP_NAME          Zip archive name, default: AutoWifi-macos.zip

Examples:
  scripts/package-app.sh
  SIGN_IDENTITY="" scripts/package-app.sh
  SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" scripts/package-app.sh
EOF
}

set_plist_string() {
  local plist_path="$1"
  local key="$2"
  local value="$3"

  /usr/libexec/PlistBuddy -c "Set :$key $value" "$plist_path" >/dev/null 2>&1 || \
    /usr/libexec/PlistBuddy -c "Add :$key string $value" "$plist_path" >/dev/null
}

create_icon() {
  local size="$1"
  local output_name="$2"

  sips -s format png -z "$size" "$size" "$ICON_SOURCE" --out "$ICONSET_DIR/$output_name" >/dev/null
}

trap cleanup EXIT

if [[ "${1:-}" == "--help" ]]; then
  show_help
  exit 0
fi

echo "==> Building $APP_NAME ($CONFIGURATION)"
(
  cd "$ROOT_DIR"
  swift build -c "$CONFIGURATION"
)

EXECUTABLE_PATH="$(find "$ROOT_DIR/.build" -path "*/$CONFIGURATION/$APP_NAME" -type f | head -n 1)"
if [[ -z "$EXECUTABLE_PATH" ]]; then
  echo "Could not find built executable for $APP_NAME." >&2
  exit 1
fi

echo "==> Preparing app bundle at $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$EXECUTABLE_PATH" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

INFO_PLIST_PATH="$CONTENTS_DIR/Info.plist"
cp "$INFO_PLIST_TEMPLATE" "$INFO_PLIST_PATH"
set_plist_string "$INFO_PLIST_PATH" "CFBundleExecutable" "$APP_NAME"
set_plist_string "$INFO_PLIST_PATH" "CFBundleName" "$APP_NAME"
set_plist_string "$INFO_PLIST_PATH" "CFBundleIdentifier" "$BUNDLE_ID"
set_plist_string "$INFO_PLIST_PATH" "CFBundleShortVersionString" "$VERSION"
set_plist_string "$INFO_PLIST_PATH" "CFBundleVersion" "$BUILD_NUMBER"
set_plist_string "$INFO_PLIST_PATH" "LSMinimumSystemVersion" "$MIN_SYSTEM_VERSION"
set_plist_string "$INFO_PLIST_PATH" "CFBundleIconFile" "AppIcon"
/usr/libexec/PlistBuddy -c "Delete :NSMainStoryboardFile" "$INFO_PLIST_PATH" >/dev/null 2>&1 || true

if [[ -f "$ICON_SOURCE" ]]; then
  echo "==> Building app icon"
  ICONSET_DIR="$TMP_DIR/AppIcon.iconset"
  mkdir -p "$ICONSET_DIR"
  create_icon 16 "icon_16x16.png"
  create_icon 32 "icon_16x16@2x.png"
  create_icon 32 "icon_32x32.png"
  create_icon 64 "icon_32x32@2x.png"
  create_icon 128 "icon_128x128.png"
  create_icon 256 "icon_128x128@2x.png"
  create_icon 256 "icon_256x256.png"
  create_icon 512 "icon_256x256@2x.png"
  create_icon 512 "icon_512x512.png"
  create_icon 1024 "icon_512x512@2x.png"
  iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/AppIcon.icns"
fi

if [[ -n "$SIGN_IDENTITY" ]]; then
  echo "==> Signing app bundle ($SIGN_IDENTITY)"
  codesign --force --deep --sign "$SIGN_IDENTITY" \
    --entitlements "$ENTITLEMENTS_PATH" \
    "$APP_DIR"
else
  echo "==> Skipping code signing"
fi

ARCHIVE_PATH="$DIST_DIR/$ZIP_NAME"
echo "==> Creating zip archive at $ARCHIVE_PATH"
rm -f "$ARCHIVE_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ARCHIVE_PATH"

echo
echo "Done."
echo "App bundle: $APP_DIR"
echo "Archive:    $ARCHIVE_PATH"
