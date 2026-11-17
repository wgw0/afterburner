"""
Afterburner: the shop cards' pictures for the HUD themes (Config/Cosmetics "HUD" Card), 1024 x 512 on a
transparent background like the other cosmetic cards (tools/blender/cosmetic_cards.py): the flight HUD in that
colour, glowing, as it looks in a dogfight. The heading tape, speed and altitude boxes, a banked pitch ladder,
the flight path marker and gun cross, and a locked target: the F-16A from behind (cosmetic_cards.py's
HUDTarget.png) in the target box.

  python tools/cosmetics/hud_cards.py --target <HUDTarget.png> --out <dir> [--only HUDAmber,HUDIce]

Writes <Id>.png for each theme.
"""

import argparse
import math
import os

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

W, H = 1024, 512
SS = 2  # drawn at twice the size, then halved (smooth lines)
FONT = r"C:\Windows\Fonts\consolab.ttf"  # a monospaced face, like the game's RobotoMono
# Config/Cosmetics: each theme's colour
THEMES = {
    "HUDAmber": (255, 176, 60),
    "HUDGold": (255, 201, 60),
    "HUDIce": (190, 235, 255),
    "HUDMint": (150, 255, 210),
    "HUDLime": (190, 255, 90),
}
BANK = math.radians(14)  # the ladder's roll: banked into a turn


def symbology():
    """The HUD's lines and text, white on transparent (an alpha mask), at SS times the size."""
    w, h = W * SS, H * SS
    mask = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(mask)
    s = SS
    lw = 4 * s  # bold: the card is shown small
    font = ImageFont.truetype(FONT, 32 * s)
    small = ImageFont.truetype(FONT, 25 * s)
    cx, cy = w / 2, h * 0.52

    # Heading tape across the top: ticks every 5 degrees, numbers every 10, the caret under the heading
    for i in range(-6, 7):
        x = cx + i * 46 * s
        tall = i % 2 == 0
        d.line([(x, 56 * s), (x, (56 + (16 if tall else 9)) * s)], fill=255, width=lw)
        if tall:
            d.text((x, 44 * s), f"{(27 + i // 2) % 36:02d}", font=small, fill=255, anchor="ms")
    d.polygon([(cx, 80 * s), (cx - 9 * s, 94 * s), (cx + 9 * s, 94 * s)], fill=255)

    # Speed (left) and altitude (right) in boxes
    for x, text in ((cx - 330 * s, "452"), (cx + 330 * s, "12,500")):
        box = d.textbbox((x, cy), text, font=font, anchor="mm")
        pad = 10 * s
        d.rectangle([box[0] - pad, box[1] - pad, box[2] + pad, box[3] + pad], outline=255, width=lw)
        d.text((x, cy), text, font=font, fill=255, anchor="mm")
    d.text((cx - 330 * s, cy + 56 * s), "G 6.4", font=small, fill=255, anchor="mm")
    d.text((cx + 330 * s, cy + 56 * s), "M 0.92", font=small, fill=255, anchor="mm")

    # Pitch ladder, rolled: solid rungs above the horizon, dashed below, numbers at the ends
    ladder = Image.new("L", (w, h), 0)
    ld = ImageDraw.Draw(ladder)
    for deg in (-5, 0, 5):
        y = cy - deg * 34 * s
        half = 190 * s if deg == 0 else 105 * s
        gap = 50 * s
        if deg == 0:
            ld.line([(cx - half, y), (cx - gap, y)], fill=255, width=lw)
            ld.line([(cx + gap, y), (cx + half, y)], fill=255, width=lw)
            continue
        for side in (-1, 1):
            x0, x1 = cx + side * gap, cx + side * half
            if deg > 0:
                ld.line([(x0, y), (x1, y)], fill=255, width=lw)
            else:
                steps = 5
                for k in range(steps):
                    a = x0 + (x1 - x0) * k / steps
                    b = x0 + (x1 - x0) * (k + 0.55) / steps
                    ld.line([(a, y), (b, y)], fill=255, width=lw)
            tip = 14 * s * (1 if deg > 0 else -1)
            ld.line([(x1, y), (x1, y + tip)], fill=255, width=lw)
            ld.text((x1 + side * 26 * s, y), f"{abs(deg)}", font=small, fill=255, anchor="mm")
    ladder = ladder.rotate(math.degrees(BANK), resample=Image.BICUBIC, center=(cx, cy))
    # Keep the ladder clear of the tapes and boxes
    clip = Image.new("L", (w, h), 0)
    ImageDraw.Draw(clip).rectangle([cx - 250 * s, 110 * s, cx + 250 * s, h - 30 * s], fill=255)
    mask = ImageChops.lighter(mask, ImageChops.multiply(ladder, clip))
    d = ImageDraw.Draw(mask)

    # Flight path marker (a circle with wings and a fin) and the gun cross
    fx, fy = cx - 30 * s, cy + 70 * s
    r = 13 * s
    d.ellipse([fx - r, fy - r, fx + r, fy + r], outline=255, width=lw)
    d.line([(fx - r - 22 * s, fy), (fx - r, fy)], fill=255, width=lw)
    d.line([(fx + r, fy), (fx + r + 22 * s, fy)], fill=255, width=lw)
    d.line([(fx, fy - r), (fx, fy - r - 12 * s)], fill=255, width=lw)
    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        d.line([(cx + dx * 8 * s, cy + dy * 8 * s), (cx + dx * 22 * s, cy + dy * 22 * s)], fill=255, width=lw)
    return mask


TARGET_AT = (0.67, 0.33)  # the locked jet, up and right of the gun cross
TARGET_SIZE = 130  # px across the lock box


def target_box(mask):
    """The lock: a box round the target with LOCK and its range under it."""
    d = ImageDraw.Draw(mask)
    s = SS
    font = ImageFont.truetype(FONT, 25 * s)
    x, y = TARGET_AT[0] * W * s, TARGET_AT[1] * H * s
    half = TARGET_SIZE / 2 * s
    lw = 4 * s
    corner = half * 0.4
    for sx in (-1, 1):
        for sy in (-1, 1):
            px, py = x + sx * half, y + sy * half
            d.line([(px, py), (px - sx * corner, py)], fill=255, width=lw)
            d.line([(px, py), (px, py - sy * corner)], fill=255, width=lw)
    d.polygon([(x, y - half - 18 * s), (x - 10 * s, y - half - 32 * s), (x + 10 * s, y - half - 32 * s)], fill=255)
    d.text((x, y + half + 30 * s), "LOCK 1.8", font=font, fill=255, anchor="mm")
    return mask


def card(colour, target):
    mask = target_box(symbology())
    mask = mask.resize((W, H), Image.LANCZOS)
    out = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    # The target first, behind the symbology
    if target:
        jet = Image.open(target).convert("RGBA")
        size = int(TARGET_SIZE * 0.82)
        jet.thumbnail((size, size), Image.LANCZOS)
        out.alpha_composite(jet, (int(TARGET_AT[0] * W - jet.width / 2), int(TARGET_AT[1] * H - jet.height / 2)))
    # A wide soft glow, a tight glow, then the lines: a HUD's light on its glass
    for radius, strength in ((10, 0.5), (3, 0.8)):
        glow = mask.filter(ImageFilter.GaussianBlur(radius)).point(lambda a, k=strength: min(255, int(a * k * 1.6)))
        layer = Image.new("RGBA", (W, H), colour + (0,))
        layer.putalpha(glow)
        out.alpha_composite(layer)
    lines = Image.new("RGBA", (W, H), tuple(min(255, c + 40) for c in colour) + (0,))
    lines.putalpha(mask)
    out.alpha_composite(lines)
    return out


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    parser = argparse.ArgumentParser()
    parser.add_argument("--target", default="", help="HUDTarget.png from tools/blender/cosmetic_cards.py")
    parser.add_argument("--out", default=os.path.join(here, "out"))
    parser.add_argument("--only", default="", help="comma list of theme ids; default: all")
    args = parser.parse_args()
    os.makedirs(args.out, exist_ok=True)
    only = set(filter(None, args.only.split(",")))
    for tid, colour in THEMES.items():
        if only and tid not in only:
            continue
        path = os.path.join(args.out, f"{tid}.png")
        card(colour, args.target or None).save(path)
        print("wrote", path)


if __name__ == "__main__":
    main()
