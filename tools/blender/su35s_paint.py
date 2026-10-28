"""
Afterburner: paints the Su-35S with the shared painter (jet_paint.py). The panel layout and markings are the
Su-27S's (su27s_paint.py); the skins are the Su-35S's.

  blender -b tools/blender/out/Su35S_base.blend --python tools/blender/su35s_paint.py -- \
      --out <absolute dir> [--skin VKS] [--preview]

Use the .blend whose FBX was imported into Studio: the textures follow its UV layout.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import su35s_generate  # noqa: E402, F401  (sets the shared generator module to the Su-35S)
import su27s_paint  # noqa: E402  (the Flanker's panel layout)
import jet_paint  # noqa: E402

srgb = jet_paint.srgb

LAYOUT = dict(su27s_paint.LAYOUT)

SCHEMES = {
    # Russian Aerospace Forces: two-tone blue-grey splinter over light grey
    "VKS": {
        "camo": [srgb(112, 128, 146), srgb(146, 160, 174), srgb(90, 104, 122)],
        "camo_scale": 2.8,
        "underside": srgb(180, 190, 198),
        "radome": srgb(214, 216, 210),
        "antiglare": srgb(56, 62, 70),
        "lower": srgb(180, 190, 198),
        "upper": srgb(112, 128, 146),
    },
    # Overall dark grey, low-visibility markings
    "Dark": {
        "base": srgb(80, 86, 94),
        "radome": srgb(66, 70, 76),
        "antiglare": srgb(48, 52, 56),
        "lower": srgb(102, 108, 116),
        "upper": srgb(80, 86, 94),
        "markings": "lowvis",
    },
    # The Flanker's blue camouflage
    "Flanker": dict(su27s_paint.SCHEMES["Flanker"]),
    # Desert camouflage: sand and brown over light blue, no national markings
    "Desert": dict(su27s_paint.SCHEMES["Desert"]),
}

if __name__ == "__main__":
    jet_paint.main(LAYOUT, SCHEMES, "VKS")
