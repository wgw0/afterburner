"""
Afterburner: MiG-29SMT base mesh generator (Blender 4.x / 5.x). Art only: the MiG-29SMT has no flight data
yet (AircraftData), so this makes the model, skins and cockpit for when it does.

The MiG-29SMT's airframe is the MiG-29A's (mig29_generate.py, measured from its drawing), so this script
uses the MiG-29A's measurements and builders, switching that module's settings for what the SMT changes:

  * the enlarged dorsal hump (more fuel), higher and wider from the canopy to between the fins
  * the retractable refuelling probe on the left of the nose, ahead of the windscreen
  * the cockpit: the head-up display over two colour displays, with standby instruments, in grey

Run headless:
  blender -b --python tools/blender/mig29smt_generate.py -- --out <dir> --manifest-luau tools/Manifests/MiG29SMT.luau
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mig29_generate as m29  # noqa: E402  (its measurements and builders; its settings are switched below)

kit = m29.kit
Y, Z = kit.Y, kit.Z
kit.AIRFRAME = "MiG29SMT"

# The hump: from behind the canopy, the spine is raised and widened back to between the fins
HUMP = {1300: (1.66, 0.46), 1600: (1.52, 0.48), 1800: (1.34, 0.44), 2000: (1.12, 0.36), 2300: (0.86, 0.22)}
kit.FUSELAGE = [
    (xd, hw, zb, zs, max(zt, HUMP[xd][0]), max(sp, HUMP[xd][1]), e) if xd in HUMP else (xd, hw, zb, zs, zt, sp, e)
    for xd, hw, zb, zs, zt, sp, e in kit.FUSELAGE
]

kit.COCKPIT = dict(kit.COCKPIT)
kit.COCKPIT["palette"] = "Modern"
kit.COCKPIT["instruments"] = [
    {"name": "RadarScope", "kind": "MFD", "u": -0.155, "v": 0.13, "size": 0.14, "live": "Radar"},
    {"name": "RightMFD", "kind": "MFD", "u": 0.155, "v": 0.13, "size": 0.14},
    {"name": "Airspeed", "kind": "Dial", "u": -0.24, "v": 0.27, "size": 0.05, "live": "Speed"},
    {"name": "Altimeter", "kind": "Dial", "u": -0.16, "v": 0.27, "size": 0.05, "live": "Altitude"},
    {"name": "GMeter", "kind": "Dial", "u": -0.08, "v": 0.27, "size": 0.045, "live": "G"},
    {"name": "ADI", "kind": "Dial", "u": 0.0, "v": 0.28, "size": 0.07, "face": "attitude"},
    {"name": "RPM", "kind": "Dial", "u": 0.08, "v": 0.27, "size": 0.045, "live": "RPM"},
    {"name": "RPM2", "kind": "Dial", "u": 0.16, "v": 0.27, "size": 0.045},
    {"name": "Fuel", "kind": "Dial", "u": 0.24, "v": 0.27, "size": 0.045},
]

_build_pitot = m29.build_pitot


def build_pitot(col):
    """The nose probe, and the refuelling probe on the left of the nose."""
    _build_pitot(col)
    x = -0.30
    z = kit.fuselage_surface_z(560, abs(x)) + 0.05
    parts = [
        kit.cylinder((x, Y(700), z - 0.02), (x, Y(420), z), 0.05, 10, radius1=0.045),
        kit.cylinder((x, Y(420), z), (x, Y(395), z), 0.045, 10, radius1=0.07),
    ]
    v, f = kit.merge(*parts)
    kit.make_object("RefuellingProbe", v, f, col, "Details")


m29.build_pitot = build_pitot

if __name__ == "__main__":
    m29.main()
