"""
Afterburner: Su-35S base mesh generator (Blender 4.x / 5.x). Art only: the Su-35S has no flight data yet
(AircraftData), so this makes the model, skins and cockpit for when it does.

The Su-35S's airframe is the Su-27S's (su27s_generate.py, measured from its drawing), so this script uses
the Su-27S's measurements and builders, switching that module's settings for what the Su-35S changes:

  * the longer, thicker tail sting (for the rear-facing radar)
  * the retractable refuelling probe on the left of the windscreen
  * two more wing pylons (12 hardpoints)
  * the glass cockpit: the head-up display over two large colour displays, with standby instruments

Run headless:
  blender -b --python tools/blender/su35s_generate.py -- --out <dir> --manifest-luau tools/Manifests/Su35S.luau
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import su27s_generate as su27  # noqa: E402  (its measurements and builders; its settings are switched below)

kit = su27.kit
Y, Z, W = kit.Y, kit.Z, su27.W
kit.AIRFRAME = "Su35S"

# The longer, thicker tail sting
_BODY = [row for row in su27._BODY if row[0] < 1600] + [
    (1600, 44, 392, 310, 310, 0.0, 2.4),
    (1700, 42, 390, 314, 314, 0.0, 2.3),
    (1800, 34, 384, 324, 324, 0.0, 2.2),
    (1900, 20, 374, 342, 342, 0.0, 2.0),
    (1960, 1, 360, 356, 356, 0.0, 2.0),
]
kit.FUSELAGE = [(xd, W(hw), Z(zb), Z(zs), Z(zt), sp, e) for xd, hw, zb, zs, zt, sp, e in _BODY]

kit.ATTACHMENTS = dict(kit.ATTACHMENTS)
kit.ATTACHMENTS.update({
    "Hardpoint11": (-3.90, Y(1200), su27.WING_Z - 0.30),
    "Hardpoint12": (3.90, Y(1200), su27.WING_Z - 0.30),
})

kit.COCKPIT = dict(kit.COCKPIT)
kit.COCKPIT["palette"] = "Modern"
kit.COCKPIT["instruments"] = [
    {"name": "RadarScope", "kind": "MFD", "u": -0.165, "v": 0.14, "size": 0.16, "live": "Radar"},
    {"name": "RightMFD", "kind": "MFD", "u": 0.165, "v": 0.14, "size": 0.16},
    {"name": "Airspeed", "kind": "Dial", "u": -0.24, "v": 0.285, "size": 0.045, "live": "Speed"},
    {"name": "Altimeter", "kind": "Dial", "u": -0.16, "v": 0.285, "size": 0.045, "live": "Altitude"},
    {"name": "GMeter", "kind": "Dial", "u": -0.08, "v": 0.285, "size": 0.04, "live": "G"},
    {"name": "ADI", "kind": "Dial", "u": 0.0, "v": 0.29, "size": 0.06, "face": "attitude"},
    {"name": "RPM", "kind": "Dial", "u": 0.08, "v": 0.285, "size": 0.04, "live": "RPM"},
    {"name": "RPM2", "kind": "Dial", "u": 0.16, "v": 0.285, "size": 0.04},
    {"name": "Fuel", "kind": "Dial", "u": 0.24, "v": 0.285, "size": 0.04},
]

_build_pitot = su27.build_pitot


def build_pitot(col):
    """The nose probe, and the refuelling probe on the left of the windscreen."""
    _build_pitot(col)
    x = -0.38
    z = kit.fuselage_surface_z(420, abs(x)) + 0.06
    parts = [
        kit.cylinder((x, Y(540), z - 0.02), (x, Y(330), z), 0.055, 10, radius1=0.05),
        kit.cylinder((x, Y(330), z), (x, Y(305), z), 0.05, 10, radius1=0.08),
    ]
    v, f = kit.merge(*parts)
    kit.make_object("RefuellingProbe", v, f, col, "Details")


su27.build_pitot = build_pitot

if __name__ == "__main__":
    su27.main()
