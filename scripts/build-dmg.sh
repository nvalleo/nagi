#!/usr/bin/env bash
#
# build-dmg.sh — package Nagi.app as a plain drag-and-drop .dmg, the
# "try it without a dev environment" entry point (#30 install/uninstall
# follow-up).
#
# Deliberately just the app, no custom installer package — see the
# discussion on issue #30 for why: a .pkg was tried first and dropped in
# favor of this, matching the "signed/notarized DMG containing the app,
# no custom installer, user drags it wherever they want" standard other
# solo/small-team macOS apps (not just IMEs) are held to. Nagi can't
# fully match that standard yet (no paid Apple Developer ID, so this is
# unsigned/unnotarized — see README.md), but the shape now matches: a
# DMG with just Nagi.app in it, not an installer.
#
# What used to require a custom installer — registering the bundled
# NagiConverter as a LaunchAgent — Nagi.app now does for itself via
# SMAppService the first time it runs (see
# app/Sources/Nagi/ConverterServiceRegistration.swift), which is what
# makes dropping the installer possible at all.
#
# The one accommodation an Input Method needs that a normal app doesn't:
# it has to land in /Library/Input Methods/, not /Applications/. This
# DMG's "drop target" is a symlink to that folder instead of the usual
# Applications alias — same drag-and-drop gesture, same
# Finder-handles-the-admin-prompt behavior when dropping into a
# root-owned folder, just a different destination. (System-wide, not
# ~/Library/Input Methods/, because a symlink baked into a DMG at build
# time can't point into an arbitrary future user's home directory —
# scripts/install-ime.sh's per-user default remains available for
# anyone building from source instead.)
#
# Also bundles "Uninstall Nagi.app" (#30 follow-up, see
# build-uninstaller.sh) — a double-clickable uninstaller for the same
# audience this DMG targets: people without a Terminal, who can't run
# scripts/uninstall-ime.sh themselves.
#
# Usage: build-dmg.sh
#
# Produces .build-dmg/Nagi-<version>.dmg. Rebuilds Nagi.app first (same
# release build build-app.sh always produces).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DMG_RESOURCES="$SCRIPT_DIR/dmg"

"$SCRIPT_DIR/build-app.sh" release
"$SCRIPT_DIR/build-uninstaller.sh"

APP_BUNDLE="$REPO_ROOT/.build-app/Nagi.app"
UNINSTALLER_APP="$REPO_ROOT/.build-app/Uninstall Nagi.app"
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_BUNDLE/Contents/Info.plist")"

OUT_DIR="$REPO_ROOT/.build-dmg"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

echo "Staging DMG contents ..."
STAGING="$WORK_DIR/staging"
mkdir -p "$STAGING"
cp -R "$APP_BUNDLE" "$STAGING/Nagi.app"
cp -R "$UNINSTALLER_APP" "$STAGING/Uninstall Nagi.app"
ln -s "/Library/Input Methods" "$STAGING/Input Methods"
cp "$DMG_RESOURCES/README.txt" "$STAGING/README.txt"

mkdir -p "$OUT_DIR"
OUT_DMG="$OUT_DIR/Nagi-$VERSION.dmg"
rm -f "$OUT_DMG"

echo "Building $OUT_DMG ..."
hdiutil create \
  -volname "Nagi $VERSION" \
  -srcfolder "$STAGING" \
  -fs HFS+ \
  -format UDZO \
  "$OUT_DMG"

echo
echo "Done: $OUT_DMG"
echo
echo "Unsigned, unnotarized — first open of Nagi.app will show a"
echo "Gatekeeper warning. See scripts/dmg/README.txt (bundled in the"
echo "DMG) for the Control-click / xattr workaround."
