"""
Afterburner: paints the F-16C Block 50 with the shared painter (jet_paint.py). The panel layout and markings
are the F-16A's (f16a_paint.py); the skins are the F-16C's.

  blender -b tools/blender/out/F16C_base.blend --python tools/blender/f16c_paint.py -- \
      --out <absolute dir> [--skin Viper] [--preview]

Use the .blend whose FBX was imported into Studio: the textures follow its UV layout.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import f16c_generate  # noqa: E402, F401  (sets the shared generator module to the F-16C)
import f16a_paint  # noqa: E402  (the F-16's panel layout)
import jet_paint  # noqa: E402

srgb = jet_paint.srgb

LAYOUT = dict(f16a_paint.LAYOUT)

SCHEMES = {
    # Two greys (FS 36118 over 36270), low-visibility insignia
    "Viper": {
        "camo": [srgb(110, 116, 122), srgb(140, 146, 152), srgb(110, 116, 122)],
        "camo_scale": 3.6,
        "underside": srgb(140, 146, 152),
        "radome": srgb(92, 96, 100),
        "antiglare": srgb(56, 60, 64),
        "lower": srgb(140, 146, 152),
        "upper": srgb(110, 116, 122),
        "markings": "lowvis",
    },
    # Two-tone blue "ghost" camouflage, low-visibility insignia
    "Ghost": {
        "camo": [srgb(92, 110, 136), srgb(126, 144, 166), srgb(76, 92, 116)],
        "camo_scale": 3.0,
        "underside": srgb(150, 164, 180),
        "radome": srgb(70, 80, 96),
        "antiglare": srgb(50, 56, 66),
        "lower": srgb(150, 164, 180),
        "upper": srgb(92, 110, 136),
        "markings": "lowvis",
    },
    # Arctic aggressor splinter: white, light grey and blue-grey, no national markings
    "Arctic": {
        "camo": [srgb(214, 218, 220), srgb(150, 160, 170), srgb(96, 110, 128)],
        "camo_scale": 2.6,
        "underside": srgb(206, 210, 212),
        "radome": srgb(96, 110, 128),
        "antiglare": srgb(50, 56, 66),
        "lower": srgb(206, 210, 212),
        "upper": srgb(214, 218, 220),
        "markings": "none",
    },
    # Overall dark grey, low-visibility insignia
    "Night": {
        "base": srgb(74, 78, 84),
        "radome": srgb(60, 64, 68),
        "antiglare": srgb(44, 46, 50),
        "lower": srgb(92, 96, 102),
        "upper": srgb(74, 78, 84),
        "markings": "lowvis",
    },
}

if __name__ == "__main__":
    jet_paint.main(LAYOUT, SCHEMES, "Viper")
