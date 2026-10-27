"""
Afterburner: paints the Mirage F1C with the shared painter (jet_paint.py): its panel layout, markings and
skins.

  blender -b tools/blender/out/MirageF1_base.blend --python tools/blender/miragef1_paint.py -- \
      --out <absolute dir> [--skin Interceptor] [--preview]

Use the .blend whose FBX was imported into Studio: the textures follow its UV layout.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import miragef1_generate as f1  # noqa: E402  (sets the shared generator module to the Mirage F1C)
import jet_paint  # noqa: E402

srgb = jet_paint.srgb
FRANCE = (srgb(186, 34, 40), srgb(226, 226, 222), srgb(30, 60, 140))  # roundel: red outside, blue centre

LAYOUT = {
    "body": ["Fuselage", "Intakes"],
    "frames": [18, 36, 54, 72, 98, 115, 135, 155, 175, 195, 215, 235, 255, 272],
    "side_lines": [(-0.30, 18, 100), (0.40, 100, 272), (-0.40, 100, 260)],
    "side_panels": [(20, 30, -0.40, 0.00), (110, 125, -0.60, -0.20), (200, 215, 0.00, 0.50)],
    "wing": (f1.wing_le_y, f1.wing_te_y),
    "wings": ["WingL", "WingR"],
    "surfaces": ["LEFlapL", "LEFlapR", "FlapL", "FlapR", "AileronL", "AileronR"],
    "tail": ["StabilatorL", "StabilatorR"],
    "spars": (0.15, 0.45, 0.75),
    "ribs": (1.0, 4.1, 0.55),
    "fin": ["Fin"],
    "rudder": ["Rudder"],
    "fin_lines": [1.3, 1.8, 2.3],
    "upper_only": ["CanopyFrame"],
    "radome": 18,
    "dark": ["InletCones"],
    "antiglare": (36, 55, 0.06, 0.30),
    "lip": (["Intakes"], 104),
    "duct": (["Intakes"], 102),
    "hot": (262, 275),
    "gun": (0.25, 0.12, 60, 90),
    "insignia": "roundel",
    "roundel_colours": FRANCE,
    "roundel_fuselage": (140, -0.05, 0.25, ["Intakes"]),
    "roundel_wing": (3.0, 0.35, 0.45),
    "fin_flash": (["Rudder"], f1.RUDDER_SPAN[0] + 0.6, 262, 0.55),
    "nozzles": [(0.0, f1.NOZZLE_Z)],
    "nozzle_y": (f1.NOZZLE_Y0, f1.NOZZLE_Y1),
    "petals": 18,
    "pitot": "metal",
}

SCHEMES = {
    # Armée de l'Air interceptor camouflage: two blue-greys over light grey
    "Interceptor": {
        "camo": [srgb(104, 118, 134), srgb(72, 84, 100), srgb(92, 104, 120)],
        "camo_scale": 2.6,
        "underside": srgb(178, 184, 190),
        "radome": srgb(52, 56, 60),
        "antiglare": srgb(52, 56, 60),
        "lower": srgb(178, 184, 190),
        "upper": srgb(104, 118, 134),
    },
    # Tactical camouflage: green and grey over light grey
    "Tactical": {
        "camo": [srgb(90, 100, 84), srgb(122, 128, 128), srgb(68, 78, 66)],
        "camo_scale": 2.6,
        "underside": srgb(170, 176, 180),
        "radome": srgb(46, 50, 48),
        "antiglare": srgb(46, 50, 48),
        "lower": srgb(170, 176, 180),
        "upper": srgb(90, 100, 84),
    },
    # Desert camouflage: sand and brown over light blue
    "Desert": {
        "camo": [srgb(198, 172, 126), srgb(142, 106, 72), srgb(170, 140, 96)],
        "camo_scale": 2.4,
        "underside": srgb(162, 186, 198),
        "radome": srgb(52, 48, 44),
        "antiglare": srgb(52, 48, 44),
        "lower": srgb(162, 186, 198),
        "upper": srgb(198, 172, 126),
        "markings": "lowvis",
    },
    # Overall light grey, low-visibility markings
    "Grey": {
        "base": srgb(150, 156, 162),
        "radome": srgb(76, 80, 84),
        "antiglare": srgb(64, 68, 72),
        "lower": srgb(166, 172, 178),
        "upper": srgb(140, 146, 152),
        "markings": "lowvis",
    },
}

if __name__ == "__main__":
    jet_paint.main(LAYOUT, SCHEMES, "Interceptor")
