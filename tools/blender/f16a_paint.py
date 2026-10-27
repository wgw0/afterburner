"""
Afterburner: paints the F-16A Fighting Falcon with the shared painter (jet_paint.py): its panel layout,
markings and skins.

  blender -b tools/blender/out/F16A_base.blend --python tools/blender/f16a_paint.py -- \
      --out <absolute dir> [--skin Falcon] [--preview]

Use the .blend whose FBX was imported into Studio: the textures follow its UV layout.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import f16a_generate as f16  # noqa: E402  (sets the shared generator module to the F-16A)
import jet_paint  # noqa: E402

srgb = jet_paint.srgb

LAYOUT = {
    "body": ["Fuselage", "Strakes", "Intake"],
    "frames": [200, 380, 490, 600, 800, 950, 1100, 1250, 1400, 1550, 1700, 1850, 2000, 2150, 2285],
    "side_lines": [(0.10, 380, 2285), (-0.40, 950, 2200)],
    "side_panels": [(1250, 1550, 0.35, 0.65), (600, 700, -0.30, 0.20)],
    "wing": (f16.wing_le_y, f16.wing_te_y),
    "wings": ["WingL", "WingR"],
    "surfaces": ["LEFlapL", "LEFlapR", "FlapL", "FlapR", "AileronL", "AileronR"],
    "tail": ["StabilatorL", "StabilatorR"],
    "spars": (0.17, 0.45, 0.80),
    "ribs": (0.9, 4.6, 0.5),
    "fin": ["Fin"],
    "rudder": ["Rudder"],
    "fin_lines": [1.8, 2.4],
    "upper_only": ["CanopyFrame"],
    "radome": 380,
    "ducts": ["IntakeDuct"],
    "antiglare": (380, 495, 0.10, 0.35),
    "lip": (["Intake"], 815),
    "hot": (2200, 2290),
    "gun": None,
    "insignia": "star_us",
    "roundel_fuselage": (1150, 0.05, 0.25, ["Fuselage"]),
    "roundel_wing": (2.7, 0.35, 0.5),
    "fin_flash": None,
    "nozzles": [(0.0, f16.NOZZLE_Z)],
    "nozzle_y": (f16.NOZZLE_Y0, f16.NOZZLE_Y1),
    "petals": 15,
    "pitot": "metal",
}

SCHEMES = {
    # The F-16's three greys wrapped round the jet (FS 36118, 36270, 36375), low-visibility insignia
    "Falcon": {
        "camo": [srgb(128, 135, 140), srgb(78, 84, 87), srgb(150, 158, 163)],
        "camo_scale": 3.2,
        "underside": srgb(150, 158, 163),
        "radome": srgb(96, 100, 104),
        "antiglare": srgb(60, 64, 68),
        "lower": srgb(150, 158, 163),
        "upper": srgb(128, 135, 140),
        "markings": "lowvis",
    },
    # Blue-grey aggressor camouflage
    "Blue": {
        "camo": [srgb(80, 98, 128), srgb(112, 132, 158), srgb(60, 74, 100)],
        "camo_scale": 2.8,
        "underside": srgb(150, 166, 182),
        "radome": srgb(60, 70, 86),
        "antiglare": srgb(50, 56, 66),
        "lower": srgb(150, 166, 182),
        "upper": srgb(80, 98, 128),
        "markings": "lowvis",
    },
    # Desert aggressor camouflage, no national markings
    "Desert": {
        "camo": [srgb(200, 172, 128), srgb(146, 108, 74), srgb(176, 146, 102)],
        "camo_scale": 2.6,
        "underside": srgb(180, 186, 188),
        "radome": srgb(70, 64, 58),
        "antiglare": srgb(60, 56, 52),
        "lower": srgb(180, 186, 188),
        "upper": srgb(200, 172, 128),
        "markings": "none",
    },
    # European camouflage: dark green and dark grey over light grey
    "Euro": {
        "camo": [srgb(66, 78, 60), srgb(70, 74, 76), srgb(50, 60, 48)],
        "camo_scale": 3.0,
        "underside": srgb(160, 166, 170),
        "radome": srgb(52, 56, 52),
        "antiglare": srgb(44, 46, 44),
        "lower": srgb(160, 166, 170),
        "upper": srgb(66, 78, 60),
        "markings": "lowvis",
    },
}

if __name__ == "__main__":
    jet_paint.main(LAYOUT, SCHEMES, "Falcon")
