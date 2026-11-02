"""
Afterburner: the game pass icons (Config/Passes), 512 x 512. Roblox shows pass icons cropped to a circle, so
each is a roundel: a bevelled metal ring in the pass's colour round a lit, textured backdrop, with the jet
renders from tools/blender/pass_icons.py on top. Made to look cool, not realistic (Will): light rays, glowing
trails, bloom, sparkles and lettering with depth.

  VIP Pilot: the F-16A in VIP Gold banking out of a gold sunburst on burner, a gold banner with VIP.
  Extra Lineup Slot: three jets in echelon through an electric-blue sky, and a glossy +1 orb.
  Custom Callsign: a jet locked in the HUD's target box under a glowing callsign tag, on a radar display.

  python tools/passes/pass_icons.py --jets <dir with PassJet_*.png> [--out docs/art/passes]
"""

import argparse
import math
import os

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

SIZE = 512
SS = 2  # drawn at twice the size, then halved
S = SIZE * SS
FONT_HEAVY = r"C:\Windows\Fonts\impact.ttf"
FONT_MONO = r"C:\Windows\Fonts\consolab.ttf"
RNG = np.random.default_rng(7)

GOLD = (255, 196, 60)
GOLD_LIGHT = (255, 236, 160)
GOLD_DEEP = (150, 92, 14)
BLUE = (70, 150, 255)
ORANGE = (255, 138, 61)
HUD = (110, 255, 150)
WHITE = (245, 247, 252)
INK = (8, 12, 24)

YY, XX = np.mgrid[0:S, 0:S].astype(np.float32) / S


# ---------------------------------------------------------------------------------------------- helpers


def to_img(rgb, alpha=None):
    """Float RGB (0-1) array to an RGBA image."""
    arr = np.clip(rgb * 255, 0, 255).astype(np.uint8)
    img = Image.fromarray(arr, "RGB").convert("RGBA")
    if alpha is not None:
        img.putalpha(Image.fromarray(np.clip(alpha * 255, 0, 255).astype(np.uint8), "L"))
    return img


def col(c):
    return np.array(c, np.float32) / 255


def radial(inner, outer, centre=(0.5, 0.5), radius=0.75, power=1.3):
    d = np.clip(np.hypot(XX - centre[0], YY - centre[1]) / radius, 0, 1) ** power
    rgb = col(inner)[None, None] * (1 - d[..., None]) + col(outer)[None, None] * d[..., None]
    return to_img(rgb)


def noise(scale, octaves=4, seed=0):
    """Soft fractal noise, 0-1, made by blowing up random grids."""
    rng = np.random.default_rng(seed)
    total = np.zeros((S, S), np.float32)
    amp, weight = 1.0, 0.0
    for o in range(octaves):
        n = max(int(scale * 2 ** o), 2)
        grid = Image.fromarray((rng.random((n, n)) * 255).astype(np.uint8), "L")
        total += np.asarray(grid.resize((S, S), Image.BICUBIC), np.float32) / 255 * amp
        weight += amp
        amp *= 0.5
    total /= weight
    return (total - total.min()) / (total.max() - total.min() + 1e-6)


def tint_layer(mask, colour, strength=1.0):
    """A colour layer whose alpha is mask (0-1)."""
    rgb = np.ones((S, S, 3), np.float32) * col(colour)[None, None]
    return to_img(rgb, np.clip(mask * strength, 0, 1))


def add(img, layer):
    """Additive (screen-like) blend of layer's colour by its alpha."""
    base = np.asarray(img, np.float32) / 255
    top = np.asarray(layer, np.float32) / 255
    rgb = base[..., :3] + top[..., :3] * top[..., 3:4]
    out = np.concatenate([np.clip(rgb, 0, 1), base[..., 3:4]], -1)
    return Image.fromarray((out * 255).astype(np.uint8), "RGBA")


def rays(img, centre, colour, count=24, alpha=0.22, length=1.0, seed=1):
    rng = np.random.default_rng(seed)
    ang = np.arctan2(YY - centre[1], XX - centre[0])
    dist = np.hypot(XX - centre[0], YY - centre[1])
    band = np.zeros((S, S), np.float32)
    for _ in range(count):
        a = rng.uniform(-math.pi, math.pi)
        w = rng.uniform(0.015, 0.06)
        diff = np.angle(np.exp(1j * (ang - a)))
        band = np.maximum(band, np.clip(1 - np.abs(diff) / w, 0, 1) * rng.uniform(0.5, 1))
    fade = np.clip(1 - dist / length, 0, 1) ** 1.2
    layer = tint_layer(band * fade, colour, alpha * 3)
    return add(img, layer.filter(ImageFilter.GaussianBlur(S * 0.004)))


def glow(img, centre, colour, radius, strength=0.9):
    d = np.hypot(XX - centre[0], YY - centre[1]) / radius
    return add(img, tint_layer(np.exp(-d * d * 2.5), colour, strength))


def streak(img, start, end, colour, width, core=WHITE, halo=2.5):
    """A glowing trail: a white-hot core in a coloured halo, fading from start to end."""
    p0, p1 = np.array(start, np.float32), np.array(end, np.float32)
    seg = p1 - p0
    length = float(np.hypot(*seg)) + 1e-6
    t = np.clip(((XX - p0[0]) * seg[0] + (YY - p0[1]) * seg[1]) / (length * length), 0, 1)
    px, py = p0[0] + seg[0] * t, p0[1] + seg[1] * t
    d = np.hypot(XX - px, YY - py)
    w = width * (1 - 0.7 * t)
    fade = (1 - t) ** 1.5
    halo_mask = np.exp(-(d / (w * halo)) ** 2) * fade
    core_mask = np.exp(-(d / (w * 0.45)) ** 2) * fade
    img = add(img, tint_layer(halo_mask, colour, 0.9))
    return add(img, tint_layer(core_mask, core, 1.0))


def speed_lines(img, direction, colour, count=40, seed=3, alpha=0.35):
    rng = np.random.default_rng(seed)
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    dx, dy = direction
    for _ in range(count):
        x, y = rng.uniform(0, 1), rng.uniform(0, 1)
        length = rng.uniform(0.08, 0.3)
        a = int(255 * alpha * rng.uniform(0.3, 1))
        d.line([(x * S, y * S), ((x + dx * length) * S, (y + dy * length) * S)], fill=colour + (a,), width=int(rng.uniform(1, 3) * SS))
    return Image.alpha_composite(img, layer.filter(ImageFilter.GaussianBlur(1.2)))


def sparkle(img, at, size, colour=WHITE):
    """A four-pointed star glint with a soft glow."""
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    x, y = at[0] * S, at[1] * S
    r = size * S
    for (ax, ay) in ((1, 0), (0, 1)):
        d.polygon([(x - ax * r, y - ay * r), (x + ay * r * 0.12, y + ax * r * 0.12), (x + ax * r, y + ay * r), (x - ay * r * 0.12, y - ax * r * 0.12)], fill=colour + (255,))
    img = Image.alpha_composite(img, layer.filter(ImageFilter.GaussianBlur(r * 0.08)))
    return glow(img, at, colour, size * 0.8, 0.6)


def bloom(img, threshold=0.72, radius=0.03, strength=0.7):
    arr = np.asarray(img, np.float32) / 255
    lum = arr[..., :3].mean(-1)
    bright = np.clip((lum - threshold) / (1 - threshold), 0, 1)[..., None] * arr[..., :3]
    layer = to_img(bright, np.ones((S, S), np.float32)).filter(ImageFilter.GaussianBlur(S * radius))
    la = np.asarray(layer, np.float32) / 255
    out = np.clip(arr[..., :3] + la[..., :3] * strength, 0, 1)
    return Image.fromarray((np.concatenate([out, arr[..., 3:4]], -1) * 255).astype(np.uint8), "RGBA")


def vignette(img, strength=0.55):
    d = np.clip(np.hypot(XX - 0.5, YY - 0.5) / 0.5, 0, 1) ** 2.2
    arr = np.asarray(img, np.float32) / 255
    arr[..., :3] *= (1 - d * strength)[..., None]
    return Image.fromarray((arr * 255).astype(np.uint8), "RGBA")


def place(img, jet_path, centre, width, rim=None, rim_strength=1.0):
    """Pastes a jet render with a soft drop shadow and, optionally, a coloured glow round its outline."""
    jet = Image.open(jet_path).convert("RGBA")
    w = int(width * S)
    h = int(jet.height * w / jet.width)
    jet = jet.resize((w, h), Image.LANCZOS)
    x, y = int(centre[0] * S - w / 2), int(centre[1] * S - h / 2)
    # The renders carry faint noise in their empty corners: clear it, or the glow draws a box round the jet
    jet.putalpha(jet.getchannel("A").point(lambda a: 0 if a < 24 else a))
    # Room round the jet so its shadow and glow can spread past its edges without being cut off
    pad = int(S * 0.06)
    padded = Image.new("RGBA", (w + pad * 2, h + pad * 2), (0, 0, 0, 0))
    padded.alpha_composite(jet, (pad, pad))
    jet, x, y = padded, x - pad, y - pad
    alpha = jet.getchannel("A")
    shadow = Image.new("RGBA", jet.size, (0, 0, 0, 0))
    shadow.putalpha(alpha.point(lambda a: a * 0.6))
    img = Image.alpha_composite(img, _onto(shadow.filter(ImageFilter.GaussianBlur(S * 0.014)), x + int(S * 0.012), y + int(S * 0.03)))
    if rim:
        halo = Image.new("RGBA", jet.size, rim + (0,))
        halo.putalpha(alpha.filter(ImageFilter.GaussianBlur(S * 0.012)).point(lambda a: min(255, a * 1.6 * rim_strength)))
        img = add(img, _onto(halo, x, y))
    return Image.alpha_composite(img, _onto(jet, x, y))


def _onto(layer, x, y):
    """A layer placed at (x, y) on a full-size transparent canvas (it may hang off any edge)."""
    full = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    full.paste(layer, (x, y), layer)
    return full


def gradient_text(img, words, font_path, size, centre, top, bottom, outline=INK, stroke=0.07, glow_colour=None, spacing=0.0):
    """Lettering with a vertical gradient, a dark outline, a bright top edge, a drop shadow and a glow."""
    font = ImageFont.truetype(font_path, int(size * S))
    mask = Image.new("L", (S, S), 0)
    md = ImageDraw.Draw(mask)
    sw = max(int(size * S * stroke), 1)
    cx, cy = centre[0] * S, centre[1] * S

    def draw(d, offset=(0, 0), **kw):
        if spacing:
            widths = [md.textlength(ch, font=font) + spacing * S for ch in words]
            x = cx - (sum(widths) - spacing * S) / 2 + offset[0]
            for ch, cw in zip(words, widths):
                d.text((x, cy + offset[1]), ch, font=font, anchor="lm", **kw)
                x += cw
        else:
            d.text((cx + offset[0], cy + offset[1]), words, font=font, anchor="mm", **kw)

    if glow_colour:
        g = Image.new("L", (S, S), 0)
        draw(ImageDraw.Draw(g), fill=255, stroke_width=sw * 2, stroke_fill=255)
        img = add(img, tint_layer(np.asarray(g.filter(ImageFilter.GaussianBlur(S * 0.02)), np.float32) / 255, glow_colour, 0.9))
    shadow = Image.new("L", (S, S), 0)
    draw(ImageDraw.Draw(shadow), offset=(S * 0.006, S * 0.012), fill=255, stroke_width=sw, stroke_fill=255)
    img = Image.alpha_composite(img, tint_layer(np.asarray(shadow.filter(ImageFilter.GaussianBlur(S * 0.006)), np.float32) / 255, (0, 0, 0), 0.7))
    outline_layer = Image.new("L", (S, S), 0)
    draw(ImageDraw.Draw(outline_layer), fill=255, stroke_width=sw, stroke_fill=255)
    img = Image.alpha_composite(img, tint_layer(np.asarray(outline_layer, np.float32) / 255, outline))
    draw(md, fill=255)
    box = mask.getbbox() or (0, 0, S, S)
    t = np.clip((YY * S - box[1]) / max(box[3] - box[1], 1), 0, 1)[..., None]
    rgb = col(top)[None, None] * (1 - t) + col(bottom)[None, None] * t
    img = Image.alpha_composite(img, to_img(rgb, np.asarray(mask, np.float32) / 255))
    # bright top edge: the mask minus itself shifted down
    shifted = ImageChops.offset(mask, 0, int(S * 0.006))
    edge = ImageChops.subtract(mask, shifted)
    return add(img, tint_layer(np.asarray(edge, np.float32) / 255, WHITE, 0.6))


def ring(img, colour, light, dark, studs=None):
    """A bevelled metal ring: shaded round the circle like turned metal, a bright inner lip, a glow inside, studs."""
    m = 0.012
    w = 0.05
    dist = np.hypot(XX - 0.5, YY - 0.5)
    outer, inner = 0.5 - m, 0.5 - m - w
    band = (dist <= outer) & (dist >= inner)
    ang = np.arctan2(YY - 0.5, XX - 0.5)
    sheen = 0.5 + 0.5 * np.cos(2 * (ang + 0.8))  # two highlights, like brushed metal
    across = (dist - inner) / w  # 0 inner edge, 1 outer
    bevel = 1 - np.abs(across - 0.35) * 1.4
    shade = np.clip(0.35 * sheen + 0.65 * bevel, 0, 1)[..., None]
    rgb = col(dark)[None, None] * (1 - shade) + col(light)[None, None] * shade
    arr = np.asarray(img, np.float32) / 255
    arr[..., :3] = np.where(band[..., None], rgb, arr[..., :3])
    img = Image.fromarray((np.clip(arr, 0, 1) * 255).astype(np.uint8), "RGBA")
    # inner shadow just inside the ring, then a thin bright lip
    inside = np.clip(1 - (inner - dist) / 0.04, 0, 1) * (dist < inner)
    img = Image.alpha_composite(img, tint_layer(inside * 0.55, (0, 0, 0)))
    lip = np.exp(-((dist - inner) / 0.004) ** 2)
    img = add(img, tint_layer(lip, light, 0.8))
    img = add(img, tint_layer(np.exp(-((dist - inner + 0.03) / 0.03) ** 2) * (dist < inner), colour, 0.25))
    if studs:
        for k in range(studs):
            a = k / studs * 2 * math.pi - math.pi / 2
            cx, cy = 0.5 + math.cos(a) * (inner + w / 2), 0.5 + math.sin(a) * (inner + w / 2)
            sd = np.hypot(XX - cx, YY - cy)
            stud = np.clip(1 - sd / 0.016, 0, 1)
            img = Image.alpha_composite(img, tint_layer((sd < 0.016).astype(np.float32), dark))
            img = add(img, tint_layer(stud ** 2, light, 1.0))
    mask = Image.fromarray(((dist <= 0.5 - m * 0.4) * 255).astype(np.uint8), "L").filter(ImageFilter.GaussianBlur(1))
    img.putalpha(ImageChops.multiply(img.getchannel("A"), mask))
    return img


# ---------------------------------------------------------------------------------------------- icons


def vip(jets):
    img = radial((110, 64, 8), (6, 6, 12), centre=(0.5, 0.4), radius=0.75)
    nebula = noise(5, 5, seed=11)
    img = add(img, tint_layer(nebula ** 2.2 * (1 - np.hypot(XX - 0.5, YY - 0.4)), (255, 170, 60), 0.5))
    img = rays(img, (0.5, 0.4), GOLD, count=28, alpha=0.3, length=0.75)
    img = glow(img, (0.5, 0.4), (255, 210, 120), 0.2, 0.7)
    # Twin afterburner trails out of the tail, then the jet over them
    img = streak(img, (0.27, 0.57), (-0.05, 0.78), (255, 140, 40), 0.018)
    img = streak(img, (0.3, 0.6), (0.02, 0.86), (255, 170, 60), 0.012)
    img = place(img, os.path.join(jets, "PassJet_VIP.png"), (0.51, 0.42), 0.68, rim=(255, 190, 70), rim_strength=0.45)
    img = glow(img, (0.25, 0.58), (255, 150, 40), 0.06, 0.9)  # the burner's bloom at the nozzle
    for at, size in (((0.78, 0.2), 0.035), ((0.2, 0.3), 0.022), ((0.7, 0.55), 0.018), ((0.36, 0.17), 0.015)):
        img = sparkle(img, at, size, GOLD_LIGHT)
    # Banner: gold metal with a bevel, VIP stamped into it
    top, bottom = 0.655, 0.82
    poly = [(0.15, top), (0.85, top), (0.81, bottom), (0.19, bottom)]
    bmask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(bmask).polygon([(x * S, y * S) for x, y in poly], fill=255)
    bm = np.asarray(bmask, np.float32) / 255
    t = np.clip((YY - top) / (bottom - top), 0, 1)
    shade = (0.85 - 0.55 * t + 0.25 * np.exp(-((t - 0.18) / 0.08) ** 2))[..., None]
    rgb = col(GOLD_DEEP)[None, None] * (1 - shade) + col(GOLD_LIGHT)[None, None] * shade
    edge = Image.new("L", (S, S), 0)
    ImageDraw.Draw(edge).polygon([((x - 0.006 if x < 0.5 else x + 0.006) * S, (y - 0.008 if y < 0.7 else y + 0.008) * S) for x, y in poly], fill=255)
    img = Image.alpha_composite(img, tint_layer(np.asarray(edge.filter(ImageFilter.GaussianBlur(S * 0.006)), np.float32) / 255, (40, 22, 2), 1.0))
    img = Image.alpha_composite(img, to_img(rgb, bm))
    img = gradient_text(img, "VIP", FONT_HEAVY, 0.15, (0.5, 0.737), (70, 38, 4), (20, 10, 0), outline=(255, 236, 170), stroke=0.035, spacing=0.012)
    img = gradient_text(img, "PILOT", FONT_HEAVY, 0.062, (0.5, 0.878), WHITE, GOLD, outline=(40, 22, 2), stroke=0.1, glow_colour=GOLD, spacing=0.014)
    img = bloom(img, 0.88, 0.025, 0.45)
    img = vignette(img, 0.45)
    return ring(img, GOLD, GOLD_LIGHT, GOLD_DEEP, studs=8)


def lineup(jets):
    img = radial((40, 120, 235), (4, 10, 34), centre=(0.55, 0.3), radius=0.85)
    clouds = noise(4, 5, seed=21)
    img = add(img, tint_layer(np.clip(clouds - 0.45, 0, 1) * 1.6 * (YY > 0.15), (170, 210, 255), 0.45))
    img = rays(img, (0.85, 0.05), (160, 210, 255), count=14, alpha=0.18, length=1.1, seed=4)
    img = speed_lines(img, (-0.92, 0.38), (200, 230, 255), count=46, alpha=0.4)
    for (x, y), name in zip(((0.34, 0.27), (0.53, 0.42), (0.72, 0.57)), ("LineupB", "LineupC", "LineupA")):
        img = streak(img, (x - 0.13, y + 0.035), (x - 0.48, y + 0.2), (110, 180, 255), 0.01)
        img = place(img, os.path.join(jets, f"PassJet_{name}.png"), (x, y), 0.4, rim=(120, 190, 255))
    img = sparkle(img, (0.86, 0.3), 0.028)
    img = sparkle(img, (0.18, 0.5), 0.018)
    # The +1 orb: glossy orange with a highlight and a glow
    cx, cy, r = 0.64, 0.775, 0.12
    img = glow(img, (cx, cy), ORANGE, 0.2, 0.8)
    d = np.hypot(XX - cx, YY - cy) / r
    orb = (d <= 1).astype(np.float32)
    shade = np.clip(1 - d, 0, 1) ** 0.6
    rgb = col((150, 50, 8))[None, None] * (1 - shade[..., None]) + col((255, 170, 80))[None, None] * shade[..., None]
    rim_ring = np.exp(-((d - 1) / 0.06) ** 2)
    img = Image.alpha_composite(img, tint_layer(rim_ring, INK, 1.0))
    img = Image.alpha_composite(img, to_img(rgb, orb))
    gloss = np.clip(1 - np.hypot((XX - cx) / (r * 0.75), (YY - (cy - r * 0.45)) / (r * 0.4)), 0, 1) ** 1.5
    img = add(img, tint_layer(gloss * orb, WHITE, 0.7))
    img = gradient_text(img, "+1", FONT_HEAVY, 0.13, (cx, cy + 0.002), WHITE, (255, 225, 190), outline=(90, 30, 0), stroke=0.06)
    img = gradient_text(img, "SLOT", FONT_HEAVY, 0.068, (0.385, 0.775), WHITE, (170, 210, 255), outline=INK, stroke=0.1, glow_colour=BLUE, spacing=0.012)
    img = bloom(img, 0.8, 0.025, 0.55)
    img = vignette(img, 0.4)
    return ring(img, BLUE, (180, 220, 255), (14, 50, 130), studs=8)


def callsign(jets):
    img = radial((16, 80, 56), (2, 10, 12), centre=(0.5, 0.58), radius=0.78)
    # Radar display: range rings, a grid and a sweep wedge
    grid = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    gd = ImageDraw.Draw(grid)
    for k in range(1, 5):
        r = k * 0.11 * S
        gd.ellipse((S / 2 - r, S * 0.58 - r, S / 2 + r, S * 0.58 + r), outline=HUD + (40,), width=SS)
    for k in range(-6, 7):
        x = S / 2 + k * 0.08 * S
        gd.line([(x, 0), (x, S)], fill=HUD + (16,), width=1)
        gd.line([(0, S * 0.58 + k * 0.08 * S), (S, S * 0.58 + k * 0.08 * S)], fill=HUD + (16,), width=1)
    img = Image.alpha_composite(img, grid)
    ang = np.arctan2(YY - 0.58, XX - 0.5)
    sweep = np.angle(np.exp(1j * (ang - 0.9)))
    wedge = np.clip(1 + sweep / 1.1, 0, 1) * (sweep < 0) * (np.hypot(XX - 0.5, YY - 0.58) < 0.44)
    img = add(img, tint_layer(wedge ** 2, HUD, 0.28))
    scan = (np.sin(YY * S * 0.9) * 0.5 + 0.5) * 0.06
    img = Image.alpha_composite(img, tint_layer(scan, (0, 0, 0)))
    img = glow(img, (0.5, 0.6), HUD, 0.25, 0.35)
    img = place(img, os.path.join(jets, "PassJet_Callsign.png"), (0.5, 0.6), 0.72, rim=(120, 255, 170))
    img = glow(img, (0.21, 0.62), (255, 150, 40), 0.05, 0.8)  # afterburner bloom
    # The target box, glowing brackets
    box = Image.new("L", (S, S), 0)
    bd = ImageDraw.Draw(box)
    x0, y0, x1, y1 = 0.19 * S, 0.44 * S, 0.81 * S, 0.79 * S
    arm, w = 0.08 * S, int(S * 0.012)
    for (cx, cy, sx, sy) in ((x0, y0, 1, 1), (x1, y0, -1, 1), (x0, y1, 1, -1), (x1, y1, -1, -1)):
        bd.line([(cx, cy + sy * arm), (cx, cy), (cx + sx * arm, cy)], fill=255, width=w, joint="curve")
    bm = np.asarray(box, np.float32) / 255
    img = add(img, tint_layer(np.asarray(box.filter(ImageFilter.GaussianBlur(S * 0.012)), np.float32) / 255, HUD, 1.2))
    img = Image.alpha_composite(img, tint_layer(bm, (210, 255, 225)))
    # Callsign tag: a glowing panel with the name in HUD green
    panel = Image.new("L", (S, S), 0)
    ImageDraw.Draw(panel).rounded_rectangle((0.17 * S, 0.245 * S, 0.83 * S, 0.37 * S), radius=S * 0.02, fill=255)
    pm = np.asarray(panel, np.float32) / 255
    img = add(img, tint_layer(np.asarray(panel.filter(ImageFilter.GaussianBlur(S * 0.03)), np.float32) / 255, HUD, 0.5))
    img = Image.alpha_composite(img, tint_layer(pm, (4, 22, 14), 0.88))
    outline = np.asarray(panel.filter(ImageFilter.FIND_EDGES).filter(ImageFilter.MaxFilter(5)), np.float32) / 255
    img = add(img, tint_layer(outline, HUD, 1.0))
    img = gradient_text(img, "YOUR NAME", FONT_MONO, 0.078, (0.5, 0.307), (220, 255, 230), HUD, outline=(4, 22, 14), stroke=0.02, glow_colour=HUD)
    tip = Image.new("L", (S, S), 0)
    ImageDraw.Draw(tip).polygon([(0.47 * S, 0.37 * S), (0.53 * S, 0.37 * S), (0.5 * S, 0.405 * S)], fill=255)
    img = add(img, tint_layer(np.asarray(tip, np.float32) / 255, HUD, 1.0))
    img = sparkle(img, (0.8, 0.5), 0.02, (200, 255, 220))
    img = bloom(img, 0.75, 0.02, 0.5)
    img = vignette(img, 0.4)
    return ring(img, HUD, (170, 255, 200), (10, 70, 40), studs=8)


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
