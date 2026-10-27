"""
Afterburner: paints the F-4E Phantom II with the shared painter (jet_paint.py): its panel layout, markings
and skins.

  blender -b tools/blender/out/F4E_base.blend --python tools/blender/f4e_paint.py -- \
      --out <absolute dir> [--skin SEA] [--preview]

Use the .blend whose FBX was imported into Studio: the textures follow its UV layout.
"""

import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import f4e_generate as f4  # noqa: E402  (sets the shared generator module to the F-4E)
import jet_paint  # noqa: E402

srgb = jet_paint.srgb
Y = f4.kit.Y


def wing_le(xa):
    """The generator's leading edge (inner and outer panels), for arrays of |x|."""
    hw = xa * f4.PX
    return Y(np.where(hw <= 615, 1160 + (hw - 205) / 0.862, 1636 + (hw - 615) / 0.885))


def wing_te(xa):
    hw = xa * f4.PX
    return Y(np.where(hw <= 610, 1963 + (hw - 185) * 0.2317, 2073 + (hw - 610) * 0.205))


LAYOUT = {
    "body": ["Fuselage", "Intakes", "GunFairing"],
    "frames": [115, 270, 400, 520, 700, 900, 1050, 1240, 1400, 1550, 1700, 1850, 2000, 2150, 2300, 2450, 2600],
    "side_lines": [(0.30, 270, 900), (1.20, 1240, 2280), (0.20, 1240, 2280)],
    "side_panels": [(300, 400, -0.40, 0.20), (1300, 1420, 0.60, 1.10), (1900, 2050, 0.30, 0.90)],
    "wing": (wing_le, wing_te),
    "wings": ["WingL", "WingR", "WingOuterL", "WingOuterR"],
    "surfaces": ["LEFlapL", "LEFlapR", "LEFlapOuterL", "LEFlapOuterR", "FlapL", "FlapR", "AileronL", "AileronR"],
    "tail": ["StabilatorL", "StabilatorR"],
    "spars": (0.15, 0.40, 0.70),
    "ribs": (1.2, 5.8, 0.6),
    "fin": ["Fin"],
    "rudder": ["Rudder"],
    "fin_lines": [2.0, 2.5],
    "upper_only": ["CanopyFrame"],
    "under_z": (0.0, -0.25),
    "radome": 270,
    "antiglare": (300, 520, 0.08, 0.40),
    "lip": (["Intakes"], 905),
    "duct": (["Intakes"], 900),
    "hot": (2100, 2280),  # bare titanium round the engines and the tail boom
    "gun": None,
    "insignia": "star_us",
    "roundel_fuselage": (1100, 0.20, 0.32, ["Intakes"]),
    "roundel_wing": (3.3, 0.42, 0.5),
    "fin_flash": None,
    "nozzles": [(-f4.NOZZLE_X, f4.NOZZLE_Z), (f4.NOZZLE_X, f4.NOZZLE_Z)],
    "nozzle_y": (f4.NOZZLE_Y0, f4.NOZZLE_Y1),
    "petals": 16,
    "pitot": "metal",
}

SCHEMES = {
    # Southeast Asia camouflage: tan and two greens over light grey (FS 30219, 34102, 34079 / 36622)
    "SEA": {
        "camo": [srgb(160, 132, 98), srgb(96, 104, 64), srgb(58, 68, 52)],
        "camo_scale": 3.0,
        "underside": srgb(198, 198, 194),
        "radome": srgb(48, 50, 48),
        "antiglare": srgb(36, 38, 36),
        "lower": srgb(198, 198, 194),
        "upper": srgb(96, 104, 64),
    },
    # Hill Gray II: two greys, low-visibility markings (FS 36320 / 36118)
    "HillGray": {
        "base": srgb(98, 108, 117),
        "radome": srgb(70, 76, 82),
        "antiglare": srgb(62, 68, 74),
        "lower": srgb(110, 118, 126),
        "upper": srgb(80, 88, 96),
        "markings": "lowvis",
    },
    # European One: two greens and a dark grey wrapped all round
    "EuroOne": {
        "camo": [srgb(64, 74, 56), srgb(42, 52, 40), srgb(70, 72, 72)],
        "camo_scale": 3.0,
        "underside": srgb(64, 74, 56),
        "radome": srgb(40, 44, 40),
        "antiglare": srgb(36, 38, 36),
        "lower": srgb(64, 74, 56),
        "upper": srgb(64, 74, 56),
        "markings": "lowvis",
    },
    # Desert camouflage: sand, brown and green over light blue, no national markings
    "Desert": {
        "camo": [srgb(196, 168, 122), srgb(138, 104, 70), srgb(110, 112, 76)],
        "camo_scale": 2.8,
        "underside": srgb(160, 184, 196),
        "radome": srgb(52, 48, 44),
        "antiglare": srgb(52, 48, 44),
        "lower": srgb(160, 184, 196),
        "upper": srgb(196, 168, 122),
        "markings": "none",
    },
}

if __name__ == "__main__":
    jet_paint.main(LAYOUT, SCHEMES, "SEA")
