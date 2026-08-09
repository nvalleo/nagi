#!/usr/bin/env bash
#
# build-mozc-server.sh — build our own mozc_server (rebranded "Nagi") from
# a pinned google/mozc tag, so Nagi.app doesn't depend on another Mozc-based
# IME being installed. See issue #9 for the M2b writeup.
#
# What this does, in order:
#   1. Shallow-clone google/mozc at MOZC_TAG into .mozc-build/mozc (once;
#      reused on reruns).
#   2. Apply scripts/mozc-patches/nagi-branding.patch, which rebrands the
#      macOS bundle ID / launchd Mach service name from Mozc's own
#      (org.mozc.inputmethod.Japanese.*) to ours
#      (com.nvleo.inputmethod.nagi.*). Two independent places need this,
#      confirmed the hard way — see the patch's own comment:
#        - src/config.bzl (MACOS_BUNDLE_ID_PREFIX) — reaches Info.plist
#          CFBundleIdentifier only.
#        - src/base/mac/mac_util.mm (kProjectPrefix) — a *hardcoded*
#          literal, unrelated to config.bzl, that
#          ipc/mach_ipc.cc's GetMachPortName() actually uses at runtime to
#          compute the launchd Mach service name. Skipping this one means
#          the built server silently never answers IPC calls (it checks in
#          under the *old* name — no crash, no error, just an eternally
#          idle process — the failure mode that cost most of the time
#          getting M2b working).
#   3. `bazelisk build //server:mozc_server_macos` for arm64 and x86_64
#      (not `bazelisk build package` — that's the full Mozc.pkg installer
#      with GUI tools that need Qt/CMake, which we don't need; the
#      converter server's deps are plain C++, no Qt).
#   4. `lipo` the two into a universal binary at .mozc-build/output/, which
#      build-app.sh copies into Nagi.app/Contents/Resources/ if present.
#
# Requires: full Xcode 16+ (Command Line Tools alone won't build this —
# same requirement as upstream, see mozc's docs/build_mozc_in_osx.md),
# Bazelisk (`brew install bazelisk`), Python 3.12+.
#
# This is a separate, heavier prerequisite than the rest of the repo's
# build (scripts/build-app.sh only needs the Swift toolchain) — expect the
# first run to take several minutes and a few GB of disk for Bazel's
# dependency cache. Reruns are fast (Bazel's action cache).

set -euo pipefail

# Same tag poc/scripts/fetch-mozc-proto.sh pins, kept in sync deliberately
# — see that script for why we don't track master.
MOZC_TAG="3.34.6239"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MOZC_BUILD_DIR="$REPO_ROOT/.mozc-build"
MOZC_SRC="$MOZC_BUILD_DIR/mozc/src"
OUTPUT_DIR="$MOZC_BUILD_DIR/output"
PATCH_FILE="$SCRIPT_DIR/mozc-patches/nagi-branding.patch"

for bin in git bazelisk python3.12; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "error: '$bin' not found on PATH." >&2
    case "$bin" in
      bazelisk) echo "  Try: brew install bazelisk" >&2 ;;
      python3.12) echo "  Try: brew install python@3.12" >&2 ;;
    esac
    exit 1
  fi
done

if [ ! -d "$MOZC_SRC" ]; then
  echo "Cloning google/mozc @ ${MOZC_TAG} ..."
  mkdir -p "$MOZC_BUILD_DIR"
  git clone --branch "$MOZC_TAG" --depth 1 https://github.com/google/mozc.git "$MOZC_BUILD_DIR/mozc"

  echo "Applying ${PATCH_FILE#$REPO_ROOT/} ..."
  (cd "$MOZC_BUILD_DIR/mozc" && git apply "$PATCH_FILE")
else
  echo "Reusing existing checkout at ${MOZC_SRC#$REPO_ROOT/} (delete it to reclone)."
fi

echo "Fetching mozc build dependencies (--noqt: mozc_server doesn't need Qt/GUI) ..."
(cd "$MOZC_SRC" && python3.12 -u build_tools/update_deps.py --noqt)

BUILD_ARCH() {
  local arch="$1"
  echo "Building mozc_server_macos (${arch}) ..."
  (cd "$MOZC_SRC" && bazelisk build //server:mozc_server_macos --config release_build --macos_cpus="$arch")

  rm -rf "$MOZC_BUILD_DIR/extract-$arch"
  mkdir -p "$MOZC_BUILD_DIR/extract-$arch"
  unzip -oq "$MOZC_SRC/bazel-bin/server/mozc_server_macos.zip" -d "$MOZC_BUILD_DIR/extract-$arch"
}

BUILD_ARCH arm64
BUILD_ARCH x86_64

echo "Assembling universal binary at ${OUTPUT_DIR#$REPO_ROOT/} ..."
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"
cp -R "$MOZC_BUILD_DIR/extract-arm64/NagiConverter.app" "$OUTPUT_DIR/NagiConverter.app"
lipo -create \
  "$MOZC_BUILD_DIR/extract-arm64/NagiConverter.app/Contents/MacOS/NagiConverter" \
  "$MOZC_BUILD_DIR/extract-x86_64/NagiConverter.app/Contents/MacOS/NagiConverter" \
  -output "$OUTPUT_DIR/NagiConverter.app/Contents/MacOS/NagiConverter"
lipo -info "$OUTPUT_DIR/NagiConverter.app/Contents/MacOS/NagiConverter"

# Ad-hoc sign, same as build-app.sh does for Nagi itself — a nested .app
# needs its own valid signature regardless of the outer bundle's.
codesign --force --sign "${CODESIGN_IDENTITY:--}" "$OUTPUT_DIR/NagiConverter.app"

echo "Done: ${OUTPUT_DIR#$REPO_ROOT/}/NagiConverter.app"
