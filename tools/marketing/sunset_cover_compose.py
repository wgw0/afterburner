"""
Afterburner: finishes the sunset cover from its render (sunset_cover_render.py) and writes the 1920 x 1080
experience thumbnail. The icon's finish (icon_compose.py) on a wide frame: the low sun's lens flare and rays,
glow round the afterburners, the flares and the blast, bloom, a punchier grade and a vignette, then the icon's
wordmark in the open sky at the top left. Made to be clicked in a Roblox thumbnail: one big subject with hot
colours on a cool ground, readable when shrunk to a phone tile, the bottom fifth kept quiet where Roblox can lay
the experience's name over it.

Where the sun, nozzles, flares and blast are comes from the JSON the render writes beside its PNG: fractions of the
frame from the top left.

  python tools/marketing/sunset_cover_compose.py <render.png> [--out docs/art/marketing/cover.png]
"""

import argparse
import json
import math
import os

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
W, H = 1920, 1080
FONT = r"C:\Windows\Fonts\impact.ttf"
# Pixel grids in units of the frame's height, so a radius of 0.1 is a tenth of the height whatever the width
YY, XX = np.mgrid[0:H, 0:W].astype(np.float32) / H
ASPECT = W / H


def dist(at):
    return np.hypot(XX - at[0] * ASPECT, YY - at[1])


def add(arr, mask, colour, strength=1.0):
    """Additive light: colour (0-255) scaled by mask (0-1)."""
    return arr + mask[..., None] * (np.array(colour, np.float32) / 255 * strength)[None, None]


def glow(arr, at, colour, radius, strength=0.9):
    d = dist(at) / radius
    return add(arr, np.exp(-d * d * 2.5), colour, strength)


def rays(arr, at, colour, count=26, strength=0.35, length=1.0, seed=9):
    rng = np.random.default_rng(seed)
    ang = np.arctan2(YY - at[1], XX - at[0] * ASPECT)
    band = np.zeros((H, W), np.float32)
    for _ in range(count):
        a = rng.uniform(-math.pi, math.pi)
        w = rng.uniform(0.012, 0.05)
        diff = np.angle(np.exp(1j * (ang - a)))
        band = np.maximum(band, np.clip(1 - np.abs(diff) / w, 0, 1) * rng.uniform(0.5, 1))
    fade = np.clip(1 - dist(at) / length, 0, 1) ** 1.3
    soft = np.asarray(Image.fromarray((band * fade * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(3)),
                      np.float32) / 255
    return add(arr, soft, colour, strength)


def sparkle(arr, at, size, colour=(255, 240, 215)):
    """A four-pointed glint: thin crossed streaks."""
    dx = np.abs(XX - at[0] * ASPECT)
    dy = np.abs(YY - at[1])
    star = np.exp(-(dy / (size * 0.05)) ** 2) * np.exp(-(dx / size) ** 2)
    star += np.exp(-(dx / (size * 0.05)) ** 2) * np.exp(-(dy / size) ** 2)
    return add(arr, np.clip(star, 0, 1), colour, 0.9)


def lens_flare(arr, sun):
    """The low sun: a hot core, a wide warm bloom, rays, a lens streak and a couple of ghosts."""
    arr = glow(arr, sun, (255, 140, 70), 0.5, 0.18)
    arr = glow(arr, sun, (255, 210, 150), 0.08, 0.6)
    arr = glow(arr, sun, (255, 252, 235), 0.025, 1.1)
    arr = rays(arr, sun, (255, 190, 120), strength=0.2, length=0.7)
    streak = np.exp(-((YY - sun[1]) / 0.004) ** 2) * np.exp(-((XX - sun[0] * ASPECT) / 0.6) ** 2)
    arr = add(arr, streak, (255, 200, 140), 0.6)
    # Ghosts along the line from the sun through the middle, kept to the open sky above the jet
    for t, r, colour, a in ((0.18, 0.025, (255, 170, 100), 0.2), (0.32, 0.05, (150, 130, 255), 0.12)):
        cx = sun[0] + (0.5 - sun[0]) * t * 2
        cy = sun[1] + (0.5 - sun[1]) * t * 2 - 0.12 * t
        d = dist((cx, cy)) / r
        ring = np.clip(1 - np.abs(d - 0.85) * 4, 0, 1) + np.clip(1 - d, 0, 1) * 0.35
        arr = add(arr, ring, colour, a)
    return arr


def bloom(arr, threshold=0.85, radius=18, strength=0.3):
    lum = arr.mean(-1)
    bright = np.clip((lum - threshold) / (1 - threshold), 0, 1)[..., None] * np.clip(arr, 0, 1)
    img = Image.fromarray((bright * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(radius))
    return arr + np.asarray(img, np.float32) / 255 * strength


def grade(arr):
    """Punchier: a touch more saturation and contrast, as the small tiles wash colour out."""
    lum = (arr * np.array([0.2126, 0.7152, 0.0722], np.float32)).sum(-1, keepdims=True)
    arr = lum + (arr - lum) * 1.18
    return np.clip((arr - 0.5) * 1.06 + 0.5, 0, None)


def shade(arr):
    """Calm, darker sky behind the wordmark; the bottom a little darker so the eye stays on the fight."""
    top = np.clip(1 - YY / 0.3, 0, 1) ** 1.6 * np.clip(1 - (XX / ASPECT) / 0.75, 0, 1) ** 0.6
    arr = arr * (1 - top * 0.42)[..., None] + top[..., None] * np.array([10, 14, 50], np.float32) / 255 * 0.42
    bottom = np.clip((YY - 0.8) / 0.2, 0, 1) ** 1.5
    arr = arr * (1 - bottom * 0.35)[..., None]
    d = np.clip(np.hypot((XX / ASPECT) - 0.5, YY - 0.5) / 0.72, 0, 1) ** 2.4
    return arr * (1 - d * 0.4)[..., None]


def wordmark(img, text, box):
    """The icon's wordmark: heavy capitals in a fiery gradient with a dark outline, a bright bevelled top edge,
    a drop shadow and an orange glow. Drawn at twice the size and halved, fitted to box (x, y, width) in px."""
    ss = 2
    x0, y0, width = box
    size = 400
    probe = ImageDraw.Draw(Image.new("L", (1, 1)))
    while probe.textlength(text, font=ImageFont.truetype(FONT, size)) > width * ss:
        size -= 4
    font = ImageFont.truetype(FONT, size)
    stroke = max(int(size * 0.07), 1)
    left, top, right, bottom = probe.textbbox((0, 0), text, font=font, stroke_width=stroke)
    pad = int(size * 0.35)
    lw, lh = right - left + pad * 2, bottom - top + pad * 2
    origin = (pad - left, pad - top)

    def mask(stroke_width=0, offset=(0, 0)):
        m = Image.new("L", (lw, lh), 0)
        ImageDraw.Draw(m).text((origin[0] + offset[0], origin[1] + offset[1]), text, font=font, fill=255,
                               stroke_width=stroke_width, stroke_fill=255)
        return m

    def layer(m, colour, strength=1.0):
        out = Image.new("RGBA", (lw, lh), colour + (0,))
        out.putalpha(m.point(lambda a: min(255, int(a * strength))))
        return out

    letters = mask()
    outline = mask(stroke)
    canvas = Image.new("RGBA", (lw, lh), (0, 0, 0, 0))
    canvas.alpha_composite(layer(mask(stroke * 2).filter(ImageFilter.GaussianBlur(size * 0.12)), (255, 110, 30), 0.9))
    canvas.alpha_composite(layer(mask(stroke, (int(size * 0.03), int(size * 0.06))).filter(
        ImageFilter.GaussianBlur(size * 0.03)), (0, 0, 0), 0.75))
    canvas.alpha_composite(layer(outline, (10, 18, 40)))
    t = np.clip((np.arange(lh, dtype=np.float32)[:, None] - (origin[1] + top + stroke)) /
                max(bottom - top - stroke * 2, 1), 0, 1)
    t = np.repeat(t, lw, 1)[..., None]
    fill = np.array([255, 246, 200], np.float32) * (1 - t) + np.array([255, 96, 24], np.float32) * t
    rgba = np.concatenate([fill, np.asarray(letters, np.float32)[..., None]], -1).astype(np.uint8)
    canvas.alpha_composite(Image.fromarray(rgba, "RGBA"))
    edge = ImageChops.subtract(letters, ImageChops.offset(letters, 0, int(size * 0.03)))
    canvas.alpha_composite(layer(edge, (255, 255, 255), 0.6))
    canvas = canvas.resize((lw // ss, lh // ss), Image.LANCZOS)
    img.alpha_composite(canvas, (int(x0 - pad / ss), int(y0 - pad / ss)))
    return img


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("render")
    parser.add_argument("--out", default=os.path.join(ROOT, "docs", "art", "marketing", "cover.png"))
    args = parser.parse_args()
    with open(os.path.splitext(args.render)[0] + ".json") as f:
        marks = json.load(f)
    arr = np.asarray(Image.open(args.render).convert("RGB").resize((W, H), Image.LANCZOS), np.float32) / 255
    arr = lens_flare(arr, marks["sun"])
    for at in marks["nozzles"]:
        arr = glow(arr, at, (255, 120, 30), 0.07, 0.8)
    for at in marks["enemy_nozzles"]:
        arr = glow(arr, at, (255, 120, 40), 0.02, 0.9)
    arr = glow(arr, marks["blast"], (255, 110, 20), 0.2, 0.4)
    arr = glow(arr, marks["blast"], (255, 190, 90), 0.07, 0.3)
    for at in marks["flares"]:
        arr = glow(arr, at, (255, 170, 80), 0.035, 0.6)
        arr = sparkle(arr, at, 0.035)
    arr = bloom(arr)
    arr = grade(arr)
    arr = shade(arr)
    img = Image.fromarray((np.clip(arr, 0, 1) * 255).astype(np.uint8)).convert("RGBA")
    img = wordmark(img, "AFTERBURNER", (56, 40, 1020))
    img.convert("RGB").save(args.out)
    print("cover written to", args.out, img.size)


if __name__ == "__main__":
    main()
