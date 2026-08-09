#!/usr/bin/env bash
#
# build-app.sh — assemble Nagi.app from the `app/` SwiftPM package.
#
# No Xcode project: `swift build` produces a plain Mach-O executable, and
# this script wraps it into a standard app bundle by hand (Contents/MacOS,
# Contents/Info.plist, ad-hoc codesign). See app/README.md for why.
#
# Debugging "installs fine, never appears in Input Sources" here took
# weeks. Two confirmed, reproducible requirements (both silent — no
# error anywhere, so there's nothing to grep for if you hit this
# again):
#
#   1. Must be a `release` build. `debug` builds carry an auto-generated
#      com.apple.security.get-task-allow entitlement, and a bundle
#      whose binary has that entitlement is silently never added to
#      the Text Input Source registry (imklaunchagent still accepts
#      its XPC connection at runtime — that part looks fine — but the
#      separate registration step that makes it selectable in System
#      Settings never happens).
#   2. CFBundleIdentifier (and, by extension, every TISInputSourceID
#      under it) must contain the literal substring ".inputmethod."
#      — confirmed by bisecting against every known-working IMKit
#      bundle on the machine (Apple's own /System/Library/Input
#      Methods/AinuIM.app, Google Japanese Input, macSKK — all of
#      them use this token) and finding the literal string embedded
#      in imklaunchagent/HIToolbox's string table. Bundle IDs without
#      it are silently never added to the registry no matter what
#      else is correct. Note the change only takes effect after a
#      full reboot — logging out and back in isn't enough to make
#      the registry re-scan pick up a bundle ID it's seen before.
#
# (Earlier theories blamed binary vs XML plist format and thin vs
# universal binaries — both were red herrings from confounded test
# runs; disregard if you find old comments mentioning them.)
#
# Built as a universal (arm64+x86_64) binary via `lipo` since that's
# what every shipped third-party IME on this machine happens to be —
# no confirmed downside, and it's what a real release build would ship
# as anyway. `swift build --arch arm64 --arch x86_64` in one shot needs
# xcbuild (no Xcode here), so each slice is built separately.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_DIR="$REPO_ROOT/app"

# M2: Nagi depends on poc/'s NagiMozcIPC (a local SwiftPM package
# dependency, see app/Package.swift) for real Mozc conversion. Its
# NagiMozcProto target's sources are generated, not checked in (see
# .gitignore) — fail with a clear message instead of a confusing SwiftPM
# "no such file" error deep in the build.
if [ ! -d "$REPO_ROOT/poc/Sources/NagiMozcProto/Generated" ]; then
  echo "error: poc/Sources/NagiMozcProto/Generated is missing." >&2
  echo "  Run ./scripts/fetch-mozc-proto.sh first (see poc/README.md)." >&2
  exit 1
fi

CONFIGURATION="${1:-release}"
case "$CONFIGURATION" in
  debug)
    echo "warning: debug builds never show up as an Input Source (see" >&2
    echo "  the get-task-allow note at the top of this script) — only" >&2
    echo "  useful here for testing that the code compiles/runs, not" >&2
    echo "  for actually installing as an IME. Use 'release' for that." >&2
    ;;
  release) ;;
  *)
    echo "usage: $0 [debug|release]" >&2
    exit 64
    ;;
esac

BUILD_DIR="$REPO_ROOT/.build-app"
BUNDLE="$BUILD_DIR/Nagi.app"

echo "Building Nagi ($CONFIGURATION, arm64)..."
swift build --package-path "$APP_DIR" -c "$CONFIGURATION" --arch arm64
ARM64_BINARY="$(swift build --package-path "$APP_DIR" -c "$CONFIGURATION" --arch arm64 --show-bin-path)/Nagi"

echo "Building Nagi ($CONFIGURATION, x86_64)..."
swift build --package-path "$APP_DIR" -c "$CONFIGURATION" --arch x86_64
X86_64_BINARY="$(swift build --package-path "$APP_DIR" -c "$CONFIGURATION" --arch x86_64 --show-bin-path)/Nagi"

for bin in "$ARM64_BINARY" "$X86_64_BINARY"; do
  if [ ! -x "$bin" ]; then
    echo "error: built binary not found at $bin" >&2
    exit 1
  fi
done

echo "Assembling $BUNDLE ..."
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS"
lipo -create "$ARM64_BINARY" "$X86_64_BINARY" -output "$BUNDLE/Contents/MacOS/Nagi"
cp "$APP_DIR/Resources/Info.plist" "$BUNDLE/Contents/Info.plist"
printf 'APPL????' > "$BUNDLE/Contents/PkgInfo"
mkdir -p "$BUNDLE/Contents/Resources"
if [ -d "$APP_DIR/Resources/icons" ]; then
  cp "$APP_DIR/Resources/icons/"* "$BUNDLE/Contents/Resources/"
fi
if [ -f "$APP_DIR/Resources/InfoPlist.strings" ]; then
  # Display names for the Input Source picker — without this, macOS
  # falls back to showing the raw TISInputSourceID string instead of
  # "Nagi"/"ひらがな" (confirmed against macSKK's own copy of this
  # file, which follows the same CFBundleName + per-mode-ID pattern).
  cp "$APP_DIR/Resources/InfoPlist.strings" "$BUNDLE/Contents/Resources/"
fi

# CODESIGN_IDENTITY overrides the default ad-hoc ("-") signature — set
# it to a `security find-identity -v -p codesigning` SHA1 hash to sign
# with a real identity (e.g. an Apple Development or Developer ID
# certificate) instead.
IDENTITY="${CODESIGN_IDENTITY:--}"
echo "Code-signing with identity '$IDENTITY' ..."
codesign --force --sign "$IDENTITY" "$BUNDLE"

echo "Done: $BUNDLE"
