#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

STATE_DIR="$ROOT_DIR/.dev-logs"
mkdir -p "$STATE_DIR"

LOG_FILE="$STATE_DIR/run-$(date +%Y%m%d-%H%M%S).log"
PID_FILE="$STATE_DIR/last.pid"
LAST_LOG_FILE="$STATE_DIR/last.log"
BINARY="$ROOT_DIR/.build/debug/PasteDock"
REBUILD=0
APP_NAME="PasteDock"
APP_BUNDLE="$APP_NAME.app"
APP_BIN_NAME="$APP_NAME"
ICON_SOURCE="$ROOT_DIR/assets/icon/AppIcon.icns"
MENU_BAR_ICON_SOURCE="$ROOT_DIR/assets/icon/menuBarTemplate.png"

if [[ "${1:-}" == "--rebuild" ]]; then
  REBUILD=1
fi

if [[ -f "$PID_FILE" ]]; then
  OLD_PID="$(cat "$PID_FILE" 2>/dev/null || true)"
  if [[ -n "$OLD_PID" ]] && kill -0 "$OLD_PID" 2>/dev/null; then
    echo "Stopping previous process: $OLD_PID"
    kill "$OLD_PID" || true
    sleep 0.5
  fi
fi

pkill -x "$APP_NAME" >/dev/null 2>&1 || true
sleep 0.3

if [[ "$REBUILD" -eq 1 || ! -x "$BINARY" ]]; then
  swift build -c debug >/dev/null
fi

if [[ -d "/Applications" && -w "/Applications" ]]; then
  DEV_APP_DIR="/Applications"
else
  DEV_APP_DIR="$HOME/Applications"
fi

DEV_APP_PATH="$DEV_APP_DIR/$APP_BUNDLE"
DEV_APP_BIN="$DEV_APP_PATH/Contents/MacOS/$APP_BIN_NAME"
ALT_APP_PATH="$HOME/Applications/$APP_BUNDLE"

mkdir -p "$DEV_APP_DIR" "$DEV_APP_PATH/Contents/MacOS" "$DEV_APP_PATH/Contents/Resources"
cp "$BINARY" "$DEV_APP_BIN"
chmod +x "$DEV_APP_BIN"
ICON_STATUS="missing"
if [[ -f "$ICON_SOURCE" ]]; then
  cp "$ICON_SOURCE" "$DEV_APP_PATH/Contents/Resources/AppIcon.icns"
  ICON_STATUS="present"
else
  echo "WARNING: App icon not found at $ICON_SOURCE" | tee -a "$LOG_FILE"
  echo "WARNING: Run bash scripts/generate-app-icon.sh" | tee -a "$LOG_FILE"
fi

MENU_BAR_ICON_STATUS="missing"
if [[ -f "$MENU_BAR_ICON_SOURCE" ]]; then
  cp "$MENU_BAR_ICON_SOURCE" "$DEV_APP_PATH/Contents/Resources/menuBarTemplate.png"
  MENU_BAR_ICON_STATUS="present"
else
  echo "WARNING: Menu bar icon not found at $MENU_BAR_ICON_SOURCE" | tee -a "$LOG_FILE"
  echo "WARNING: Run bash scripts/generate-app-icon.sh" | tee -a "$LOG_FILE"
fi

if [[ "$DEV_APP_PATH" == "/Applications/$APP_BUNDLE" && -d "$ALT_APP_PATH" ]]; then
  echo "WARNING: Found another app copy at $ALT_APP_PATH" | tee -a "$LOG_FILE"
  echo "WARNING: Remove stale copies to avoid Accessibility confusion." | tee -a "$LOG_FILE"
fi

cat > "$DEV_APP_PATH/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>PasteDock</string>
  <key>CFBundleDisplayName</key>
  <string>PasteDock</string>
  <key>CFBundleExecutable</key>
  <string>PasteDock</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>com.justdoit.pastedock</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0.0</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
</dict>
</plist>
PLIST

resolve_identity() {
  if [[ -n "${DEV_SIGN_IDENTITY:-}" ]]; then
    echo "$DEV_SIGN_IDENTITY"
    return
  fi

  local identity_output
  identity_output="$(security find-identity -v -p codesigning 2>/dev/null || true)"

  local candidate
  candidate="$(printf '%s\n' "$identity_output" | rg -m1 'Developer ID Application' || true)"
  if [[ -z "$candidate" ]]; then
    candidate="$(printf '%s\n' "$identity_output" | rg -m1 'Apple Development' || true)"
  fi

  if [[ -n "$candidate" ]]; then
    printf '%s\n' "$candidate" | sed -E 's/.*"(.*)".*/\1/'
  fi
}

SIGNING_MODE="unsigned_or_unknown"
SIGN_IDENTITY="$(resolve_identity || true)"
if [[ -n "$SIGN_IDENTITY" ]]; then
  if codesign --force --deep --timestamp --options runtime --sign "$SIGN_IDENTITY" "$DEV_APP_PATH" >/dev/null 2>&1; then
    SIGNING_MODE="certificate:$SIGN_IDENTITY"
  else
    echo "WARNING: Failed to sign with identity: $SIGN_IDENTITY" | tee -a "$LOG_FILE"
    echo "WARNING: Accessibility trust may be unstable across rebuilds." | tee -a "$LOG_FILE"
  fi
else
  echo "WARNING: No signing identity found (Developer ID Application or Apple Development)." | tee -a "$LOG_FILE"
  echo "WARNING: Accessibility trust can break after rebuilds. Set DEV_SIGN_IDENTITY to fix." | tee -a "$LOG_FILE"
fi

open -na "$DEV_APP_PATH"

APP_PID=""
for _ in {1..20}; do
  APP_PID="$(pgrep -f "$DEV_APP_BIN" | tail -n 1 || true)"
  if [[ -n "$APP_PID" ]]; then
    break
  fi
  sleep 0.2
done

if [[ -n "$APP_PID" ]]; then
  echo "$APP_PID" > "$PID_FILE"
else
  rm -f "$PID_FILE"
fi

echo "$LOG_FILE" > "$LAST_LOG_FILE"

echo "Started PasteDock"
echo "- pid: ${APP_PID:-unknown}"
echo "- script log: $LOG_FILE"
if [[ "$REBUILD" -eq 1 ]]; then
  echo "- mode: rebuilt"
else
  echo "- mode: reuse existing binary (use --rebuild to force build)"
fi
echo "- dev app bundle: $DEV_APP_PATH"
echo "- accessibility bundle id: com.justdoit.pastedock"
echo "- signing mode: $SIGNING_MODE"
echo "- app icon: $ICON_STATUS"
echo "- menu bar icon: $MENU_BAR_ICON_STATUS"
echo "- runtime log: ~/Library/Application Support/com-justdoit-pastedock/logs/runtime.log"
