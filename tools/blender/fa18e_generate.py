"""
Afterburner: F/A-18E Super Hornet base mesh generator (Blender 4.x / 5.x). Art only: the F/A-18E has no
flight data yet (AircraftData), so this makes the model, skins and cockpit for when it does.

The Super Hornet is a scaled-up Hornet, and Commons has no three-view of it, so this script builds it from
the F/A-18C (fa18c_generate.py, measured from NASA's three-view) and the published differences:

  * 1.24 m longer (18.31 m against 17.07 m): a 0.86 m plug behind the cockpit and 0.38 m in the rear
    fuselage. Stations are mapped through stretch() before the F/A-18C module computes anything, so all of
    its shapes, parts and attachments follow.
  * the larger wing (13.62 m span over the wingtip rails against 11.43 m, chords 15% longer), larger
    leading-edge extensions, and larger tailerons and fins
  * the rectangular, raked "caret" intakes
  * 11 hardpoints: the wingtip rails, three pylons under each wing, two on the intakes and the centreline

Run headless:
  blender -b --python tools/blender/fa18e_generate.py -- --out <dir> --manifest-luau tools/Manifests/FA18E.luau
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import f5e_generate as kit  # noqa: E402  (shared helpers)

PX = 107.8  # the F/A-18C drawing's scale
PLUGS = ((790, 0.86 * PX), (1300, 0.38 * PX))  # (station, length): the fuselage opens behind each station
CG_XD = 1154 + 40  # the F/A-18C's 25% MAC, moved aft for the larger wing


def stretch(xd):
    """F/A-18C drawing station -> F/A-18E station."""
    return xd + sum(length for at, length in PLUGS if xd > at)


def _y(xd):
    return (stretch(CG_XD) - stretch(xd)) / PX


# The F/A-18C module reads kit.Y when it is imported, so the stretch goes in first
kit.Y = _y
import fa18c_generate as f18  # noqa: E402  (its measurements and builders, on stretched stations)

Y, Z, W = _y, kit.Z, f18.W
kit.Y = _y  # the F/A-18C module sets the calibration; keep the stretched mapping
kit.AIRFRAME = "FA18E"
kit.LENGTH = 18.31
kit.CG_FROM_PITOT = stretch(CG_XD) / PX

# The larger wing: the same root leading edge and sweep, chords 15% longer, out to the larger span
CHORD, TIP_X = 1.15, 6.45
root_chord = (kit.WING_ROOT_LE - kit.WING_ROOT_TE) * CHORD
kit.WING_ROOT_TE = kit.WING_ROOT_LE - root_chord
kit.WING_TIP_CHORD *= CHORD
span_ratio = (TIP_X - kit.WING_ROOT_X) / (kit.WING_TIP_X - kit.WING_ROOT_X)
kit.WING_TIP_X = TIP_X
kit.TE_FLAP_SPAN = (1.10, 1.10 + (3.90 - 1.10) * span_ratio)
kit.AILERON_SPAN = (kit.TE_FLAP_SPAN[1] + 0.05, TIP_X - 0.10)
_tip_le = kit.WING_ROOT_LE - (TIP_X - kit.WING_ROOT_X) * math.tan(kit.WING_SWEEP_LE)
kit.RAIL_Y = _tip_le - kit.WING_TIP_CHORD / 2


def wing_le_y(x):
    return kit.WING_ROOT_LE - (x - kit.WING_ROOT_X) * math.tan(kit.WING_SWEEP_LE)


def wing_te_y(x):
    tip_te = _tip_le - kit.WING_TIP_CHORD
    return kit.WING_ROOT_TE + (x - kit.WING_ROOT_X) * (tip_te - kit.WING_ROOT_TE) / (TIP_X - kit.WING_ROOT_X)


# Larger extensions, tailerons and fins
f18.LERX_EDGE = [(hw * 1.15, xd) for hw, xd in f18.LERX_EDGE]
T = 1.15
f18.STAB_TIP_X = f18.STAB_ROOT_X + (f18.STAB_TIP_X - f18.STAB_ROOT_X) * T
f18.STAB_ROOT_TE = f18.STAB_ROOT_LE - (f18.STAB_ROOT_LE - f18.STAB_ROOT_TE) * T
f18.STAB_TIP_LE = f18.STAB_ROOT_LE - (f18.STAB_ROOT_LE - f18.STAB_TIP_LE) * T
f18.STAB_TIP_TE = f18.STAB_ROOT_LE - (f18.STAB_ROOT_LE - f18.STAB_TIP_TE) * T
f18.FIN_TIP_Z = f18.FIN_ROOT_Z + (f18.FIN_TIP_Z - f18.FIN_ROOT_Z) * 1.10
f18.FIN_ROOT_TE = f18.FIN_ROOT_LE - (f18.FIN_ROOT_LE - f18.FIN_ROOT_TE) * 1.10
f18.FIN_TIP_LE = f18.FIN_ROOT_LE - (f18.FIN_ROOT_LE - f18.FIN_TIP_LE) * 1.10
f18.FIN_TIP_TE = f18.FIN_ROOT_LE - (f18.FIN_ROOT_LE - f18.FIN_TIP_TE) * 1.10

# Caret intakes: boxier, and raked more at the lip
f18.LIP_TOP, f18.LIP_BOTTOM = 960, 1025
_rounded_ring = f18.rounded_ring


def rounded_ring(cx, y_of, hw, zc, hh, e=2.6, segments=20):
    return _rounded_ring(cx, y_of, hw, zc, hh, 4.5, segments)


f18.rounded_ring = rounded_ring

kit.HULL = {"size": [2.6, 1.9, 16.8], "at": [0, 0.1, -1.6]}
kit.HITBOXES = dict(kit.HITBOXES)
kit.HITBOXES.update({
    "WingL": {"size": [5.4, 0.4, 3.6], "at": [-3.9, round(kit.WING_Z, 2), 1.6]},
    "WingR": {"size": [5.4, 0.4, 3.6], "at": [3.9, round(kit.WING_Z, 2), 1.6]},
})
kit.ATTACHMENTS = dict(kit.ATTACHMENTS)
for k in [k for k in kit.ATTACHMENTS if k.startswith("Hardpoint")]:
    del kit.ATTACHMENTS[k]
WZ = kit.WING_Z
kit.ATTACHMENTS.update({
    "WingtipL": (-(TIP_X + 0.05), kit.RAIL_Y, WZ),
    "WingtipR": (TIP_X + 0.05, kit.RAIL_Y, WZ),
    "Hardpoint1": (-(TIP_X + 0.08), kit.RAIL_Y, WZ - 0.10),
    "Hardpoint2": (TIP_X + 0.08, kit.RAIL_Y, WZ - 0.10),
    "Hardpoint3": (-4.90, wing_le_y(4.90) - 1.0, WZ - 0.30),
    "Hardpoint4": (4.90, wing_le_y(4.90) - 1.0, WZ - 0.30),
    "Hardpoint5": (-3.60, wing_le_y(3.60) - 1.2, WZ - 0.30),
    "Hardpoint6": (3.60, wing_le_y(3.60) - 1.2, WZ - 0.30),
    "Hardpoint7": (-2.30, wing_le_y(2.30) - 1.4, WZ - 0.30),
    "Hardpoint8": (2.30, wing_le_y(2.30) - 1.4, WZ - 0.30),
    "Hardpoint9": (-0.80, Y(1150), Z(450)),
    "Hardpoint10": (0.80, Y(1150), Z(450)),
    "Hardpoint11": (0, Y(1300), Z(450)),
})

if __name__ == "__main__":
    f18.main()
