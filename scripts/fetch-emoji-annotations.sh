#!/usr/bin/env bash
#
# fetch-emoji-annotations.sh — fetch CLDR emoji annotations (en/ja keyword
# data) and the Unicode emoji-test.txt allowlist, then generate
# app/Resources/emoji-shortcodes.json via generate-emoji-shortcode-dictionary.py.
#
# Idempotent: rerunning with the same CLDR_TAG/EMOJI_TEST_VERSION produces
# byte-identical output.
#
# Requires: curl, python3
#
# Why three sources:
#   - CLDR's basic annotations.json carries hand-curated keywords (English
#     + Japanese) for every codepoint it knows about, not just emoji —
#     plain symbols like "{" have entries too, and it only covers base
#     emoji (no ZWJ sequences like family/profession, no VS16-qualified
#     forms like "❤️").
#   - CLDR's annotationsDerived/annotations.json fills in the rest —
#     algorithmically-derived keywords for ZWJ sequences and skin-tone/
#     hair variants. Confirmed empirically (see generate-emoji-shortcode-
#     dictionary.py) that "family: man, woman, boy" only exists here, not
#     in the basic set.
#   - emoji-test.txt (published separately by Unicode, not CLDR) is the
#     authoritative list of which sequences are actually emoji, used as
#     an allowlist filter in the generator script.
# See #19.

set -euo pipefail

# Pinned CLDR-JSON release tag and Unicode emoji-test.txt version. Bump
# deliberately, together — see poc's MOZC_TAG comment for the same
# reasoning applied here.
CLDR_TAG="48.2.1"
EMOJI_TEST_VERSION="16.0"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Scratch directory the raw CLDR/Unicode files land in. Not vendored into
# git — only the generated app/Resources/emoji-shortcodes.json is used at
# build time, and even that is a build product (see build-app.sh).
FETCH_DIR="$REPO_ROOT/.emoji-fetch"
OUT_FILE="$REPO_ROOT/app/Resources/emoji-shortcodes.json"

CLDR_JSON_ROOT="https://raw.githubusercontent.com/unicode-org/cldr-json/${CLDR_TAG}/cldr-json"
ANNOTATIONS_BASE_URL="${CLDR_JSON_ROOT}/cldr-annotations-full/annotations"
ANNOTATIONS_DERIVED_BASE_URL="${CLDR_JSON_ROOT}/cldr-annotations-derived-full/annotationsDerived"
EMOJI_TEST_URL="https://unicode.org/Public/emoji/${EMOJI_TEST_VERSION}/emoji-test.txt"

for bin in curl python3; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "error: '$bin' not found on PATH." >&2
    exit 1
  fi
done

echo "Fetching CLDR emoji annotations @ ${CLDR_TAG} ..."
rm -rf "$FETCH_DIR"
mkdir -p "$FETCH_DIR"

curl -fsSL "${ANNOTATIONS_BASE_URL}/en/annotations.json" -o "$FETCH_DIR/annotations-en.json"
curl -fsSL "${ANNOTATIONS_BASE_URL}/ja/annotations.json" -o "$FETCH_DIR/annotations-ja.json"
curl -fsSL "${ANNOTATIONS_DERIVED_BASE_URL}/en/annotations.json" -o "$FETCH_DIR/annotations-derived-en.json"
curl -fsSL "${ANNOTATIONS_DERIVED_BASE_URL}/ja/annotations.json" -o "$FETCH_DIR/annotations-derived-ja.json"

echo "Fetching Unicode emoji-test.txt @ ${EMOJI_TEST_VERSION} ..."
curl -fsSL "$EMOJI_TEST_URL" -o "$FETCH_DIR/emoji-test.txt"

echo "Generating $OUT_FILE ..."
python3 "$SCRIPT_DIR/generate-emoji-shortcode-dictionary.py" \
  --annotations-en "$FETCH_DIR/annotations-en.json" \
  --annotations-ja "$FETCH_DIR/annotations-ja.json" \
  --annotations-derived-en "$FETCH_DIR/annotations-derived-en.json" \
  --annotations-derived-ja "$FETCH_DIR/annotations-derived-ja.json" \
  --emoji-test "$FETCH_DIR/emoji-test.txt" \
  --out "$OUT_FILE"

echo "Done: ${OUT_FILE#$REPO_ROOT/}"
