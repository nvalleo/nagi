#!/usr/bin/env bash
#
# build-icons.sh — regenerate Nagi's app icon (Nagi.icns) and mode/menu-bar
# badge (nagi.tiff) into app/Resources/icons/, from the SVG sources under
# scripts/icons/src/ (see scripts/icons/generate.py, issue #25).
#
# Rasterizes via scripts/icons/svg2png.swift (AppKit's SVG decoder — no
# third-party dependency), then assembles the platform formats with the
# same system tools Apple's own icon pipeline uses:
#   - iconutil -c icns   for the Dock/Finder .icns (from an .iconset dir)
#   - tiffutil -cathidpicheck   for the multi-representation 1x/2x TIFF,
#     matching the format of Apple's own IME mode icons (confirmed against
#     /System/Library/Input Methods/JapaneseIM-RomajiTyping.app's
#     Hiragana.tiff and AinuIM.app's Ainu.tiff).
#
# Only needs to be re-run after editing scripts/icons/generate.py (design
# tweaks) — the output .icns/.tiff are committed like any other resource,
# not regenerated as part of build-app.sh.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ICONS_DIR="$SCRIPT_DIR/icons"
DEST_DIR="$REPO_ROOT/app/Resources/icons"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

echo "Generating SVG sources..."
python3 "$ICONS_DIR/generate.py"

rasterize() {
  swift "$ICONS_DIR/svg2png.swift" "$1" "$2" "$3"
}

echo "Rendering .icns (Dock/Finder)..."
ICONSET="$WORK_DIR/Nagi.iconset"
mkdir -p "$ICONSET"
# name pt-size px-size pairs per Apple's .iconset naming convention.
declare -a ICONSET_SPECS=(
  "icon_16x16.png:16"
  "icon_16x16@2x.png:32"
  "icon_32x32.png:32"
  "icon_32x32@2x.png:64"
  "icon_128x128.png:128"
  "icon_128x128@2x.png:256"
  "icon_256x256.png:256"
  "icon_256x256@2x.png:512"
  "icon_512x512.png:512"
  "icon_512x512@2x.png:1024"
)
for spec in "${ICONSET_SPECS[@]}"; do
  name="${spec%%:*}"
  px="${spec##*:}"
  rasterize "$ICONS_DIR/src/app-icon.svg" "$ICONSET/$name" "$px"
done
iconutil -c icns "$ICONSET" -o "$WORK_DIR/Nagi.icns"

echo "Rendering nagi.tiff (menu bar / input-source list, 1x + 2x of a 16pt icon)..."
rasterize "$ICONS_DIR/src/badge.svg" "$WORK_DIR/badge-16.tiff" 16
rasterize "$ICONS_DIR/src/badge.svg" "$WORK_DIR/badge-32.tiff" 32
tiffutil -cathidpicheck "$WORK_DIR/badge-16.tiff" "$WORK_DIR/badge-32.tiff" -out "$WORK_DIR/nagi.tiff"

mkdir -p "$DEST_DIR"
cp "$WORK_DIR/Nagi.icns" "$DEST_DIR/Nagi.icns"
cp "$WORK_DIR/nagi.tiff" "$DEST_DIR/nagi.tiff"

echo "Done:"
echo "  $DEST_DIR/Nagi.icns"
echo "  $DEST_DIR/nagi.tiff"
