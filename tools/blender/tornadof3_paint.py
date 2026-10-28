"""
Afterburner: paints the Tornado F3 with the shared painter (jet_paint.py): its panel layout, markings and
skins.

  blender -b tools/blender/out/TornadoF3_base.blend --python tools/blender/tornadof3_paint.py -- \
      --out <absolute dir> [--skin AirDefence] [--preview]

Use the .blend whose FBX was imported into Studio: the textures follow its UV layout. Stations are the IDS
drawing's, mapped through the generator's stretch() like the model's.
"""

import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tornadof3_generate as tor  # noqa: E402  (sets the shared generator module to the Tornado F3)
import jet_paint  # noqa: E402

srgb = jet_paint.srgb
S = tor.stretch
RAF = (srgb(30, 50, 120), srgb(226, 226, 222), srgb(186, 34, 40))  # outer ring to centre


OFF = S(1000) - 1000  # the stretch is a constant shift over the wing


def edge(xd0, slope):
    """A wing edge as a function of |x| for arrays: the generator's line, shifted by the stretch."""
    return lambda xa: tor.kit.Y(xd0 + OFF + (np.asarray(xa) * tor.PX - 244) * slope)


LAYOUT = {
    "body": ["Fuselage", "Nacelles", "Gloves"],
    "frames": [S(xd) for xd in (235, 340, 430, 592, 700, 760, 830, 900, 1000, 1100, 1200, 1300, 1400, 1500)],
    "side_lines": [(0.40, S(235), S(700)), (0.05, S(760), S(1550)), (-0.65, S(300), S(1300))],
    "side_panels": [(S(260), S(330), -0.70, -0.10), (S(1000), S(1100), -0.85, -0.40), (S(1350), S(1450), -0.60, -0.10)],
    "wing": (edge(925, 0.458), edge(1178, 0.264)),
    "wings": ["WingL", "WingR"],
    "surfaces": ["LEFlapL", "LEFlapR", "FlapL", "FlapR", "AileronL", "AileronR"],
    "tail": ["StabilatorL", "StabilatorR"],
    "spars": (0.12, 0.45, 0.75),
    "ribs": (2.4, 6.7, 0.7),
    "fin": ["Fin"],
    "rudder": ["Rudder"],
    "fin_lines": [1.6, 2.4, 3.2],
    "upper_only": ["CanopyFrame"],
    "under_z": (-0.30, -0.65),
    "radome": S(235),
    "ducts": ["IntakeDucts"],
    "antiglare": (S(245), S(340), 0.10, 0.60),
    "lip": (["Nacelles"], S(680)),
    "hot": (S(1560), S(1600)),
    "gun": None,
    "insignia": "roundel",
    "roundel_colours": RAF,
    "roundel_fuselage": (S(720), -0.15, 0.30, ["Nacelles"]),
    "roundel_wing": (5.2, 0.42, 0.5),
    "fin_flash": None,
    "nozzles": [(-tor.NOZZLE_X, tor.NOZZLE_Z), (tor.NOZZLE_X, tor.NOZZLE_Z)],
    "nozzle_y": (tor.NOZZLE_Y0, tor.NOZZLE_Y1),
    "petals": 16,
    "pitot": "metal",
}

SCHEMES = {
    # RAF air defence grey: two light greys, low-visibility roundels
    "AirDefence": {
        "base": srgb(150, 156, 160),
        "radome": srgb(120, 124, 128),
        "antiglare": srgb(70, 74, 78),
        "lower": srgb(178, 182, 184),
        "upper": srgb(150, 156, 160),
        "markings": "lowvis",
    },
    # Darker grey of the later years, low-visibility roundels
    "DarkGrey": {
        "base": srgb(104, 110, 116),
        "radome": srgb(84, 88, 92),
        "antiglare": srgb(56, 60, 64),
        "lower": srgb(128, 134, 140),
        "upper": srgb(104, 110, 116),
        "markings": "lowvis",
    },
    # Grey splinter camouflage, full-colour roundels
    "Splinter": {
        "camo": [srgb(128, 136, 142), srgb(90, 98, 106), srgb(156, 162, 166)],
        "camo_scale": 2.6,
        "underside": srgb(176, 180, 184),
        "radome": srgb(70, 74, 78),
        "antiglare": srgb(56, 60, 64),
        "lower": srgb(176, 180, 184),
        "upper": srgb(128, 136, 142),
    },
    # Desert pink, no national markings
    "Desert": {
        "base": srgb(206, 176, 158),
        "radome": srgb(186, 160, 144),
        "antiglare": srgb(80, 70, 64),
        "lower": srgb(216, 192, 178),
        "upper": srgb(206, 176, 158),
        "markings": "none",
    },
}

if __name__ == "__main__":
    jet_paint.main(LAYOUT, SCHEMES, "AirDefence")
