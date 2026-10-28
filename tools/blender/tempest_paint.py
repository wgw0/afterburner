"""
Afterburner: paints the Tempest-class concept with the shared painter (jet_paint.py): its panel layout,
markings and skins.

  blender -b tools/blender/out/Tempest_base.blend --python tools/blender/tempest_paint.py -- \
      --out <absolute dir> [--skin Shadow] [--preview]

Use the .blend whose FBX was imported into Studio: the textures follow its UV layout.
"""

import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tempest_generate as tp  # noqa: E402  (sets the shared generator module to the Tempest)
import jet_paint  # noqa: E402

srgb = jet_paint.srgb
MARK = (srgb(40, 46, 54), srgb(226, 226, 222), srgb(40, 150, 170))  # a fictional roundel, outer ring to centre


def edge(fn):
    """A wing edge as a function of |x| for arrays."""
    return lambda xa: fn(np.asarray(xa))


LAYOUT = {
    "body": ["Fuselage", "Nacelles", "Strakes"],
    "frames": [200, 300, 640, 750, 900, 1050, 1200, 1350, 1500],
    "side_lines": [(0.30, 100, 650), (0.15, 700, 1600), (-0.40, 300, 1550)],
    "side_panels": [(150, 260, -0.20, 0.10), (950, 1100, -0.55, -0.30), (1250, 1350, 0.0, 0.30)],
    "wing": (edge(tp.wing_le_y), edge(tp.wing_te_y)),
    "wings": ["WingL", "WingR"],
    "surfaces": ["LEFlapL", "LEFlapR", "FlapL", "FlapR", "AileronL", "AileronR"],
    "tail": [],
    "spars": (0.14, 0.45, 0.80),
    "ribs": (2.4, 6.4, 0.8),
    "fin": ["FinL", "FinR"],
    "rudder": ["RudderL", "RudderR"],
    "fin_lines": [1.2, 1.9, 2.6],
    "upper_only": ["CanopyFrame"],
    "under_z": (0.10, -0.25),
    "radome": 200,
    "ducts": ["IntakeDucts"],
    "antiglare": (210, 300, 0.40, 1.00),
    "lip": (["Nacelles"], 740),
    "hot": (1600, 1660),
    "gun": None,
    "insignia": "roundel",
    "roundel_colours": MARK,
    "roundel_fuselage": (1560, 1.10, 0.26, ["FinL", "FinR"]),
    "roundel_wing": (5.0, 0.42, 0.5),
    "fin_flash": None,
    "nozzles": [(-tp.NOZZLE_X, tp.NOZZLE_Z), (tp.NOZZLE_X, tp.NOZZLE_Z)],
    "nozzle_y": (tp.NOZZLE_Y0, tp.NOZZLE_Y1),
    "petals": 12,
    "pitot": "metal",
}

SCHEMES = {
    # Two dark greys, low-visibility markings
    "Shadow": {
        "camo": [srgb(78, 84, 92), srgb(100, 106, 114), srgb(78, 84, 92)],
        "camo_scale": 3.4,
        "underside": srgb(100, 106, 114),
        "radome": srgb(78, 84, 92),
        "antiglare": srgb(60, 64, 70),
        "lower": srgb(100, 106, 114),
        "upper": srgb(78, 84, 92),
        "markings": "lowvis",
    },
    # Light grey, full-colour markings
    "Storm": {
        "base": srgb(146, 152, 158),
        "radome": srgb(130, 136, 142),
        "antiglare": srgb(80, 86, 92),
        "lower": srgb(166, 170, 174),
        "upper": srgb(146, 152, 158),
    },
    # Night: near-black blue-grey, low-visibility markings
    "Night": {
        "base": srgb(46, 52, 62),
        "radome": srgb(46, 52, 62),
        "antiglare": srgb(36, 40, 46),
        "lower": srgb(58, 64, 74),
        "upper": srgb(46, 52, 62),
        "markings": "lowvis",
    },
    # Demonstrator: white and blue-grey splinter, full-colour markings
    "Demonstrator": {
        "camo": [srgb(222, 224, 226), srgb(110, 130, 152), srgb(60, 72, 90)],
        "camo_scale": 2.2,
        "underside": srgb(214, 216, 218),
        "radome": srgb(60, 72, 90),
        "antiglare": srgb(40, 46, 54),
        "lower": srgb(214, 216, 218),
        "upper": srgb(222, 224, 226),
    },
}

if __name__ == "__main__":
    jet_paint.main(LAYOUT, SCHEMES, "Shadow")
