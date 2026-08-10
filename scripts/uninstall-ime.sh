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
# Does NOT touch the Text Input Source registry (com.apple.HIToolbox)
# directly — that's a private format and editing it by hand risks
# corrupting entries for other IMEs. Only the app bundle is removed and
# the currently-running NagiConverter job stopped; macOS is left to
# notice the backing bundle is gone on its own.
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
#
# It won't notice on its own without a reboot — confirmed (#30 install/
# uninstall follow-up): a plain `rm -rf` of Nagi.app leaves "ひらがな
# (Nagi)" listed in System Settings' Input Sources, just no longer
# switchable to. But removing that stale entry by hand with the "−"
# button in System Settings works immediately, no reboot needed — also
# confirmed. See docs/architecture.md's "Mozc IPC" section for the full
# note, including why Google 日本語入力's own uninstaller doesn't show
# the same stale entry (it likely does the "−" button's deregistration
# itself before deleting files, not just `rm -rf`).

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
# so stop it unconditionally. No plist to delete here (see above) — just
# best-effort stop the running job, if any.
CONVERTER_LABEL="com.nvleo.inputmethod.nagi.Converter"
echo "Stopping $CONVERTER_LABEL (if running) ..."
launchctl bootout "gui/$(id -u)/$CONVERTER_LABEL" >/dev/null 2>&1 || true

echo
echo "Done. Nagi's files are removed and NagiConverter is stopped."
echo
echo "'ひらがな (Nagi)' will still show up in System Settings > Keyboard >"
echo "Input Sources — it just won't be switchable to anymore (confirmed"
echo "behavior, not a bug: see docs/architecture.md, 'Mozc IPC'). To"
echo "clear the stale entry, no reboot needed:"
echo "  System Settings > Keyboard > Input Sources > Edit... > select"
echo "  'ひらがな (Nagi)' > '−'. Confirmed this clears it immediately."
echo "  (A reboot also clears it, same as it does for additions, if"
echo "  removing it by hand isn't an option for some reason.)"
