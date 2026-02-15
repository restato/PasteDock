#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

CONFIG="${1:-release}"
if [[ "$CONFIG" != "release" && "$CONFIG" != "debug" ]]; then
  echo "Usage: $0 [release|debug]" >&2
  exit 1
fi

TARGET="PasteDock"
BUILD_ID="$(date +%Y%m%d-%H%M%S)-$(uuidgen | cut -d- -f1)"
OUT_DIR="$ROOT_DIR/artifacts/$TARGET/$BUILD_ID-$CONFIG"
mkdir -p "$OUT_DIR"

swift build -c "$CONFIG"
BIN_PATH="$ROOT_DIR/.build/$CONFIG/$TARGET"
if [[ ! -x "$BIN_PATH" ]]; then
  echo "Binary not found: $BIN_PATH" >&2
  exit 1
fi

cp "$BIN_PATH" "$OUT_DIR/$TARGET"
shasum -a 256 "$OUT_DIR/$TARGET" > "$OUT_DIR/$TARGET.sha256"

cat <<MSG
Build complete
- config: $CONFIG
- binary: $OUT_DIR/$TARGET
- sha256: $OUT_DIR/$TARGET.sha256
MSG
