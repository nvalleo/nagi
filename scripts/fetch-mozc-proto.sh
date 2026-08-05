#!/usr/bin/env bash
#
# fetch-mozc-proto.sh — fetch commands.proto and its transitive dependencies
# from a pinned google/mozc tag, then regenerate Swift types with
# protoc-gen-swift.
#
# Idempotent: rerunning with the same MOZC_TAG produces byte-identical
# output in poc/Sources/NagiMozcProto/Generated/.
#
# Requires: curl, protoc, protoc-gen-swift (brew install protobuf swift-protobuf)

set -euo pipefail

# Pinned google/mozc tag. Picked at the start of M0 (latest tag on `master`
# at the time). Bump deliberately — see poc/README.md for why we don't
# track master.
MOZC_TAG="3.34.6239"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POC_DIR="$(cd "$SCRIPT_DIR/.." && pwd)/poc"

# Scratch directory the raw .proto files land in. Not vendored into git —
# see the "Why not vendor" note in poc/Sources/NagiMozcProto/README.md.
PROTO_ROOT="$POC_DIR/.mozc-proto"
OUT_DIR="$POC_DIR/Sources/NagiMozcProto/Generated"

BASE_URL="https://raw.githubusercontent.com/google/mozc/${MOZC_TAG}/src"

# commands.proto's transitive import closure, traced by hand from
# `import` statements in each file. Re-check this list if MOZC_TAG changes
# and protoc starts complaining about missing imports.
PROTO_FILES=(
  "protocol/commands.proto"
  "protocol/candidate_window.proto"
  "protocol/config.proto"
  "protocol/engine_builder.proto"
  "protocol/user_dictionary_storage.proto"
)

for bin in curl protoc protoc-gen-swift; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "error: '$bin' not found on PATH. Try: brew install protobuf swift-protobuf" >&2
    exit 1
  fi
done

echo "Fetching Mozc protos @ ${MOZC_TAG} ..."
rm -rf "$PROTO_ROOT"
mkdir -p "$PROTO_ROOT/protocol"

for f in "${PROTO_FILES[@]}"; do
  echo "  $f"
  curl -fsSL "${BASE_URL}/${f}" -o "${PROTO_ROOT}/${f}"
done

echo "Generating Swift into ${OUT_DIR#$POC_DIR/} ..."
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

proto_paths=()
for f in "${PROTO_FILES[@]}"; do
  proto_paths+=("${PROTO_ROOT}/${f}")
done

protoc \
  --proto_path="$PROTO_ROOT" \
  --swift_out="$OUT_DIR" \
  --swift_opt=Visibility=Public \
  "${proto_paths[@]}"

echo "Done. Generated files:"
find "$OUT_DIR" -name '*.pb.swift' | sed "s|$POC_DIR/|  poc/|"
