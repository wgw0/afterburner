"""
Afterburner: Su-30SM base mesh generator (Blender 4.x / 5.x). Art only: the Su-30SM has no flight data yet
(AircraftData), so this makes the model, skins and cockpit for when it does.

The Su-30SM's airframe is the Su-27S's (su27s_generate.py, measured from its drawing), so this script uses
the Su-27S's measurements and builders, switching that module's settings for what the Su-30SM changes:

  * the two-seat cockpit: the canopy runs back over the rear seat, and the dorsal hump starts behind it
  * the canards on the leading-edge extensions, beside the windscreen
  * two more wing pylons (12 hardpoints)
  * the front cockpit: the head-up display over two colour displays, with standby instruments, in grey

Run headless:
  blender -b --python tools/blender/su30sm_generate.py -- --out <dir> --manifest-luau tools/Manifests/Su30SM.luau
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import su27s_generate as su27  # noqa: E402  (its measurements and builders; its settings are switched below)

kit = su27.kit
Y, Z, W = kit.Y, kit.Z, su27.W
kit.AIRFRAME = "Su30SM"

# The canopy runs back over the rear seat; the hump rises behind it
_BODY = [row for row in su27._BODY if row[0] < 700] + [
    (700, 68, 374, 262, 262, 0.0, 2.8),
    (780, 84, 372, 268, 262, 0.0, 2.9),
    (850, 112, 371, 305, 236, 0.42, 3.1),
    (920, 140, 372, 335, 240, 0.45, 3.4),
] + [row for row in su27._BODY if row[0] >= 1000]
kit.FUSELAGE = [(xd, W(hw), Z(zb), Z(zs), Z(zt), sp, e) for xd, hw, zb, zs, zt, sp, e in _BODY]

kit.CANOPY = [
    (xd, w, Z(row)) for xd, w, row in (
        (360, 0.10, 250), (400, 0.30, 228), (440, 0.38, 210), (470, 0.42, 198), (520, 0.44, 188),
        (600, 0.45, 184), (700, 0.45, 182), (770, 0.42, 188), (820, 0.34, 205), (860, 0.22, 225), (880, 0.12, 236),
    )
]
kit.CANOPY_FRAMES = (455, 640, 830)  # windscreen bow, the frame between the cockpits, the canopy's rear

# Canards: root and tip (half width px, leading-edge xd, trailing-edge xd), at the extensions' height
CANARD_ROOT, CANARD_TIP = (112, 640, 778), (275, 868, 920)
CANARD_Z = Z(325)

kit.ATTACHMENTS = dict(kit.ATTACHMENTS)
kit.ATTACHMENTS.update({
    "Hardpoint11": (-3.90, Y(1200), su27.WING_Z - 0.30),
    "Hardpoint12": (3.90, Y(1200), su27.WING_Z - 0.30),
})

kit.COCKPIT = dict(kit.COCKPIT)
kit.COCKPIT["palette"] = "Modern"
kit.COCKPIT["instruments"] = [
    {"name": "RadarScope", "kind": "MFD", "u": -0.17, "v": 0.13, "size": 0.15, "live": "Radar"},
    {"name": "RightMFD", "kind": "MFD", "u": 0.17, "v": 0.13, "size": 0.15},
    {"name": "Airspeed", "kind": "Dial", "u": -0.24, "v": 0.27, "size": 0.05, "live": "Speed"},
    {"name": "Altimeter", "kind": "Dial", "u": -0.16, "v": 0.27, "size": 0.05, "live": "Altitude"},
    {"name": "GMeter", "kind": "Dial", "u": -0.08, "v": 0.27, "size": 0.045, "live": "G"},
    {"name": "ADI", "kind": "Dial", "u": 0.0, "v": 0.28, "size": 0.07, "face": "attitude"},
    {"name": "RPM", "kind": "Dial", "u": 0.08, "v": 0.27, "size": 0.045, "live": "RPM"},
    {"name": "RPM2", "kind": "Dial", "u": 0.16, "v": 0.27, "size": 0.045},
    {"name": "Fuel", "kind": "Dial", "u": 0.24, "v": 0.27, "size": 0.045},
]

_build_seat = su27.build_seat
_build_pitot = su27.build_pitot


def build_seat(col):
    """The front seat, and the rear seat (higher) as its own part."""
    _build_seat(col)
    ey, ez = Y(730), su27.EYE[2] + 0.10
    parts = [
        kit.box((0, ey - 0.05, ez - 0.70), (0.46, 0.48, 0.10)),
        kit.box((0, ey - 0.33, ez - 0.38), (0.46, 0.12, 0.66)),
        kit.box((0, ey - 0.30, ez + 0.04), (0.34, 0.20, 0.24)),
    ]
    v, f = kit.merge(*parts)
    kit.make_object("RearSeat", v, f, col, "Details")


def build_pitot(col):
    """The nose probe, and the canards (all-moving, origin on their spigot)."""
    _build_pitot(col)
    (r_hw, r_le, r_te), (t_hw, t_le, t_te) = CANARD_ROOT, CANARD_TIP
    root_le, root_te = (W(r_hw), Y(r_le), CANARD_Z), (W(r_hw), Y(r_te), CANARD_Z)
    tip_le, tip_te = (W(t_hw), Y(t_le), CANARD_Z), (W(t_hw), Y(t_te), CANARD_Z)
    pivot_y = Y(r_le) - (Y(r_le) - Y(r_te)) * 0.45
    for side, name in ((1, "R"), (-1, "L")):
        v, f = kit.panel(root_le, root_te, tip_le, tip_te, (0, 0, 1), 0.045, 0.0, 1.0, 0, 1, 4, 6)
        if side < 0:
            v, f = kit.mirror_x(v), kit.flip_faces(f)
        kit.make_object(f"Canard{name}", v, f, col, "Wings", "ControlSurface", origin=(side * W(r_hw), pivot_y, CANARD_Z),
                        hinge={"axis": (1, 0, 0), "min": -20, "max": 20, "control": "Elevon" + name})


su27.build_seat = build_seat
su27.build_pitot = build_pitot

if __name__ == "__main__":
    su27.main()
