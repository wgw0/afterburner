"""
Afterburner: paints the Gripen C with the shared painter (jet_paint.py): its panel layout, markings and
skins.

  blender -b tools/blender/out/GripenC_base.blend --python tools/blender/gripenc_paint.py -- \
      --out <absolute dir> [--skin Grey] [--preview]

Use the .blend whose FBX was imported into Studio: the textures follow its UV layout.
"""

import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gripenc_generate as gr  # noqa: E402  (sets the shared generator module to the Gripen C)
import jet_paint  # noqa: E402

srgb = jet_paint.srgb
SWEDEN = (srgb(30, 70, 140), srgb(240, 196, 40), srgb(30, 70, 140))  # outer ring to centre (simplified)


def edge(fn):
    """A wing edge as a function of |x| for arrays."""
    return lambda xa: fn(np.asarray(xa))


LAYOUT = {
    "body": ["Fuselage", "Intakes"],
    "frames": [200, 300, 400, 600, 720, 800, 900, 1000, 1100, 1200, 1300],
    "side_lines": [(0.30, 200, 720), (0.05, 720, 1340), (-0.45, 300, 1300)],
    "side_panels": [(220, 290, -0.30, 0.20), (900, 1000, -0.55, -0.15), (1150, 1250, -0.40, 0.10)],
    "wing": (edge(gr.wing_le_y), edge(gr.wing_te_y)),
    "wings": ["WingL", "WingR"],
    "surfaces": ["LEFlapL", "LEFlapR", "FlapL", "FlapR", "AileronL", "AileronR"],
    "tail": ["CanardL", "CanardR"],
    "spars": (0.10, 0.45, 0.80),
    "ribs": (1.2, 4.0, 0.5),
    "fin": ["Fin"],
    "rudder": ["Rudder"],
    "fin_lines": [1.2, 1.8],
    "upper_only": ["CanopyFrame"],
    "under_z": (-0.20, -0.45),
    "radome": 200,
    "ducts": ["IntakeDucts"],
    "antiglare": (210, 300, 0.10, 0.45),
    "lip": (["Intakes"], 520),
    "hot": (1300, 1360),
    "gun": None,
    "insignia": "roundel",
    "roundel_colours": SWEDEN,
    "roundel_fuselage": (1250, 1.20, 0.22, ["Fin"]),
    "roundel_wing": (3.0, 0.32, 0.5),
    "fin_flash": None,
    "nozzles": [(0.0, gr.NOZZLE_Z)],
    "nozzle_y": (gr.NOZZLE_Y0, gr.NOZZLE_Y1),
    "petals": 14,
    "pitot": "metal",
}

SCHEMES = {
    # Two greys, low-visibility markings
    "Grey": {
        "camo": [srgb(122, 128, 134), srgb(146, 152, 156), srgb(122, 128, 134)],
        "camo_scale": 3.4,
        "underside": srgb(150, 156, 160),
        "radome": srgb(104, 110, 116),
        "antiglare": srgb(60, 64, 68),
        "lower": srgb(150, 156, 160),
        "upper": srgb(122, 128, 134),
        "markings": "lowvis",
    },
    # Overall dark grey, low-visibility markings
    "DarkGrey": {
        "base": srgb(86, 92, 98),
        "radome": srgb(72, 76, 80),
        "antiglare": srgb(50, 54, 58),
        "lower": srgb(100, 106, 112),
        "upper": srgb(86, 92, 98),
        "markings": "lowvis",
    },
    # Splinter camouflage: greens, brown and black over light grey, full-colour markings
    "Splinter": {
        "camo": [srgb(78, 96, 66), srgb(110, 92, 64), srgb(50, 60, 46)],
        "camo_scale": 2.4,
        "underside": srgb(160, 166, 168),
        "radome": srgb(50, 56, 48),
        "antiglare": srgb(40, 44, 40),
        "lower": srgb(160, 166, 168),
        "upper": srgb(78, 96, 66),
    },
    # Arctic: white and light grey, no national markings
    "Arctic": {
        "camo": [srgb(222, 226, 228), srgb(170, 178, 184), srgb(206, 210, 212)],
        "camo_scale": 2.6,
        "underside": srgb(214, 218, 220),
        "radome": srgb(120, 128, 134),
        "antiglare": srgb(60, 64, 68),
        "lower": srgb(214, 218, 220),
        "upper": srgb(222, 226, 228),
        "markings": "none",
    },
}

if __name__ == "__main__":
    jet_paint.main(LAYOUT, SCHEMES, "Grey")
