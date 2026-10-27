"""
Afterburner: paints the F-14A Tomcat with the shared painter (jet_paint.py): its panel layout, markings
and skins.

  blender -b tools/blender/out/F14A_base.blend --python tools/blender/f14a_paint.py -- \
      --out <absolute dir> [--skin Navy] [--preview]

Use the .blend whose FBX was imported into Studio: the textures follow its UV layout.
"""

import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import f14a_generate as f14  # noqa: E402  (sets the shared generator module to the F-14A)
import jet_paint  # noqa: E402

srgb = jet_paint.srgb


def edge(root, tip):
    """A wing edge as set (turned to 35 degrees), as a function of |x| for arrays: the line through its
    turned root and tip points."""
    x0, y0, _ = f14.turned((f14.SWEPT["root_x"], root, f14.WING_Z))
    x1, y1, _ = f14.turned((tip[0], tip[1], f14.WING_Z))

    def fn(xa):
        return y0 + (np.asarray(xa) - x0) * (y1 - y0) / (x1 - x0)

    return fn


LAYOUT = {
    "body": ["Fuselage", "Nacelles", "Gloves"],
    "frames": [270, 400, 500, 650, 830, 1050, 1200, 1350, 1500, 1650, 1800, 1950, 2100, 2250],
    "side_lines": [(0.35, 270, 1040), (0.60, 1200, 2250), (-0.30, 800, 2150)],
    "side_panels": [(300, 380, -0.20, 0.30), (1300, 1450, -0.40, 0.10), (1900, 2050, -0.40, 0.10)],
    "wing": (edge(f14.SWEPT["root_le"], f14.SWEPT["tip_le"]), edge(f14.SWEPT["root_te"], f14.SWEPT["tip_te"])),
    "wings": ["WingL", "WingR"],
    "surfaces": ["LEFlapL", "LEFlapR", "FlapL", "FlapR"],
    "tail": ["StabilatorL", "StabilatorR"],
    "spars": (0.14, 0.45, 0.78),
    "ribs": (3.2, 9.0, 0.7),
    "fin": ["FinL", "FinR"],
    "rudder": ["RudderL", "RudderR"],
    "fin_lines": [1.6, 2.3, 2.9],
    "upper_only": ["CanopyFrame"],
    "under_z": (0.10, -0.15),
    "radome": 270,
    "ducts": ["IntakeDucts"],
    "antiglare": (280, 400, 0.10, 0.45),
    "lip": (["Nacelles"], 820),
    "hot": (2150, 2300),
    "gun": None,
    "insignia": "star_us",
    "roundel_fuselage": (1450, 0.10, 0.32, ["Nacelles"]),
    "roundel_wing": (5.2, 0.42, 0.5),
    "fin_flash": None,
    "nozzles": [(-f14.NOZZLE_X, f14.NOZZLE_Z), (f14.NOZZLE_X, f14.NOZZLE_Z)],
    "nozzle_y": (f14.NOZZLE_Y0, f14.NOZZLE_Y1),
    "petals": 18,
    "pitot": "metal",
}

SCHEMES = {
    # The Navy's two greys (FS 36320 over 36375), low-visibility markings
    "Navy": {
        "base": srgb(118, 128, 136),
        "radome": srgb(150, 156, 160),
        "antiglare": srgb(70, 76, 82),
        "lower": srgb(160, 168, 174),
        "upper": srgb(118, 128, 136),
        "markings": "lowvis",
    },
    # Light gull grey over gloss white, full-colour markings (the 1970s scheme)
    "Gull": {
        "base": srgb(176, 176, 172),
        "radome": srgb(210, 206, 196),
        "antiglare": srgb(40, 42, 40),
        "lower": srgb(232, 232, 228),
        "upper": srgb(176, 176, 172),
    },
    # Three-tone grey camouflage, low-visibility markings
    "Ghost": {
        "camo": [srgb(128, 136, 142), srgb(96, 104, 112), srgb(152, 160, 166)],
        "camo_scale": 3.4,
        "underside": srgb(160, 168, 174),
        "radome": srgb(120, 126, 130),
        "antiglare": srgb(70, 76, 82),
        "lower": srgb(160, 168, 174),
        "upper": srgb(128, 136, 142),
        "markings": "lowvis",
    },
    # Desert camouflage: sand, brown and green over light grey, no national markings
    "Desert": {
        "camo": [srgb(196, 168, 122), srgb(140, 104, 70), srgb(118, 116, 80)],
        "camo_scale": 3.2,
        "underside": srgb(176, 182, 186),
        "radome": srgb(196, 192, 182),
        "antiglare": srgb(56, 52, 48),
        "lower": srgb(176, 182, 186),
        "upper": srgb(196, 168, 122),
        "markings": "none",
    },
}

if __name__ == "__main__":
    jet_paint.main(LAYOUT, SCHEMES, "Navy")
