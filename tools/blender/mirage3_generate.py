"""
Afterburner: Mirage IIIE base mesh generator (Blender 4.x / 5.x).

Builds a mid-poly, modular Mirage IIIE at real-world size, measured from a reference drawing, in the same
form as the F-5E (see f5e_generate.py, whose helpers this script uses): separate objects per part, moving
parts with their origin on the hinge line, four texture sets, a manifest for the Studio assembler, an FBX
for the 3D importer, and the cockpit well for the cockpit interior (cockpit_kit.py).

  * the fuselage: pointed radome, the cockpit section, the dorsal spine behind the canopy, the area of
    the half-round side intakes faired into it, the tall tail end over the nozzle
  * half-round intakes with their half-cone centre bodies (the "souris"), canopy and frame
  * the tailless 60-odd degree delta with two elevons a side (pitch and roll mixed)
  * the fin with its dorsal fillet and rudder, the brake-chute fairing over the nozzle
  * single nozzle with afterburner cone, ejection seat, pitot, landing gear (struts, wheels, doors)

Run headless:
  blender -b --python tools/blender/mirage3_generate.py -- --out <dir> --manifest-luau tools/Manifests/MirageIII.luau

Reference: the Wikimedia Commons line drawing "Dassault Mirage III line drawing.svg" (Lirdon, CC BY-SA
4.0), rendered 3840 px wide. Its side view is drawn nose-right; stations are measured as xd, pixels aft of
the pitot tip, and rows are the drawing's pixel rows. Its top view is drawn at 45°; turned upright (30°
in the rendered copy) it gives the half widths at the same stations. The drawing's three views share one
scale, set from the published 8.22 m span (177.1 px/m). Its length then matches the published 15.03 m
excluding the probe to within 1%. See docs/art/reference/MirageIII/SOURCES.md (kept out of git).
"""

import argparse
import math
import os
import sys

from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import f5e_generate as kit  # noqa: E402  (shared helpers; its module settings are switched below)

kit.AIRFRAME = "MirageIII"
kit.REF_PX_PER_M = 177.1
kit.REF_PITOT_XD = 0.0
kit.REF_Z0_ROW = 680.0
# 25% of the mean aerodynamic chord: the delta's MAC is 5.94 m, its leading edge at station 1356
kit.CG_FROM_PITOT = 1619 / 177.1
kit.LENGTH = round(2860 / 177.1, 2)  # pitot tip to nozzle exit
Y, Z = kit.Y, kit.Z

# Fuselage stations: (xd, half width, bottom z, shoulder z, top z, spine half width, exponent).
# The body under the cockpit is narrow; behind the canopy the spine runs level at the canopy's height,
# and the body widens over the intake ducts to swallow them at the wing.
kit.FUSELAGE = [
    (185, 0.012, -0.47, -0.41, -0.41, 0.0, 2.0),  # radome tip
    (250, 0.144, -0.536, -0.237, -0.237, 0.0, 2.0),
    (300, 0.203, -0.582, -0.141, -0.141, 0.0, 2.0),
    (400, 0.316, -0.666, 0.034, 0.034, 0.0, 2.0),  # radome joint
    (500, 0.409, -0.695, 0.175, 0.175, 0.0, 2.1),
    (560, 0.42, -0.711, 0.20, 0.20, 0.0, 2.3),  # windscreen base
    (700, 0.44, -0.711, 0.226, 0.226, 0.0, 2.5),
    (850, 0.46, -0.711, 0.27, 0.27, 0.0, 2.6),  # intake lips
    (950, 0.48, -0.711, 0.31, 0.80, 0.30, 2.6),  # spine rises inside the canopy's rear
    (1000, 0.50, -0.711, 0.33, 0.875, 0.33, 2.5),
    (1200, 0.62, -0.711, 0.45, 0.88, 0.36, 2.4),
    (1400, 0.74, -0.711, 0.60, 0.90, 0.40, 2.4),
    (1600, 0.84, -0.705, 0.78, 0.92, 0.42, 2.3),
    (1800, 0.86, -0.71, 0.93, 0.93, 0.0, 2.2),  # intakes merged; fin fillet starts
    (2000, 0.78, -0.72, 0.95, 0.95, 0.0, 2.2),
    (2250, 0.70, -0.78, 0.97, 0.97, 0.0, 2.1),  # ventral fairing
    (2480, 0.63, -0.82, 0.99, 0.99, 0.0, 2.0),
    (2560, 0.60, -0.70, 0.95, 0.95, 0.0, 2.0),
    (2620, 0.56, -0.47, 0.88, 0.88, 0.0, 2.0),  # tail end over the nozzle
    (2680, 0.50, -0.36, 0.70, 0.70, 0.0, 2.0),
]
kit.FUSELAGE_RINGS = 64
kit.FUSELAGE_SEGMENTS = 44
kit.SPINE_UPPER_ONLY = True

# Half-round intakes: (xd, outer half width, top z, bottom z); the lip is almost unswept
kit.INTAKES = [
    (868, 0.85, 0.34, -0.51),
    (950, 0.90, 0.36, -0.53),
    (1100, 0.92, 0.40, -0.55),
    (1300, 0.92, 0.45, -0.52),
    (1500, 0.90, 0.52, -0.45),
    (1650, 0.87, 0.60, -0.35),
]
kit.INTAKE_LIP_SWEEP = 0.05
SOURIS = {"tip": 815, "base": 905, "radius": 0.21, "x": 0.64, "z": -0.09}  # half-cone centre bodies

# Canopy: (xd, half width at the sill, top z). It ends level with the spine.
kit.CANOPY = [
    (530, 0.10, 0.20),
    (580, 0.28, 0.42),
    (640, 0.33, 0.62),
    (700, 0.37, 0.74),
    (760, 0.39, 0.84),
    (820, 0.40, 0.875),
    (900, 0.39, 0.88),
    (960, 0.36, 0.88),
    (1000, 0.32, 0.88),
]
kit.CANOPY_FRAMES = (705, 950)

# Delta wing, measured on the upright top view: the leading edge passes half width 202 px at station 1248
# and sweeps back 0.507 px across per px aft; the trailing edge runs from station 2416 at the root to
# 2370 at the tip. The elevons hinge on a line square across the jet at station 2250.
WING_Z = Z(700)
WING_ROOT_X, WING_TIP_X = 0.55, 4.06
WING_THICKNESS = 0.04
ELEVON_HINGE_Y = Y(2250)
ELEVON_IN = (0.95, 2.45)
ELEVON_OUT = (2.50, 3.75)


def wing_le_y(x):
    return Y(1248 + (x * kit.REF_PX_PER_M - 202) / 0.507)


def wing_te_y(x):
    return Y(2416 + (x - 0.86) * (2370 - 2416) / (4.09 - 0.86))


# Fin (root embedded in the spine) and rudder, from the side view
FIN_ROOT_Z, FIN_TIP_Z = 0.97, Z(130)
FIN_ROOT_LE, FIN_ROOT_TE = Y(1940), Y(2620)
FIN_TIP_LE, FIN_TIP_TE = Y(2670), Y(2843)
FIN_THICKNESS = 0.045
RUDDER_HINGE = 0.78
RUDDER_SPAN = (1.05, 2.55)

NOZZLE_Z, NOZZLE_R = Z(660), 0.42
NOZZLE_Y0, NOZZLE_Y1 = Y(2650), Y(2860)
CHUTE = {"from": 2590, "to": 2880, "z": Z(522), "radius": 0.15}

# Gear (modelled down, hidden in flight): from photos, scaled to the published 4.50 m height
GROUND_Z = FIN_TIP_Z - 4.50
NOSE_WHEEL = {"at": (0, Y(760), GROUND_Z + 0.22), "radius": 0.22, "width": 0.14}
MAIN_WHEEL = {"at": (1.58, Y(1950), GROUND_Z + 0.33), "radius": 0.33, "width": 0.18}

kit.HULL = {"size": [1.7, 1.6, 15.0], "at": [0, 0.05, -0.5]}
kit.HITBOXES = {
    "Cockpit": {"size": [0.9, 1.0, 2.4], "at": [0, 0.5, -4.1]},
    "Fuselage": {"size": [1.7, 1.4, 6.0], "at": [0, 0, -2.0]},
    "Engine": {"size": [1.4, 1.4, 4.6], "at": [0, 0.1, 4.0]},
    "WingL": {"size": [3.2, 0.4, 5.0], "at": [-2.4, round(WING_Z, 2), 2.0]},
    "WingR": {"size": [3.2, 0.4, 5.0], "at": [2.4, round(WING_Z, 2), 2.0]},
    "Tail": {"size": [0.6, 2.4, 3.6], "at": [0, 2.0, 5.1]},
}
EYE = (0, Y(860), 0.70)
kit.ATTACHMENTS = {
    "CockpitEye": EYE,
    "GunMuzzle": (0, Y(1000), -0.60),  # the twin DEFA 552s under the intakes
    "Nozzle1": (0, NOZZLE_Y1, NOZZLE_Z),
    "WingtipL": (-(WING_TIP_X + 0.02), Y(2330), WING_Z),
    "WingtipR": (WING_TIP_X + 0.02, Y(2330), WING_Z),
    "FlareDispenser": (0, Y(2500), -0.80),
    "ChaffDispenser": (0, Y(2440), -0.84),
    "ChaseCam": (0, -20.5, 3.5),
    "Hardpoint1": (-2.8, Y(2100), WING_Z - 0.15),
    "Hardpoint2": (2.8, Y(2100), WING_Z - 0.15),
    "Hardpoint3": (-1.6, Y(1950), WING_Z - 0.15),
    "Hardpoint4": (1.6, Y(1950), WING_Z - 0.15),
    "Hardpoint5": (0, Y(1700), -0.80),
}

# Cockpit interior (cockpit_kit.py, art pipeline §7), after Mirage IIIE cockpit photos: the CSF 97 sight
# on the glareshield, the Cyrano II radar scope under it, flight instruments to its left, engine
# instruments to its right, the attitude indicator and the compass below. Dark grey and black.
kit.COCKPIT = {
    "well": {"back": 3.86, "front": 5.06, "half_width": 0.34, "floor": -0.32, "flange": 0.07},
    "panel": {"distance": 0.68, "top": -0.17, "bottom": -0.62, "tilt": 10, "half_width": 0.32},
    "coaming": {"overhang": 0.04, "length": 0.35, "drop": 0.06},
    "consoles": {"top": -0.55, "width": 0.10, "aft": -0.35, "fore": 0.45, "throttle": 0.02},
    "stick": "centre",
    "stick_fore": 0.40,
    "sight": "Gunsight",
    "sight_body": (0.13, 0.15, 0.08),
    "sight_glass": (0.13, 0.11),
    "palette": "French",
    "instruments": [
        {"name": "RadarScope", "kind": "Scope", "u": 0.0, "v": 0.08, "size": 0.10, "hood": 0.04, "live": "Radar"},
        {"name": "GMeter", "kind": "Dial", "u": -0.225, "v": 0.075, "size": 0.06, "live": "G"},
        {"name": "Airspeed", "kind": "Dial", "u": -0.13, "v": 0.08, "size": 0.085, "live": "Speed"},
        {"name": "RPM", "kind": "Dial", "u": 0.13, "v": 0.08, "size": 0.085, "live": "RPM"},
        {"name": "EGT", "kind": "Dial", "u": 0.225, "v": 0.075, "size": 0.06},
        {"name": "AOA", "kind": "Dial", "u": -0.225, "v": 0.165, "size": 0.055},
        {"name": "Altimeter", "kind": "Dial", "u": -0.13, "v": 0.18, "size": 0.085, "live": "Altitude"},
        {"name": "ADI", "kind": "Dial", "u": 0.0, "v": 0.20, "size": 0.10, "face": "attitude"},
        {"name": "VVI", "kind": "Dial", "u": 0.13, "v": 0.18, "size": 0.075},
        {"name": "Fuel", "kind": "Dial", "u": 0.225, "v": 0.165, "size": 0.055},
        {"name": "Clock", "kind": "Dial", "u": -0.17, "v": 0.29, "size": 0.055},
        {"name": "HSI", "kind": "Dial", "u": 0.0, "v": 0.31, "size": 0.095, "face": "compass"},
        {"name": "Caution", "kind": "Lights", "u": 0.17, "v": 0.29, "size": 0.11},
    ],
}


# ---------------------------------------------------------------------------------------------------
# Builders
# ---------------------------------------------------------------------------------------------------


def build_souris(col):
    """The intakes' half-cone centre bodies: cones on the fuselage side, half buried in it."""
    parts = []
    for side in (1, -1):
        x = side * SOURIS["x"]
        tip = (x, Y(SOURIS["tip"]), SOURIS["z"])
        base = (x, Y(SOURIS["base"]), SOURIS["z"])
        parts.append(kit.cylinder(tip, base, 0.004, 20, radius1=SOURIS["radius"], caps=True))
        parts.append(kit.cylinder(base, (x, Y(SOURIS["base"] + 60), SOURIS["z"]), SOURIS["radius"], 20, caps=True))
    v, f = kit.merge(*parts)
    kit.make_object("InletCones", v, f, col, "Body")


def build_wings(col):
    root_le = (WING_ROOT_X, wing_le_y(WING_ROOT_X), WING_Z)
    root_te = (WING_ROOT_X, wing_te_y(WING_ROOT_X), WING_Z)
    tip_le = (WING_TIP_X, wing_le_y(WING_TIP_X), WING_Z)
    tip_te = (WING_TIP_X, wing_te_y(WING_TIP_X), WING_Z)
    span = WING_TIP_X - WING_ROOT_X
    up = (0, 0, 1)

    def s_of(x):
        return (x - WING_ROOT_X) / span

    def hinge_f(s):
        x = kit.lerp(WING_ROOT_X, WING_TIP_X, s)
        return (wing_le_y(x) - ELEVON_HINGE_Y) / (wing_le_y(x) - wing_te_y(x))

    def zero(_s):
        return 0.0

    def one(_s):
        return 1.0

    def hinge_point(s):
        x = kit.lerp(WING_ROOT_X, WING_TIP_X, s)
        return Vector((x, ELEVON_HINGE_Y, WING_Z))

    geo = (root_le, root_te, tip_le, tip_te, up, WING_THICKNESS)
    for side, name in ((1, "R"), (-1, "L")):
        def m(v):
            return v if side > 0 else kit.mirror_x(v)

        def mf(f):
            return f if side > 0 else kit.flip_faces(f)

        box = [
            kit.panel_var(*geo, zero, hinge_f, 0, s_of(ELEVON_OUT[1]), 12, 12),  # ahead of the hinge
            kit.panel_var(*geo, zero, one, s_of(ELEVON_OUT[1]), 1, 2, 12),  # tip, full chord
            kit.panel_var(*geo, hinge_f, one, 0, s_of(ELEVON_IN[0]), 1, 4),  # root strip
            kit.panel_var(*geo, hinge_f, one, s_of(ELEVON_IN[1]), s_of(ELEVON_OUT[0]), 1, 4),
        ]
        v, f = kit.merge(*box)
        kit.make_object(f"Wing{name}", m(v), mf(f), col, "Wings")
        for part, (x0, x1) in (("ElevonIn", ELEVON_IN), ("ElevonOut", ELEVON_OUT)):
            s0, s1 = s_of(x0), s_of(x1)
            v, f = kit.panel_var(*geo, hinge_f, one, s0, s1, 4, 6)
            a, b = hinge_point(s0), hinge_point(s1)
            kit.make_object(f"{part}{name}", m(v), mf(f), col, "Wings", "ControlSurface",
                            origin=tuple(m([tuple(a.lerp(b, 0.5))])[0]),
                            hinge={"axis": tuple(m([tuple(b - a)])[0]), "min": -20, "max": 20, "control": "Elevon" + name})


def build_tail(col):
    side_n = (1, 0, 0)
    root_le, root_te = (0, FIN_ROOT_LE, FIN_ROOT_Z), (0, FIN_ROOT_TE, FIN_ROOT_Z)
    tip_le, tip_te = (0, FIN_TIP_LE, FIN_TIP_Z), (0, FIN_TIP_TE, FIN_TIP_Z)
    h = FIN_TIP_Z - FIN_ROOT_Z

    def frac(z):
        return (z - FIN_ROOT_Z) / h

    g = (root_le, root_te, tip_le, tip_te, side_n, FIN_THICKNESS)
    fin = [
        kit.panel(*g, 0.0, RUDDER_HINGE, 0, 1, 8, 10),
        kit.panel(*g, RUDDER_HINGE, 1.0, 0, frac(RUDDER_SPAN[0]), 1, 4),
        kit.panel(*g, RUDDER_HINGE, 1.0, frac(RUDDER_SPAN[1]), 1, 2, 4),
    ]
    # Dorsal fillet: a low wedge along the spine from station 1800 into the fin's leading edge
    le_at = Y(2065)
    outline = [(Y(1800), 0.93), (kit.lerp(Y(1800), le_at, 0.5), 1.02), (le_at, Z(445)), (FIN_ROOT_LE - 0.4, FIN_ROOT_Z)]
    half = [0.04, 0.035, 0.025, 0.045]
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
    # Brake-chute fairing over the nozzle
    c = CHUTE
    body = kit.cylinder((0, Y(c["from"]), c["z"]), (0, Y(c["to"] - 40), c["z"]), c["radius"] * 0.8, 16,
                        radius1=c["radius"], caps=True)
    cap = kit.cylinder((0, Y(c["to"] - 40), c["z"]), (0, Y(c["to"]), c["z"] - 0.02), c["radius"], 16,
                       radius1=0.05, caps=True)
    v, f = kit.merge(body, cap)
    kit.make_object("ChuteFairing", v, f, col, "Body")


def build_engine(col):
    p0, p1 = (0, NOZZLE_Y0, NOZZLE_Z), (0, NOZZLE_Y1, NOZZLE_Z)
    nv, nf = kit.cylinder(p0, p1, NOZZLE_R + 0.05, 24, radius1=NOZZLE_R, caps=False)
    iv, i_f = kit.cylinder(p0, p1, NOZZLE_R - 0.02, 24, radius1=NOZZLE_R - 0.035, caps=False)
    n = 24
    lip = [(n + i, n + (i + 1) % n, len(nv) + n + (i + 1) % n, len(nv) + n + i) for i in range(n)]
    verts, faces = kit.merge((nv, nf), (iv, kit.flip_faces(i_f)))
    kit.make_object("Nozzle", verts, faces + lip, col, "Details", "Nozzle", extra={"engine": "C"})
    cv, cf = kit.cylinder((0, NOZZLE_Y1 + 0.15, NOZZLE_Z), (0, NOZZLE_Y0 + 0.05, NOZZLE_Z), NOZZLE_R - 0.06, 18,
                          radius1=0.06, caps=True)
    kit.make_object("Afterburner", cv, cf, col, "Details", "Afterburner", extra={"engine": "C"})


def build_seat(col):
    _, ey, ez = EYE
    parts = [
        kit.box((0, ey - 0.05, ez - 0.70), (0.46, 0.48, 0.10)),
        kit.box((0, ey - 0.33, ez - 0.38), (0.46, 0.12, 0.66)),
        kit.box((0, ey - 0.30, ez + 0.04), (0.34, 0.20, 0.24)),
    ]
    v, f = kit.merge(*parts)
    kit.make_object("EjectionSeat", v, f, col, "Details")


def build_pitot(col):
    boom = kit.cylinder((0, Y(0), Z(766)), (0, Y(190), Z(760)), 0.022, 8)
    v, f = kit.merge(boom)
    kit.make_object("Pitot", v, f, col, "Details")


def build_gear(col):
    nx, ny, nz = NOSE_WHEEL["at"]
    top = (0, ny + 0.10, -0.62)
    v, f = kit.cylinder(top, (0, ny, nz + 0.10), 0.05, 10)
    kit.make_object("NoseGearStrut", v, f, col, "Details", "Gear", origin=top,
                    hinge={"axis": (1, 0, 0), "min": 0, "max": 95, "control": "Gear"})
    v, f = kit.wheel(NOSE_WHEEL["at"], NOSE_WHEEL["radius"], NOSE_WHEEL["width"])
    kit.make_object("NoseGearWheel", v, f, col, "Details", "GearWheel", origin=NOSE_WHEEL["at"],
                    hinge={"axis": (1, 0, 0), "min": -720, "max": 720, "control": "Wheel"})
    for side, name in ((1, "R"), (-1, "L")):
        v, f = kit.box((side * 0.15, ny + 0.1, -0.76), (0.03, 0.7, 0.26))
        kit.make_object(f"NoseGearDoor{name}", v, f, col, "Details", "GearDoor", origin=(side * 0.13, ny + 0.1, -0.64),
                        hinge={"axis": (0, 1, 0), "min": 0, "max": 85, "control": "GearDoor"})
    mx, my, mz = MAIN_WHEEL["at"]
    for side, name in ((1, "R"), (-1, "L")):
        top = (side * 1.40, my + 0.10, WING_Z - 0.05)
        v, f = kit.cylinder(top, (side * (mx - 0.14), my, mz + 0.08), 0.07, 10)
        kit.make_object(f"MainGearStrut{name}", v, f, col, "Details", "Gear", origin=top,
                        hinge={"axis": (0, 1, 0), "min": 0, "max": 90, "control": "Gear"})
        centre = (side * mx, my, mz)
        v, f = kit.wheel(centre, MAIN_WHEEL["radius"], MAIN_WHEEL["width"])
        kit.make_object(f"MainGearWheel{name}", v, f, col, "Details", "GearWheel", origin=centre,
                        hinge={"axis": (1, 0, 0), "min": -720, "max": 720, "control": "Wheel"})
        v, f = kit.box((side * 1.30, my, WING_Z - 0.38), (0.04, 0.95, 0.55))
        kit.make_object(f"MainGearDoor{name}", v, f, col, "Details", "GearDoor", origin=(side * 1.28, my, WING_Z - 0.10),
                        hinge={"axis": (0, 1, 0), "min": 0, "max": 85, "control": "GearDoor"})


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
    build_souris(cols["Body"])
    kit.build_canopy(cols["Glass"], cols["Body"])
    build_wings(cols["Wings"])
    build_tail(cols["Body"])
    build_engine(cols["Details"])
    build_seat(cols["Details"])
    build_pitot(cols["Details"])
    build_gear(cols["Gear"])
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
