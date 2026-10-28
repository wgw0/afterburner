"""
Afterburner: paints the Mirage 2000C with the shared painter (jet_paint.py): its panel layout, markings and
skins.

  blender -b tools/blender/out/Mirage2000C_base.blend --python tools/blender/mirage2000_paint.py -- \
      --out <absolute dir> [--skin AirDefence] [--preview]

Use the .blend whose FBX was imported into Studio: the textures follow its UV layout.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mirage2000_generate as m2k  # noqa: E402  (sets the shared generator module to the Mirage 2000C)
import jet_paint  # noqa: E402

srgb = jet_paint.srgb
FRANCE = (srgb(186, 34, 40), srgb(226, 226, 222), srgb(30, 60, 140))
m3 = m2k.m3

LAYOUT = {
    "body": ["Fuselage", "Intakes"],
    "frames": [78, 105, 145, 198, 230, 270, 310, 350, 390, 430, 470, 510, 550, 590],
    "side_lines": [(-0.30, 78, 198), (0.10, 230, 590), (-0.45, 230, 520)],
    "side_panels": [(85, 100, -0.50, -0.05), (250, 280, -0.40, 0.00), (480, 510, 0.10, 0.45)],
    "wing": (m2k.wing_le_y, m2k.wing_te_y),
    "wings": ["WingL", "WingR"],
    "surfaces": ["ElevonInL", "ElevonInR", "ElevonOutL", "ElevonOutR"],
    "spars": (0.15, 0.45, 0.78),
    "ribs": (1.1, 4.5, 0.6),
    "fin": ["Fin"],
    "rudder": ["Rudder"],
    "fin_lines": [1.4, 2.0, 2.6],
    "upper_only": ["CanopyFrame"],
    "radome": 78,
    "dark": ["InletCones"],
    "antiglare": (80, 107, 0.06, 0.30),
    "lip": (["Intakes"], 205),
    "duct": (["Intakes"], 202),
    "hot": (570, 600),
    "gun": (0.30, 0.15, 215, 270),
    "insignia": "roundel",
    "roundel_colours": FRANCE,
    "roundel_fuselage": (290, -0.20, 0.26, ["Intakes"]),
    "roundel_wing": (3.0, 0.36, 0.5),
    "fin_flash": (["Rudder"], m2k.RUDDER_SPAN[0] + 0.6, 560, 0.50),
    "nozzles": [(0.0, m3.NOZZLE_Z)],
    "nozzle_y": (m3.NOZZLE_Y0, m3.NOZZLE_Y1),
    "petals": 18,
    "pitot": "metal",
}

SCHEMES = {
    # Armée de l'Air air-defence blue-greys over light grey
    "AirDefence": {
        "camo": [srgb(122, 134, 148), srgb(92, 104, 120), srgb(140, 150, 162)],
        "camo_scale": 2.6,
        "underside": srgb(176, 182, 188),
        "radome": srgb(70, 76, 84),
        "antiglare": srgb(56, 62, 70),
        "lower": srgb(176, 182, 188),
        "upper": srgb(122, 134, 148),
    },
    # Overall grey, low-visibility markings
    "Grey": {
        "base": srgb(140, 146, 152),
        "radome": srgb(84, 88, 92),
        "antiglare": srgb(64, 68, 72),
        "lower": srgb(162, 168, 174),
        "upper": srgb(132, 138, 144),
        "markings": "lowvis",
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
    # Desert camouflage, no national markings
    "Desert": {
        "camo": [srgb(198, 172, 126), srgb(142, 106, 72), srgb(170, 140, 96)],
        "camo_scale": 2.4,
        "underside": srgb(162, 186, 198),
        "radome": srgb(52, 48, 44),
        "antiglare": srgb(52, 48, 44),
        "lower": srgb(162, 186, 198),
        "upper": srgb(198, 172, 126),
        "markings": "none",
    },
}

if __name__ == "__main__":
    jet_paint.main(LAYOUT, SCHEMES, "AirDefence")
