"""
Afterburner: paints the Su-57 with the shared painter (jet_paint.py): its panel layout, markings and
skins.

  blender -b tools/blender/out/Su57_base.blend --python tools/blender/su57_paint.py -- \
      --out <absolute dir> [--skin VKS] [--preview]

Use the .blend whose FBX was imported into Studio: the textures follow its UV layout.
"""

import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import su57_generate as su57  # noqa: E402  (sets the shared generator module to the Su-57)
import jet_paint  # noqa: E402

srgb = jet_paint.srgb


def edge(fn):
    """A wing edge as a function of |x| for arrays."""
    return lambda xa: fn(np.asarray(xa))


LAYOUT = {
    "body": ["Fuselage", "Nacelles", "Strakes"],
    "frames": [180, 290, 505, 700, 900, 1100, 1300, 1500, 1700],
    "side_lines": [(0.40, 100, 550), (0.10, 600, 1700), (-0.30, 300, 1600)],
    "side_panels": [(150, 260, -0.10, 0.20), (1000, 1150, -0.70, -0.40), (1300, 1400, 0.20, 0.50)],
    "wing": (edge(su57.wing_le_y), edge(su57.wing_te_y)),
    "wings": ["WingL", "WingR"],
    "surfaces": ["LEFlapL", "LEFlapR", "FlapL", "FlapR", "AileronL", "AileronR"],
    "tail": ["StabilatorL", "StabilatorR"],
    "spars": (0.14, 0.45, 0.80),
    "ribs": (2.4, 6.4, 0.8),
    "fin": ["FinL", "FinR"],
    "rudder": ["RudderL", "RudderR"],
    "fin_lines": [1.2, 1.9, 2.6],
    "upper_only": ["CanopyFrame"],
    "under_z": (0.10, -0.25),
    "radome": 180,
    "ducts": ["IntakeDucts"],
    "antiglare": (190, 290, 0.50, 1.10),
    "lip": (["Nacelles"], 880),
    "hot": (1650, 1720),
    "gun": None,
    "insignia": "star_ru",
    "roundel_fuselage": (1580, 1.30, 0.30, ["FinL", "FinR"]),
    "roundel_wing": (5.5, 0.40, 0.5),
    "fin_flash": None,
    "nozzles": [(-su57.NOZZLE_X, su57.NOZZLE_Z), (su57.NOZZLE_X, su57.NOZZLE_Z)],
    "nozzle_y": (su57.NOZZLE_Y0, su57.NOZZLE_Y1),
    "petals": 12,
    "pitot": "stripes",
}

SCHEMES = {
    # Aerospace Forces: blue-grey splinter over light grey
    "VKS": {
        "camo": [srgb(104, 120, 140), srgb(140, 154, 168), srgb(80, 94, 112)],
        "camo_scale": 2.4,
        "underside": srgb(176, 186, 194),
        "radome": srgb(80, 94, 112),
        "antiglare": srgb(56, 62, 70),
        "lower": srgb(176, 186, 194),
        "upper": srgb(104, 120, 140),
    },
    # Overall dark grey, low-visibility markings
    "Dark": {
        "base": srgb(76, 82, 90),
        "radome": srgb(66, 70, 76),
        "antiglare": srgb(48, 52, 56),
        "lower": srgb(96, 102, 110),
        "upper": srgb(76, 82, 90),
        "markings": "lowvis",
    },
    # Two light greys, low-visibility markings
    "Grey": {
        "camo": [srgb(132, 140, 146), srgb(156, 162, 166), srgb(132, 140, 146)],
        "camo_scale": 3.4,
        "underside": srgb(162, 168, 172),
        "radome": srgb(110, 116, 122),
        "antiglare": srgb(70, 76, 82),
        "lower": srgb(162, 168, 172),
        "upper": srgb(132, 140, 146),
        "markings": "lowvis",
    },
    # Desert camouflage: sand and brown over light blue, no national markings
    "Desert": {
        "camo": [srgb(198, 170, 124), srgb(142, 104, 70), srgb(170, 140, 96)],
        "camo_scale": 2.8,
        "underside": srgb(160, 184, 196),
        "radome": srgb(52, 48, 44),
        "antiglare": srgb(52, 48, 44),
        "lower": srgb(160, 184, 196),
        "upper": srgb(198, 170, 124),
        "markings": "none",
    },
}

if __name__ == "__main__":
    jet_paint.main(LAYOUT, SCHEMES, "VKS")
