#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

COUNT="${1:-3}"
CONFIG="${2:-release}"

if ! [[ "$COUNT" =~ ^[0-9]+$ ]] || [[ "$COUNT" -lt 1 ]]; then
  echo "Usage: $0 <count>=3 [release|debug]" >&2
  exit 1
fi

for ((i=1; i<=COUNT; i++)); do
  echo "[${i}/${COUNT}] Building $CONFIG"
  bash "$ROOT_DIR/scripts/build-demo-binary.sh" "$CONFIG"
done

echo "Done: built $COUNT time(s) for $CONFIG"
