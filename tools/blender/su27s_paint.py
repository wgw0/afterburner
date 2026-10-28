"""
Afterburner: paints the Su-27S Flanker with the shared painter (jet_paint.py): its panel layout, markings and
skins.

  blender -b tools/blender/out/Su27S_base.blend --python tools/blender/su27s_paint.py -- \
      --out <absolute dir> [--skin Flanker] [--preview]

Use the .blend whose FBX was imported into Studio: the textures follow its UV layout.
"""

import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import su27s_generate as su27  # noqa: E402  (sets the shared generator module to the Su-27S)
import jet_paint  # noqa: E402

srgb = jet_paint.srgb


def edge(fn):
    """A wing edge as a function of |x| for arrays."""
    return lambda xa: fn(np.asarray(xa))


LAYOUT = {
    "body": ["Fuselage", "Nacelles", "Strakes"],
    "frames": [270, 360, 455, 700, 800, 900, 1000, 1100, 1200, 1300, 1400, 1500, 1600, 1750],
    "side_lines": [(1.10, 270, 700), (0.40, 700, 1500), (-0.30, 950, 1600)],
    "side_panels": [(300, 360, 0.60, 1.10), (1000, 1100, -0.70, -0.20), (1350, 1450, -0.60, -0.10)],
    "wing": (edge(su27.wing_le_y), edge(su27.wing_te_y)),
    "wings": ["WingL", "WingR"],
    "surfaces": ["LEFlapL", "LEFlapR", "FlapL", "FlapR", "AileronL", "AileronR"],
    "tail": ["StabilatorL", "StabilatorR"],
    "spars": (0.12, 0.45, 0.80),
    "ribs": (2.0, 6.8, 0.7),
    "fin": ["FinL", "FinR"],
    "rudder": ["RudderL", "RudderR"],
    "fin_lines": [1.5, 2.3, 3.0],
    "upper_only": ["CanopyFrame"],
    "under_z": (0.20, -0.10),
    "radome": 270,
    "ducts": ["IntakeDucts"],
    "antiglare": (280, 360, 0.80, 1.30),
    "lip": (["Nacelles"], 900),
    "hot": (1560, 1620),
    "gun": None,
    "insignia": "star_ru",
    "roundel_fuselage": (1500, 2.30, 0.40, ["FinL", "FinR"]),
    "roundel_wing": (5.0, 0.50, 0.5),
    "fin_flash": None,
    "nozzles": [(-su27.NOZZLE_X, su27.NOZZLE_Z), (su27.NOZZLE_X, su27.NOZZLE_Z)],
    "nozzle_y": (su27.NOZZLE_Y0, su27.NOZZLE_Y1),
    "petals": 18,
    "pitot": "stripes",
}

SCHEMES = {
    # The Flanker's three blue-greys over light blue
    "Flanker": {
        "camo": [srgb(150, 172, 190), srgb(96, 130, 160), srgb(180, 196, 206)],
        "camo_scale": 3.4,
        "underside": srgb(186, 204, 214),
        "radome": srgb(220, 222, 216),
        "antiglare": srgb(60, 70, 76),
        "lower": srgb(186, 204, 214),
        "upper": srgb(150, 172, 190),
    },
    # Overall grey, low-visibility markings
    "Grey": {
        "camo": [srgb(126, 134, 140), srgb(100, 108, 116), srgb(146, 152, 158)],
        "camo_scale": 3.2,
        "underside": srgb(160, 166, 172),
        "radome": srgb(74, 78, 82),
        "antiglare": srgb(56, 60, 64),
        "lower": srgb(160, 166, 172),
        "upper": srgb(126, 134, 140),
        "markings": "lowvis",
    },
    # Naval blue-grey: dark blue over light grey
    "Naval": {
        "camo": [srgb(78, 100, 132), srgb(58, 76, 104), srgb(96, 118, 146)],
        "camo_scale": 3.0,
        "underside": srgb(176, 186, 194),
        "radome": srgb(200, 202, 196),
        "antiglare": srgb(40, 48, 58),
        "lower": srgb(176, 186, 194),
        "upper": srgb(78, 100, 132),
    },
    # Desert camouflage: sand and brown over light blue, no national markings
    "Desert": {
        "camo": [srgb(198, 170, 124), srgb(142, 104, 70), srgb(170, 140, 96)],
        "camo_scale": 3.0,
        "underside": srgb(160, 184, 196),
        "radome": srgb(52, 48, 44),
        "antiglare": srgb(52, 48, 44),
        "lower": srgb(160, 184, 196),
        "upper": srgb(198, 170, 124),
        "markings": "none",
    },
}

if __name__ == "__main__":
    jet_paint.main(LAYOUT, SCHEMES, "Flanker")
