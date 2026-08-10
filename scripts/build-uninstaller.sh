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

# nagi-tis-disable — a small compiled helper that clears the stale
# "ひらがな (Nagi)" Input Sources entry TISDisableInputSource-side after
# removal (#30 follow-up). AppleScript can't call Carbon APIs directly,
# so it shells out to this instead. Built into Contents/Resources/,
# which osacompile's app template already provides.
swiftc -O -o "$OUT_APP/Contents/Resources/nagi-tis-disable" "$SCRIPT_DIR/dmg/nagi-tis-disable.swift"

echo "Done: $OUT_APP"
