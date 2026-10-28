"""
Afterburner: paints the F-15E Strike Eagle with the shared painter (jet_paint.py). The panel layout and
markings are the F-15C's (f15c_paint.py), with the conformal fuel tanks painted as body; the skins are the
F-15E's.

  blender -b tools/blender/out/F15E_base.blend --python tools/blender/f15e_paint.py -- \
      --out <absolute dir> [--skin Strike] [--preview]

Use the .blend whose FBX was imported into Studio: the textures follow its UV layout.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import f15e_generate  # noqa: E402, F401  (sets the shared generator module to the F-15E)
import f15c_paint  # noqa: E402  (the F-15's panel layout)
import jet_paint  # noqa: E402

srgb = jet_paint.srgb

LAYOUT = dict(f15c_paint.LAYOUT)
LAYOUT["body"] = LAYOUT["body"] + ["ConformalTanks"]
LAYOUT["roundel_fuselage"] = (1350, 0.25, 0.28, ["ConformalTanks"])  # on the tanks, which cover the intakes

SCHEMES = {
    # Gunship grey all over (FS 36118), low-visibility markings
    "Strike": {
        "base": srgb(86, 92, 98),
        "radome": srgb(76, 80, 86),
        "antiglare": srgb(52, 56, 60),
        "lower": srgb(96, 102, 108),
        "upper": srgb(86, 92, 98),
        "markings": "lowvis",
    },
    # Two light greys, low-visibility markings
    "Ghost": {
        "camo": [srgb(112, 120, 128), srgb(134, 142, 150), srgb(112, 120, 128)],
        "camo_scale": 3.6,
        "underside": srgb(134, 142, 150),
        "radome": srgb(118, 124, 130),
        "antiglare": srgb(70, 76, 82),
        "lower": srgb(134, 142, 150),
        "upper": srgb(112, 120, 128),
        "markings": "lowvis",
    },
    # Three-grey splinter camouflage, full-colour markings
    "Splinter": {
        "camo": [srgb(120, 126, 132), srgb(84, 90, 96), srgb(150, 156, 160)],
        "camo_scale": 2.6,
        "underside": srgb(150, 156, 160),
        "radome": srgb(84, 90, 96),
        "antiglare": srgb(52, 56, 60),
        "lower": srgb(150, 156, 160),
        "upper": srgb(120, 126, 132),
    },
    # Desert camouflage: sand and brown over light grey, no national markings
    "Desert": {
        "camo": [srgb(198, 170, 124), srgb(146, 110, 74), srgb(176, 146, 100)],
        "camo_scale": 3.2,
        "underside": srgb(172, 184, 192),
        "radome": srgb(70, 64, 56),
        "antiglare": srgb(56, 52, 48),
        "lower": srgb(172, 184, 192),
        "upper": srgb(198, 170, 124),
        "markings": "none",
    },
}

if __name__ == "__main__":
    jet_paint.main(LAYOUT, SCHEMES, "Strike")
