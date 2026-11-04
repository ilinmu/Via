#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${1:-release}"

case "$CONFIGURATION" in
  release)
    cargo build --manifest-path "$ROOT_DIR/core/Cargo.toml" -p via-ffi --release
    ;;
  debug)
    cargo build --manifest-path "$ROOT_DIR/core/Cargo.toml" -p via-ffi
    ;;
  *)
    echo "Usage: scripts/build-core.sh [release|debug]" >&2
    exit 2
    ;;
esac

DYLIB="$ROOT_DIR/core/target/$CONFIGURATION/libvia_core.dylib"
if [[ ! -f "$DYLIB" ]]; then
  echo "Missing built policy core at $DYLIB" >&2
  exit 1
fi

mkdir -p "$ROOT_DIR/dist"
cp "$DYLIB" "$ROOT_DIR/dist/libvia_core.dylib"

echo "Policy core: $ROOT_DIR/dist/libvia_core.dylib"
