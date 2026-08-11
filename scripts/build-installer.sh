#!/usr/bin/env bash
#
# build-installer.sh — compiles scripts/dmg/Install Nagi.applescript
# into a double-clickable "Install Nagi.app" (#30 follow-up). Sidesteps
# a macOS Finder drag-and-drop limitation that made the .dmg's old
# "drag Nagi.app onto the bundled 'Input Methods' symlink" instructions
# silently fail on a real machine — see that .applescript's header for
# the full story.
#
# Usage: build-installer.sh
#
# Produces .build-app/Install Nagi.app. Called by build-dmg.sh, which
# stages the result into the .dmg alongside Nagi.app itself.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT_DIR="$REPO_ROOT/.build-app"
OUT_APP="$OUT_DIR/Install Nagi.app"

mkdir -p "$OUT_DIR"
rm -rf "$OUT_APP"

osacompile -o "$OUT_APP" "$SCRIPT_DIR/dmg/Install Nagi.applescript"

# Nagi's real icon, not a desaturated variant like Uninstall Nagi.app's
# — this app effectively *is* "Nagi, before its first launch", so the
# real mark fits; see build-uninstaller.sh for why the uninstaller goes
# the other way instead. Overwriting applet.icns (CFBundleIconFile in
# the Info.plist osacompile generates) and removing the Assets.car
# osacompile also emits is enough to make macOS use it — see
# build-uninstaller.sh for why both steps are needed.
cp "$REPO_ROOT/app/Resources/icons/Nagi.icns" "$OUT_APP/Contents/Resources/applet.icns"
rm -f "$OUT_APP/Contents/Resources/Assets.car"

# Re-sign: osacompile ad-hoc-signs the bundle it emits, but the icon
# swap above changes bundle contents after that signature was sealed,
# so the Sealed Resources osacompile recorded no longer match reality.
# Left unfixed, this makes Gatekeeper report "a sealed resource is
# missing or invalid" — the "Install Nagi.app is damaged" dialog with
# no GUI bypass, confirmed on a real downloaded-via-browser .dmg. Ad-hoc
# ("-") to match build-app.sh's default; CODESIGN_IDENTITY isn't
# threaded through here since this bundle carries no compiled code of
# its own to protect, just needs a signature that matches its current
# contents.
codesign --force --sign - "$OUT_APP"

echo "Done: $OUT_APP"
