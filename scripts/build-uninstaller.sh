#!/usr/bin/env bash
#
# build-uninstaller.sh — compiles scripts/dmg/Uninstall Nagi.applescript
# into a double-clickable "Uninstall Nagi.app" (#30 follow-up). GUI
# counterpart to scripts/uninstall-ime.sh, for people who installed via
# the .dmg and don't have/want a Terminal — see that .applescript's
# header for what it actually does.
#
# Usage: build-uninstaller.sh
#
# Produces .build-app/Uninstall Nagi.app. Called by build-dmg.sh, which
# stages the result into the .dmg alongside Nagi.app itself.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT_DIR="$REPO_ROOT/.build-app"
OUT_APP="$OUT_DIR/Uninstall Nagi.app"

mkdir -p "$OUT_DIR"
rm -rf "$OUT_APP"

osacompile -o "$OUT_APP" "$SCRIPT_DIR/dmg/Uninstall Nagi.applescript"

# Use a desaturated variant of Nagi's own icon instead of osacompile's
# default AppleScript applet icon (a generic scroll) — same mark, gray
# instead of "Twilight Navy", so this doesn't look unrelated/unbranded
# next to Nagi.app in the .dmg, but also isn't mistakable for the real
# app at a glance (scripts/icons/generate.py, #30 follow-up). Overwriting
# applet.icns (CFBundleIconFile in the Info.plist osacompile generates)
# is enough on its own, but osacompile also emits an Assets.car asset
# catalog wrapping the same default icon under CFBundleIconName, which
# newer macOS prefers over the loose .icns when both are present —
# removing it forces the applet.icns fallback to actually be used.
cp "$REPO_ROOT/app/Resources/icons/Uninstall-Nagi.icns" "$OUT_APP/Contents/Resources/applet.icns"
rm -f "$OUT_APP/Contents/Resources/Assets.car"

# nagi-tis-disable — a small compiled helper that removes Nagi's entry
# from AppleEnabledInputSources after removal (#30 follow-up — see
# app/Sources/Nagi/InputSourceRegistration.swift for why that's the
# mechanism that actually works, not TISDisableInputSource). AppleScript
# can't call CoreFoundation preference APIs directly, so it shells out to
# this instead. Built into Contents/Resources/, which osacompile's app
# template already provides.
swiftc -O -o "$OUT_APP/Contents/Resources/nagi-tis-disable" "$SCRIPT_DIR/dmg/nagi-tis-disable.swift"

# Re-sign: osacompile ad-hoc-signs the bundle it emits, but the icon
# swap and nagi-tis-disable addition above change bundle contents after
# that signature was sealed, so the Sealed Resources osacompile recorded
# no longer match reality. Left unfixed, this makes Gatekeeper report "a
# sealed resource is missing or invalid" — an "is damaged" dialog with
# no GUI bypass (found via Install Nagi.app's build script sharing this
# exact bug, confirmed on a real downloaded-via-browser .dmg — this
# script was never actually exercised through a real download before
# that). Ad-hoc ("-") to match build-app.sh's default.
codesign --force --sign - "$OUT_APP"

echo "Done: $OUT_APP"
