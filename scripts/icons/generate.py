#!/usr/bin/env python3
"""generate.py — regenerate Nagi's icon SVG sources (issue #25).

Writes scripts/icons/src/app-icon.svg (1024x1024, for Nagi.icns — Dock/
Finder) and scripts/icons/src/badge.svg (256x256, downsampled to 32/16 for
nagi.tiff — the menu bar / input-source-list icon).

The mark: a sun (the light of the momentary calm that "凪" names — dawn or
dusk, when the land and sea breezes swap and the wind briefly dies) over
two horizontal strokes whose amplitude decreases top to bottom, i.e. the
wind dying down into a flat, calm sea. Both SVGs use the same two-stroke
mark (an earlier three-stroke version of app-icon.svg looked like a
different icon once shrunk down to badge size, which defeats the point of
a badge — see issue #25) — only the canvas and stroke weight scale up.

Badge geometry (dark rounded-square background nearly filling the frame,
bold white glyph) intentionally matches Apple's own IME mode icons —
confirmed against /System/Library/Input Methods/JapaneseIM-RomajiTyping.app
and AinuIM.app's own Hiragana.tiff/Ainu.tiff, both dark badge + white glyph,
not a transparent template image.

Palette ("Twilight Navy", picked over three other options — see issue #25):
  ink       #14202E  background, top of the vertical gradient
  ink-deep  #0F1822  background, bottom of the vertical gradient
  pale      #F4ECDE  the wave strokes / badge glyph
  gold      #E7C08A  the sun

Re-run after any tweak here, then `scripts/build-icons.sh` to rasterize.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from wave import wave_path

INK = "#14202E"
INK_DEEP = "#0F1822"
PALE = "#F4ECDE"
GOLD = "#E7C08A"

OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "src")


def app_icon_svg():
    size = 1024
    r = 229  # ~22.4%, matching macOS's Big-Sur-era squircle-ish icon radius
    cx = size / 2

    sun_cy, sun_r = 300, 42
    w1 = wave_path(cx, 500, 560, 70, 1.0, samples=56)
    w2 = wave_path(cx, 660, 560, 18, 1.0, samples=48)

    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" viewBox="0 0 {size} {size}">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="{INK}"/>
      <stop offset="1" stop-color="{INK_DEEP}"/>
    </linearGradient>
  </defs>
  <rect x="0" y="0" width="{size}" height="{size}" rx="{r}" ry="{r}" fill="url(#bg)"/>
  <circle cx="{cx}" cy="{sun_cy}" r="{sun_r}" fill="{GOLD}"/>
  <path d="{w1}" fill="none" stroke="{PALE}" stroke-width="44" stroke-linecap="round"/>
  <path d="{w2}" fill="none" stroke="{PALE}" stroke-width="44" stroke-linecap="round"/>
</svg>
'''


def badge_svg():
    # Designed at 256 canvas, downsampled to 32/16 for crisp anti-aliasing.
    # Same two-stroke mark as app-icon.svg — see module docstring.
    size = 256
    r = 40
    cx = size / 2

    sun_cy, sun_r = 68, 16
    w1 = wave_path(cx, 152, 168, 26, 1.0, samples=48)
    w2 = wave_path(cx, 202, 168, 7, 1.0, samples=40)

    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" viewBox="0 0 {size} {size}">
  <rect x="0" y="0" width="{size}" height="{size}" rx="{r}" ry="{r}" fill="{INK}"/>
  <circle cx="{cx}" cy="{sun_cy}" r="{sun_r}" fill="{GOLD}"/>
  <path d="{w1}" fill="none" stroke="{PALE}" stroke-width="22" stroke-linecap="round"/>
  <path d="{w2}" fill="none" stroke="{PALE}" stroke-width="22" stroke-linecap="round"/>
</svg>
'''


if __name__ == "__main__":
    os.makedirs(OUT_DIR, exist_ok=True)
    app_path = os.path.join(OUT_DIR, "app-icon.svg")
    badge_path = os.path.join(OUT_DIR, "badge.svg")
    with open(app_path, "w") as f:
        f.write(app_icon_svg())
    with open(badge_path, "w") as f:
        f.write(badge_svg())
    print(f"wrote {app_path}")
    print(f"wrote {badge_path}")
