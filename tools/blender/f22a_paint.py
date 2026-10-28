"""
Afterburner: paints the F-22A Raptor with the shared painter (jet_paint.py): its panel layout, markings and
skins.

  blender -b tools/blender/out/F22A_base.blend --python tools/blender/f22a_paint.py -- \
      --out <absolute dir> [--skin AirDominance] [--preview]

Use the .blend whose FBX was imported into Studio: the textures follow its UV layout.
"""

import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import f22a_generate as f22  # noqa: E402  (sets the shared generator module to the F-22A)
import jet_paint  # noqa: E402

srgb = jet_paint.srgb
S = f22.side


def edge(fn):
    """A wing edge as a function of |x| for arrays."""
    return lambda xa: fn(np.asarray(xa))


LAYOUT = {
    "body": ["Fuselage", "Nacelles", "Strakes"],
    "frames": [S(xd) for xd in (150, 250, 525, 700, 850, 1000, 1150, 1300, 1420)],
    "side_lines": [(0.40, S(100), S(550)), (0.10, S(600), S(1450)), (-0.40, S(300), S(1400))],
    "side_panels": [(S(150), S(230), -0.10, 0.20), (S(800), S(950), -0.70, -0.40), (S(1100), S(1200), 0.30, 0.60)],
    "wing": (edge(f22.wing_le_y), edge(f22.wing_te_y)),
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
    "radome": S(150),
    "ducts": ["IntakeDucts"],
    "antiglare": (S(160), S(250), 0.30, 0.90),
    "lip": (["Nacelles"], S(600)),
    "hot": (S(1420), S(1480)),
    "gun": None,
    "insignia": "star_us",
    "roundel_fuselage": (S(1100), 0.20, 0.26, ["Nacelles"]),
    "roundel_wing": (5.0, 0.40, 0.5),
    "fin_flash": None,
    "nozzles": [(-f22.NOZZLE_X, f22.NOZZLE_Z), (f22.NOZZLE_X, f22.NOZZLE_Z)],
    "nozzle_y": (f22.NOZZLE_Y0, f22.NOZZLE_Y1),
    "petals": 12,
    "pitot": "metal",
}

SCHEMES = {
    # Two greys (FS 36170 over 36320), low-visibility markings
    "AirDominance": {
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
    # Grey splinter camouflage, no national markings
    "Splinter": {
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
    jet_paint.main(LAYOUT, SCHEMES, "AirDominance")
