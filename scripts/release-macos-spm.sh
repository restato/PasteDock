#!/usr/bin/env bash
set -euo pipefail

log() {
  printf "[release-spm] %s\n" "$*"
}

die() {
  printf "[release-spm][error] %s\n" "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

require_env() {
  local key="$1"
  [[ -n "${!key:-}" ]] || die "Missing required env var: $key"
}

usage() {
  cat <<'EOF'
Usage:
  bash scripts/release-macos-spm.sh [release|debug] [--tag vX.Y.Z] [--skip-notarize]

Environment:
  APP_NAME            (default: PasteDock)
  APP_TARGET          (default: PasteDock)
  APP_EXECUTABLE      (default: APP_TARGET)
  BUNDLE_ID           (default: com.justdoit.pastedock)
  MIN_MACOS_VERSION   (default: 14.0)
  BUILD_DIR           (default: <repo>/build)
  ICON_PATH           (default: <repo>/assets/icon/AppIcon.icns)
  MENU_BAR_ICON_PATH  (default: <repo>/assets/icon/menuBarTemplate.png)
  VOL_NAME            (default: APP_NAME)
  RELEASE_TAG         (optional if --tag provided or exact tag checked out)
  BUNDLE_VERSION      (optional; default: <semver>.<commit-count>)

Required env vars:
  DEVELOPER_ID_APP
  NOTARY_PROFILE      (required unless --skip-notarize)
EOF
}

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

CONFIG="${CONFIGURATION:-release}"
RELEASE_TAG="${RELEASE_TAG:-}"
SKIP_NOTARIZE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    release|debug)
      CONFIG="$1"
      shift
      ;;
    --tag)
      [[ $# -ge 2 ]] || die "--tag requires a value"
      RELEASE_TAG="$2"
      shift 2
      ;;
    --skip-notarize)
      SKIP_NOTARIZE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown argument: $1"
      ;;
  esac
done

[[ "$CONFIG" == "release" || "$CONFIG" == "debug" ]] || die "Config must be release or debug"

require_cmd swift
require_cmd codesign
require_cmd hdiutil
require_cmd shasum
require_cmd spctl
require_cmd uuidgen
if [[ "$SKIP_NOTARIZE" -eq 0 ]]; then
  require_cmd xcrun
fi

APP_NAME="${APP_NAME:-PasteDock}"
APP_TARGET="${APP_TARGET:-PasteDock}"
APP_EXECUTABLE="${APP_EXECUTABLE:-$APP_TARGET}"
BUNDLE_ID="${BUNDLE_ID:-com.justdoit.pastedock}"
MIN_MACOS_VERSION="${MIN_MACOS_VERSION:-14.0}"
BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/build}"
ICON_PATH="${ICON_PATH:-$ROOT_DIR/assets/icon/AppIcon.icns}"
MENU_BAR_ICON_PATH="${MENU_BAR_ICON_PATH:-$ROOT_DIR/assets/icon/menuBarTemplate.png}"
VOL_NAME="${VOL_NAME:-$APP_NAME}"

require_env DEVELOPER_ID_APP
if [[ "$SKIP_NOTARIZE" -eq 0 ]]; then
  require_env NOTARY_PROFILE
fi

if [[ -z "$RELEASE_TAG" ]]; then
  if git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    RELEASE_TAG="$(git -C "$ROOT_DIR" describe --tags --exact-match 2>/dev/null || true)"
  fi
fi
[[ -n "$RELEASE_TAG" ]] || die "Set RELEASE_TAG or pass --tag vX.Y.Z"
[[ "$RELEASE_TAG" =~ ^v[0-9]+(\.[0-9]+){2}([.-][0-9A-Za-z]+)*$ ]] || die "Tag must look like vX.Y.Z"

SEMVER="${RELEASE_TAG#v}"
BASE_VERSION="${SEMVER%%-*}"
BASE_VERSION="${BASE_VERSION%%+*}"

COMMIT_COUNT=1
GIT_COMMIT="unknown"
if git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  COMMIT_COUNT="$(git -C "$ROOT_DIR" rev-list --count HEAD 2>/dev/null || echo 1)"
  GIT_COMMIT="$(git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null || echo unknown)"
fi
BUNDLE_VERSION="${BUNDLE_VERSION:-$BASE_VERSION.$COMMIT_COUNT}"

RUN_ID="$(date +%Y%m%d-%H%M%S)-$(uuidgen | cut -d- -f1)"
TAG_SAFE="$(printf '%s' "$RELEASE_TAG" | tr -c 'A-Za-z0-9._-' '_')"
OUT_DIR="$BUILD_DIR/${APP_NAME}-release/${RUN_ID}-${CONFIG}"
DMG_NAME="${APP_NAME}-${TAG_SAFE}.dmg"
DMG_PATH="$OUT_DIR/$DMG_NAME"
CHECKSUM_PATH="$DMG_PATH.sha256"
METADATA_PATH="$OUT_DIR/metadata.txt"
LATEST_POINTER="$BUILD_DIR/latest-release-dir.txt"

STAGING_DIR="$(mktemp -d "/tmp/${APP_NAME}.release.XXXXXX")"
APP_PATH="$STAGING_DIR/${APP_NAME}.app"
DMG_STAGING_DIR="$STAGING_DIR/dmg-staging"

cleanup() {
  rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

mkdir -p "$OUT_DIR" "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources" "$DMG_STAGING_DIR"

log "Building target ($APP_TARGET) with swift build -c $CONFIG"
swift build -c "$CONFIG" --product "$APP_TARGET"

BIN_PATH="$ROOT_DIR/.build/$CONFIG/$APP_TARGET"
[[ -x "$BIN_PATH" ]] || die "Binary not found: $BIN_PATH"

cp "$BIN_PATH" "$APP_PATH/Contents/MacOS/$APP_EXECUTABLE"
chmod +x "$APP_PATH/Contents/MacOS/$APP_EXECUTABLE"

ICON_STATUS="missing"
if [[ -f "$ICON_PATH" ]]; then
  cp "$ICON_PATH" "$APP_PATH/Contents/Resources/AppIcon.icns"
  ICON_STATUS="present"
else
  log "App icon not found ($ICON_PATH). Continuing without icon."
fi

MENU_BAR_ICON_STATUS="missing"
if [[ -f "$MENU_BAR_ICON_PATH" ]]; then
  cp "$MENU_BAR_ICON_PATH" "$APP_PATH/Contents/Resources/menuBarTemplate.png"
  MENU_BAR_ICON_STATUS="present"
else
  log "Menu bar icon not found ($MENU_BAR_ICON_PATH). Continuing without menu bar template icon."
fi

cat > "$APP_PATH/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleExecutable</key>
  <string>$APP_EXECUTABLE</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleVersion</key>
  <string>$BUNDLE_VERSION</string>
  <key>CFBundleShortVersionString</key>
  <string>$BASE_VERSION</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_MACOS_VERSION</string>
</dict>
</plist>
PLIST

log "Signing app bundle"
codesign \
  --force \
  --deep \
  --options runtime \
  --timestamp \
  --sign "$DEVELOPER_ID_APP" \
  "$APP_PATH"

log "Verifying app signature"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
if ! spctl -a -t exec -vv "$APP_PATH"; then
  log "Pre-notarization Gatekeeper check failed for app (expected on some systems). Continuing."
fi

cp -R "$APP_PATH" "$DMG_STAGING_DIR/"
ln -s /Applications "$DMG_STAGING_DIR/Applications"

log "Creating DMG: $DMG_PATH"
hdiutil create \
  -volname "$VOL_NAME" \
  -srcfolder "$DMG_STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null

log "Signing DMG"
codesign --force --timestamp --sign "$DEVELOPER_ID_APP" "$DMG_PATH"
codesign --verify --verbose=2 "$DMG_PATH"

NOTARIZATION_RESULT="skipped"
if [[ "$SKIP_NOTARIZE" -eq 0 ]]; then
  log "Submitting DMG for notarization"
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait | tee "$OUT_DIR/notarytool.log"

  log "Stapling notarization ticket"
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"
  NOTARIZATION_RESULT="completed"
fi

log "Running Gatekeeper verification"
spctl -a -t open --context context:primary-signature -vv "$DMG_PATH"

log "Generating checksum"
shasum -a 256 "$DMG_PATH" > "$CHECKSUM_PATH"

{
  echo "release_tag=$RELEASE_TAG"
  echo "base_version=$BASE_VERSION"
  echo "bundle_version=$BUNDLE_VERSION"
  echo "config=$CONFIG"
  echo "app_name=$APP_NAME"
  echo "app_target=$APP_TARGET"
  echo "bundle_id=$BUNDLE_ID"
  echo "min_macos_version=$MIN_MACOS_VERSION"
  echo "developer_id_app=$DEVELOPER_ID_APP"
  echo "notary_profile=${NOTARY_PROFILE:-}"
  echo "notarization_result=$NOTARIZATION_RESULT"
  echo "icon_status=$ICON_STATUS"
  echo "menu_bar_icon_status=$MENU_BAR_ICON_STATUS"
  echo "git_commit=$GIT_COMMIT"
  echo "dmg_path=$DMG_PATH"
  echo "sha256_path=$CHECKSUM_PATH"
} > "$METADATA_PATH"

printf '%s\n' "$OUT_DIR" > "$LATEST_POINTER"

log "Done"
log "Artifact directory: $OUT_DIR"
log "DMG: $DMG_PATH"
log "SHA256: $CHECKSUM_PATH"
log "Metadata: $METADATA_PATH"
