#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Via"
EXECUTABLE_NAME="Via"
DISPLAY_NAME="${DISPLAY_NAME:-Via}"
CONFIGURATION="${CONFIGURATION:-release}"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist}"
APP_DIR="$DIST_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"
CORE_DYLIB="$ROOT_DIR/core/target/$CONFIGURATION/libvia_core.dylib"
INFO_PLIST_TEMPLATE="$ROOT_DIR/Via/Info.plist"
ENTITLEMENTS_PATH="$ROOT_DIR/Via/Via.entitlements"
PRIVACY_MANIFEST="$ROOT_DIR/Via/PrivacyInfo.xcprivacy"
ICON_SOURCE="$ROOT_DIR/Via/Assets.xcassets/AppIcon.appiconset/icon_1024x1024.png"
BUNDLE_ID="${BUNDLE_ID:-io.github.ilinmu.via}"
VERSION="${VERSION:-1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
MIN_SYSTEM_VERSION="${MIN_SYSTEM_VERSION:-13.0}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
ZIP_NAME="${ZIP_NAME:-$APP_NAME-macos.zip}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/via-package.XXXXXX")"

cleanup() {
  rm -rf "$TMP_DIR"
}

# Command Line Tools can ship a SDK whose SwiftUI declares @State as a macro
# while omitting the SwiftUIMacros plugin (that plugin ships with Xcode). In
# that setup, fall back to the newest installed SDK that still uses the
# property-wrapper implementation.
select_swift_sdk() {
  if [[ -n "${SDKROOT:-}" ]]; then
    return
  fi

  local swift_bin plugins_dir
  swift_bin="$(xcrun --find swift 2>/dev/null || true)"
  [[ -n "$swift_bin" ]] || return
  plugins_dir="$(cd "$(dirname "$swift_bin")/../lib/swift/host/plugins" 2>/dev/null && pwd || true)"
  if [[ -n "$plugins_dir" && -e "$plugins_dir/libSwiftUIMacros.dylib" ]]; then
    return
  fi

  local sdk interface
  while IFS= read -r sdk; do
    interface="$sdk/System/Library/Frameworks/SwiftUICore.framework/Modules/SwiftUICore.swiftmodule/arm64e-apple-macos.swiftinterface"
    if [[ -f "$interface" ]] && ! grep -q 'macro State' "$interface"; then
      export SDKROOT="$sdk"
      echo "==> SwiftUIMacros is unavailable; building with SDK at $sdk"
      return
    fi
  done < <(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX*.sdk 2>/dev/null | sort -r)
}

show_help() {
  cat <<'EOF'
Usage:
  scripts/package-app.sh

Environment variables:
  CONFIGURATION     Build configuration, default: release
  DIST_DIR          Output directory, default: <repo>/dist
  BUNDLE_ID         App bundle identifier, default: io.github.ilinmu.via
  DISPLAY_NAME      App display name, default: Via
  VERSION           CFBundleShortVersionString, default: 1.0
  BUILD_NUMBER      CFBundleVersion, default: 1
  MIN_SYSTEM_VERSION Minimum macOS version, default: 13.0
  SIGN_IDENTITY     Code signing identity. Default is "-" for ad-hoc signing.
                    Set to an empty string to skip signing.
  ZIP_NAME          Zip archive name, default: Via-macos.zip

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

echo "==> Building the shared policy core ($CONFIGURATION)"
"$ROOT_DIR/scripts/build-core.sh" "$CONFIGURATION"

select_swift_sdk

echo "==> Building $APP_NAME ($CONFIGURATION)"
(
  cd "$ROOT_DIR"
  swift build -c "$CONFIGURATION"
)

BIN_PATH="$(cd "$ROOT_DIR" && swift build -c "$CONFIGURATION" --show-bin-path)"
EXECUTABLE_PATH="$BIN_PATH/$EXECUTABLE_NAME"
if [[ ! -f "$EXECUTABLE_PATH" ]]; then
  echo "Could not find built executable for $EXECUTABLE_NAME at $EXECUTABLE_PATH." >&2
  exit 1
fi

echo "==> Preparing app bundle at $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$FRAMEWORKS_DIR"
cp "$EXECUTABLE_PATH" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

if [[ ! -f "$CORE_DYLIB" ]]; then
  echo "Could not find the policy core at $CORE_DYLIB." >&2
  exit 1
fi
cp "$CORE_DYLIB" "$FRAMEWORKS_DIR/libvia_core.dylib"

INFO_PLIST_PATH="$CONTENTS_DIR/Info.plist"
cp "$INFO_PLIST_TEMPLATE" "$INFO_PLIST_PATH"
set_plist_string "$INFO_PLIST_PATH" "CFBundleExecutable" "$APP_NAME"
set_plist_string "$INFO_PLIST_PATH" "CFBundleName" "$DISPLAY_NAME"
set_plist_string "$INFO_PLIST_PATH" "CFBundleDisplayName" "$DISPLAY_NAME"
set_plist_string "$INFO_PLIST_PATH" "CFBundleIdentifier" "$BUNDLE_ID"
set_plist_string "$INFO_PLIST_PATH" "CFBundleShortVersionString" "$VERSION"
set_plist_string "$INFO_PLIST_PATH" "CFBundleVersion" "$BUILD_NUMBER"
set_plist_string "$INFO_PLIST_PATH" "LSMinimumSystemVersion" "$MIN_SYSTEM_VERSION"
set_plist_string "$INFO_PLIST_PATH" "CFBundleIconFile" "AppIcon"
/usr/libexec/PlistBuddy -c "Delete :NSMainStoryboardFile" "$INFO_PLIST_PATH" >/dev/null 2>&1 || true

if [[ -f "$PRIVACY_MANIFEST" ]]; then
  cp "$PRIVACY_MANIFEST" "$RESOURCES_DIR/PrivacyInfo.xcprivacy"
fi

for localization in en zh-Hans; do
  source_dir="$ROOT_DIR/Via/$localization.lproj"
  if [[ -d "$source_dir" ]]; then
    cp -R "$source_dir" "$RESOURCES_DIR/"
  fi
done

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
  echo "==> Signing policy core"
  codesign --force --sign "$SIGN_IDENTITY" "$FRAMEWORKS_DIR/libvia_core.dylib"

  echo "==> Signing app bundle ($SIGN_IDENTITY)"
  # The embedded policy core is signed above; sign the app itself rather than
  # using the discouraged --deep flag.
  codesign --force --sign "$SIGN_IDENTITY" \
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
