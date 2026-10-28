"""
Afterburner: paints the MiG-29SMT with the shared painter (jet_paint.py). The panel layout and markings are
the MiG-29A's (mig29_paint.py); the skins are the SMT's.

  blender -b tools/blender/out/MiG29SMT_base.blend --python tools/blender/mig29smt_paint.py -- \
      --out <absolute dir> [--skin VKS] [--preview]

Use the .blend whose FBX was imported into Studio: the textures follow its UV layout.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mig29smt_generate  # noqa: E402, F401  (sets the shared generator module to the MiG-29SMT)
import mig29_paint  # noqa: E402  (the MiG-29's panel layout)
import jet_paint  # noqa: E402

srgb = jet_paint.srgb

LAYOUT = dict(mig29_paint.LAYOUT)

SCHEMES = {
    # Russian Aerospace Forces: two greys
    "VKS": {
        "camo": [srgb(132, 140, 146), srgb(100, 108, 116), srgb(150, 156, 160)],
        "camo_scale": 3.2,
        "underside": srgb(170, 176, 180),
        "radome": srgb(214, 216, 210),
        "antiglare": srgb(56, 60, 64),
        "lower": srgb(170, 176, 180),
        "upper": srgb(132, 140, 146),
    },
    # Overall blue-grey, low-visibility markings
    "Blue": {
        "base": srgb(108, 124, 142),
        "radome": srgb(84, 96, 110),
        "antiglare": srgb(56, 62, 70),
        "lower": srgb(140, 154, 168),
        "upper": srgb(108, 124, 142),
        "markings": "lowvis",
    },
    # Grey and green splinter camouflage over light grey
    "Splinter": {
        "camo": [srgb(104, 116, 100), srgb(136, 142, 144), srgb(80, 92, 78)],
        "camo_scale": 2.6,
        "underside": srgb(168, 176, 180),
        "radome": srgb(52, 56, 52),
        "antiglare": srgb(44, 46, 44),
        "lower": srgb(168, 176, 180),
        "upper": srgb(104, 116, 100),
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
    jet_paint.main(LAYOUT, SCHEMES, "VKS")
