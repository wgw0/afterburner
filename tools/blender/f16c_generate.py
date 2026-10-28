"""
Afterburner: F-16C Block 50 base mesh generator (Blender 4.x / 5.x). Art only: the F-16C has no flight data
yet (AircraftData), so this makes the model, skins and cockpit for when it does.

The F-16C's airframe is the F-16A's (f16a_generate.py, measured from its drawing), so this script uses the
F-16A's measurements and builders, switching that module's settings for what the Block 50 changes:

  * the larger "big mouth" intake for the F110 engine
  * the four IFF blade antennas on the nose ahead of the windscreen
  * the cockpit: the wide HUD over the up-front controls, two multifunction displays either side below
    them, and the standby instruments, with the side stick

Run headless:
  blender -b --python tools/blender/f16c_generate.py -- --out <dir> --manifest-luau tools/Manifests/F16C.luau
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import f16a_generate as f16  # noqa: E402  (its measurements and builders; its settings are switched below)

kit = f16.kit
Y = kit.Y
kit.AIRFRAME = "F16C"

# The modular common inlet duct: wider and deeper at the lip than the F-16A's
f16.INTAKE = {"lip": 800, "hw": 0.53, "top": -0.32, "bottom": -0.96, "fade": 1100}

kit.COCKPIT = dict(kit.COCKPIT)
kit.COCKPIT["instruments"] = [
    {"name": "UFC", "kind": "Lights", "u": 0.0, "v": 0.085, "size": 0.12},
    {"name": "RadarScope", "kind": "MFD", "u": -0.215, "v": 0.20, "size": 0.12, "live": "Radar"},
    {"name": "RightMFD", "kind": "MFD", "u": 0.215, "v": 0.20, "size": 0.12},
    {"name": "RWR", "kind": "Scope", "u": -0.235, "v": 0.075, "size": 0.06},
    {"name": "Airspeed", "kind": "Dial", "u": -0.12, "v": 0.075, "size": 0.06, "live": "Speed"},
    {"name": "Altimeter", "kind": "Dial", "u": 0.12, "v": 0.075, "size": 0.06, "live": "Altitude"},
    {"name": "RPM", "kind": "Dial", "u": 0.235, "v": 0.075, "size": 0.055, "live": "RPM"},
    {"name": "ADI", "kind": "Dial", "u": 0.0, "v": 0.20, "size": 0.09, "face": "attitude"},
    {"name": "GMeter", "kind": "Dial", "u": -0.07, "v": 0.29, "size": 0.045, "live": "G"},
    {"name": "HSI", "kind": "Dial", "u": 0.04, "v": 0.295, "size": 0.06, "face": "compass"},
]

_build_pitot = f16.build_pitot


def build_pitot(col):
    """The pitot, and the four IFF blade antennas ("bird slicers") across the top of the nose."""
    _build_pitot(col)
    parts = []
    xd = 430
    for x in (-0.22, -0.09, 0.09, 0.22):
        z = kit.fuselage_surface_z(xd, abs(x))
        parts.append(kit.box((x, Y(xd), z + 0.07), (0.02, 0.10, 0.16)))
    v, f = kit.merge(*parts)
    kit.make_object("Antennas", v, f, col, "Details")


f16.build_pitot = build_pitot

if __name__ == "__main__":
    f16.main()
