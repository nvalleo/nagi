#!/usr/bin/env bash
#
# uninstall-ime.sh — remove Nagi.app and stop the bundled NagiConverter
# service. The counterpart to install-ime.sh, which had no uninstall
# script at all until now (#25 install/uninstall follow-up).
#
# Usage: uninstall-ime.sh [--system | --all]
#
#   (no flags)  removes ~/Library/Input Methods/Nagi.app — the
#               install-ime.sh default.
#   --system    removes /Library/Input Methods/Nagi.app instead (sudo).
#   --all       removes from both locations.
#
# Does NOT touch the Text Input Source registry (com.apple.HIToolbox)
# directly — that's a private format and editing it by hand risks
# corrupting entries for other IMEs. Only the app bundle and the
# NagiConverter LaunchAgent are removed here; macOS is left to notice
# the backing bundle is gone on its own.
#
# That noticing needs a reboot, same as additions do — confirmed (#25
# install/uninstall follow-up): a plain `rm -rf` of Nagi.app leaves
# "ひらがな (Nagi)" listed in System Settings' Input Sources, just no
# longer switchable to. See docs/architecture.md's "Mozc IPC" section
# for the full note, including why Google 日本語入力's own uninstaller
# doesn't show the same stale entry (it likely deregisters via TIS
# before deleting files, not just `rm -rf`).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TARGET="user"
for arg in "$@"; do
  case "$arg" in
    --system) TARGET="system" ;;
    --all) TARGET="all" ;;
    *)
      echo "usage: $0 [--system | --all]" >&2
      exit 64
      ;;
  esac
done

USER_DIR="$HOME/Library/Input Methods"
SYSTEM_DIR="/Library/Input Methods"

remove_bundle() {
  local dir="$1" sudo_prefix="$2"
  local bundle="$dir/Nagi.app"
  if [ -d "$bundle" ]; then
    echo "Removing $bundle ..."
    $sudo_prefix rm -rf "$bundle"
  else
    echo "Not installed at $bundle — nothing to remove there."
  fi
}

case "$TARGET" in
  user) remove_bundle "$USER_DIR" "" ;;
  system) remove_bundle "$SYSTEM_DIR" "sudo" ;;
  all)
    remove_bundle "$USER_DIR" ""
    remove_bundle "$SYSTEM_DIR" "sudo"
    ;;
esac

# The NagiConverter LaunchAgent is always per-user (see install-ime.sh),
# regardless of which Input Methods directory Nagi.app itself came from,
# so stop and remove it unconditionally.
CONVERTER_LABEL="com.nvleo.inputmethod.nagi.Converter"
CONVERTER_PLIST="$HOME/Library/LaunchAgents/$CONVERTER_LABEL.plist"

if [ -f "$CONVERTER_PLIST" ]; then
  echo "Stopping $CONVERTER_LABEL ..."
  launchctl bootout "gui/$(id -u)/$CONVERTER_LABEL" >/dev/null 2>&1 || true
  rm -f "$CONVERTER_PLIST"
else
  echo "$CONVERTER_LABEL is not registered — nothing to stop."
fi

echo
echo "Done. Nagi's files are removed and NagiConverter is stopped."
echo
echo "'ひらがな (Nagi)' will likely still show up in System Settings >"
echo "Keyboard > Input Sources — it just won't be switchable to anymore"
echo "(confirmed behavior, not a bug: see docs/architecture.md, 'Mozc"
echo "IPC'). To clear the stale entry:"
echo "  1. Select it and remove it with the '−' button, if System"
echo "     Settings lets you (worth trying first — it's the faster"
echo "     path if it works)."
echo "  2. Otherwise, reboot — the same fallback install-ime.sh"
echo "     documents for additions clears stale removals too."
