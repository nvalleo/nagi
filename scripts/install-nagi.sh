#!/usr/bin/env bash
#
# install-nagi.sh — one-line installer for people who just want Nagi
# running, without building from source or fighting Gatekeeper by hand
# (#30 follow-up, replacing the earlier .dmg + "Install Nagi.app"
# approach — see build-release-zip.sh for why that was abandoned).
#
#   curl -fsSL https://github.com/nv-leo/nagi/releases/latest/download/install-nagi.sh | bash
#
# Downloads the latest release's Nagi.zip with curl (which — unlike a
# browser — never sets com.apple.quarantine on what it fetches, so the
# ad-hoc-signed, unnotarized Nagi.app it contains never hits the "is
# damaged, no GUI bypass" Gatekeeper wall a browser download would),
# unzips it, and installs to /Library/Input Methods/ (system-wide,
# matching the old .dmg's target — scripts/install-ime.sh's per-user
# default remains available for anyone building from source instead).
#
# Prefer not to pipe a script straight into a shell without reading it
# first? Entirely reasonable — download it, read it, then run it:
#   curl -fsSLO https://github.com/nv-leo/nagi/releases/latest/download/install-nagi.sh
#   less install-nagi.sh
#   bash install-nagi.sh
#
# Asks for your admin password once (via sudo, for the
# /Library/Input Methods/ write) — nothing else needs elevated
# privileges. Safe to rerun to update to a newer release; stops any
# running Nagi process first so the copy below doesn't fail with
# "resource busy" (same reasoning as uninstall-ime.sh).

set -euo pipefail

REPO="nv-leo/nagi"
# Overridable for testing against a pre-release (GitHub's own
# releases/latest/download/ redirect skips anything marked
# "Pre-release", so it 404s until a release is promoted to Latest):
#   NAGI_ZIP_URL="https://github.com/nv-leo/nagi/releases/download/vX.Y.Z/Nagi.zip" \
#     curl -fsSL .../install-nagi.sh | bash
ZIP_URL="${NAGI_ZIP_URL:-https://github.com/$REPO/releases/latest/download/Nagi.zip}"
DEST_DIR="/Library/Input Methods"
DEST="$DEST_DIR/Nagi.app"

# Plain-text fallback on non-interactive/no-color terminals, same as
# install-ime.sh.
if [ -t 1 ] && command -v tput >/dev/null 2>&1 && [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
  BOLD="$(tput bold)"; GREEN="$(tput setaf 2)"; RESET="$(tput sgr0)"
else
  BOLD=""; GREEN=""; RESET=""
fi
heading() { printf '\n%s%s%s\n' "$BOLD" "$*" "$RESET"; }
done_step() { printf '  %s✓%s %s\n' "$GREEN" "$RESET" "$*"; }

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

echo "Downloading Nagi from $ZIP_URL ..."
curl -fsSL "$ZIP_URL" -o "$WORK_DIR/Nagi.zip"

echo "Extracting ..."
ditto -x -k "$WORK_DIR/Nagi.zip" "$WORK_DIR"

if [ ! -d "$WORK_DIR/Nagi.app" ]; then
  echo "error: Nagi.app not found inside Nagi.zip after extracting — the" >&2
  echo "release asset's shape may have changed; please file an issue." >&2
  exit 1
fi

# Best-effort: stop any already-running instance before overwriting it
# — an orphaned process holding an IMKit/XPC connection can make the
# copy below fail with "resource busy" (same reasoning as
# uninstall-ime.sh).
pkill -f '/Nagi.app/Contents/MacOS/Nagi' >/dev/null 2>&1 || true

echo "Installing to $DEST (this needs your admin password — $DEST_DIR is a system folder) ..."
sudo mkdir -p "$DEST_DIR"
sudo rm -rf "$DEST"
sudo cp -R "$WORK_DIR/Nagi.app" "$DEST"
# Strip extended attributes (harmless here since curl never quarantines
# anything, but rules it out as a variable — same belt-and-suspenders
# move install-ime.sh makes) and bump mtime.
sudo xattr -cr "$DEST"
sudo touch "$DEST"

echo "Launching Nagi ..."
open "$DEST"

heading "Nagi.app installed to $DEST"
done_step "Downloaded and installed"
done_step "Launched — first-run setup (NagiConverter + Text Input Source"
echo "    self-registration) runs automatically from here"

heading "One manual step left (macOS, not Nagi, requires this):"
echo "  Log out and back in once — Nagi only becomes selectable in System"
echo "  Settings > Keyboard > Input Sources, the menu bar, and its"
echo "  conversion engine alike, at the next login, not immediately. No"
echo "  full restart needed, just a log out — the same one-time step"
echo "  Google 日本語入力 and other third-party macOS IMEs also require."
echo
echo "After logging back in: System Settings > Keyboard > Input Sources"
echo "should already list \"Nagi\" under Japanese — no \"+\" needed. Switch"
echo "to it from the menu bar Input menu and try typing \"nagi\" + Enter in"
echo "TextEdit — expect \"なぎ\"."
echo
echo "To uninstall later: double-click \"Uninstall Nagi.app\" in"
echo "/Applications/ (deployed there automatically on Nagi's first"
echo "launch, i.e. by the \"Launching Nagi ...\" step just above), or run"
echo "scripts/uninstall-ime.sh from a clone of the repo if you have one."
