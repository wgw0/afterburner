"""
Afterburner: the game pass icons (Config/Passes), 512 x 512. Roblox shows pass icons cropped to a circle, so
each is a roundel: a ring in the pass's colour round a lit backdrop, with the jet renders from
tools/blender/pass_icons.py on top.

  VIP Pilot: the F-16A in VIP Gold, banking out of a gold sunburst, gold contrails, "VIP" across the bottom.
  Extra Lineup Slot: three jets in echelon in three camos, and a "+1" badge.
  Custom Callsign: a jet under the HUD's target box, with a callsign over it the way the game shows names.

  python tools/passes/pass_icons.py --jets <dir with PassJet_*.png> [--out docs/art/passes]
"""

import argparse
import math
import os

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

SIZE = 512
SS = 2  # drawn at twice the size, then halved
S = SIZE * SS
FONT_HEAVY = r"C:\Windows\Fonts\impact.ttf"
FONT_MONO = r"C:\Windows\Fonts\consolab.ttf"

GOLD = (255, 196, 60)
GOLD_DEEP = (176, 112, 20)
BLUE = (70, 150, 255)
ORANGE = (255, 138, 61)
HUD = (110, 255, 150)
WHITE = (245, 247, 252)
INK = (8, 12, 24)


def radial(inner, outer, centre=(0.5, 0.5), radius=0.75):
    """A radial gradient from inner (at centre) to outer (at radius, as a fraction of the size)."""
    img = Image.new("RGB", (S, S))
    px = img.load()
    cx, cy = centre[0] * S, centre[1] * S
    r = radius * S
    for y in range(0, S, 2):
        for x in range(0, S, 2):
            t = min(math.hypot(x - cx, y - cy) / r, 1.0) ** 1.3
            c = tuple(int(inner[i] + (outer[i] - inner[i]) * t) for i in range(3))
            px[x, y] = c
            if x + 1 < S:
                px[x + 1, y] = c
            if y + 1 < S:
                px[x, y + 1] = c
                if x + 1 < S:
                    px[x + 1, y + 1] = c
    return img.convert("RGBA")


def rays(img, centre, colour, count=18, alpha=46):
    """A sunburst of soft wedges from centre."""
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    cx, cy = centre[0] * S, centre[1] * S
    for i in range(count):
        a0 = (i / count) * 2 * math.pi
        a1 = a0 + math.pi / count * 0.55
        far = S * 1.2
        d.polygon(
            [(cx, cy), (cx + far * math.cos(a0), cy + far * math.sin(a0)), (cx + far * math.cos(a1), cy + far * math.sin(a1))],
            fill=colour + (alpha,),
        )
    return Image.alpha_composite(img, layer.filter(ImageFilter.GaussianBlur(S * 0.006)))


def glow(img, centre, colour, radius, strength=200):
    """A soft round glow."""
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    cx, cy = centre[0] * S, centre[1] * S
    r = radius * S
    d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=colour + (strength,))
    return Image.alpha_composite(img, layer.filter(ImageFilter.GaussianBlur(r * 0.55)))


def streak(img, start, end, colour, width, fade=True):
    """A contrail: a soft line that fades from start to end."""
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    steps = 60
    for i in range(steps):
        t0, t1 = i / steps, (i + 1) / steps
        a = int(230 * (1 - t0) ** 1.4) if fade else 230
        p0 = (start[0] * S + (end[0] - start[0]) * S * t0, start[1] * S + (end[1] - start[1]) * S * t0)
        p1 = (start[0] * S + (end[0] - start[0]) * S * t1, start[1] * S + (end[1] - start[1]) * S * t1)
        d.line([p0, p1], fill=colour + (a,), width=max(int(width * S * (1 - 0.5 * t0)), 1))
    soft = layer.filter(ImageFilter.GaussianBlur(S * 0.004))
    return Image.alpha_composite(img, soft)


def place(img, jet_path, centre, width, shadow=True):
    """Pastes a jet render, scaled to width (fraction of the size), centred on centre, with a soft shadow."""
    jet = Image.open(jet_path).convert("RGBA")
    w = int(width * S)
    h = int(jet.height * w / jet.width)
    jet = jet.resize((w, h), Image.LANCZOS)
    x, y = int(centre[0] * S - w / 2), int(centre[1] * S - h / 2)
    if shadow:
        sh = Image.new("RGBA", jet.size, (0, 0, 0, 0))
        sh.putalpha(jet.getchannel("A").point(lambda a: a * 0.55))
        sh = sh.filter(ImageFilter.GaussianBlur(S * 0.012))
        img.alpha_composite(sh, (x + int(S * 0.015), y + int(S * 0.03)))
    img.alpha_composite(jet, (x, y))
    return img


def text(img, words, font_path, size, centre, fill, outline=INK, stroke=0.06, spacing=0):
    """Text centred on centre (fractions), with an outline stroke as a fraction of the size."""
    font = ImageFont.truetype(font_path, int(size * S))
    d = ImageDraw.Draw(img)
    sw = max(int(size * S * stroke), 1)
    if spacing:
        widths = [d.textlength(ch, font=font) + spacing * S for ch in words]
        total = sum(widths) - spacing * S
        x = centre[0] * S - total / 2
        for ch, cw in zip(words, widths):
            d.text((x, centre[1] * S), ch, font=font, fill=fill, anchor="lm", stroke_width=sw, stroke_fill=outline)
            x += cw
    else:
        d.text((centre[0] * S, centre[1] * S), words, font=font, fill=fill, anchor="mm", stroke_width=sw, stroke_fill=outline)
    return img


def ring(img, colour, inner_colour=None):
    """The roundel's ring, with a thin bright edge inside it, and everything outside the circle cleared."""
    d = ImageDraw.Draw(img)
    m = S * 0.012
    w = S * 0.045
    d.ellipse((m, m, S - m, S - m), outline=colour, width=int(w))
    edge = inner_colour or tuple(min(255, c + 70) for c in colour)
    d.ellipse((m + w, m + w, S - m - w, S - m - w), outline=edge, width=int(S * 0.006))
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).ellipse((m * 0.4, m * 0.4, S - m * 0.4, S - m * 0.4), fill=255)
    img.putalpha(ImageChops.multiply(img.getchannel("A"), mask))
    return img


def vip(jets):
    img = radial((70, 46, 10), (6, 8, 16), centre=(0.5, 0.42), radius=0.72)
    img = rays(img, (0.5, 0.42), GOLD, count=20, alpha=40)
    img = glow(img, (0.5, 0.42), GOLD, 0.26, strength=150)
    img = streak(img, (0.22, 0.56), (-0.06, 0.74), (255, 222, 140), 0.03)  # the afterburner's trail
    img = place(img, os.path.join(jets, "PassJet_VIP.png"), (0.5, 0.42), 0.7)
    # A gold banner across the bottom with VIP on it
    d = ImageDraw.Draw(img)
    top, bottom = 0.65 * S, 0.82 * S
    d.polygon([(0.17 * S, top), (0.83 * S, top), (0.79 * S, bottom), (0.21 * S, bottom)], fill=GOLD_DEEP + (255,))
    d.polygon([(0.18 * S, top + S * 0.008), (0.82 * S, top + S * 0.008), (0.785 * S, bottom - S * 0.008), (0.215 * S, bottom - S * 0.008)], fill=GOLD + (255,))
    img = text(img, "VIP", FONT_HEAVY, 0.15, (0.5, 0.735), INK, outline=GOLD, stroke=0.0, spacing=0.012)
    img = text(img, "PILOT", FONT_HEAVY, 0.06, (0.5, 0.875), GOLD, stroke=0.12, spacing=0.012)
    return ring(img, GOLD_DEEP, GOLD)


def lineup(jets):
    img = radial((40, 96, 190), (6, 14, 34), centre=(0.5, 0.38), radius=0.8)
    img = glow(img, (0.5, 0.4), (120, 190, 255), 0.3, strength=90)
    for (x, y), name in zip(((0.34, 0.28), (0.53, 0.43), (0.72, 0.58)), ("LineupB", "LineupC", "LineupA")):
        img = streak(img, (x - 0.12, y + 0.04), (x - 0.42, y + 0.2), (230, 240, 255), 0.01)
        img = place(img, os.path.join(jets, f"PassJet_{name}.png"), (x, y), 0.4)
    # The +1 badge
    d = ImageDraw.Draw(img)
    cx, cy, r = 0.64 * S, 0.77 * S, 0.115 * S
    d.ellipse((cx - r - S * 0.012, cy - r - S * 0.012, cx + r + S * 0.012, cy + r + S * 0.012), fill=INK + (255,))
    d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=ORANGE + (255,))
    img = text(img, "+1", FONT_HEAVY, 0.13, (0.64, 0.765), WHITE, stroke=0.05)
    img = text(img, "SLOT", FONT_HEAVY, 0.065, (0.4, 0.77), WHITE, stroke=0.12, spacing=0.01)
    return ring(img, (34, 92, 200), BLUE)


def callsign(jets):
    img = radial((20, 70, 50), (4, 12, 14), centre=(0.5, 0.55), radius=0.75)
    img = glow(img, (0.5, 0.6), HUD, 0.22, strength=60)
    # Faint HUD pitch lines behind
    d = ImageDraw.Draw(img)
    for i, y in enumerate((0.22, 0.86)):
        d.line([(0.2 * S, y * S), (0.38 * S, y * S)], fill=HUD + (70,), width=int(S * 0.006))
        d.line([(0.62 * S, y * S), (0.8 * S, y * S)], fill=HUD + (70,), width=int(S * 0.006))
    img = place(img, os.path.join(jets, "PassJet_Callsign.png"), (0.5, 0.6), 0.72)
    # The target box round the jet, corner brackets only
    d = ImageDraw.Draw(img)
    x0, y0, x1, y1 = 0.2 * S, 0.44 * S, 0.8 * S, 0.78 * S
    arm, w = 0.07 * S, int(S * 0.012)
    for (cx, cy, sx, sy) in ((x0, y0, 1, 1), (x1, y0, -1, 1), (x0, y1, 1, -1), (x1, y1, -1, -1)):
        d.line([(cx, cy + sy * arm), (cx, cy), (cx + sx * arm, cy)], fill=HUD + (255,), width=w, joint="curve")
    # The callsign tag over it
    tag_top, tag_bottom = 0.25 * S, 0.37 * S
    d.rounded_rectangle((0.18 * S, tag_top, 0.82 * S, tag_bottom), radius=S * 0.02, fill=(6, 20, 14, 220), outline=HUD + (255,), width=int(S * 0.008))
    img = text(img, "YOUR NAME", FONT_MONO, 0.075, (0.5, 0.31), HUD, outline=(6, 20, 14), stroke=0.0)
    d = ImageDraw.Draw(img)
    d.polygon([(0.47 * S, tag_bottom), (0.53 * S, tag_bottom), (0.5 * S, tag_bottom + S * 0.03)], fill=HUD + (255,))
    return ring(img, (24, 120, 70), HUD)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--jets", required=True)
    parser.add_argument("--out", default=os.path.join("docs", "art", "passes"))
    args = parser.parse_args()
    os.makedirs(args.out, exist_ok=True)
    for name, make in (("VIP", vip), ("ExtraLineupSlot", lineup), ("CustomCallsign", callsign)):
        img = make(args.jets).resize((SIZE, SIZE), Image.LANCZOS)
        path = os.path.join(args.out, f"Pass_{name}.png")
        img.save(path)
        print("pass icon", path)


if __name__ == "__main__":
    main()
