#!/usr/bin/env bash
#
# Builds libautowifi_jni.so for the Android shell and copies it into the
# jniLibs directory Gradle packages.
#
# Usage: scripts/build-android-core.sh
#
# Requires cargo-ndk (cargo install cargo-ndk) and an Android NDK. Set
# ANDROID_NDK_HOME or ANDROID_NDK_ROOT when the NDK is not auto-detected.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$ROOT_DIR/platforms/android/app/src/main/jniLibs"

if ! command -v cargo-ndk >/dev/null 2>&1; then
  echo "cargo-ndk is required: cargo install cargo-ndk" >&2
  exit 1
fi

if [[ -z "${ANDROID_NDK_HOME:-}" && -z "${ANDROID_NDK_ROOT:-}" && -n "${ANDROID_NDK_LATEST_HOME:-}" ]]; then
  export ANDROID_NDK_HOME="$ANDROID_NDK_LATEST_HOME"
fi

# cargo-ndk runs `cargo metadata` in the current directory, so build from the
# workspace root rather than passing --manifest-path.
(
  cd "$ROOT_DIR/core"
  cargo ndk \
    -t arm64-v8a \
    -t armeabi-v7a \
    -t x86_64 \
    -o "$OUT_DIR" \
    build -p autowifi-jni --release
)

echo "JNI libraries:"
find "$OUT_DIR" -name 'libautowifi_jni.so' -print
