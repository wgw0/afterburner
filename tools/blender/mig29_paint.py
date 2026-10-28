"""
Afterburner: paints the MiG-29A with the shared painter (jet_paint.py): its panel layout, markings and
skins.

  blender -b tools/blender/out/MiG29A_base.blend --python tools/blender/mig29_paint.py -- \
      --out <absolute dir> [--skin Grey] [--preview]

Use the .blend whose FBX was imported into Studio: the textures follow its UV layout.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mig29_generate as m29  # noqa: E402  (sets the shared generator module to the MiG-29A)
import jet_paint  # noqa: E402

srgb = jet_paint.srgb

LAYOUT = {
    "body": ["Fuselage", "Nacelles", "Strakes"],
    "frames": [400, 550, 700, 830, 1100, 1300, 1500, 1700, 1900, 2100, 2300, 2500],
    "side_lines": [(0.60, 400, 1100), (0.95, 1100, 2400), (-0.30, 1300, 2500)],
    "side_panels": [(450, 550, 0.30, 0.70), (1500, 1650, -0.45, -0.05), (2000, 2150, -0.45, -0.05)],
    "wing": (m29.wing_le_y, m29.wing_te_y),
    "wings": ["WingL", "WingR"],
    "surfaces": ["LEFlapL", "LEFlapR", "FlapL", "FlapR", "AileronL", "AileronR"],
    "tail": ["StabilatorL", "StabilatorR"],
    "spars": (0.15, 0.45, 0.80),
    "ribs": (1.8, 5.6, 0.6),
    "fin": ["FinL", "FinR"],
    "rudder": ["RudderL", "RudderR"],
    "fin_lines": [1.5, 2.2, 2.8],
    "upper_only": ["CanopyFrame"],
    "radome": 400,
    "ducts": ["IntakeDucts"],
    "antiglare": (420, 700, 0.08, 0.35),
    "lip": (["Nacelles"], 1400),
    "hot": (2450, 2620),
    "gun": None,
    "insignia": "star_ru",
    "roundel_fuselage": (2560, 1.90, 0.33, ["FinL", "FinR"]),
    "roundel_wing": (3.8, 0.42, 0.5),
    "fin_flash": None,
    "nozzles": [(-m29.NACELLE_X, m29.NOZZLE_Z), (m29.NACELLE_X, m29.NOZZLE_Z)],
    "nozzle_y": (m29.NOZZLE_Y0, m29.NOZZLE_Y1),
    "petals": 16,
    "pitot": "stripes",
}

SCHEMES = {
    # Soviet two-tone grey and grey-green over light grey
    "Grey": {
        "camo": [srgb(150, 160, 166), srgb(108, 126, 126), srgb(132, 146, 152)],
        "camo_scale": 3.2,
        "underside": srgb(178, 186, 190),
        "radome": srgb(214, 216, 210),
        "antiglare": srgb(60, 66, 66),
        "lower": srgb(178, 186, 190),
        "upper": srgb(150, 160, 166),
    },
    # Central European grey camouflage, low-visibility markings
    "Euro": {
        "camo": [srgb(116, 122, 128), srgb(84, 90, 96), srgb(140, 146, 150)],
        "camo_scale": 3.0,
        "underside": srgb(160, 166, 170),
        "radome": srgb(70, 74, 78),
        "antiglare": srgb(56, 60, 64),
        "lower": srgb(160, 166, 170),
        "upper": srgb(116, 122, 128),
        "markings": "lowvis",
    },
    # Blue-grey, low-visibility markings
    "BlueGrey": {
        "camo": [srgb(110, 132, 156), srgb(80, 98, 120), srgb(150, 166, 180)],
        "camo_scale": 2.8,
        "underside": srgb(170, 184, 196),
        "radome": srgb(70, 80, 92),
        "antiglare": srgb(56, 62, 70),
        "lower": srgb(170, 184, 196),
        "upper": srgb(110, 132, 156),
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
    jet_paint.main(LAYOUT, SCHEMES, "Grey")
