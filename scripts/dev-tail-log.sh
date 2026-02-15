#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LAST_LOG_FILE="$ROOT_DIR/.dev-logs/last.log"

RUNTIME1="$HOME/Library/Application Support/com-justdoit-pastedock/logs/runtime.log"

pick_existing() {
  local newest=""
  local newest_mtime=0
  for f in "$@"; do
    if [[ -f "$f" ]]; then
      local mtime
      mtime=$(stat -f %m "$f" 2>/dev/null || echo 0)
      if [[ "$mtime" -gt "$newest_mtime" ]]; then
        newest="$f"
        newest_mtime="$mtime"
      fi
    fi
  done
  echo "$newest"
}

LOG_PATH=""
if [[ -f "$LAST_LOG_FILE" ]]; then
  CANDIDATE="$(cat "$LAST_LOG_FILE" 2>/dev/null || true)"
  if [[ -n "$CANDIDATE" && -f "$CANDIDATE" ]]; then
    LOG_PATH="$CANDIDATE"
  fi
fi

if [[ -z "$LOG_PATH" ]]; then
  LOG_PATH="$(pick_existing "$RUNTIME1")"
fi

if [[ -z "$LOG_PATH" ]]; then
  echo "No log file found yet."
  echo "Try: bash scripts/dev-run.sh"
  exit 1
fi

echo "Tailing: $LOG_PATH"
tail -f "$LOG_PATH"
