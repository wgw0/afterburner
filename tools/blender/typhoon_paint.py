"""
Afterburner: paints the Eurofighter Typhoon with the shared painter (jet_paint.py): its panel layout,
markings and skins.

  blender -b tools/blender/out/Typhoon_base.blend --python tools/blender/typhoon_paint.py -- \
      --out <absolute dir> [--skin AirDefence] [--preview]

Use the .blend whose FBX was imported into Studio: the textures follow its UV layout.
"""

import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import typhoon_generate as ty  # noqa: E402  (sets the shared generator module to the Typhoon)
import jet_paint  # noqa: E402

srgb = jet_paint.srgb
RAF = (srgb(30, 50, 120), srgb(226, 226, 222), srgb(186, 34, 40))  # outer ring to centre


def edge(fn):
    """A wing edge as a function of |x| for arrays."""
    return lambda xa: fn(np.asarray(xa))


LAYOUT = {
    "body": ["Fuselage", "Intakes"],
    "frames": [200, 260, 425, 640, 760, 900, 1000, 1100, 1200, 1300, 1400, 1500, 1620],
    "side_lines": [(0.60, 200, 700), (0.40, 760, 1700), (-0.30, 600, 1600)],
    "side_panels": [(220, 300, 0.0, 0.30), (950, 1050, 0.10, 0.50), (1350, 1450, 0.0, 0.40)],
    "wing": (edge(ty.wing_le_y), edge(ty.wing_te_y)),
    "wings": ["WingL", "WingR"],
    "surfaces": ["LEFlapL", "LEFlapR", "FlapL", "FlapR", "AileronL", "AileronR"],
    "tail": ["CanardL", "CanardR"],
    "spars": (0.10, 0.45, 0.80),
    "ribs": (1.6, 5.2, 0.6),
    "fin": ["Fin"],
    "rudder": ["Rudder"],
    "fin_lines": [1.4, 2.2, 3.0],
    "upper_only": ["CanopyFrame"],
    "under_z": (-0.10, -0.40),
    "radome": 200,
    "ducts": ["IntakeDucts"],
    "antiglare": (210, 260, 0.10, 0.60),
    "lip": (["Intakes"], 580),
    "hot": (1660, 1720),
    "gun": None,
    "insignia": "roundel",
    "roundel_colours": RAF,
    "roundel_fuselage": (780, 0.25, 0.25, ["Fuselage"]),
    "roundel_wing": (4.0, 0.38, 0.5),
    "fin_flash": None,
    "nozzles": [(-ty.NOZZLE_X, ty.NOZZLE_Z), (ty.NOZZLE_X, ty.NOZZLE_Z)],
    "nozzle_y": (ty.NOZZLE_Y0, ty.NOZZLE_Y1),
    "petals": 14,
    "pitot": "metal",
}

SCHEMES = {
    # Air defence light grey, low-visibility roundels
    "AirDefence": {
        "base": srgb(150, 156, 160),
        "radome": srgb(120, 124, 128),
        "antiglare": srgb(70, 74, 78),
        "lower": srgb(172, 176, 178),
        "upper": srgb(150, 156, 160),
        "markings": "lowvis",
    },
    # Two greys, full-colour roundels
    "TwoTone": {
        "camo": [srgb(118, 126, 132), srgb(146, 152, 156), srgb(118, 126, 132)],
        "camo_scale": 3.4,
        "underside": srgb(160, 166, 170),
        "radome": srgb(96, 102, 108),
        "antiglare": srgb(60, 64, 68),
        "lower": srgb(160, 166, 170),
        "upper": srgb(118, 126, 132),
    },
    # Overall dark grey, low-visibility roundels
    "DarkGrey": {
        "base": srgb(86, 92, 98),
        "radome": srgb(72, 76, 80),
        "antiglare": srgb(50, 54, 58),
        "lower": srgb(100, 106, 112),
        "upper": srgb(86, 92, 98),
        "markings": "lowvis",
    },
    # Desert camouflage: sand and brown over light grey, no national markings
    "Desert": {
        "camo": [srgb(198, 170, 124), srgb(146, 110, 74), srgb(176, 146, 100)],
        "camo_scale": 2.8,
        "underside": srgb(172, 184, 192),
        "radome": srgb(70, 64, 56),
        "antiglare": srgb(56, 52, 48),
        "lower": srgb(172, 184, 192),
        "upper": srgb(198, 170, 124),
        "markings": "none",
    },
}

if __name__ == "__main__":
    jet_paint.main(LAYOUT, SCHEMES, "AirDefence")
