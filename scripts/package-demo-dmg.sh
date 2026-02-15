#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

CONFIG="${1:-release}"
COUNT="${2:-1}"
SIGN_IDENTITY="${DEMO_SIGN_IDENTITY:-${DEV_SIGN_IDENTITY:-}}"

if [[ "$CONFIG" != "release" && "$CONFIG" != "debug" ]]; then
  echo "Usage: $0 [release|debug] [count]" >&2
  exit 1
fi

if ! [[ "$COUNT" =~ ^[0-9]+$ ]] || [[ "$COUNT" -lt 1 ]]; then
  echo "Usage: $0 [release|debug] [count>=1]" >&2
  exit 1
fi

TARGET="PasteDock"
APP_NAME="$TARGET.app"
VOL_NAME="$TARGET"
ICON_SOURCE="$ROOT_DIR/assets/icon/AppIcon.icns"
MENU_BAR_ICON_SOURCE="$ROOT_DIR/assets/icon/menuBarTemplate.png"

swift build -c "$CONFIG"
BIN_PATH="$ROOT_DIR/.build/$CONFIG/$TARGET"
if [[ ! -x "$BIN_PATH" ]]; then
  echo "Binary not found: $BIN_PATH" >&2
  exit 1
fi

for ((i=1; i<=COUNT; i++)); do
  BUILD_ID="$(date +%Y%m%d-%H%M%S)-$(uuidgen | cut -d- -f1)"
  OUT_DIR="$ROOT_DIR/artifacts/$TARGET-dmg/$BUILD_ID-$CONFIG"
  STAGING_DIR="$(mktemp -d "/tmp/${TARGET}.dmg.staging.XXXXXX")"
  APP_DIR="$STAGING_DIR/$APP_NAME"

  mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$OUT_DIR"
  cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/$TARGET"
  chmod +x "$APP_DIR/Contents/MacOS/$TARGET"
  ICON_STATUS="missing"
  if [[ -f "$ICON_SOURCE" ]]; then
    cp "$ICON_SOURCE" "$APP_DIR/Contents/Resources/AppIcon.icns"
    ICON_STATUS="present"
  else
    echo "INFO: App icon missing ($ICON_SOURCE)." >&2
    echo "INFO: Run bash scripts/generate-app-icon.sh to include icon in DMG app bundle." >&2
  fi

  MENU_BAR_ICON_STATUS="missing"
  if [[ -f "$MENU_BAR_ICON_SOURCE" ]]; then
    cp "$MENU_BAR_ICON_SOURCE" "$APP_DIR/Contents/Resources/menuBarTemplate.png"
    MENU_BAR_ICON_STATUS="present"
  else
    echo "INFO: Menu bar icon missing ($MENU_BAR_ICON_SOURCE)." >&2
    echo "INFO: Run bash scripts/generate-app-icon.sh to include menu bar icon in DMG app bundle." >&2
  fi

  cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>$TARGET</string>
  <key>CFBundleDisplayName</key>
  <string>$TARGET</string>
  <key>CFBundleExecutable</key>
  <string>$TARGET</string>
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

  SIGNING_MODE="unsigned_or_unknown"
  if [[ -n "$SIGN_IDENTITY" ]]; then
    if codesign --force --deep --timestamp --options runtime --sign "$SIGN_IDENTITY" "$APP_DIR" >/dev/null 2>&1; then
      SIGNING_MODE="certificate:$SIGN_IDENTITY"
    else
      SIGNING_MODE="sign_failed"
      echo "WARNING: Failed to sign demo app with identity: $SIGN_IDENTITY" >&2
      echo "WARNING: Accessibility trust can be unstable on unsigned/ad-hoc builds." >&2
    fi
  else
    echo "INFO: DEMO_SIGN_IDENTITY not set; building unsigned demo DMG." >&2
    echo "INFO: Accessibility trust can be unstable on unsigned/ad-hoc builds." >&2
  fi

  ln -s /Applications "$STAGING_DIR/Applications"

  DMG_PATH="$OUT_DIR/$TARGET.dmg"
  hdiutil create \
    -volname "$VOL_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH" >/dev/null

  if [[ -n "$SIGN_IDENTITY" ]]; then
    codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG_PATH" >/dev/null 2>&1 || true
  fi

  shasum -a 256 "$DMG_PATH" > "$DMG_PATH.sha256"
  {
    echo "build_id=$BUILD_ID"
    echo "config=$CONFIG"
    echo "bundle_id=com.justdoit.pastedock"
    echo "signing_mode=$SIGNING_MODE"
    echo "sign_identity=${SIGN_IDENTITY:-}"
    echo "icon_status=$ICON_STATUS"
    echo "menu_bar_icon_status=$MENU_BAR_ICON_STATUS"
  } > "$OUT_DIR/metadata.txt"

  rm -rf "$STAGING_DIR"

  echo "[$i/$COUNT] DMG created: $DMG_PATH"
  echo "[$i/$COUNT] SHA256: $DMG_PATH.sha256"
  echo "[$i/$COUNT] metadata: $OUT_DIR/metadata.txt"
done
