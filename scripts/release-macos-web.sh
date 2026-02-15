#!/usr/bin/env bash
set -euo pipefail

log() {
  printf "[release] %s\n" "$*"
}

die() {
  printf "[release][error] %s\n" "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

require_env() {
  local key="$1"
  [[ -n "${!key:-}" ]] || die "Missing required env var: $key"
}

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/build}"

# Required configuration
APP_NAME="${APP_NAME:-}"
SCHEME="${SCHEME:-}"
DEVELOPER_ID_APP="${DEVELOPER_ID_APP:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
EXPORT_OPTIONS_PLIST="${EXPORT_OPTIONS_PLIST:-}"

# Project selection: set exactly one
PROJECT_PATH="${PROJECT_PATH:-}"
WORKSPACE_PATH="${WORKSPACE_PATH:-}"

# Optional configuration
CONFIGURATION="${CONFIGURATION:-Release}"
ARCHIVE_PATH="${ARCHIVE_PATH:-$BUILD_DIR/$APP_NAME.xcarchive}"
EXPORT_PATH="${EXPORT_PATH:-$BUILD_DIR/export}"
DMG_PATH="${DMG_PATH:-$BUILD_DIR/$APP_NAME.dmg}"
VOL_NAME="${VOL_NAME:-$APP_NAME}"

usage() {
  cat <<'EOF'
Usage:
  1) Copy scripts/.env.release.example to .env.release and fill values
  2) source .env.release
  3) bash scripts/release-macos-web.sh

Required env vars:
  APP_NAME
  SCHEME
  DEVELOPER_ID_APP
  NOTARY_PROFILE
  EXPORT_OPTIONS_PLIST
  and exactly one of:
    PROJECT_PATH
    WORKSPACE_PATH
EOF
}

[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && usage && exit 0

require_cmd xcodebuild
require_cmd xcrun
require_cmd codesign
require_cmd hdiutil
require_cmd shasum
require_cmd spctl

require_env APP_NAME
require_env SCHEME
require_env DEVELOPER_ID_APP
require_env NOTARY_PROFILE
require_env EXPORT_OPTIONS_PLIST

[[ -f "$EXPORT_OPTIONS_PLIST" ]] || die "ExportOptions.plist not found: $EXPORT_OPTIONS_PLIST"

if [[ -n "$PROJECT_PATH" && -n "$WORKSPACE_PATH" ]]; then
  die "Set only one of PROJECT_PATH or WORKSPACE_PATH"
fi
if [[ -z "$PROJECT_PATH" && -z "$WORKSPACE_PATH" ]]; then
  die "Set one of PROJECT_PATH or WORKSPACE_PATH"
fi

if [[ -n "$PROJECT_PATH" ]]; then
  [[ -f "$PROJECT_PATH" ]] || die "Project not found: $PROJECT_PATH"
  PROJECT_ARG=(-project "$PROJECT_PATH")
else
  [[ -d "$WORKSPACE_PATH" ]] || die "Workspace not found: $WORKSPACE_PATH"
  PROJECT_ARG=(-workspace "$WORKSPACE_PATH")
fi

mkdir -p "$BUILD_DIR"
rm -rf "$ARCHIVE_PATH" "$EXPORT_PATH" "$DMG_PATH" "$DMG_PATH.sha256"

log "Archiving app"
xcodebuild \
  "${PROJECT_ARG[@]}" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "generic/platform=macOS" \
  -archivePath "$ARCHIVE_PATH" \
  archive

log "Exporting archive"
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS_PLIST" \
  -exportPath "$EXPORT_PATH"

APP_PATH="$EXPORT_PATH/$APP_NAME.app"
if [[ ! -d "$APP_PATH" ]]; then
  FOUND_APP="$(find "$EXPORT_PATH" -maxdepth 2 -type d -name "*.app" | head -n 1 || true)"
  [[ -n "$FOUND_APP" ]] || die "No .app found under export path: $EXPORT_PATH"
  APP_PATH="$FOUND_APP"
fi

log "Signing app with hardened runtime"
codesign \
  --force \
  --deep \
  --options runtime \
  --timestamp \
  --sign "$DEVELOPER_ID_APP" \
  "$APP_PATH"

log "Verifying app signature"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
spctl -a -t exec -vv "$APP_PATH"

STAGING_DIR="$BUILD_DIR/dmg-staging"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
cp -R "$APP_PATH" "$STAGING_DIR/"

log "Creating DMG"
hdiutil create \
  -volname "$VOL_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

log "Signing DMG"
codesign --force --timestamp --sign "$DEVELOPER_ID_APP" "$DMG_PATH"
codesign --verify --verbose=2 "$DMG_PATH"

log "Submitting DMG for notarization"
xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait

log "Stapling notarization ticket"
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"

log "Gatekeeper verification"
spctl -a -t open --context context:primary-signature -vv "$DMG_PATH"

log "Generating checksum"
shasum -a 256 "$DMG_PATH" > "$DMG_PATH.sha256"

log "Done"
log "DMG: $DMG_PATH"
log "SHA256: $DMG_PATH.sha256"
