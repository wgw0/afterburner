"""
Afterburner: finishes the experience icon from the render (tools/marketing/icon_render.py) and writes the
512 x 512 icon. On top of the render: the low sun's lens flare and rays, glow round the afterburners and the
flares (with their smoke), bloom and a vignette, then the wordmark: heavy capitals in a fiery gradient with a
dark outline, a bright bevelled top edge and an orange glow, so it reads at the small sizes Roblox shows icons
at. The effects are the pass icons' (tools/passes/pass_icons.py).

  python tools/marketing/icon_compose.py <render.png> [--out docs/art/marketing/icon.png]
"""

import argparse
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "passes"))
import pass_icons as fx  # noqa: E402  (the shared effects, drawn at fx.S = 1024)

SIZE = 512
S = fx.S
FONT = r"C:\Windows\Fonts\impact.ttf"
SUN = (0.9, 0.33)  # where the low sun sits, just off the jet's tail, on the horizon
NOZZLES = (0.66, 0.665)
FLARES = ((0.683, 0.832), (0.65, 0.762))  # the bright flare balls in the render (fractions of the frame)
TAIL = (0.64, 0.7)


def lens_flare(img):
    """The sun: a hot core, a wide warm bloom, rays, and ghosts along the line through the centre."""
    img = fx.glow(img, SUN, (255, 170, 90), 0.42, 0.55)
    img = fx.glow(img, SUN, (255, 220, 160), 0.12, 1.0)
    img = fx.glow(img, SUN, (255, 255, 240), 0.035, 1.0)
    img = fx.rays(img, SUN, (255, 190, 120), count=22, alpha=0.16, length=0.7, seed=9)
    # A horizontal streak, as a camera lens draws one
    streak = np.exp(-((fx.YY - SUN[1]) / 0.006) ** 2) * np.exp(-((fx.XX - SUN[0]) / 0.4) ** 2)
    img = fx.add(img, fx.tint_layer(streak, (255, 200, 140), 0.8))
    # (only between the sun and the middle: further out they'd land on the jet)
    for t, r, colour, a in ((0.3, 0.03, (255, 160, 90), 0.35), (0.55, 0.06, (140, 120, 255), 0.18)):
        cx, cy = SUN[0] + (0.5 - SUN[0]) * t * 2, SUN[1] + (0.5 - SUN[1]) * t * 2
        d = np.hypot(fx.XX - cx, fx.YY - cy) / r
        ring = np.clip(1 - np.abs(d - 0.85) * 4, 0, 1) + np.clip(1 - d, 0, 1) * 0.35
        img = fx.add(img, fx.tint_layer(ring, colour, a))
    return img


def wordmark(img, text):
    """The wordmark across the top, sized to the frame."""
    size = 0.2
    probe = ImageDraw.Draw(Image.new("L", (1, 1)))
    while probe.textlength(text, font=ImageFont.truetype(FONT, int(size * S))) > S * 0.9 and size > 0.05:
        size -= 0.004
    return fx.gradient_text(img, text, FONT, size, (0.5, 0.11), (255, 246, 200), (255, 96, 24), outline=(10, 18, 40),
                            stroke=0.075, glow_colour=(255, 120, 40))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("render")
    parser.add_argument("--out", default=os.path.join(ROOT, "docs", "art", "marketing", "icon.png"))
    args = parser.parse_args()
    img = Image.open(args.render).convert("RGBA").resize((S, S), Image.LANCZOS)
    img = lens_flare(img)
    # Afterburners and flares glow; the flares trail smoke back towards the tail
    img = fx.glow(img, NOZZLES, (255, 120, 30), 0.07, 0.9)
    for at in FLARES:
        img = fx.streak(img, at, (at[0] - (at[0] - TAIL[0]) * 0.7, at[1] - (at[1] - TAIL[1]) * 0.7), (255, 200, 150), 0.006, core=(255, 240, 220))
        img = fx.glow(img, at, (255, 170, 80), 0.05, 1.0)
        img = fx.sparkle(img, at, 0.03, (255, 235, 200))
    # Calm, darker sky at the top so the wordmark sits on it
    top = np.clip(1 - fx.YY / 0.26, 0, 1) ** 1.5
    img = Image.alpha_composite(img, fx.tint_layer(top * 0.45, (10, 14, 50)))
    img = fx.bloom(img, 0.8, 0.02, 0.45)
    img = fx.vignette(img, 0.35)
    img = wordmark(img, "AFTERBURNER")
    out = img.resize((SIZE, SIZE), Image.LANCZOS).convert("RGB")
    out.save(args.out)
    print("icon written to", args.out, out.size)


if __name__ == "__main__":
    main()
