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
# it has to land in /Library/Input Methods/, not /Applications/. An
# earlier version of this script handled that with a symlink to that
# folder as the drop target, same idea as the usual Applications alias
# — but real-machine testing (#30 follow-up) found that Finder's
# drag-and-drop only escalates to an admin password prompt for a fixed
# allowlist of destinations (Applications, Applications/Utilities,
# Desktop, a handful of Library subfolders); a drop onto an alias/symlink
# pointing anywhere else, /Library/Input Methods included, is silently
# blocked by system policy instead — no error, no password prompt, the
# app just doesn't get copied (see
# https://developer.apple.com/forums/thread/712148). A README fix alone
# wasn't good enough here (most people don't read the README before
# dragging), so the drop target is gone: see "Install Nagi.app" below,
# which sidesteps the policy entirely rather than working around it.
# (System-wide only, not ~/Library/Input Methods/ — scripts/install-ime.sh's
# per-user default remains available for anyone building from source
# instead.)
#
# Just two things at the top level: Nagi.app and Install Nagi.app
# (#30 follow-up, see build-installer.sh). No bundled README.txt, no
# bundled fallback "Uninstall Nagi.app" — a straight "two files, drag
# one, click the other" DMG stays legible without either. Nagi.app
# itself embeds its own copy of the uninstaller and deploys it to
# /Applications/ on first launch regardless (#33,
# UninstallerDeployment.swift), so the normal uninstall path is
# unaffected; what's genuinely lost by leaving the DMG-level fallback
# out is a GUI uninstall option for the one case where Nagi.app never
# managed to launch at all (e.g. Gatekeeper blocked Install Nagi.app
# itself and the user gave up) — that case falls back to removing
# /Library/Input Methods/Nagi.app by hand in Finder, or
# scripts/uninstall-ime.sh for anyone who cloned the repo.
#
# Usage: build-dmg.sh
#
# Produces .build-dmg/Nagi-<version>.dmg. Rebuilds Nagi.app first (same
# release build build-app.sh always produces).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

"$SCRIPT_DIR/build-app.sh" release
"$SCRIPT_DIR/build-installer.sh"

APP_BUNDLE="$REPO_ROOT/.build-app/Nagi.app"
INSTALLER_APP="$REPO_ROOT/.build-app/Install Nagi.app"
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_BUNDLE/Contents/Info.plist")"

OUT_DIR="$REPO_ROOT/.build-dmg"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

echo "Staging DMG contents ..."
STAGING="$WORK_DIR/staging"
mkdir -p "$STAGING"
cp -R "$APP_BUNDLE" "$STAGING/Nagi.app"
cp -R "$INSTALLER_APP" "$STAGING/Install Nagi.app"

# Hide the staged Nagi.app from Finder — it has to be right next to
# "Install Nagi.app" for that installer's `dirname`-relative lookup to
# find it (see Install Nagi.applescript), but a real, identically-named,
# identically-iconed Nagi.app sitting in the same window as the
# installer invites double-clicking the wrong one, which would run Nagi
# straight off the read-only mounted volume instead of installing it.
# `chflags hidden` (not a dot-prefixed rename) so the installer's path
# lookup doesn't need to change to match.
chflags hidden "$STAGING/Nagi.app"

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
echo "Unsigned, unnotarized — \"Install Nagi.app\" strips the quarantine"
echo "attribute itself before opening Nagi.app, so this doesn't surface"
echo "as a Gatekeeper prompt during that flow. Install Nagi.app itself"
echo "still shows one (it's unsigned too) — see app/README.md's"
echo "\"Prebuilt download\" section for the Control-click / xattr fallback."
