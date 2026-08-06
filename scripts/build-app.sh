#!/usr/bin/env bash
#
# build-app.sh — assemble Nagi.app from the `app/` SwiftPM package.
#
# No Xcode project: `swift build` produces a plain Mach-O executable, and
# this script wraps it into a standard app bundle by hand (Contents/MacOS,
# Contents/Info.plist, ad-hoc codesign). See app/README.md for why.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_DIR="$REPO_ROOT/app"

CONFIGURATION="${1:-debug}"
case "$CONFIGURATION" in
  debug|release) ;;
  *)
    echo "usage: $0 [debug|release]" >&2
    exit 64
    ;;
esac

BUILD_DIR="$REPO_ROOT/.build-app"
BUNDLE="$BUILD_DIR/Nagi.app"

echo "Building Nagi ($CONFIGURATION)..."
swift build --package-path "$APP_DIR" -c "$CONFIGURATION"

BINARY="$(swift build --package-path "$APP_DIR" -c "$CONFIGURATION" --show-bin-path)/Nagi"
if [ ! -x "$BINARY" ]; then
  echo "error: built binary not found at $BINARY" >&2
  exit 1
fi

echo "Assembling $BUNDLE ..."
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS"
cp "$BINARY" "$BUNDLE/Contents/MacOS/Nagi"
cp "$APP_DIR/Resources/Info.plist" "$BUNDLE/Contents/Info.plist"

echo "Ad-hoc code-signing (required for InputMethodKit to accept the bundle) ..."
codesign --force --sign - "$BUNDLE"

echo "Done: $BUNDLE"
