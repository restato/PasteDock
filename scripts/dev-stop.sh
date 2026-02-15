#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PID_FILE="$ROOT_DIR/.dev-logs/last.pid"

if [[ ! -f "$PID_FILE" ]]; then
  echo "No pid file found."
  exit 0
fi

PID="$(cat "$PID_FILE" 2>/dev/null || true)"
if [[ -z "$PID" ]]; then
  echo "No pid recorded."
  exit 0
fi

if kill -0 "$PID" 2>/dev/null; then
  kill "$PID"
  echo "Stopped process: $PID"
else
  echo "Process not running: $PID"
fi

pkill -x PasteDock >/dev/null 2>&1 || true
