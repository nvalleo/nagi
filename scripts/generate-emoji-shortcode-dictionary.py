#!/usr/bin/env python3
"""generate-emoji-shortcode-dictionary.py

Builds app/Resources/emoji-shortcodes.json from:
  - CLDR basic annotations (en/ja) — hand-curated keyword data, but only
    for base emoji: no ZWJ sequences (family/profession combos), no
    VS16-qualified forms (e.g. "❤️" as opposed to bare "❤").
  - CLDR annotationsDerived (en/ja) — algorithmically-derived keywords
    that fill in exactly those two gaps.
  - Unicode emoji-test.txt — the authoritative list of which codepoint
    sequences are actually emoji, used here purely as an allowlist filter.
    `component` entries (skin tone / hair modifiers in isolation) are
    excluded: they're not meaningful standalone search results.

Lookup order per emoji-test.txt entry: try the exact fully-qualified
string against both annotation sources first, then retry with VS16
(U+FE0F) stripped — CLDR's keys are inconsistent about whether they carry
it, confirmed empirically against both datasets.

Output is a JSON array, ordered the same as emoji-test.txt (Unicode's own
CLDR-derived grouping — smileys, people, animals, ... in that order, which
reads better than codepoint order for a candidate list):

  [{"emoji": "😀", "keywords": ["grinning face", "face", "grin", "grinning",
    "にっこり", "笑顔", ...]}, ...]

See scripts/fetch-emoji-annotations.sh, which fetches the three input
files and invokes this script.
"""

import argparse
import json
import re
import sys

EMOJI_TEST_LINE = re.compile(
    r"^([0-9A-Fa-f ]+?)\s*;\s*(fully-qualified|minimally-qualified|unqualified|component)\s*#"
)


def load_emoji_order(path):
    """Returns emoji strings in emoji-test.txt's own order, deduplicated,
    skipping `component`-status entries (see module docstring)."""
    seen = set()
    order = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            match = EMOJI_TEST_LINE.match(line)
            if not match:
                continue
            codepoints, status = match.groups()
            if status == "component":
                continue
            emoji = "".join(chr(int(cp, 16)) for cp in codepoints.split())
            if emoji not in seen:
                seen.add(emoji)
                order.append(emoji)
    return order


def load_keywords(path):
    """Returns {emoji: [keyword, ...]} from one CLDR annotations.json or
    annotationsDerived/annotations.json (same inner shape, different top-
    level key), `tts` (the descriptive name) first, then `default`
    (individual keywords), in the file's own order."""
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    root = data.get("annotations", data.get("annotationsDerived"))
    raw = root["annotations"]
    result = {}
    for emoji, entry in raw.items():
        keywords = list(entry.get("tts", [])) + list(entry.get("default", []))
        if keywords:
            result[emoji] = keywords
    return result


def dedupe_preserve_order(items):
    seen = set()
    out = []
    for item in items:
        if item not in seen:
            seen.add(item)
            out.append(item)
    return out


VS16 = "️"


def keywords_for(emoji, *sources):
    """Looks `emoji` up in each of `sources` (dicts of {emoji: [keyword,
    ...]}), trying the exact string first and then with VS16 stripped —
    see module docstring. Merges hits from every source/variant, in the
    order given."""
    variants = [emoji]
    if VS16 in emoji:
        variants.append(emoji.replace(VS16, ""))
    keywords = []
    for source in sources:
        for variant in variants:
            keywords += source.get(variant, [])
    return dedupe_preserve_order(keywords)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--annotations-en", required=True)
    parser.add_argument("--annotations-ja", required=True)
    parser.add_argument("--annotations-derived-en", required=True)
    parser.add_argument("--annotations-derived-ja", required=True)
    parser.add_argument("--emoji-test", required=True)
    parser.add_argument("--out", required=True)
    args = parser.parse_args()

    emoji_order = load_emoji_order(args.emoji_test)
    keywords_en = load_keywords(args.annotations_en)
    keywords_ja = load_keywords(args.annotations_ja)
    keywords_derived_en = load_keywords(args.annotations_derived_en)
    keywords_derived_ja = load_keywords(args.annotations_derived_ja)

    entries = []
    skipped = 0
    for emoji in emoji_order:
        keywords = keywords_for(emoji, keywords_en, keywords_derived_en, keywords_ja, keywords_derived_ja)
        if not keywords:
            # No CLDR annotation for this emoji (rare — usually a very
            # recently added codepoint CLDR hasn't caught up to yet).
            # Unsearchable, so not worth including.
            skipped += 1
            continue
        entries.append({"emoji": emoji, "keywords": keywords})

    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(entries, f, ensure_ascii=False, separators=(",", ":"))

    print(f"Wrote {len(entries)} emoji ({skipped} skipped, no annotation) to {args.out}", file=sys.stderr)


if __name__ == "__main__":
    main()
