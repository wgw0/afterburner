"""
Afterburner: paints the F-15C Eagle with the shared painter (jet_paint.py): its panel layout, markings and
skins.

  blender -b tools/blender/out/F15C_base.blend --python tools/blender/f15c_paint.py -- \
      --out <absolute dir> [--skin ModEagle] [--preview]

Use the .blend whose FBX was imported into Studio: the textures follow its UV layout.
"""

import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import f15c_generate as f15  # noqa: E402  (sets the shared generator module to the F-15C)
import jet_paint  # noqa: E402

srgb = jet_paint.srgb


def edge(fn):
    """A wing edge as a function of |x| for arrays."""
    return lambda xa: fn(np.asarray(xa))


LAYOUT = {
    "body": ["Fuselage", "Nacelles", "Strakes"],
    "frames": [200, 330, 460, 620, 860, 1000, 1150, 1300, 1450, 1600, 1750, 1900, 2050, 2200, 2350],
    "side_lines": [(0.95, 300, 1050), (0.55, 1050, 2300), (-0.20, 860, 2250)],
    "side_panels": [(330, 420, 0.20, 0.70), (1350, 1500, -0.35, 0.20), (1900, 2050, -0.35, 0.20)],
    "wing": (edge(f15.wing_le_y), edge(f15.wing_te_y)),
    "wings": ["WingL", "WingR"],
    "surfaces": ["LEFlapL", "LEFlapR", "FlapL", "FlapR", "AileronL", "AileronR"],
    "tail": ["StabilatorL", "StabilatorR"],
    "spars": (0.14, 0.45, 0.78),
    "ribs": (1.6, 6.3, 0.7),
    "fin": ["FinL", "FinR"],
    "rudder": ["RudderL", "RudderR"],
    "fin_lines": [1.4, 2.2, 3.0],
    "upper_only": ["CanopyFrame"],
    "under_z": (0.25, -0.05),
    "radome": 200,
    "ducts": ["IntakeDucts"],
    "antiglare": (210, 460, 0.60, 1.20),
    "lip": (["Nacelles"], 830),
    "hot": (2300, 2420),
    "gun": None,
    "insignia": "star_us",
    "roundel_fuselage": (1100, 0.55, 0.30, ["Nacelles"]),
    "roundel_wing": (5.0, 0.45, 0.5),
    "fin_flash": None,
    "nozzles": [(-f15.NOZZLE_X, f15.NOZZLE_Z), (f15.NOZZLE_X, f15.NOZZLE_Z)],
    "nozzle_y": (f15.NOZZLE_Y0, f15.NOZZLE_Y1),
    "petals": 18,
    "pitot": "metal",
}

SCHEMES = {
    # "Mod Eagle": dark and light ghost greys (FS 36176 over 36251), low-visibility markings
    "ModEagle": {
        "camo": [srgb(112, 120, 128), srgb(134, 142, 150), srgb(112, 120, 128)],
        "camo_scale": 3.6,
        "underside": srgb(134, 142, 150),
        "radome": srgb(128, 134, 140),
        "antiglare": srgb(70, 76, 82),
        "lower": srgb(134, 142, 150),
        "upper": srgb(112, 120, 128),
        "markings": "lowvis",
    },
    # Air Superiority Blue all over, full-colour markings (the 1970s scheme)
    "Blue": {
        "base": srgb(148, 164, 182),
        "radome": srgb(188, 192, 196),
        "antiglare": srgb(40, 44, 48),
        "lower": srgb(160, 174, 190),
        "upper": srgb(148, 164, 182),
    },
    # Aggressor: three blues and greys in splinter camouflage
    "Aggressor": {
        "camo": [srgb(88, 112, 150), srgb(140, 160, 186), srgb(60, 76, 108)],
        "camo_scale": 3.0,
        "underside": srgb(170, 180, 192),
        "radome": srgb(60, 76, 108),
        "antiglare": srgb(50, 58, 72),
        "lower": srgb(170, 180, 192),
        "upper": srgb(88, 112, 150),
        "markings": "lowvis",
    },
    # Desert camouflage: sand and brown over light grey, no national markings
    "Desert": {
        "camo": [srgb(198, 170, 124), srgb(146, 110, 74), srgb(176, 146, 100)],
        "camo_scale": 3.2,
        "underside": srgb(172, 184, 192),
        "radome": srgb(70, 64, 56),
        "antiglare": srgb(56, 52, 48),
        "lower": srgb(172, 184, 192),
        "upper": srgb(198, 170, 124),
        "markings": "none",
    },
}

if __name__ == "__main__":
    jet_paint.main(LAYOUT, SCHEMES, "ModEagle")
