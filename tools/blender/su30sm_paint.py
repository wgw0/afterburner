"""
Afterburner: paints the Su-30SM with the shared painter (jet_paint.py). The panel layout and markings are the
Su-27S's (su27s_paint.py), with the canards painted like the tailerons; the skins are the Su-30SM's.

  blender -b tools/blender/out/Su30SM_base.blend --python tools/blender/su30sm_paint.py -- \
      --out <absolute dir> [--skin VKS] [--preview]

Use the .blend whose FBX was imported into Studio: the textures follow its UV layout.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import su30sm_generate  # noqa: E402, F401  (sets the shared generator module to the Su-30SM)
import su27s_paint  # noqa: E402  (the Flanker's panel layout)
import jet_paint  # noqa: E402

srgb = jet_paint.srgb

LAYOUT = dict(su27s_paint.LAYOUT)
LAYOUT["tail"] = LAYOUT["tail"] + ["CanardL", "CanardR"]

SCHEMES = {
    # Russian Aerospace Forces: two blue-greys over light grey
    "VKS": {
        "camo": [srgb(120, 134, 148), srgb(90, 104, 120), srgb(150, 162, 172)],
        "camo_scale": 3.2,
        "underside": srgb(176, 186, 194),
        "radome": srgb(214, 216, 210),
        "antiglare": srgb(56, 62, 70),
        "lower": srgb(176, 186, 194),
        "upper": srgb(120, 134, 148),
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
    # Naval: dark blue over light grey
    "Naval": {
        "camo": [srgb(70, 90, 122), srgb(52, 68, 96), srgb(88, 108, 136)],
        "camo_scale": 3.0,
        "underside": srgb(176, 186, 194),
        "radome": srgb(200, 202, 196),
        "antiglare": srgb(40, 48, 58),
        "lower": srgb(176, 186, 194),
        "upper": srgb(70, 90, 122),
    },
    # Desert camouflage: sand and brown over light blue, no national markings
    "Desert": {
        "camo": [srgb(198, 170, 124), srgb(142, 104, 70), srgb(170, 140, 96)],
        "camo_scale": 3.0,
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
