"""
Afterburner: badge icons for the achievements (LIV-02). One 512 x 512 PNG per achievement in
src/shared/Achievements.luau, drawn here so badges can be created before there's commissioned art.

Each badge is a roundel: a ring in the achievement's rarity colour (the same colours as the Career screen,
UI/Theme Rarity), a dark navy centre with an emblem for the achievement, and its name on a banner. Roblox
shows badges cropped to a circle, so everything sits inside the inscribed circle.

  python tools/badges/badges_generate.py [--out docs/art/badges]
"""

import argparse
import math
import os
import re

from PIL import Image, ImageDraw, ImageFont

SIZE = 512
SS = 2  # supersampling
FONT_BOLD = r"C:\Windows\Fonts\bahnschrift.ttf"
FONT_HEAVY = r"C:\Windows\Fonts\impact.ttf"

NAVY = (16, 27, 50)
NAVY_DARK = (8, 14, 28)
ORANGE = (255, 138, 61)
WHITE = (240, 244, 250)
RARITY = {
    "Common": (176, 190, 210),
    "Uncommon": (96, 200, 96),
    "Rare": (70, 140, 255),
    "Epic": (176, 90, 255),
    "Legendary": (240, 185, 55),
}

# Emblem per achievement: (kind, argument)
EMBLEMS = {
    "FirstBlood": ("jet", None),
    "GunsOnly": ("crosshair", None),
    "Victor": ("star", None),
    "AceInADay": ("number", "5"),
    "Untouchable": ("shield", None),
    "Notched": ("missile", "dodge"),
    "ZoneHunter": ("flag", None),
    "Veteran": ("number", "50"),
    "TestPilot": ("jet", "delta"),
    "FoxOne": ("missile", "1"),
    "FoxThree": ("missile", "3"),
    "DoubleTrouble": ("number", "2"),
    "HatTrick": ("number", "3"),
    "Flawless": ("shield", "star"),
    "TeamPlayer": ("formation", None),
    "EscapeArtist": ("missile", "dodge3"),
    "TopOfTheTable": ("trophy", None),
    "Centurion": ("number", "100"),
    "Collector": ("number", "10"),
    "HighFlyer": ("number", "25"),
    "ThreadTheNeedle": ("bridge", None),
    # The hangar and the bank (October 2026)
    "FullHangar": ("hangar", None),
    "FullyKitted": ("wrench", None),
    "MasterMechanic": ("wrench", "star"),
    "Savings": ("coins", "50K"),
    "HighRoller": ("coins", "250K"),
    "Tycoon": ("coins", "1M"),
    "Researcher": ("flask", "10K"),
    "Boffin": ("flask", "100K"),
    "SharpDresser": ("brush", "5"),
    "FashionIcon": ("brush", "25"),
    "Wardrobe": ("brush", "50"),
}


def read_achievements(path):
    """(id, rarity, name) for every achievement, read from the Luau source."""
    src = open(path, encoding="utf-8").read()
    found = []
    for block in re.finditer(r"\{([^{}]*?id\s*=\s*\"[^\"]+\"[^{}]*?)\}", src, re.S):
        body = block.group(1)
        get = lambda key: re.search(key + r'\s*=\s*"([^"]*)"', body)
        aid, rarity, name = get("id"), get("rarity"), get("name")
        if aid and rarity and name:
            found.append((aid.group(1), rarity.group(1), name.group(1)))
    return found


def S(v):
    return v * SS


def poly(d, pts, cx, cy, scale, fill, angle=0.0):
    c, s = math.cos(angle), math.sin(angle)
    d.polygon([(S(cx + (x * c - y * s) * scale), S(cy + (x * s + y * c) * scale)) for x, y in pts], fill=fill)


JET = [(0, -1.0), (0.12, -0.55), (0.14, -0.15), (0.85, 0.25), (0.85, 0.38), (0.14, 0.22), (0.12, 0.62), (0.38, 0.85),
       (0.38, 0.95), (0, 0.85), (-0.38, 0.95), (-0.38, 0.85), (-0.12, 0.62), (-0.14, 0.22), (-0.85, 0.38),
       (-0.85, 0.25), (-0.14, -0.15), (-0.12, -0.55)]
DELTA = [(0, -1.0), (0.13, -0.5), (0.15, -0.1), (0.85, 0.55), (0.85, 0.7), (0.3, 0.75), (0.25, 0.95), (0, 0.85),
         (-0.25, 0.95), (-0.3, 0.75), (-0.85, 0.7), (-0.85, 0.55), (-0.15, -0.1), (-0.13, -0.5)]
MISSILE = [(0, -1.0), (0.09, -0.8), (0.09, 0.55), (0.28, 0.85), (0.28, 0.97), (0.09, 0.85), (-0.09, 0.85),
           (-0.28, 0.97), (-0.28, 0.85), (-0.09, 0.55), (-0.09, -0.8)]


def star(d, cx, cy, r, fill):
    pts = []
    for i in range(10):
        a = -math.pi / 2 + i * math.pi / 5
        rr = r if i % 2 == 0 else r * 0.42
        pts.append((math.cos(a) * rr, math.sin(a) * rr))
    poly(d, pts, cx, cy, 1, fill)


def amount(d, text, x, y, size, fill):
    """A figure beside an emblem (50K, 25): Impact, shrunk to fit."""
    font = ImageFont.truetype(FONT_HEAVY, S(size))
    while d.textlength(text, font=font) > S(150) and size > 40:
        size -= 6
        font = ImageFont.truetype(FONT_HEAVY, S(size))
    d.text((S(x), S(y)), text, font=font, fill=fill, anchor="mm")


def wrench(d, cx, cy, scale, angle, fill):
    """A spanner: a handle with an open jaw at the top end."""
    c, s = math.cos(angle), math.sin(angle)

    def at(x, y):
        return (S(cx + (x * c - y * s) * scale), S(cy + (x * s + y * c) * scale))

    d.polygon([at(-0.13, -0.55), at(0.13, -0.55), at(0.13, 0.9), at(-0.13, 0.9)], fill=fill)
    hx, hy = at(0, -0.72)
    r = S(0.36 * scale)
    d.ellipse([hx - r, hy - r, hx + r, hy + r], fill=fill)
    jx, jy = at(0, -0.92)
    jr = S(0.17 * scale)
    d.ellipse([jx - jr, jy - jr, jx + jr, jy + jr], fill=NAVY)
    d.polygon([at(-0.17, -0.92), at(0.17, -0.92), at(0.17, -1.2), at(-0.17, -1.2)], fill=NAVY)
    ex, ey = at(0, 0.9)
    er = S(0.19 * scale)
    d.ellipse([ex - er, ey - er, ex + er, ey + er], fill=fill)


def emblem(d, kind, arg, cx, cy, accent):
    if kind == "jet":
        poly(d, DELTA if arg == "delta" else JET, cx, cy, 105, WHITE)
    elif kind == "crosshair":
        w = S(9)
        d.ellipse([S(cx - 92), S(cy - 92), S(cx + 92), S(cy + 92)], outline=WHITE, width=w)
        d.ellipse([S(cx - 40), S(cy - 40), S(cx + 40), S(cy + 40)], outline=WHITE, width=w)
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            d.line([S(cx + dx * 55), S(cy + dy * 55), S(cx + dx * 118), S(cy + dy * 118)], fill=WHITE, width=w)
        d.ellipse([S(cx - 9), S(cy - 9), S(cx + 9), S(cy + 9)], fill=ORANGE)
    elif kind == "star":
        star(d, cx, cy, 110, WHITE)
    elif kind == "number":
        size = 190 if len(arg) <= 1 else (160 if len(arg) == 2 else 128)
        font = ImageFont.truetype(FONT_HEAVY, S(size))
        text = arg if len(arg) > 2 else "x" + arg if arg in ("2", "3", "5") else arg
        d.text((S(cx), S(cy)), text, font=font, fill=WHITE, anchor="mm")
    elif kind == "shield":
        pts = [(0, -1.0), (0.8, -0.72), (0.75, 0.1), (0.45, 0.6), (0, 1.0), (-0.45, 0.6), (-0.75, 0.1), (-0.8, -0.72)]
        poly(d, pts, cx, cy, 108, WHITE)
        poly(d, [(x * 0.78, y * 0.78) for x, y in pts], cx, cy - 4, 108, NAVY)
        if arg == "star":
            star(d, cx, cy - 4, 52, accent)
        else:
            poly(d, JET, cx, cy - 2, 52, accent)
    elif kind == "missile":
        if arg and arg.startswith("dodge"):
            n = 3 if arg == "dodge3" else 1
            for i in range(n):
                off = (i - (n - 1) / 2) * 62
                poly(d, MISSILE, cx - 40 + off, cy + 10, 80, WHITE, angle=math.radians(35))
            poly(d, JET, cx + 58, cy - 48, 52, accent, angle=math.radians(-20))
        else:
            poly(d, MISSILE, cx - 30, cy, 112, WHITE, angle=math.radians(30))
            font = ImageFont.truetype(FONT_HEAVY, S(110))
            d.text((S(cx + 62), S(cy + 10)), arg, font=font, fill=accent, anchor="mm")
    elif kind == "flag":
        w = S(10)
        d.line([S(cx - 60), S(cy - 110), S(cx - 60), S(cy + 110)], fill=WHITE, width=w)
        d.polygon([(S(cx - 55), S(cy - 105)), (S(cx + 95), S(cy - 70)), (S(cx - 55), S(cy - 30))], fill=accent)
        d.ellipse([S(cx - 105), S(cy + 85), S(cx - 15), S(cy + 120)], outline=WHITE, width=S(6))
    elif kind == "formation":
        for dx, dy in ((0, -55), (-75, 35), (75, 35)):
            poly(d, JET, cx + dx, cy + dy, 52, WHITE)
    elif kind == "trophy":
        d.pieslice([S(cx - 80), S(cy - 150), S(cx + 80), S(cy + 30)], 0, 180, fill=WHITE)
        d.rectangle([S(cx - 80), S(cy - 100), S(cx + 80), S(cy - 60)], fill=WHITE)
        d.rectangle([S(cx - 14), S(cy + 25), S(cx + 14), S(cy + 75)], fill=WHITE)
        d.rectangle([S(cx - 60), S(cy + 75), S(cx + 60), S(cy + 100)], fill=WHITE)
        font = ImageFont.truetype(FONT_HEAVY, S(70))
        d.text((S(cx), S(cy - 50)), "1", font=font, fill=accent, anchor="mm")
    elif kind == "hangar":
        # An arched hangar, open at the front, a jet inside
        d.pieslice([S(cx - 130), S(cy - 110), S(cx + 130), S(cy + 150)], 180, 360, fill=WHITE)
        d.rectangle([S(cx - 130), S(cy + 18), S(cx + 130), S(cy + 92)], fill=WHITE)
        d.pieslice([S(cx - 100), S(cy - 70), S(cx + 100), S(cy + 130)], 180, 360, fill=NAVY_DARK)
        d.rectangle([S(cx - 100), S(cy + 28), S(cx + 100), S(cy + 92)], fill=NAVY_DARK)
        poly(d, JET, cx, cy + 40, 50, accent)
    elif kind == "wrench":
        if arg == "star":
            wrench(d, cx, cy + 6, 100, math.radians(40), WHITE)
            wrench(d, cx, cy + 6, 100, math.radians(-40), WHITE)
            star(d, cx, cy - 2, 42, accent)
        else:
            wrench(d, cx, cy + 6, 112, math.radians(35), WHITE)
    elif kind == "coins":
        # A stack of coins with the amount beside it
        for i in range(4):
            y = cy + 70 - i * 30
            d.ellipse([S(cx - 135), S(y - 22), S(cx - 30), S(y + 22)], fill=accent, outline=NAVY_DARK, width=S(4))
        d.ellipse([S(cx - 123), S(cy - 34), S(cx - 42), S(cy - 6)], outline=NAVY_DARK, width=S(3))
        amount(d, arg, cx + 58, cy + 10, 110, WHITE)
    elif kind == "flask":
        # A lab flask (research), its liquid in the ring colour
        neck = [(-0.18, -1.0), (0.18, -1.0), (0.18, -0.35), (0.62, 0.7), (0.62, 0.9), (-0.62, 0.9), (-0.62, 0.7),
                (-0.18, -0.35)]
        poly(d, neck, cx - 58, cy + 8, 100, WHITE)
        # The liquid follows the flask's sloping sides, inset from the glass
        liquid = [(-0.38, 0.3), (0.38, 0.3), (0.55, 0.7), (0.55, 0.82), (-0.55, 0.82), (-0.55, 0.7)]
        poly(d, liquid, cx - 58, cy + 8, 100, accent)
        amount(d, arg, cx + 66, cy + 10, 110, WHITE)
    elif kind == "brush":
        # A paint roller (the roller in the ring colour) on its bent wire frame, and how many skins
        w = S(9)
        d.rounded_rectangle([S(cx - 140), S(cy - 100), S(cx - 30), S(cy - 52)], radius=S(16), fill=accent)
        d.rounded_rectangle([S(cx - 140), S(cy - 100), S(cx - 30), S(cy - 52)], radius=S(16), outline=WHITE, width=S(5))
        frame = [(cx - 30, cy - 76), (cx - 12, cy - 76), (cx - 12, cy - 28), (cx - 72, cy - 14), (cx - 72, cy + 12)]
        d.line([(S(x), S(y)) for x, y in frame], fill=WHITE, width=w, joint="curve")
        d.rounded_rectangle([S(cx - 86), S(cy + 8), S(cx - 58), S(cy + 92)], radius=S(12), fill=WHITE)
        amount(d, arg, cx + 66, cy + 10, 130, WHITE)
    elif kind == "bridge":
        w = S(9)
        d.line([S(cx - 130), S(cy + 20), S(cx + 130), S(cy + 20)], fill=WHITE, width=S(12))
        for tx in (-65, 65):
            d.line([S(cx + tx), S(cy - 95), S(cx + tx), S(cy + 70)], fill=WHITE, width=w)
        d.arc([S(cx - 65), S(cy - 95), S(cx + 65), S(cy + 120)], 180, 360, fill=WHITE, width=S(5))
        poly(d, JET, cx, cy + 75, 34, accent, angle=0)


def badge(aid, rarity, name, out):
    ring = RARITY.get(rarity, RARITY["Common"])
    img = Image.new("RGBA", (S(SIZE), S(SIZE)), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = SIZE / 2
    d.ellipse([S(6), S(6), S(SIZE - 6), S(SIZE - 6)], fill=ring)
    d.ellipse([S(30), S(30), S(SIZE - 30), S(SIZE - 30)], fill=NAVY_DARK)
    d.ellipse([S(40), S(40), S(SIZE - 40), S(SIZE - 40)], fill=NAVY)
    # Rarity ticks round the ring
    for i in range(24):
        a = i * math.tau / 24
        r0, r1 = c - 26, c - 10
        d.line([S(c + math.cos(a) * r0), S(c + math.sin(a) * r0), S(c + math.cos(a) * r1), S(c + math.sin(a) * r1)],
               fill=NAVY_DARK, width=S(3))
    kind, arg = EMBLEMS.get(aid, ("jet", None))
    emblem(d, kind, arg, c, c - 40, ring)
    # Name banner
    font_size = 46
    font = ImageFont.truetype(FONT_BOLD, S(font_size))
    while d.textlength(name.upper(), font=font) > S(330) and font_size > 26:
        font_size -= 2
        font = ImageFont.truetype(FONT_BOLD, S(font_size))
    by = c + 120
    d.rounded_rectangle([S(c - 190), S(by - 34), S(c + 190), S(by + 34)], radius=S(16), fill=ring)
    d.text((S(c), S(by + 2)), name.upper(), font=font, fill=NAVY_DARK, anchor="mm")
    img = img.resize((SIZE, SIZE), Image.LANCZOS)
    img.save(os.path.join(out, f"{aid}.png"))


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    root = os.path.abspath(os.path.join(here, "..", ".."))
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", default=os.path.join(root, "docs", "art", "badges"))
    args = parser.parse_args()
    os.makedirs(args.out, exist_ok=True)
    achievements = read_achievements(os.path.join(root, "src", "shared", "Achievements.luau"))
    for aid, rarity, name in achievements:
        badge(aid, rarity, name, args.out)
    missing = [aid for aid, _, _ in achievements if aid not in EMBLEMS]
    print(f"{len(achievements)} badges written to {args.out}" + (f"; default emblem for {missing}" if missing else ""))


if __name__ == "__main__":
    main()
