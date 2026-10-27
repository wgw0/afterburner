"""
Afterburner: Mirage 2000C base mesh generator (Blender 4.x / 5.x). Art only: the Mirage 2000C has no flight
data yet (AircraftData).

The Mirage 2000 is laid out like the Mirage III (half-round intakes with half-cone centre bodies, a
tailless delta with two elevons a side, a single fin), so this script uses the Mirage IIIE's builders
(mirage3_generate.py) with its own measurements, switching that module's settings the way the jets switch
the F-5E kit's. The fin, pitot and the parts that differ are built here. A cockpit well is opened for the
cockpit interior.

Run headless:
  blender -b --python tools/blender/mirage2000_generate.py -- --out <dir> --manifest-luau tools/Manifests/Mirage2000C.luau

Reference: the Commons three-view "Dassault Mirage 2000C 3-view line drawing.gif" (retraced by
Henrickson, CC BY-SA 3.0), 1000 px wide. Its top view has the nose right (tip at x = 640, centreline row
390.5); its side view has the nose left (tip at x = 362) and the canopy drawn open, so the canopy is taken
from its closed outline. Stations (xd) are pixels aft of each view's nose tip; heights are side-view rows
(row 566, the nozzle's axis, is z = 0). The scale comes from the published 14.36 m length (42.0 px/m),
which gives a 9.29 m span against the published 9.13 m. The drawing is small, so shapes are good to
about 3 cm. See docs/art/reference/Mirage2000C/SOURCES.md (kept out of git).
"""

import argparse
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mirage3_generate as m3  # noqa: E402  (its builders; its settings are switched below)

kit = m3.kit
kit.AIRFRAME = "Mirage2000C"
kit.REF_PX_PER_M = 42.0
kit.REF_PITOT_XD = 0.0
kit.REF_Z0_ROW = 566.0
kit.CG_FROM_PITOT = 336 / 42.0  # 25% of the 5.30 m mean aerodynamic chord
kit.LENGTH = 14.36
kit.SPINE_UPPER_ONLY = True
Y, Z = kit.Y, kit.Z
PX = kit.REF_PX_PER_M


def W(px):
    return px / PX


kit.FUSELAGE = [
    (0, 0.012, -0.53, -0.47, -0.47, 0.0, 2.0),  # radome tip
    (40, W(9), -0.67, -0.07, -0.07, 0.0, 2.0),
    (78, W(14), -0.76, 0.10, 0.10, 0.0, 2.1),  # radome joint
    (105, W(16), -0.76, 0.24, 0.24, 0.0, 2.3),  # windscreen base
    (150, W(17), -0.76, 0.31, 0.31, 0.0, 2.5),
    (195, W(18), -0.76, 0.31, 0.31, 0.0, 2.5),
    (215, 0.55, -0.76, 0.33, 0.79, 0.30, 2.5),  # the spine rises behind the canopy
    (260, 0.70, -0.74, 0.40, 0.66, 0.32, 2.5),
    (350, 0.74, -0.71, 0.45, 0.62, 0.30, 2.4),
    (450, 0.72, -0.69, 0.50, 0.62, 0.0, 2.3),
    (520, 0.66, -0.55, 0.67, 0.67, 0.0, 2.2),
    (575, 0.58, -0.48, 0.55, 0.55, 0.0, 2.1),
    (595, 0.52, -0.45, 0.45, 0.45, 0.0, 2.0),  # nozzle
]
kit.FUSELAGE_RINGS = 60
kit.FUSELAGE_SEGMENTS = 44

kit.INTAKES = [
    (198, 0.98, 0.24, -0.76),
    (230, 1.07, 0.24, -0.76),
    (270, 1.05, 0.20, -0.72),
    (330, 0.95, 0.12, -0.65),
    (380, 0.85, 0.05, -0.55),
]
kit.INTAKE_LIP_SWEEP = 0.05
m3.SOURIS = {"tip": 180, "base": 200, "radius": 0.20, "x": 0.68, "z": -0.25}

kit.CANOPY = [
    (105, 0.10, 0.26),
    (120, 0.25, 0.45),
    (140, 0.33, 0.62),
    (160, 0.38, 0.76),
    (180, 0.40, 0.83),
    (200, 0.38, 0.84),
    (215, 0.33, 0.80),
    (225, 0.26, 0.79),
]
kit.CANOPY_FRAMES = (145, 220)

# Delta wing: the leading edge passes half width 48 px at station 247 and sweeps 1.59 px back per px out
# (58 degrees); the trailing edge is square across at station 503, the elevon hinge at 478.
m3.WING_Z = Z(585)
m3.WING_ROOT_X, m3.WING_TIP_X = 0.55, W(192)
m3.WING_THICKNESS = 0.04
m3.ELEVON_HINGE_Y = Y(478)
m3.ELEVON_IN = (W(36), W(97))
m3.ELEVON_OUT = (W(99), W(182))


def wing_le_y(x):
    return Y(247 + (x * PX - 48) * 1.59)


def wing_te_y(x):
    return Y(503 + 0 * x)


m3.wing_le_y, m3.wing_te_y = wing_le_y, wing_te_y

FIN_ROOT_Z, FIN_TIP_Z = 0.62, Z(437)
FIN_ROOT_LE, FIN_ROOT_TE = Y(402), Y(577)
FIN_TIP_LE, FIN_TIP_TE = Y(557), Y(589)
FIN_THICKNESS = 0.045
RUDDER_HINGE = 0.73
RUDDER_SPAN = (Z(527), Z(468))

m3.NOZZLE_Z, m3.NOZZLE_R = Z(566), 0.45
m3.NOZZLE_Y0, m3.NOZZLE_Y1 = Y(588), Y(603)

GROUND_Z = FIN_TIP_Z - 5.20  # published height
m3.NOSE_WHEEL = {"at": (0, Y(160), GROUND_Z + 0.24), "radius": 0.24, "width": 0.14}
m3.MAIN_WHEEL = {"at": (1.70, Y(380), GROUND_Z + 0.33), "radius": 0.33, "width": 0.18}

kit.HULL = {"size": [1.7, 1.5, 14.2], "at": [0, -0.1, -0.8]}
kit.HITBOXES = {
    "Cockpit": {"size": [0.9, 1.0, 2.2], "at": [0, 0.4, -3.8]},
    "Fuselage": {"size": [2.1, 1.4, 5.5], "at": [0, -0.1, -1.4]},
    "Engine": {"size": [1.5, 1.3, 4.5], "at": [0, -0.05, 3.8]},
    "WingL": {"size": [3.6, 0.4, 5.0], "at": [-2.4, round(m3.WING_Z, 2), 2.5]},
    "WingR": {"size": [3.6, 0.4, 5.0], "at": [2.4, round(m3.WING_Z, 2), 2.5]},
    "Tail": {"size": [0.6, 2.6, 4.0], "at": [0, 1.9, 5.3]},
}
m3.EYE = (0, Y(180), 0.62)
kit.ATTACHMENTS = {
    "CockpitEye": m3.EYE,
    "GunMuzzle": (0, Y(215), -0.65),  # the two DEFA 554s under the intakes
    "Nozzle1": (0, m3.NOZZLE_Y1, m3.NOZZLE_Z),
    "WingtipL": (-(m3.WING_TIP_X + 0.02), Y(495), m3.WING_Z),
    "WingtipR": (m3.WING_TIP_X + 0.02, Y(495), m3.WING_Z),
    "FlareDispenser": (0, Y(560), -0.50),
    "ChaffDispenser": (0, Y(550), -0.55),
    "ChaseCam": (0, -20.0, 3.6),
    "Hardpoint1": (-3.0, Y(440), m3.WING_Z - 0.15),  # outboard wing pylons (Magic)
    "Hardpoint2": (3.0, Y(440), m3.WING_Z - 0.15),
    "Hardpoint3": (-1.8, Y(400), m3.WING_Z - 0.15),  # inboard wing pylons (Super 530)
    "Hardpoint4": (1.8, Y(400), m3.WING_Z - 0.15),
    "Hardpoint5": (-0.45, Y(330), -0.78),  # fuselage stations
    "Hardpoint6": (0.45, Y(330), -0.78),
    "Hardpoint7": (0, Y(380), -0.78),
}

# Cockpit interior (cockpit_kit.py, art pipeline §7), after Mirage 2000C cockpit photos: the head-up
# display on the glareshield, the radar display under it, flight instruments either side, the engine
# instruments right. Dark grey and black.
kit.COCKPIT = {
    "well": {"back": Y(193), "front": Y(138), "half_width": 0.30, "floor": -0.30, "flange": 0.06},
    "panel": {"distance": 0.65, "top": -0.16, "bottom": -0.60, "tilt": 10, "half_width": 0.30},
    "coaming": {"overhang": 0.04, "length": 0.30, "drop": 0.06},
    "consoles": {"top": -0.52, "width": 0.09, "aft": -0.35, "fore": 0.42, "throttle": 0.02},
    "stick": "centre",
    "stick_fore": 0.38,
    "sight": "HUD",
    "palette": "French",
    "instruments": [
        {"name": "RadarScope", "kind": "MFD", "u": 0.0, "v": 0.09, "size": 0.10, "live": "Radar"},
        {"name": "GMeter", "kind": "Dial", "u": -0.21, "v": 0.075, "size": 0.05, "live": "G"},
        {"name": "Airspeed", "kind": "Dial", "u": -0.125, "v": 0.08, "size": 0.07, "live": "Speed"},
        {"name": "Altimeter", "kind": "Dial", "u": 0.125, "v": 0.08, "size": 0.07, "live": "Altitude"},
        {"name": "RPM", "kind": "Dial", "u": 0.21, "v": 0.075, "size": 0.05, "live": "RPM"},
        {"name": "AOA", "kind": "Dial", "u": -0.21, "v": 0.16, "size": 0.05},
        {"name": "VVI", "kind": "Dial", "u": -0.125, "v": 0.175, "size": 0.06},
        {"name": "ADI", "kind": "Dial", "u": 0.0, "v": 0.20, "size": 0.09, "face": "attitude"},
        {"name": "EGT", "kind": "Dial", "u": 0.125, "v": 0.175, "size": 0.06},
        {"name": "Fuel", "kind": "Dial", "u": 0.21, "v": 0.16, "size": 0.05},
        {"name": "HSI", "kind": "Dial", "u": 0.0, "v": 0.30, "size": 0.085, "face": "compass"},
        {"name": "Caution", "kind": "Lights", "u": 0.16, "v": 0.28, "size": 0.09},
    ],
}


def build_tail(col):
    side_n = (1, 0, 0)
    g = ((0, FIN_ROOT_LE, FIN_ROOT_Z), (0, FIN_ROOT_TE, FIN_ROOT_Z), (0, FIN_TIP_LE, FIN_TIP_Z),
         (0, FIN_TIP_TE, FIN_TIP_Z), side_n, FIN_THICKNESS)
    h = FIN_TIP_Z - FIN_ROOT_Z

    def frac(z):
        return (z - FIN_ROOT_Z) / h

    fin = [
        kit.panel(*g, 0.0, RUDDER_HINGE, 0, 1, 8, 10),
        kit.panel(*g, RUDDER_HINGE, 1.0, 0, frac(RUDDER_SPAN[0]), 1, 4),
        kit.panel(*g, RUDDER_HINGE, 1.0, frac(RUDDER_SPAN[1]), 1, 2, 4),
    ]
    # The curved dorsal fillet running into the fin's leading edge
    outline = [(Y(300), 0.60), (Y(370), 0.64), (Y(410), 0.82), (Y(410), FIN_ROOT_Z)]
    half = [0.04, 0.035, 0.025, 0.04]
    n = len(outline)
    fv = [(-t, y, z) for (y, z), t in zip(outline, half)] + [(t, y, z) for (y, z), t in zip(outline, half)]
    ff = [tuple(range(n)), tuple(reversed(range(n, 2 * n)))] + [(i, n + i, n + (i + 1) % n, (i + 1) % n) for i in range(n)]
    fin.append((fv, ff))
    v, f = kit.merge(*fin)
    kit.make_object("Fin", v, f, col, "Body")
    v, f = kit.panel(*g, RUDDER_HINGE, 1.0, frac(RUDDER_SPAN[0]), frac(RUDDER_SPAN[1]), 6, 6)
    a, b = kit.hinge_line(*g[:4], RUDDER_HINGE, frac(RUDDER_SPAN[0]), frac(RUDDER_SPAN[1]))
    kit.make_object("Rudder", v, f, col, "Body", "ControlSurface", origin=tuple(a.lerp(b, 0.5)),
                    hinge={"axis": tuple(b - a), "min": -25, "max": 25, "control": "Rudder"})


def build_pitot(col):
    v, f = kit.cylinder((0, Y(-22), Z(587)), (0, Y(1), Z(587)), 0.02, 8)
    kit.make_object("Pitot", v, f, col, "Details")


def main():
    import bpy

    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", default=os.path.join(os.path.dirname(__file__), "out"))
    parser.add_argument("--manifest-luau", default=None)
    args = parser.parse_args(argv)
    os.makedirs(args.out, exist_ok=True)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0

    a = kit.AIRFRAME
    root = kit.collection(a)
    cols = {name: kit.collection(f"{a}_{name}", root) for name in ("Body", "Wings", "Details", "Glass", "Gear", "Attachments")}

    kit.build_fuselage(cols["Body"])
    kit.build_intakes(cols["Body"])
    m3.build_souris(cols["Body"])
    kit.build_canopy(cols["Glass"], cols["Body"])
    m3.build_wings(cols["Wings"])
    build_tail(cols["Body"])
    m3.build_engine(cols["Details"])
    m3.build_seat(cols["Details"])
    build_pitot(cols["Details"])
    m3.build_gear(cols["Gear"])
    kit.add_attachment_empties(cols["Attachments"])

    kit.smooth_all()
    kit.unwrap_sets()
    import cockpit_kit  # after the UVs: the well moves vertices, not UVs

    cockpit_kit.open_well()
    counts = kit.triangle_counts()
    manifest = kit.write_manifest(os.path.join(args.out, f"{a}_manifest.json"), args.manifest_luau, counts)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(args.out, f"{a}_base.blend"))
    kit.export(args.out)

    print("=" * 60)
    print(f"{a}: {len(kit.PARTS)} parts, {manifest['triangles']} triangles")
    for name, tris in sorted(counts.items(), key=lambda kv: -kv[1]):
        print(f"  {name:22s} {tris:6d}")
    print("=" * 60)


if __name__ == "__main__":
    main()
