"""
Afterburner: paints the F/A-18C Hornet with the shared painter (jet_paint.py): its panel layout, markings and
skins.

  blender -b tools/blender/out/FA18C_base.blend --python tools/blender/fa18c_paint.py -- \
      --out <absolute dir> [--skin Navy] [--preview]

Use the .blend whose FBX was imported into Studio: the textures follow its UV layout.
"""

import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fa18c_generate as f18  # noqa: E402  (sets the shared generator module to the F/A-18C)
import jet_paint  # noqa: E402

srgb = jet_paint.srgb


def edge(fn):
    """A wing edge as a function of |x| for arrays."""
    return lambda xa: fn(np.asarray(xa))


LAYOUT = {
    "body": ["Fuselage", "Nacelles", "Strakes"],
    "frames": [190, 290, 385, 520, 700, 800, 900, 1000, 1100, 1200, 1300, 1400, 1500, 1600, 1700],
    "side_lines": [(0.40, 200, 780), (0.10, 1000, 1700), (-0.30, 200, 950)],
    "side_panels": [(220, 300, -0.10, 0.30), (1050, 1150, -0.45, -0.05), (1450, 1550, -0.30, 0.20)],
    "wing": (edge(f18.wing_le_y), edge(f18.wing_te_y)),
    "wings": ["WingL", "WingR"],
    "surfaces": ["LEFlapL", "LEFlapR", "FlapL", "FlapR", "AileronL", "AileronR"],
    "tail": ["StabilatorL", "StabilatorR"],
    "spars": (0.22, 0.45, 0.70),
    "ribs": (1.2, 5.7, 0.7),
    "fin": ["FinL", "FinR"],
    "rudder": ["RudderL", "RudderR"],
    "fin_lines": [1.2, 1.8, 2.4],
    "upper_only": ["CanopyFrame"],
    "under_z": (0.15, -0.10),
    "radome": 190,
    "ducts": ["IntakeDucts"],
    "antiglare": (200, 385, 0.30, 0.90),
    "lip": (["Nacelles"], 1010),
    "hot": (1700, 1770),
    "gun": None,
    "insignia": "star_us",
    "roundel_fuselage": (1080, -0.20, 0.24, ["Nacelles"]),
    "roundel_wing": (4.6, 0.40, 0.5),
    "fin_flash": None,
    "nozzles": [(-f18.NOZZLE_X, f18.NOZZLE_Z), (f18.NOZZLE_X, f18.NOZZLE_Z)],
    "nozzle_y": (f18.NOZZLE_Y0, f18.NOZZLE_Y1),
    "petals": 16,
    "pitot": "metal",
}

SCHEMES = {
    # The Navy's tactical paint scheme: two greys (FS 36320 over 36375), low-visibility markings
    "Navy": {
        "base": srgb(118, 128, 136),
        "radome": srgb(128, 134, 140),
        "antiglare": srgb(70, 76, 82),
        "lower": srgb(160, 168, 174),
        "upper": srgb(118, 128, 136),
        "markings": "lowvis",
    },
    # Light gull grey over gloss white, full-colour markings (as delivered)
    "Gull": {
        "base": srgb(176, 176, 172),
        "radome": srgb(200, 198, 190),
        "antiglare": srgb(40, 42, 40),
        "lower": srgb(232, 232, 228),
        "upper": srgb(176, 176, 172),
    },
    # Adversary splinter camouflage: tan, brown and green, no national markings
    "Adversary": {
        "camo": [srgb(196, 172, 128), srgb(128, 96, 66), srgb(104, 112, 78)],
        "camo_scale": 2.8,
        "underside": srgb(186, 190, 186),
        "radome": srgb(66, 62, 56),
        "antiglare": srgb(56, 52, 48),
        "lower": srgb(186, 190, 186),
        "upper": srgb(196, 172, 128),
        "markings": "none",
    },
    # Three-tone grey (Canadian-style), low-visibility markings
    "Ghost": {
        "camo": [srgb(112, 120, 128), srgb(140, 148, 156), srgb(96, 104, 112)],
        "camo_scale": 3.2,
        "underside": srgb(160, 168, 174),
        "radome": srgb(120, 126, 130),
        "antiglare": srgb(60, 66, 72),
        "lower": srgb(160, 168, 174),
        "upper": srgb(112, 120, 128),
        "markings": "lowvis",
    },
}

if __name__ == "__main__":
    jet_paint.main(LAYOUT, SCHEMES, "Navy")
