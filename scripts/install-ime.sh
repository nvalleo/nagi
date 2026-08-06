#!/usr/bin/env bash
#
# install-ime.sh — build Nagi.app and register it as an Input Method.
#
# macOS only picks up new entries under ~/Library/Input Methods/ when it
# rescans input sources, which this script can't reliably trigger
# headlessly — see the printed instructions at the end.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

CONFIGURATION="${1:-debug}"
"$SCRIPT_DIR/build-app.sh" "$CONFIGURATION"

SRC="$REPO_ROOT/.build-app/Nagi.app"
DEST_DIR="$HOME/Library/Input Methods"
DEST="$DEST_DIR/Nagi.app"

mkdir -p "$DEST_DIR"

echo "Installing to $DEST ..."
rm -rf "$DEST"
cp -R "$SRC" "$DEST"

echo
echo "Installed. macOS won't notice a new Input Method until you:"
echo "  1. Open System Settings > Keyboard > Input Sources > Edit... > '+'"
echo "  2. Find 'Nagi' under Japanese and add it."
echo "     (If it doesn't show up, log out and back in, then retry —"
echo "     the Input Method registry is only rescanned at login.)"
echo "  3. Switch to it from the menu bar Input menu and try typing"
echo "     'nagi' + Enter in TextEdit — expect 'なぎ'."
echo
echo "To reinstall after a code change, rerun this script (uninstall +"
echo "reinstall isn't automatic; delete '$DEST' by hand if you need a"
echo "clean slate — e.g. after switching input sources away from it)."
