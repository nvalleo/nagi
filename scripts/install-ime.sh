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

# Plain-text fallback on non-interactive/no-color terminals — never the
# only way information is conveyed (numbers/checkmarks carry the meaning
# too), just a bit easier to scan when available.
if [ -t 1 ] && command -v tput >/dev/null 2>&1 && [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
  BOLD="$(tput bold)"; DIM="$(tput dim)"; GREEN="$(tput setaf 2)"; RESET="$(tput sgr0)"
else
  BOLD=""; DIM=""; GREEN=""; RESET=""
fi
heading() { printf '\n%s%s%s\n' "$BOLD" "$*" "$RESET"; }
done_step() { printf '  %s✓%s %s\n' "$GREEN" "$RESET" "$*"; }

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
  OTHER_DIR="$HOME/Library/Input Methods"
  SUDO="sudo"
else
  DEST_DIR="$HOME/Library/Input Methods"
  OTHER_DIR="/Library/Input Methods"
  SUDO=""
fi
DEST="$DEST_DIR/Nagi.app"

# Installing to both locations at once is the one confirmed way to get a
# pile of duplicate "ひらがな" entries in Input Sources: macOS registers
# each physical Nagi.app path as its own entry under the same
# TISInputSourceID, and — per the reboot note below — nothing prunes the
# stale one until a full reboot. Warn rather than silently doing it again.
if [ -d "$OTHER_DIR/Nagi.app" ]; then
  echo "warning: Nagi.app is also installed at '$OTHER_DIR/Nagi.app'." >&2
  echo "  Installing to both locations registers duplicate 'ひらがな'" >&2
  echo "  Input Source entries (confirmed after M2). Remove the other" >&2
  echo "  one unless you specifically want both:" >&2
  if [ "$SYSTEM_WIDE" = true ]; then
    echo "    rm -rf \"$OTHER_DIR/Nagi.app\"" >&2
  else
    echo "    sudo rm -rf \"$OTHER_DIR/Nagi.app\"" >&2
  fi
  echo >&2
fi

$SUDO mkdir -p "$DEST_DIR"

echo "Installing to $DEST ..."
$SUDO rm -rf "$DEST"
$SUDO cp -R "$SRC" "$DEST"
# Strip extended attributes (harmless, but rules out quarantine/
# provenance metadata as a variable) and bump mtime.
$SUDO xattr -cr "$DEST"
$SUDO touch "$DEST"

heading "Nagi.app installed to $DEST"
done_step "Built and code-signed"
done_step "Copied into place"

heading "A few manual steps are still needed (macOS, not Nagi, requires these):"
echo "  1. Reboot the machine (logging out and back in is NOT enough —"
echo "     the Text Input Source registry only re-scans on a full boot)."
echo "  2. System Settings > Keyboard > Input Sources > Edit... > '+'"
echo "  3. Find 'Nagi' under Japanese and add it. Watch for duplicate"
echo "     'ひらがな' entries if Google Japanese Input / macSKK etc. are"
echo "     also installed — check the icon to tell them apart."
echo "  4. Switch to it from the menu bar Input menu and try typing"
echo "     'nagi' + Enter in TextEdit — expect 'なぎ'."
echo
echo "NagiConverter itself needs no separate registration step (#30) —"
echo "Nagi.app registers it via SMAppService the first time it actually"
echo "runs, which step 4 above triggers on its own."
if [ "$SYSTEM_WIDE" != true ]; then
  echo
  echo "If it still doesn't show up under Japanese after that, retry with"
  echo "  ./scripts/install-ime.sh $CONFIGURATION --system"
  echo "which installs to /Library/Input Methods/ (system-wide) instead —"
  echo "this is where other installed IMEs on this machine actually live."
fi
echo
echo "${DIM}To reinstall after a code change, rerun this script (uninstall +"
echo "reinstall isn't automatic — use scripts/uninstall-ime.sh for a clean"
echo "slate). A reboot is only needed again if the bundle ID or"
echo "InputMethodConnectionName changed; ordinary code changes are picked"
echo "up by imklaunchagent on the next launch of Nagi.${RESET}"

# Best-effort convenience: land the user on the right System Settings
# pane for step 2 above. Not required — silently does nothing if it
# fails (e.g. no GUI session) rather than treating it as an error, since
# the manual steps printed above are the actual source of truth. The
# pane bundle ID is the one System Settings (Ventura's replacement for
# System Preferences, so this holds for LSMinimumSystemVersion 13.0+)
# uses for Keyboard; there's no documented deep link straight to the
# Input Sources edit sheet.
open "x-apple.systempreferences:com.apple.Keyboard-Settings.extension" >/dev/null 2>&1 || true
