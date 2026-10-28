"""
Afterburner: F-15E Strike Eagle base mesh generator (Blender 4.x / 5.x). Art only: the F-15E has no flight
data yet (AircraftData), so this makes the model, skins and cockpit for when it does.

The F-15E's airframe is the F-15C's (f15c_generate.py, measured from its drawing), so this script uses the
F-15C's measurements and builders, switching that module's settings for what the F-15E changes:

  * the two-seat cockpit: the canopy runs back over the rear seat, with a frame between the cockpits, and
    the spine rises behind it
  * the conformal fuel tanks along the outsides of the intakes, under the wing roots
  * the navigation and targeting pods under the intakes
  * the front cockpit: the wide HUD over the up-front controls, with three displays below

Run headless:
  blender -b --python tools/blender/f15e_generate.py -- --out <dir> --manifest-luau tools/Manifests/F15E.luau
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import f15c_generate as f15  # noqa: E402  (its measurements and builders; its settings are switched below)

kit = f15.kit
Y, Z, W = kit.Y, kit.Z, f15.W
kit.AIRFRAME = "F15E"

# The canopy runs back over the rear seat; the spine rises behind it rather than behind the front seat
_BODY = [row for row in f15._BODY if row[0] < 1000] + [
    (1000, 92, 676, 450, 450, 0.0, 3.0),
    (1150, 96, 680, 450, 450, 0.0, 3.0),
    (1220, 104, 682, 470, 432, 0.38, 3.3),
    (1300, 118, 683, 518, 452, 0.38, 3.6),
] + [row for row in f15._BODY if row[0] >= 1500]
kit.FUSELAGE = [(xd, W(hw), Z(zb), Z(zs), Z(zt), sp, e) for xd, hw, zb, zs, zt, sp, e in _BODY]

kit.CANOPY = [
    (460, 0.10, Z(478)),
    (500, 0.30, Z(455)),
    (550, 0.40, Z(426)),
    (590, 0.45, Z(403)),  # windscreen bow
    (650, 0.47, Z(385)),
    (720, 0.47, Z(375)),
    (850, 0.47, Z(372)),
    (1000, 0.46, Z(374)),
    (1100, 0.42, Z(388)),
    (1180, 0.33, Z(410)),
    (1250, 0.20, Z(430)),
]
kit.CANOPY_FRAMES = (590, 860, 1180)  # windscreen bow, the frame between the cockpits, the canopy's rear

# Conformal fuel tanks: (xd, centre x m, half width m, centre z m, half height m) along each intake's side
CFT = [(980, 1.62, 0.06, 0.25, 0.20), (1080, 1.64, 0.20, 0.22, 0.40), (1600, 1.60, 0.22, 0.20, 0.44),
       (1950, 1.52, 0.18, 0.18, 0.36), (2080, 1.46, 0.05, 0.18, 0.12)]

kit.COCKPIT = dict(kit.COCKPIT)
kit.COCKPIT["instruments"] = [
    {"name": "UFC", "kind": "Lights", "u": 0.0, "v": 0.08, "size": 0.10},
    {"name": "RadarScope", "kind": "MFD", "u": -0.215, "v": 0.12, "size": 0.12, "live": "Radar"},
    {"name": "RightMFD", "kind": "MFD", "u": 0.215, "v": 0.12, "size": 0.12},
    {"name": "CentreMFD", "kind": "MFD", "u": 0.0, "v": 0.20, "size": 0.10},
    {"name": "Airspeed", "kind": "Dial", "u": -0.25, "v": 0.25, "size": 0.05, "live": "Speed"},
    {"name": "Altimeter", "kind": "Dial", "u": -0.18, "v": 0.25, "size": 0.05, "live": "Altitude"},
    {"name": "GMeter", "kind": "Dial", "u": -0.11, "v": 0.29, "size": 0.04, "live": "G"},
    {"name": "RPM", "kind": "Dial", "u": 0.11, "v": 0.29, "size": 0.04, "live": "RPM"},
    {"name": "ADI", "kind": "Dial", "u": 0.18, "v": 0.25, "size": 0.05, "face": "attitude"},
    {"name": "Fuel", "kind": "Dial", "u": 0.25, "v": 0.25, "size": 0.05},
]

kit.ATTACHMENTS = dict(kit.ATTACHMENTS)
# Missile stations on the conformal tanks' lower corners, in place of the F-15C's fuselage stations
kit.ATTACHMENTS.update({
    "Hardpoint5": (-1.75, Y(1250), -0.18),
    "Hardpoint6": (1.75, Y(1250), -0.18),
    "Hardpoint7": (-1.75, Y(1800), -0.18),
    "Hardpoint8": (1.75, Y(1800), -0.18),
})

_build_seat = f15.build_seat
_build_pitot = f15.build_pitot


def build_seat(col):
    """Both ejection seats (the rear one higher), as one part."""
    _build_seat(col)
    _, ey, ez = f15.EYE
    ey, ez = Y(1010), ez + 0.10
    parts = [
        kit.box((0, ey - 0.05, ez - 0.70), (0.46, 0.48, 0.10)),
        kit.box((0, ey - 0.33, ez - 0.38), (0.46, 0.12, 0.66)),
        kit.box((0, ey - 0.30, ez + 0.04), (0.34, 0.20, 0.24)),
    ]
    v, f = kit.merge(*parts)
    kit.make_object("RearSeat", v, f, col, "Details")


def build_pitot(col):
    """The pitots, the conformal fuel tanks and the navigation and targeting pods."""
    _build_pitot(col)
    tanks = []
    for side in (1, -1):
        rings = [f15.rounded_ring(side * cx, lambda _z, xd=xd: Y(xd), hw, zc, hh, 3.0, 16) for xd, cx, hw, zc, hh in CFT]
        tanks.append(kit.lofted(rings, True, True))
    v, f = kit.merge(*tanks)
    kit.make_object("ConformalTanks", v, f, col, "Body")
    pods = []
    for side in (1, -1):
        y0, y1 = Y(850), Y(1250)
        pods.append(kit.cylinder((side * 1.10, y0, -0.45), (side * 1.10, y1, -0.45), 0.17, 12, radius1=0.17))
        pods.append(kit.cylinder((side * 1.10, y0 + 0.25, -0.45), (side * 1.10, y0, -0.45), 0.04, 12, radius1=0.17))
        pods.append(kit.box((side * 1.10, (y0 + y1) / 2, -0.30), (0.08, 1.2, 0.14)))
    v, f = kit.merge(*pods)
    kit.make_object("Pods", v, f, col, "Details")


f15.build_seat = build_seat
f15.build_pitot = build_pitot

if __name__ == "__main__":
    f15.main()
