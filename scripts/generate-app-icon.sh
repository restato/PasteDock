#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ICON_DIR="$ROOT_DIR/assets/icon"
SOURCE_PATH="$ICON_DIR/source.png"
ICONSET_DIR="$ICON_DIR/AppIcon.iconset"
ICNS_PATH="$ICON_DIR/AppIcon.icns"
MENU_BAR_TEMPLATE_PATH="$ICON_DIR/menuBarTemplate.png"

if [[ ! -f "$SOURCE_PATH" ]]; then
  echo "Missing source icon: $SOURCE_PATH" >&2
  exit 1
fi

rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"

swift "$ROOT_DIR/scripts/generate-app-icon.swift" "$SOURCE_PATH" "$ICONSET_DIR" "$MENU_BAR_TEMPLATE_PATH"
iconutil -c icns "$ICONSET_DIR" -o "$ICNS_PATH"

echo "Generated iconset: $ICONSET_DIR"
echo "Generated icns: $ICNS_PATH"
echo "Generated menu bar icon: $MENU_BAR_TEMPLATE_PATH"
