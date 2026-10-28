"""
Afterburner: paints the F/A-18E Super Hornet with the shared painter (jet_paint.py). The panel layout and
markings are the F/A-18C's (fa18c_paint.py) on the stretched stations, with the larger wing; the skins are
the Super Hornet's.

  blender -b tools/blender/out/FA18E_base.blend --python tools/blender/fa18e_paint.py -- \
      --out <absolute dir> [--skin Navy] [--preview]

Use the .blend whose FBX was imported into Studio: the textures follow its UV layout.
"""

import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fa18e_generate as f18e  # noqa: E402  (sets the shared generator module to the F/A-18E)
import fa18c_paint  # noqa: E402  (the Hornet's panel layout)
import jet_paint  # noqa: E402

srgb = jet_paint.srgb

LAYOUT = dict(fa18c_paint.LAYOUT)
LAYOUT["wing"] = (lambda xa: f18e.wing_le_y(np.asarray(xa)), lambda xa: f18e.wing_te_y(np.asarray(xa)))
LAYOUT["ribs"] = (1.2, 6.4, 0.7)
LAYOUT["roundel_wing"] = (5.2, 0.45, 0.5)

SCHEMES = {
    # The Navy's two greys (FS 36320 over 36375), low-visibility markings
    "Navy": dict(fa18c_paint.SCHEMES["Navy"]),
    # Squadron commander's jet: the greys with full-colour markings
    "CAG": {
        "base": srgb(124, 134, 142),
        "radome": srgb(128, 134, 140),
        "antiglare": srgb(60, 66, 72),
        "lower": srgb(166, 172, 178),
        "upper": srgb(124, 134, 142),
    },
    # Adversary blue splinter, no national markings
    "Adversary": {
        "camo": [srgb(86, 106, 138), srgb(132, 150, 172), srgb(62, 78, 106)],
        "camo_scale": 2.8,
        "underside": srgb(170, 180, 192),
        "radome": srgb(62, 78, 106),
        "antiglare": srgb(50, 56, 66),
        "lower": srgb(170, 180, 192),
        "upper": srgb(86, 106, 138),
        "markings": "none",
    },
    # Overall dark grey, low-visibility markings
    "Ghost": {
        "base": srgb(84, 90, 96),
        "radome": srgb(76, 80, 86),
        "antiglare": srgb(52, 56, 60),
        "lower": srgb(98, 104, 110),
        "upper": srgb(84, 90, 96),
        "markings": "lowvis",
    },
}

if __name__ == "__main__":
    jet_paint.main(LAYOUT, SCHEMES, "Navy")
