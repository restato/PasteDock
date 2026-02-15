#!/usr/bin/env bash
set -euo pipefail

APP_NAME="PasteDock.app"
BIN_SUFFIX="/Contents/MacOS/PasteDock"
SYSTEM_PATH="/Applications/$APP_NAME"
USER_PATH="$HOME/Applications/$APP_NAME"

APP_PATH=""
RUNNING_PID="$(pgrep -x PasteDock | head -n 1 || true)"
if [[ -n "$RUNNING_PID" ]]; then
  RUNNING_CMD="$(ps -p "$RUNNING_PID" -o command= | sed -e 's/^ *//' || true)"
  if [[ "$RUNNING_CMD" == *"$BIN_SUFFIX"* ]]; then
    APP_PATH="${RUNNING_CMD%%$BIN_SUFFIX*}"
  fi
fi

if [[ -z "$APP_PATH" ]]; then
  if [[ -d "$SYSTEM_PATH" ]]; then
    APP_PATH="$SYSTEM_PATH"
  elif [[ -d "$USER_PATH" ]]; then
    APP_PATH="$USER_PATH"
  fi
fi

if [[ -z "$APP_PATH" || ! -d "$APP_PATH" ]]; then
  echo "Dev app not found. Run: bash scripts/dev-run.sh --rebuild"
  exit 1
fi

open -R "$APP_PATH"
