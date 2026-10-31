"""
Afterburner: the level-reward liveries (Config/LevelRewards.SKINS), the game's own paint for every jet:
  Squadron  Squadron Black (level 10): gloss near-black, dark-grey panel lines, orange cheat line and fin band
  AceGold   Ace Gold (level 25): gunmetal with gold leading edges, fin tips and a fuselage pinstripe
  Legend    Legend Chrome (level 50): polished chrome, black anti-glare panel and radome, orange fin tips
No national markings. Each painter (jet_paint.py, f5e_paint.py, mig21_paint.py) paints the base from the
scheme as usual, honouring three extra keys:
  rough        base roughness; metalness  base metalness; line_colour  panel lines lighten towards this
and then calls trim() for the stripes. Every stripe is placed from the jet's own baked texels (the
fuselage's height, the most forward point of each tail surface, the top of each fin), so one scheme fits
every airframe without a per-jet layout.
"""

import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import f5e_paint as paint  # noqa: E402

srgb, smooth = paint.srgb, paint.smooth

ORANGE = srgb(255, 138, 61)  # the game's accent, #FF8A3D
GOLD = srgb(232, 184, 92)

SCHEMES = {
    "Squadron": {
        "base": srgb(24, 25, 28),
        "upper": srgb(24, 25, 28),
        "lower": srgb(24, 25, 28),
        "radome": srgb(30, 31, 34),
        "antiglare": srgb(13, 13, 14),
        "walkway": srgb(36, 37, 40),
        "insignia": srgb(24, 25, 28),
        "markings": "none",
        "rough": 0.32,
        "line_colour": srgb(58, 60, 64),
        "livery": "Squadron",
    },
    "AceGold": {
        "base": srgb(64, 68, 74),
        "upper": srgb(64, 68, 74),
        "lower": srgb(64, 68, 74),
        "radome": srgb(48, 51, 56),
        "antiglare": srgb(26, 27, 30),
        "walkway": srgb(44, 46, 50),
        "insignia": srgb(64, 68, 74),
        "markings": "none",
        "rough": 0.34,
        "metalness": 0.45,
        "livery": "AceGold",
    },
    "Legend": {
        "base": srgb(232, 234, 238),
        "upper": srgb(232, 234, 238),
        "lower": srgb(232, 234, 238),
        "metal": True,
        "radome": srgb(22, 22, 24),
        "antiglare": srgb(14, 14, 15),
        "walkway": srgb(60, 62, 66),
        "insignia": srgb(232, 234, 238),
        "markings": "none",
        "rough": 0.08,
        "metalness": 1.0,
        "livery": "Legend",
    },
}

# The Wings camos (Config/Cosmetics "Camo", SHP-07), painted on every jet like the level liveries: sold once
# for every jet. VIP Gold comes with the VIP Pilot pass.
SCHEMES.update({
    "VIPGold": {
        "base": srgb(238, 238, 234),
        "upper": srgb(238, 238, 234),
        "lower": srgb(238, 238, 234),
        "radome": srgb(30, 30, 32),
        "antiglare": srgb(20, 20, 22),
        "walkway": srgb(200, 200, 196),
        "insignia": srgb(238, 238, 234),
        "markings": "none",
        "rough": 0.24,
        "livery": "VIPGold",
    },
    "ArcticSplinter": {
        "camo": [srgb(228, 232, 236), srgb(170, 178, 186), srgb(146, 174, 200)],
        "camo_style": "splinter",
        "camo_scale": 3.0,
        "underside": srgb(214, 220, 226),
        "base": srgb(228, 232, 236),
        "upper": srgb(228, 232, 236),
        "lower": srgb(214, 220, 226),
        "radome": srgb(120, 128, 136),
        "antiglare": srgb(52, 58, 66),
        "walkway": srgb(150, 158, 166),
        "insignia": srgb(228, 232, 236),
        "markings": "none",
    },
    "TigerStripe": {
        "camo": [srgb(232, 142, 40), srgb(22, 20, 18), srgb(232, 142, 40)],
        "camo_style": "tiger",
        "camo_scale": 1.5,
        "underside": srgb(226, 150, 60),
        "base": srgb(232, 142, 40),
        "upper": srgb(232, 142, 40),
        "lower": srgb(226, 150, 60),
        "radome": srgb(22, 20, 18),
        "antiglare": srgb(16, 15, 14),
        "walkway": srgb(60, 56, 52),
        "insignia": srgb(232, 142, 40),
        "markings": "none",
    },
})

# (colour, roughness, metalness) of each livery's stripes
ACCENT = {
    "Squadron": (ORANGE, 0.3, 0.0),
    "AceGold": (GOLD, 0.22, 1.0),
    "Legend": (ORANGE, 0.3, 0.0),
    "VIPGold": (GOLD, 0.2, 1.0),
}


def with_liveries(schemes):
    """A jet's own schemes plus the level liveries and the Wings camos."""
    return {**schemes, **SCHEMES}


def base(scheme, metal_paint):
    """Base roughness and metalness for a scheme (the painters' defaults unless the scheme gives them)."""
    return scheme.get("rough", 0.38 if metal_paint else 0.56), scheme.get("metalness", 0.75 if metal_paint else 0.0)


def lines(scheme, colour, line):
    """Panel lines lightened towards line_colour (on dark schemes, where darkening them would not show)."""
    if "line_colour" in scheme:
        colour = colour + scheme["line_colour"] * (0.6 * line)[..., None]
    return colour


def _front(y, station, mask, step=0.05):
    """Metres aft of the most forward texel of `mask` at the same station (span position), interpolated
    between stations so a swept edge stays straight."""
    out = np.full(y.shape, 99.0, np.float32)
    if not mask.any():
        return out
    s0 = station[mask].min()
    idx = np.floor((station[mask] - s0) / step).astype(np.int64)
    n = int(idx.max()) + 1
    front = np.full(n, -1e9, np.float32)
    np.maximum.at(front, idx, y[mask])
    ok = front > -1e8
    centres = s0 + (np.arange(n) + 0.5) * step
    return np.where(mask, np.interp(station, centres[ok], front[ok]) - y, out)


def _cheat_line(P, fus, y_front, y_back, frac, step=0.25):
    """Height of a straight cheat line along the fuselage: fitted through the point `frac` of the way up
    the fuselage at each station between y_back and y_front."""
    y, z = P[..., 1], P[..., 2]
    m = fus & (y < y_front) & (y > y_back)
    if m.sum() < 100:
        return None
    k = np.floor((y[m] - y_back) / step).astype(np.int64)
    n = int(k.max()) + 1
    lo, hi = np.full(n, 1e9, np.float32), np.full(n, -1e9, np.float32)
    np.minimum.at(lo, k, z[m])
    np.maximum.at(hi, k, z[m])
    ok = hi > lo
    yb = y_back + (np.arange(n) + 0.5) * step
    a, b = np.polyfit(yb[ok], (lo + frac * (hi - lo))[ok], 1)
    return a * y + b


def _band(d, half, soft=0.006):
    return 1 - smooth(half - soft, half + soft, np.abs(d))


def trim(scheme, P, N, ao, line, colour, rough, metal, fus, wings, wing_le, tails, fins, keep, y_front, y_back):
    """The livery's stripes over a painted Body or Wings set.
    fus: the Fuselage part; wings: wing parts (with their leading-edge flaps); wing_le: metres aft of the
    wing's leading edge; tails: one mask per tailplane or canard part; fins: fin and rudder parts;
    keep: texels that keep their paint (radome, anti-glare, intake lips and ducts, hot metal, cockpit
    well); y_front, y_back: where the cheat line runs (Blender Y, forward is +Y)."""
    kind = scheme.get("livery")
    if not kind:
        return colour, rough, metal
    accent = kind
    if kind == "VIPGold":
        kind = "AceGold"  # the same gold leading edges, fin tips and pinstripes, over white
    x, y, z = P[..., 0], P[..., 1], P[..., 2]
    side = np.abs(N[..., 2]) < 0.6
    shape = x.shape
    mask = np.zeros(shape, np.float32)

    # Fins: one group per side (a centre fin is split down the middle too), each with its own top
    for half in (x <= 0, x > 0):
        f = fins & half
        if not f.any():
            continue
        top, root = z[f].max(), np.percentile(z[f], 5)
        h = max(top - root, 0.3)
        if kind == "Squadron":
            band = _band(z - (top - 0.28 * h), 0.07 * h)
        elif kind == "AceGold":
            band = smooth(top - 0.12 * h - 0.01, top - 0.12 * h + 0.01, z)
            band = np.maximum(band, (_front(y, z, f) < 0.10).astype(np.float32))
        else:
            band = smooth(top - 0.09 * h - 0.01, top - 0.09 * h + 0.01, z)
        mask = np.maximum(mask, np.where(f, band, 0))

    if kind == "AceGold":
        # Gold leading edges on the wings, tailplanes and canards
        mask = np.maximum(mask, np.where(wings & (wing_le < 0.10) & (wing_le > -0.5), 1.0, 0))
        for t in tails:
            mask = np.maximum(mask, (_front(y, np.abs(x), t) < 0.10).astype(np.float32))

    if kind in ("Squadron", "AceGold"):
        zl = _cheat_line(P, fus, y_front, y_back, 0.6)
        if zl is not None:
            # Tapered to a point at each end
            taper = smooth(y_back, y_back + 0.8, y) * smooth(y_front, y_front - 0.8, y)
            if kind == "Squadron":
                stripe = _band(z - zl, 0.05 * taper)
            else:  # a pair of pinstripes
                stripe = np.maximum(_band(z - zl - 0.035, 0.016 * taper), _band(z - zl + 0.035, 0.016 * taper))
            mask = np.maximum(mask, np.where(fus & side & (y < y_front) & (y > y_back), stripe, 0))

    mask = np.where(keep, 0, mask)
    c, r, m = ACCENT[accent]
    shade = (1 - 0.3 * line) * (0.55 + 0.45 * np.power(np.clip(ao, 0, 1), 0.8))
    colour = colour * (1 - mask[..., None]) + (c * shade[..., None]) * mask[..., None]
    rough = rough * (1 - mask) + (r + 0.12 * line) * mask
    metal = metal * (1 - mask) + m * mask
    return colour, rough, metal
