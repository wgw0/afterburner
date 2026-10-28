"""
Afterburner: paints the F-35A Lightning II with the shared painter (jet_paint.py): its panel layout, markings and
skins.

  blender -b tools/blender/out/F35A_base.blend --python tools/blender/f35a_paint.py -- \
      --out <absolute dir> [--skin Stealth] [--preview]

Use the .blend whose FBX was imported into Studio: the textures follow its UV layout.
"""

import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import f35a_generate as f35  # noqa: E402  (sets the shared generator module to the F-35A)
import jet_paint  # noqa: E402

srgb = jet_paint.srgb


def edge(fn):
    """A wing edge as a function of |x| for arrays."""
    return lambda xa: fn(np.asarray(xa))


LAYOUT = {
    "body": ["Fuselage", "Nacelles", "Strakes"],
    "frames": [150, 230, 590, 700, 850, 1000, 1150, 1300, 1420],
    "side_lines": [(0.40, 100, 550), (0.10, 600, 1450), (-0.40, 300, 1400)],
    "side_panels": [(150, 230, -0.10, 0.20), (800, 950, -0.70, -0.40), (1100, 1200, 0.30, 0.60)],
    "wing": (edge(f35.wing_le_y), edge(f35.wing_te_y)),
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
    "radome": 150,
    "ducts": ["IntakeDucts"],
    "antiglare": (160, 250, 0.30, 0.90),
    "lip": (["Nacelles"], 560),
    "hot": (1460, 1520),
    "gun": None,
    "insignia": "star_us",
    "roundel_fuselage": (1100, 0.20, 0.26, ["Nacelles"]),
    "roundel_wing": (4.3, 0.38, 0.5),
    "fin_flash": None,
    "nozzles": [(0.0, f35.NOZZLE_Z)],
    "nozzle_y": (f35.NOZZLE_Y0, f35.NOZZLE_Y1),
    "petals": 12,
    "pitot": "metal",
}

SCHEMES = {
    # Two greys (FS 36170 over 36320), low-visibility markings
    "Stealth": {
        "camo": [srgb(104, 110, 116), srgb(130, 136, 142), srgb(104, 110, 116)],
        "camo_scale": 3.2,
        "underside": srgb(130, 136, 142),
        "radome": srgb(104, 110, 116),
        "antiglare": srgb(84, 90, 96),
        "lower": srgb(130, 136, 142),
        "upper": srgb(104, 110, 116),
        "markings": "lowvis",
    },
    # Overall dark grey, low-visibility markings
    "Dark": {
        "base": srgb(78, 82, 88),
        "radome": srgb(78, 82, 88),
        "antiglare": srgb(60, 64, 68),
        "lower": srgb(90, 94, 100),
        "upper": srgb(78, 82, 88),
        "markings": "lowvis",
    },
    # Light ghost grey, full-colour markings
    "Ghost": {
        "base": srgb(150, 156, 160),
        "radome": srgb(140, 146, 150),
        "antiglare": srgb(90, 96, 100),
        "lower": srgb(168, 172, 176),
        "upper": srgb(150, 156, 160),
    },
    # Grey splinter aggressor camouflage, no national markings
    "Aggressor": {
        "camo": [srgb(120, 128, 136), srgb(86, 94, 102), srgb(152, 158, 164)],
        "camo_scale": 2.4,
        "underside": srgb(150, 156, 162),
        "radome": srgb(86, 94, 102),
        "antiglare": srgb(60, 66, 72),
        "lower": srgb(150, 156, 162),
        "upper": srgb(120, 128, 136),
        "markings": "none",
    },
}

if __name__ == "__main__":
    jet_paint.main(LAYOUT, SCHEMES, "Stealth")
