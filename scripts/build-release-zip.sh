#!/usr/bin/env bash
#
# build-release-zip.sh — package Nagi.app as a .zip for the curl-based
# installer (scripts/install-nagi.sh), replacing the earlier .dmg +
# "Install Nagi.app" approach (#30 follow-up).
#
# The .dmg approach was abandoned after real-machine testing found a
# dead end: any ad-hoc signed app (no paid Apple Developer ID, so no
# Developer ID signature or notarization — see app/README.md) that a
# browser marks with com.apple.quarantine is reported by Gatekeeper as
# "is damaged and can't be opened" on macOS 15+, with no Control-click
# / "Open Anyway" GUI bypass at all — unlike a Developer ID-signed but
# unnotarized app, which does get that bypass. No amount of fixing the
# .dmg/installer bundling (a real, separate bug involving stale Sealed
# Resources was found and fixed along the way, but didn't solve this)
# changes that; it's inherent to ad-hoc signing plus quarantine on
# modern macOS.
#
# curl doesn't set com.apple.quarantine on what it downloads (unlike a
# browser) — Gatekeeper's quarantine mount-option enforcement never
# gets involved, and the ad-hoc/notarization warning never triggers.
# So the fix is distribution-channel-level, not code-level:
# scripts/install-nagi.sh downloads this .zip with curl instead of a
# person clicking a browser download link.
#
# `ditto`, not `zip`/`Compress-Archive`-equivalent tools, because it's
# the one Apple documents as preserving what a code-signed .app bundle
# actually needs intact through a zip round-trip: extended attributes,
# resource forks, and the code signature itself (which is sensitive to
# exactly this kind of mangling — see build-installer.sh's/
# build-uninstaller.sh's history of a similar signature-invalidation
# bug for how easy that is to get wrong by accident).
#
# Usage: build-release-zip.sh
#
# Produces .build-release/Nagi.zip. Rebuilds Nagi.app first (same
# release build build-app.sh always produces).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

"$SCRIPT_DIR/build-app.sh" release

APP_BUNDLE="$REPO_ROOT/.build-app/Nagi.app"
OUT_DIR="$REPO_ROOT/.build-release"
OUT_ZIP="$OUT_DIR/Nagi.zip"

mkdir -p "$OUT_DIR"
rm -f "$OUT_ZIP"

echo "Zipping $APP_BUNDLE -> $OUT_ZIP ..."
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$OUT_ZIP"

echo
echo "Done: $OUT_ZIP"
echo
echo "Ad-hoc signed, unnotarized, but that's fine here — this .zip is"
echo "meant to be uploaded as a GitHub Release asset and fetched by"
echo "scripts/install-nagi.sh via curl, which never sets"
echo "com.apple.quarantine (a browser download of this same .zip would"
echo "hit the same Gatekeeper wall Nagi.app itself does; see that"
echo "script's header)."
