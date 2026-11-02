#!/usr/bin/env bash
#
# Builds the shared Rust policy core as a static XCFramework for the iOS shell.
#
# Usage: scripts/build-ios-core.sh
#
# Requires the Rust targets below (the script adds them through rustup when it
# is available) and Xcode's xcodebuild.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${OUT_DIR:-$ROOT_DIR/platforms/ios/Frameworks}"
HEADERS_DIR="$OUT_DIR/include"
XCFRAMEWORK="$OUT_DIR/AutoWifiCore.xcframework"
MANIFEST="$ROOT_DIR/core/Cargo.toml"

DEVICE_TARGET="aarch64-apple-ios"
SIM_ARM_TARGET="aarch64-apple-ios-sim"
SIM_X86_TARGET="x86_64-apple-ios"

if command -v rustup >/dev/null 2>&1; then
  rustup target add "$DEVICE_TARGET" "$SIM_ARM_TARGET" "$SIM_X86_TARGET"
fi

for target in "$DEVICE_TARGET" "$SIM_ARM_TARGET" "$SIM_X86_TARGET"; do
  echo "==> Building autowifi-ffi for $target"
  cargo build --manifest-path "$MANIFEST" -p autowifi-ffi --release --target "$target"
done

mkdir -p "$HEADERS_DIR"
cp "$ROOT_DIR/core/include/autowifi_core.h" "$HEADERS_DIR/autowifi_core.h"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/autowifi-xcframework.XXXXXX")"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

# `xcodebuild -create-xcframework` rejects two separate libraries that both
# identify as `ios-simulator`, so merge the simulator slices into one fat
# archive first.
SIM_LIB="$TMP_DIR/libautowifi_core_simulator.a"
xcrun lipo -create \
  "$ROOT_DIR/core/target/$SIM_ARM_TARGET/release/libautowifi_core.a" \
  "$ROOT_DIR/core/target/$SIM_X86_TARGET/release/libautowifi_core.a" \
  -output "$SIM_LIB"

TMP_XCFRAMEWORK="$TMP_DIR/AutoWifiCore.xcframework"
xcodebuild -create-xcframework \
  -library "$ROOT_DIR/core/target/$DEVICE_TARGET/release/libautowifi_core.a" \
  -headers "$HEADERS_DIR" \
  -library "$SIM_LIB" \
  -headers "$HEADERS_DIR" \
  -output "$TMP_XCFRAMEWORK"

if [[ -e "$XCFRAMEWORK" ]]; then
  rm -rf "$XCFRAMEWORK"
fi
mv "$TMP_XCFRAMEWORK" "$XCFRAMEWORK"

echo "XCFramework: $XCFRAMEWORK"
