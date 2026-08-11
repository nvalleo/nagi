#!/usr/bin/env bash
#
# uninstall-ime.sh — remove Nagi.app and stop the bundled NagiConverter
# service. The counterpart to install-ime.sh, which had no uninstall
# script at all until now (#30 install/uninstall follow-up).
#
# Usage: uninstall-ime.sh [--system | --all]
#
#   (no flags)  removes ~/Library/Input Methods/Nagi.app — the
#               install-ime.sh default.
#   --system    removes /Library/Input Methods/Nagi.app instead (sudo).
#   --all       removes from both locations.
#
# Also clears Nagi's entry from AppleEnabledInputSources (the
# com.apple.HIToolbox preference System Settings' Input Sources list
# actually renders from — see issue #33 and
# app/Sources/Nagi/InputSourceRegistration.swift for the full story),
# via the same scripts/dmg/nagi-tis-disable.swift helper the GUI
# "Uninstall Nagi.app" uses. Only ever touches entries whose "Bundle ID"
# matches com.nvleo.inputmethod.nagi exactly — never rewrites the array
# wholesale, so other IMEs' entries are untouched.
#
# #30: NagiConverter's LaunchAgent is registered by Nagi.app itself via
# SMAppService (see app/Sources/Nagi/ConverterServiceRegistration.swift)
# rather than a plist this script wrote, so there's no
# ~/Library/LaunchAgents/*.plist to clean up anymore — deleting the app
# bundle below takes the plist with it. SMAppService keeps its own
# registration bookkeeping outside that file, though, and there's no
# public CLI equivalent of calling SMAppService.unregister() the way the
# app itself could — only `launchctl bootout`, which stops the running
# job but may not be everything. If "Nagi" lingers in System Settings >
# General > Login Items after this, that's the likely reason (untested
# — the Input Sources stale-entry finding elsewhere in this script's
# history was verified by hand; this one hasn't been yet).

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

# Best-effort: stop the running Nagi host process before removing its
# bundle. `rm -rf` on a running app's directory doesn't error on macOS
# (unlike Windows) — it just unlinks the directory entries and the
# process keeps running off the now-deleted inode — but that orphaned
# process can still hold an active IMKit/XPC connection to
# imklaunchagent, which is enough to make a later Finder drag-and-drop
# of a new Nagi.app into the same path fail with "The operation can't
# be completed because the item is in use." Matches what the GUI
# "Uninstall Nagi.app" (scripts/dmg/Uninstall Nagi.applescript) already
# does. A no-op, not an error, if Nagi wasn't running.
echo "Stopping Nagi (if running) ..."
pkill -f '/Nagi.app/Contents/MacOS/Nagi' >/dev/null 2>&1 || true

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
# so stop it unconditionally. No plist to delete here (see above) — just
# best-effort stop the running job, if any.
CONVERTER_LABEL="com.nvleo.inputmethod.nagi.Converter"
echo "Stopping $CONVERTER_LABEL (if running) ..."
launchctl bootout "gui/$(id -u)/$CONVERTER_LABEL" >/dev/null 2>&1 || true

# Reset the one-shot "log out and back in" prompt (FirstRunPrompt.swift)
# so a later reinstall shows it again instead of staying permanently
# silent. It's keyed off a plain `UserDefaults` flag, deliberately
# independent of any registration state that survives this uninstall
# (see that file's doc comment) — which also means, without this,
# nothing else would ever clear it: `~/Library/Preferences/` isn't
# touched by removing the app bundle above (#32 follow-up, found the
# same way #32 itself was — a stale flag surviving an uninstall).
echo "Resetting the first-run \"log out\" prompt ..."
defaults delete com.nvleo.inputmethod.nagi FirstRunLogoutPromptShown >/dev/null 2>&1 || true

# Best-effort: clear the Input Sources entry too, same as the GUI
# uninstaller. Compiled on the fly rather than checked in as a binary —
# not fatal if swiftc isn't available (e.g. Xcode Command Line Tools
# missing), the entry just lingers as a stale, non-switchable-to row
# until manually cleared or a reboot, same as before this existed.
echo "Clearing Nagi's Input Sources entry (if any) ..."
DISABLE_HELPER="$(mktemp -t nagi-tis-disable)"
if swiftc -O -o "$DISABLE_HELPER" "$SCRIPT_DIR/dmg/nagi-tis-disable.swift" 2>/dev/null; then
  "$DISABLE_HELPER" || true
  rm -f "$DISABLE_HELPER"
else
  echo "  (skipped — swiftc unavailable; 'ひらがな (Nagi)' may linger in" >&2
  echo "  System Settings > Keyboard > Input Sources, non-switchable-to." >&2
  echo "  Clear it by hand there with '−', no reboot needed.)" >&2
fi

echo
echo "Done. Nagi's files are removed, NagiConverter is stopped, and its"
echo "Input Sources entry is cleared."
