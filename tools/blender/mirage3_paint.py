"""
Afterburner: paints the Mirage IIIE with the shared painter (jet_paint.py): its panel layout, markings and
skins.

  blender -b tools/blender/out/MirageIII_base.blend --python tools/blender/mirage3_paint.py -- \
      --out <absolute dir> [--skin Tactical] [--preview]

Use the .blend whose FBX was imported into Studio: the textures follow its UV layout.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mirage3_generate as mir  # noqa: E402  (sets the shared generator module to the Mirage IIIE)
import jet_paint  # noqa: E402

srgb = jet_paint.srgb
FRANCE = (srgb(186, 34, 40), srgb(226, 226, 222), srgb(30, 60, 140))  # roundel: red outside, blue centre

LAYOUT = {
    "body": ["Fuselage", "Intakes"],
    "frames": [400, 520, 700, 868, 1000, 1150, 1300, 1450, 1600, 1750, 1900, 2050, 2200, 2350, 2500, 2620],
    "side_lines": [(-0.30, 400, 868), (0.05, 1000, 2620), (-0.45, 1000, 2480)],
    "side_panels": [(420, 500, -0.45, -0.05), (1050, 1150, -0.40, 0.00), (1900, 2000, 0.20, 0.55), (2250, 2350, -0.40, 0.10)],
    "wing": (mir.wing_le_y, mir.wing_te_y),
    "wings": ["WingL", "WingR"],
    "surfaces": ["ElevonInL", "ElevonInR", "ElevonOutL", "ElevonOutR"],
    "spars": (0.12, 0.45, 0.80),
    "ribs": (1.2, 4.0, 0.6),
    "fin": ["Fin"],
    "rudder": ["Rudder"],
    "fin_lines": [1.4, 1.9, 2.4],
    "upper_only": ["CanopyFrame", "ChuteFairing"],
    "radome": 400,
    "dark": ["InletCones"],
    "antiglare": (420, 538, 0.06, 0.31),
    "lip": (["Intakes"], 890),
    "duct": (["Intakes"], 880),
    "hot": (2560, 2680),
    "gun": (0.30, 0.15, 1000, 1250),
    "insignia": "roundel",
    "roundel_colours": FRANCE,
    "roundel_fuselage": (1230, -0.05, 0.27, ["Intakes"]),
    "roundel_wing": (2.95, 0.36, 0.5),
    "fin_flash": (["Rudder"], mir.RUDDER_SPAN[0] + 0.7, 2560, 0.45),
    "nozzles": [(0.0, mir.NOZZLE_Z)],
    "nozzle_y": (mir.NOZZLE_Y0, mir.NOZZLE_Y1),
    "petals": 18,
    "pitot": "metal",
}

SCHEMES = {
    # Armée de l'Air tactical camouflage: dark green and grey over aluminium-lacquered undersides
    "Tactical": {
        "camo": [srgb(88, 98, 82), srgb(120, 126, 128), srgb(66, 76, 64)],
        "camo_scale": 2.8,
        "underside": srgb(176, 180, 182),
        "underside_metal": True,
        "radome": srgb(44, 48, 46),
        "antiglare": srgb(44, 48, 46),
        "lower": srgb(176, 180, 182),
        "upper": srgb(88, 98, 82),
    },
    # Natural metal, as delivered
    "Silver": {
        "base": srgb(182, 186, 190),
        "metal": True,
        "radome": srgb(40, 42, 44),
        "antiglare": srgb(44, 46, 48),
        "lower": srgb(182, 186, 190),
        "upper": srgb(182, 186, 190),
    },
    # Desert camouflage: sand and brown over light blue
    "Desert": {
        "camo": [srgb(196, 170, 124), srgb(140, 104, 70), srgb(176, 146, 98)],
        "camo_scale": 2.6,
        "underside": srgb(160, 184, 196),
        "radome": srgb(52, 48, 44),
        "antiglare": srgb(52, 48, 44),
        "lower": srgb(160, 184, 196),
        "upper": srgb(196, 170, 124),
        "markings": "lowvis",
    },
    # Two-tone air-superiority grey
    "Grey": {
        "base": srgb(132, 140, 148),
        "radome": srgb(70, 74, 78),
        "antiglare": srgb(60, 64, 68),
        "lower": srgb(162, 168, 174),
        "upper": srgb(118, 126, 134),
        "markings": "lowvis",
    },
}

if __name__ == "__main__":
    jet_paint.main(LAYOUT, SCHEMES, "Tactical")
