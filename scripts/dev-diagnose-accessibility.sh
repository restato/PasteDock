#!/usr/bin/env bash
set -euo pipefail

APP_NAME="PasteDock.app"
BIN_SUFFIX="/Contents/MacOS/PasteDock"
SYSTEM_APP="/Applications/$APP_NAME"
USER_APP="$HOME/Applications/$APP_NAME"
RUNTIME_LOG="$HOME/Library/Application Support/com-justdoit-pastedock/logs/runtime.log"

APP_PATH=""
RUNNING_PID="$(pgrep -x PasteDock | head -n 1 || true)"
RUNNING_CMD=""
if [[ -n "$RUNNING_PID" ]]; then
  RUNNING_CMD="$(ps -p "$RUNNING_PID" -o command= | sed -e 's/^ *//' || true)"
  if [[ "$RUNNING_CMD" == *"$BIN_SUFFIX"* ]]; then
    APP_PATH="${RUNNING_CMD%%$BIN_SUFFIX*}"
  fi
fi

if [[ -z "$APP_PATH" ]]; then
  if [[ -d "$SYSTEM_APP" ]]; then
    APP_PATH="$SYSTEM_APP"
  elif [[ -d "$USER_APP" ]]; then
    APP_PATH="$USER_APP"
  else
    echo "app_path=(not found)"
    echo "hint=run bash scripts/dev-run.sh --rebuild first"
    exit 1
  fi
fi

INFO_PLIST="$APP_PATH/Contents/Info.plist"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO_PLIST" 2>/dev/null || echo '(missing)')"
APP_BIN="$APP_PATH$BIN_SUFFIX"
ICON_PATH="$APP_PATH/Contents/Resources/AppIcon.icns"

echo "app_path=$APP_PATH"
echo "app_bin=$APP_BIN"
echo "bundle_id=$BUNDLE_ID"
echo "icon_present=$( [[ -f "$ICON_PATH" ]] && echo yes || echo no )"
echo "running_pid=${RUNNING_PID:-}"
echo "running_cmd=${RUNNING_CMD:-}"
echo "installed_system=$( [[ -d "$SYSTEM_APP" ]] && echo yes || echo no )"
echo "installed_user=$( [[ -d "$USER_APP" ]] && echo yes || echo no )"
if [[ -d "$SYSTEM_APP" && -d "$USER_APP" ]]; then
  echo "warning=both /Applications and ~/Applications copies exist; remove stale one"
fi

echo "--- codesign -dv --verbose=4"
codesign -dv --verbose=4 "$APP_PATH" 2>&1 | sed -n '1,80p'

echo "--- designated requirement"
codesign -d -r- "$APP_PATH" 2>&1 | sed -n '1,40p'

echo "--- gatekeeper"
spctl -a -vv "$APP_PATH" 2>&1 | sed -n '1,40p' || true

echo "--- running process"
pgrep -fal "$BIN_SUFFIX" || echo "(not running)"

echo "--- runtime log (last 80 lines)"
if [[ -f "$RUNTIME_LOG" ]]; then
  tail -n 80 "$RUNTIME_LOG"
else
  echo "runtime log missing: $RUNTIME_LOG"
fi
