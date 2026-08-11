#!/usr/bin/env python3
"""generate.py — regenerate Nagi's icon SVG sources (issue #25).

Writes scripts/icons/src/app-icon.svg (1024x1024, for Nagi.icns — Dock/
Finder), scripts/icons/src/badge.svg (256x256, downsampled to 32/16 for
nagi.tiff — the menu bar / input-source-list icon), and
scripts/icons/src/uninstaller-icon.svg (1024x1024, for
Uninstall-Nagi.icns — #30 follow-up: same mark and geometry as
app-icon.svg, desaturated, so "Uninstall Nagi.app" doesn't sit next to
Nagi.app in the .dmg looking like an unrelated, unbranded utility, but
also isn't mistakable for the real app at a glance).

The mark: a sun (the light of the momentary calm that "凪" names — dawn or
dusk, when the land and sea breezes swap and the wind briefly dies) over
two horizontal strokes whose amplitude decreases top to bottom, i.e. the
wind dying down into a flat, calm sea. Both SVGs use the same two-stroke
mark (an earlier three-stroke version of app-icon.svg looked like a
different icon once shrunk down to badge size, which defeats the point of
a badge — see issue #25) — only the canvas and stroke weight scale up.

Badge geometry (rounded-square badge nearly filling the frame, with the
sun + wave mark cut out of it as transparent holes, not painted on top of
it) intentionally matches Apple's own IME mode icons — confirmed against
/System/Library/Input Methods/JapaneseIM-RomajiTyping.app and AinuIM.app's
own Hiragana.tiff/Ainu.tiff. Both are read under `TISIconIsTemplate =
true` (see Info.plist — needed for CustomIcon below, the Input Sources
list row's icon, to render at all), which is a bundle-wide flag: the
system discards all RGB and repaints using only alpha as a mask. An
earlier version of this file got that backwards — filled the badge shape
*and* painted an opaque colored glyph on top of it, i.e. alpha==1 across
virtually the whole frame — which the real machine renders as an
undifferentiated solid-tinted square: the glyph's outline needs to *be*
alpha, not color, or its shape carries no information after tinting
(issue #35 follow-up, where nagi.tiff's real-machine appearance was
finally checked against this, rather than just checked for visual
correctness in isolation). Dropping TISIconIsTemplate entirely instead
(to keep this file's real color, Google 日本語入力-style) was also tried
— broke the list row's CustomIcon without fixing the menu bar badge
either; reverted. Unlike the list row (which re-reads its icon live —
every asset swap during that investigation showed up there immediately,
no logout needed), the menu bar badge stayed blank regardless of what
was tried here, for a reason unrelated to color/alpha at all: a changed
icon for an already-registered Text Input Source only gets picked up by
the menu bar at the next login (see InputSourceRegistration.swift) —
relaunching Nagi or toggling other input sources doesn't do it. Confirmed
working after a real logout/login, once this alpha-cutout redraw was
combined with correct HiDPI tagging (scripts/icons/mktiff.swift, replacing
`tiffutil -cathidpicheck` which never tagged the 2x representation as
HiDPI at all — see that script's header).

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

# Grayscale variant, used only for uninstaller-icon.svg / Uninstall-
# Nagi.icns. A luminance-preserving desaturation of the palette above
# (background luma ~25-30) read as "the same dark icon, barely
# different" next to app-icon.svg's near-black navy at a glance — not
# distinct enough (#30 follow-up). Deliberately lightened well past
# that instead, closer to macOS's own "grayed out" mid-gray, so the
# background itself unambiguously reads as gray rather than a dark navy
# that merely isn't quite navy.
INK_GRAY = "#5A5A5A"
INK_DEEP_GRAY = "#434343"
PALE_GRAY = "#F7F7F7"
GOLD_GRAY = "#A6A6A6"

OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "src")


def app_icon_svg(ink=INK, ink_deep=INK_DEEP, pale=PALE, gold=GOLD):
    size = 1024
    r = 229  # ~22.4%, matching macOS's Big-Sur-era squircle-ish icon radius
    cx = size / 2

    sun_cy, sun_r = 300, 42
    w1 = wave_path(cx, 500, 560, 70, 1.0, samples=56)
    w2 = wave_path(cx, 660, 560, 18, 1.0, samples=48)

    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" viewBox="0 0 {size} {size}">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="{ink}"/>
      <stop offset="1" stop-color="{ink_deep}"/>
    </linearGradient>
  </defs>
  <rect x="0" y="0" width="{size}" height="{size}" rx="{r}" ry="{r}" fill="url(#bg)"/>
  <circle cx="{cx}" cy="{sun_cy}" r="{sun_r}" fill="{gold}"/>
  <path d="{w1}" fill="none" stroke="{pale}" stroke-width="44" stroke-linecap="round"/>
  <path d="{w2}" fill="none" stroke="{pale}" stroke-width="44" stroke-linecap="round"/>
</svg>
'''


def template_icon_svg():
    # For TISIconLabels > CustomIcon (#30 follow-up) — the glyph System
    # Settings' Keyboard > Input Sources list actually renders next to
    # "ひらがな (Nagi)", which turned out to be a *different* asset from
    # everything else in this file. tsInputModeMenuIconFileKey /
    # tsInputMethodIconFileKey (badge_svg, below) drive the menu bar
    # Input menu; Kotoeri's own RomajiTyping.app has neither key set at
    # all and still shows its glyph correctly there, which is what
    # exposed this — that list specifically reads TISIconLabels instead,
    # confirmed against /System/Library/Input Methods/AinuIM.app (the
    # one bundled IME that *does* set it). Without it, Nagi's list row
    # falls back to some generic system glyph instead of this mark.
    #
    # Template images are a single flat shape (here: solid black) plus
    # alpha, no color — the system tints them itself (list highlight,
    # dark/light mode, ...). Same two-stroke mark as everywhere else,
    # sized like AinuIM's own Ainu@2x.pdf (that MediaBox is 28x36pt;
    # ours is the wider mark, so a bit wider than tall instead), and
    # rendered via svg2pdf.swift rather than svg2png.swift since
    # CustomIcon wants a PDF, not a bitmap format.
    width, height = 32, 26
    cx = width / 2

    sun_cy, sun_r = 6, 3.4
    w1 = wave_path(cx, 14.5, 30, 3.6, 1.0, samples=40)
    w2 = wave_path(cx, 21, 30, 1.0, 1.0, samples=32)

    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">
  <circle cx="{cx}" cy="{sun_cy}" r="{sun_r}" fill="#000000"/>
  <path d="{w1}" fill="none" stroke="#000000" stroke-width="2.6" stroke-linecap="round"/>
  <path d="{w2}" fill="none" stroke="#000000" stroke-width="2.6" stroke-linecap="round"/>
</svg>
'''


def badge_svg():
    # Designed at 256 canvas, downsampled to 32/16 for crisp anti-aliasing.
    # Same two-stroke mark as app-icon.svg, but knocked *out* of the badge
    # rather than painted on top of it — an SVG mask draws the badge shape
    # in mask-white (kept opaque) and the sun + waves in mask-black
    # (punched to fully transparent) so the compound alpha channel itself
    # carries the glyph, matching AinuIM.app's own Ainu.tiff byte-for-byte
    # in structure (#35 follow-up — TISIconIsTemplate=true, which the
    # Input Sources list row's CustomIcon needs, discards this file's
    # color and repaints from alpha alone; a plain opaque colored badge
    # rendered as an undifferentiated solid-tinted blob under that flag).
    # The fill color below (INK) never reaches the screen once tinted,
    # but a real color beats an arbitrary black/white choice for anyone
    # opening this file directly (Xcode SVG preview, `open badge.svg`, ...).
    size = 256
    r = 40
    cx = size / 2

    sun_cy, sun_r = 68, 16
    w1 = wave_path(cx, 152, 168, 26, 1.0, samples=48)
    w2 = wave_path(cx, 202, 168, 7, 1.0, samples=40)

    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" viewBox="0 0 {size} {size}">
  <defs>
    <mask id="knockout" maskUnits="userSpaceOnUse" x="0" y="0" width="{size}" height="{size}">
      <rect x="0" y="0" width="{size}" height="{size}" rx="{r}" ry="{r}" fill="#ffffff"/>
      <circle cx="{cx}" cy="{sun_cy}" r="{sun_r}" fill="#000000"/>
      <path d="{w1}" fill="none" stroke="#000000" stroke-width="26" stroke-linecap="round"/>
      <path d="{w2}" fill="none" stroke="#000000" stroke-width="26" stroke-linecap="round"/>
    </mask>
  </defs>
  <rect x="0" y="0" width="{size}" height="{size}" rx="{r}" ry="{r}" fill="{INK}" mask="url(#knockout)"/>
</svg>
'''


if __name__ == "__main__":
    os.makedirs(OUT_DIR, exist_ok=True)
    app_path = os.path.join(OUT_DIR, "app-icon.svg")
    badge_path = os.path.join(OUT_DIR, "badge.svg")
    uninstaller_path = os.path.join(OUT_DIR, "uninstaller-icon.svg")
    template_path = os.path.join(OUT_DIR, "template-icon.svg")
    with open(app_path, "w") as f:
        f.write(app_icon_svg())
    with open(badge_path, "w") as f:
        f.write(badge_svg())
    with open(uninstaller_path, "w") as f:
        f.write(app_icon_svg(ink=INK_GRAY, ink_deep=INK_DEEP_GRAY, pale=PALE_GRAY, gold=GOLD_GRAY))
    with open(template_path, "w") as f:
        f.write(template_icon_svg())
    print(f"wrote {app_path}")
    print(f"wrote {badge_path}")
    print(f"wrote {uninstaller_path}")
    print(f"wrote {template_path}")
