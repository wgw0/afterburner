"""
Afterburner: paints the MiG-23MLD with the shared painter (jet_paint.py): its panel layout, markings and
skins.

  blender -b tools/blender/out/MiG23MLD_base.blend --python tools/blender/mig23_paint.py -- \
      --out <absolute dir> [--skin Tactical] [--preview]

Use the .blend whose FBX was imported into Studio: the textures follow its UV layout.
"""

import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mig23_generate as m23  # noqa: E402  (sets the shared generator module to the MiG-23MLD)
import jet_paint  # noqa: E402

srgb = jet_paint.srgb


def edge(y_of):
    """A wing edge at the combat sweep, as a function of |x| for arrays: the spread wing's straight edge
    turned about the pivot is still straight, so it's the line through its two turned ends."""
    x0, y0, _ = m23.swept((m23.WING_ROOT_X, y_of(m23.WING_ROOT_X), m23.WING_Z))
    x1, y1, _ = m23.swept((m23.WING_TIP_X, y_of(m23.WING_TIP_X), m23.WING_Z))

    def fn(xa):
        return y0 + (np.asarray(xa) - x0) * (y1 - y0) / (x1 - x0)

    return fn


LAYOUT = {
    "body": ["Fuselage", "Intakes", "Gloves"],
    "frames": [300, 520, 680, 830, 990, 1150, 1300, 1450, 1600, 1750, 1900, 2050, 2200, 2350, 2500, 2650, 2790],
    "side_lines": [(0.0, 300, 990), (0.45, 1100, 2790), (-0.35, 1100, 2790)],
    "side_panels": [(550, 650, -0.40, 0.10), (1300, 1400, -0.30, 0.30), (2300, 2400, 0.00, 0.45)],
    "wing": (edge(m23.spread_le_y), edge(m23.spread_te_y)),
    "wings": ["WingL", "WingR"],
    "surfaces": ["LEFlapL", "LEFlapR", "FlapL", "FlapR"],
    "tail": ["StabilatorL", "StabilatorR"],
    "spars": (0.15, 0.45, 0.70),
    "ribs": (2.0, 6.0, 0.6),
    "fin": ["Fin"],
    "rudder": ["Rudder"],
    "fin_lines": [1.4, 1.9],
    "upper_only": ["CanopyFrame"],
    "radome": 520,
    "antiglare": (540, 680, 0.08, 0.30),
    "lip": (["Intakes"], 1075),
    "duct": (["Intakes"], 1070),
    "hot": (2600, 2790),
    "gun": None,
    "insignia": "star_ru",
    "roundel_fuselage": (2600, 1.55, 0.36, ["Fin"]),
    "roundel_wing": (3.6, 0.40, 0.5),
    "fin_flash": None,
    "nozzles": [(0.0, m23.NOZZLE_Z)],
    "nozzle_y": (m23.NOZZLE_Y0, m23.NOZZLE_Y1),
    "petals": 20,
    "pitot": "stripes",
}

SCHEMES = {
    # Tactical camouflage: tan and two greens over light blue
    "Tactical": {
        "camo": [srgb(176, 150, 104), srgb(100, 112, 70), srgb(64, 80, 58)],
        "camo_scale": 2.8,
        "underside": srgb(150, 182, 200),
        "radome": srgb(70, 84, 64),
        "antiglare": srgb(44, 46, 40),
        "lower": srgb(150, 182, 200),
        "upper": srgb(100, 112, 70),
    },
    # Two-tone grey-green over light grey, as on late Floggers
    "TwoTone": {
        "camo": [srgb(112, 122, 104), srgb(70, 78, 72), srgb(92, 100, 88)],
        "camo_scale": 3.0,
        "underside": srgb(168, 176, 180),
        "radome": srgb(60, 70, 60),
        "antiglare": srgb(44, 46, 44),
        "lower": srgb(168, 176, 180),
        "upper": srgb(112, 122, 104),
    },
    # Air-defence grey
    "Grey": {
        "base": srgb(140, 150, 158),
        "radome": srgb(70, 80, 74),
        "antiglare": srgb(54, 58, 62),
        "lower": srgb(170, 180, 186),
        "upper": srgb(140, 150, 158),
    },
    # Desert camouflage: sand and brown over light blue, low-visibility markings
    "Desert": {
        "camo": [srgb(198, 170, 124), srgb(142, 104, 70), srgb(170, 140, 96)],
        "camo_scale": 2.6,
        "underside": srgb(160, 184, 196),
        "radome": srgb(52, 48, 44),
        "antiglare": srgb(52, 48, 44),
        "lower": srgb(160, 184, 196),
        "upper": srgb(198, 170, 124),
        "markings": "lowvis",
    },
}

if __name__ == "__main__":
    jet_paint.main(LAYOUT, SCHEMES, "Tactical")
