#!/usr/bin/env bash
#
# install-ime.sh — build Nagi.app and register it as an Input Method.
#
# macOS only picks up new/changed Input Method registrations after a
# full reboot — logging out and back in is NOT enough, even though
# that's the commonly-cited advice. See build-app.sh for the other
# hard-won requirements (release build, ".inputmethod." in the bundle
# ID) that have to be right before a reboot is even worth trying.
#
# Usage: install-ime.sh [debug|release] [--system]
#
#   --system installs to /Library/Input Methods/ (system-wide) instead
#   of the per-user ~/Library/Input Methods/. Verified working under
#   --system; per-user was never re-verified after the ".inputmethod."
#   fix (an earlier, since-superseded finding claimed per-user doesn't
#   get picked up at all — that finding predates the real root cause,
#   so it's untrusted but left as the default-suspect path).
#
#   The build itself always runs as the invoking user (not root), even
#   under --system, so `.build`/`.build-app` don't end up root-owned —
#   only the final copy into /Library/Input Methods/ needs elevation,
#   and this script prompts for it via `sudo` itself. Don't run the
#   whole script with `sudo`.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

CONFIGURATION="release"
SYSTEM_WIDE=false
for arg in "$@"; do
  case "$arg" in
    debug|release) CONFIGURATION="$arg" ;;
    --system) SYSTEM_WIDE=true ;;
    *)
      echo "usage: $0 [debug|release] [--system]" >&2
      exit 64
      ;;
  esac
done

"$SCRIPT_DIR/build-app.sh" "$CONFIGURATION"

SRC="$REPO_ROOT/.build-app/Nagi.app"
if [ "$SYSTEM_WIDE" = true ]; then
  DEST_DIR="/Library/Input Methods"
  SUDO="sudo"
else
  DEST_DIR="$HOME/Library/Input Methods"
  SUDO=""
fi
DEST="$DEST_DIR/Nagi.app"

$SUDO mkdir -p "$DEST_DIR"

echo "Installing to $DEST ..."
$SUDO rm -rf "$DEST"
$SUDO cp -R "$SRC" "$DEST"
# Strip extended attributes (harmless, but rules out quarantine/
# provenance metadata as a variable) and bump mtime.
$SUDO xattr -cr "$DEST"
$SUDO touch "$DEST"

echo
echo "Installed. macOS won't notice a new/changed Input Method until you:"
echo "  1. Reboot the machine (logging out and back in is NOT enough —"
echo "     the Text Input Source registry only re-scans on a full boot)."
echo "  2. Open System Settings > Keyboard > Input Sources > Edit... > '+'"
echo "  3. Find 'Nagi' under Japanese and add it. Watch for duplicate"
echo "     'ひらがな' entries if Google Japanese Input / macSKK etc. are"
echo "     also installed — check the icon to tell them apart."
echo "  4. Switch to it from the menu bar Input menu and try typing"
echo "     'nagi' + Enter in TextEdit — expect 'なぎ'."
if [ "$SYSTEM_WIDE" != true ]; then
  echo
  echo "If it still doesn't show up under Japanese after that, retry with"
  echo "  ./scripts/install-ime.sh $CONFIGURATION --system"
  echo "which installs to /Library/Input Methods/ (system-wide) instead —"
  echo "this is where other installed IMEs on this machine actually live."
fi
echo
echo "To reinstall after a code change, rerun this script (uninstall +"
echo "reinstall isn't automatic; delete '$DEST' by hand if you need a"
echo "clean slate — e.g. after switching input sources away from it). A"
echo "reboot is only needed again if the bundle ID or"
echo "InputMethodConnectionName changed; ordinary code changes are"
echo "picked up by imklaunchagent on the next launch of Nagi."
