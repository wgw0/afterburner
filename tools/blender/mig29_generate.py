"""
Afterburner: MiG-29A base mesh generator (Blender 4.x / 5.x).

Builds a mid-poly, modular MiG-29A at real-world size, measured from a reference drawing, in the same form
as the F-5E (f5e_generate.py, whose helpers this uses): separate objects per part, moving parts with
their origin on the hinge line, four texture sets, a manifest for the Studio assembler, an FBX, and the
cockpit well.

  * the narrow forward fuselage with the radome and the tall canopy, running back as a central spine
    between the engines
  * two engine nacelles under the wing roots with their raked intakes
  * big leading-edge extensions blending into the wing, and the tail booms beside the nacelles
  * the swept wing with leading-edge flaps, flaps and ailerons
  * all-moving stabilators and twin fins canted out, each with a rudder, on the booms
  * twin nozzles with afterburner cones, ejection seat, pitot, landing gear (struts, wheels, doors)

Run headless:
  blender -b --python tools/blender/mig29_generate.py -- --out <dir> --manifest-luau tools/Manifests/MiG29A.luau

Reference: the Commons three-view "Mikoyan MiG-29 3-view.svg" (Kaboldy, CC BY-SA 3.0), rendered 3840 px
wide: side view on top and top view below, both nose left with the pitot tip at x = 52. Stations (xd) are
pixels aft of it; heights are side-view rows (row 585, the nozzles' axis, is z = 0); half widths are
pixels from the top view's centreline (row 1768). The scale comes from the published 17.37 m length
(171.8 px/m); the span then comes out 11.27 m against the published 11.36 m. See
docs/art/reference/MiG29A/SOURCES.md (kept out of git).
"""

import argparse
import math
import os
import sys

from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import f5e_generate as kit  # noqa: E402  (shared helpers; its module settings are switched below)

kit.AIRFRAME = "MiG29A"
kit.REF_PX_PER_M = 171.8
kit.REF_PITOT_XD = 0.0
kit.REF_Z0_ROW = 585.0
kit.CG_FROM_PITOT = 1783 / 171.8  # 25% of the 3.73 m mean aerodynamic chord
kit.LENGTH = 17.37
kit.SPINE_UPPER_ONLY = True
Y, Z = kit.Y, kit.Z
PX = kit.REF_PX_PER_M


def W(px):
    return px / PX


# The forward fuselage, then the central spine between the nacelles
kit.FUSELAGE = [
    (200, 0.02, 0.21, 0.29, 0.29, 0.0, 2.0),  # radome tip
    (300, 0.25, 0.12, 0.52, 0.52, 0.0, 2.0),
    (400, 0.35, 0.04, 0.76, 0.76, 0.0, 2.0),
    (500, 0.41, 0.04, 0.89, 0.89, 0.0, 2.1),
    (600, 0.42, 0.02, 0.99, 0.99, 0.0, 2.2),
    (700, 0.47, 0.06, 1.15, 1.15, 0.0, 2.4),  # windscreen base
    (900, 0.50, 0.10, 1.15, 1.15, 0.0, 2.5),
    (1050, 0.54, 0.10, 1.15, 1.15, 0.0, 2.5),
    (1100, 0.56, 0.10, 1.15, 1.60, 0.35, 2.5),  # the spine rises inside the canopy's rear
    (1300, 0.60, 0.05, 1.10, 1.55, 0.40, 2.5),
    (1600, 0.62, 0.00, 0.95, 1.22, 0.36, 2.5),
    (1800, 0.62, 0.00, 0.90, 1.02, 0.0, 2.5),
    (2000, 0.60, 0.00, 0.89, 0.89, 0.0, 2.4),
    (2300, 0.55, 0.00, 0.75, 0.75, 0.0, 2.3),
    (2500, 0.45, 0.05, 0.60, 0.60, 0.0, 2.2),
    (2620, 0.22, 0.12, 0.45, 0.45, 0.0, 2.0),  # tail end between the nozzles
]
kit.FUSELAGE_RINGS = 62
kit.FUSELAGE_SEGMENTS = 40

kit.CANOPY = [
    (700, 0.12, 1.24),
    (750, 0.30, 1.40),
    (800, 0.38, 1.52),
    (850, 0.42, 1.62),
    (900, 0.43, 1.68),
    (1000, 0.43, 1.71),
    (1060, 0.41, 1.71),
    (1110, 0.36, 1.68),
    (1150, 0.28, 1.62),
]
kit.CANOPY_FRAMES = (830, 1100)

# Engine nacelles: (xd, half width, centre z, half height), centred at x = NACELLE_X. The intake lip is
# raked: its top at station 1153, its bottom at 1378.
NACELLE_X = 0.88
NACELLE = [(1265, 0.42, -0.15, 0.40), (1450, 0.45, -0.15, 0.45), (1800, 0.48, -0.10, 0.45), (2200, 0.50, -0.05, 0.42),
           (2480, 0.48, 0.0, 0.45), (2560, 0.46, 0.0, 0.46)]
LIP_TOP, LIP_BOTTOM = 1153, 1378

# Leading-edge extensions (half width m, xd), at the wing's height
LERX_EDGE = [(0.47, 740), (0.58, 800), (0.75, 900), (0.93, 1000), (1.10, 1150), (1.30, 1300), (1.47, 1420), (W(283), 1529)]
BOOM_X, BOOM = W(310), (2150, 2830)

WING_Z = Z(510)


def wing_le_y(x):
    return Y(1529 + (x * PX - 283) * 0.905)


def wing_te_y(x):
    return Y(2248 + (x * PX - 303) * 0.194)


kit.WING_Z = WING_Z
kit.WING_ROOT_X, kit.WING_TIP_X = 1.30, W(968)
kit.WING_ROOT_LE, kit.WING_ROOT_TE = wing_le_y(1.30), wing_te_y(1.30)
kit.WING_SWEEP_LE = math.atan((wing_le_y(1.30) - wing_le_y(W(968))) / (W(968) - 1.30))
kit.WING_TIP_CHORD = wing_le_y(W(968)) - wing_te_y(W(968))
kit.WING_THICKNESS = 0.045
kit.LE_FLAP_CHORD = 0.15
kit.TE_HINGE = 0.80
kit.TE_FLAP_SPAN = (1.80, 3.60)
kit.AILERON_SPAN = (3.65, 4.90)
kit.RAIL_Y = (wing_le_y(W(968)) + wing_te_y(W(968))) / 2
kit.RAIL_LENGTH = 1.2

STAB_ROOT_X, STAB_TIP_X = BOOM_X, W(640)
STAB_ROOT_LE, STAB_ROOT_TE = Y(2418), Y(2808)
STAB_TIP_LE, STAB_TIP_TE = Y(2790), Y(2955)
STAB_Z = Z(520)
STAB_THICKNESS = 0.045

FIN_X, FIN_CANT = BOOM_X - 0.05, math.radians(6)
FIN_ROOT_Z, FIN_TIP_Z = 0.62, Z(35)
FIN_ROOT_LE, FIN_ROOT_TE = Y(2137), Y(2714)
FIN_TIP_LE, FIN_TIP_TE = Y(2638), Y(2733)
FIN_THICKNESS = 0.045
RUDDER_HINGE = 0.75
RUDDER_SPAN = (1.08, 2.27)

NOZZLE_Z, NOZZLE_R = Z(585), 0.42
NOZZLE_Y0, NOZZLE_Y1 = Y(2560), Y(2723)

GROUND_Z = FIN_TIP_Z - 4.73  # published height
NOSE_WHEEL = {"at": (0, Y(1239), GROUND_Z + 0.30), "radius": 0.30, "width": 0.16}
MAIN_WHEEL = {"at": (1.55, Y(1868), GROUND_Z + 0.41), "radius": 0.41, "width": 0.22}

kit.HULL = {"size": [3.0, 1.8, 16.0], "at": [0, 0.2, -1.2]}
kit.HITBOXES = {
    "Cockpit": {"size": [0.9, 1.0, 2.4], "at": [0, 1.35, -4.6]},
    "Fuselage": {"size": [2.8, 1.6, 6.5], "at": [0, 0.2, -1.2]},
    "Engine": {"size": [2.6, 1.2, 5.0], "at": [0, -0.1, 3.8]},
    "WingL": {"size": [4.2, 0.4, 3.6], "at": [-3.6, round(WING_Z, 2), 1.5]},
    "WingR": {"size": [4.2, 0.4, 3.6], "at": [3.6, round(WING_Z, 2), 1.5]},
    "Tail": {"size": [7.5, 3.0, 3.6], "at": [0, 1.2, 5.6]},
}
EYE = (0, Y(960), 1.48)
kit.ATTACHMENTS = {
    "CockpitEye": EYE,
    "GunMuzzle": (-0.95, Y(900), 0.55),  # GSh-30-1 in the left leading-edge extension
    "Nozzle1": (-NACELLE_X, NOZZLE_Y1, NOZZLE_Z),
    "Nozzle2": (NACELLE_X, NOZZLE_Y1, NOZZLE_Z),
    "WingtipL": (-(kit.WING_TIP_X + 0.05), kit.RAIL_Y, WING_Z),
    "WingtipR": (kit.WING_TIP_X + 0.05, kit.RAIL_Y, WING_Z),
    "FlareDispenser": (0, Y(2450), 0.70),
    "ChaffDispenser": (0, Y(2400), 0.72),
    "ChaseCam": (0, -21.5, 4.0),
    "Hardpoint1": (-4.2, Y(2000), WING_Z - 0.15),
    "Hardpoint2": (4.2, Y(2000), WING_Z - 0.15),
    "Hardpoint3": (-3.3, Y(1900), WING_Z - 0.15),
    "Hardpoint4": (3.3, Y(1900), WING_Z - 0.15),
    "Hardpoint5": (-2.4, Y(1800), WING_Z - 0.15),
    "Hardpoint6": (2.4, Y(1800), WING_Z - 0.15),
    "Hardpoint7": (0, Y(1700), -0.12),
}

# Cockpit interior (cockpit_kit.py, art pipeline §7), after MiG-29A cockpit photos: the ILS-31 head-up
# display on the glareshield, the attitude indicator in the middle, flight instruments left, engine
# instruments (two of each) and the small radar repeater right. Turquoise.
kit.COCKPIT = {
    "well": {"back": 4.49, "front": 5.55, "half_width": 0.36, "floor": 0.50, "flange": 0.06},
    "panel": {"distance": 0.65, "top": -0.18, "bottom": -0.62, "tilt": 12, "half_width": 0.32},
    "coaming": {"overhang": 0.04, "length": 0.32, "drop": 0.06},
    "consoles": {"top": -0.53, "width": 0.10, "aft": -0.35, "fore": 0.42, "throttle": 0.02},
    "stick": "centre",
    "stick_fore": 0.40,
    "sight": "HUD",
    "palette": "Soviet",
    "instruments": [
        {"name": "GMeter", "kind": "Dial", "u": -0.22, "v": 0.075, "size": 0.055, "live": "G"},
        {"name": "Airspeed", "kind": "Dial", "u": -0.12, "v": 0.08, "size": 0.075, "live": "Speed"},
        {"name": "Caution", "kind": "Lights", "u": 0.0, "v": 0.085, "size": 0.12},
        {"name": "RPM", "kind": "Dial", "u": 0.12, "v": 0.08, "size": 0.075, "live": "RPM"},
        {"name": "RadarScope", "kind": "Scope", "u": 0.22, "v": 0.085, "size": 0.08, "live": "Radar"},
        {"name": "AOA", "kind": "Dial", "u": -0.22, "v": 0.165, "size": 0.05},
        {"name": "Altimeter", "kind": "Dial", "u": -0.12, "v": 0.175, "size": 0.075, "live": "Altitude"},
        {"name": "ADI", "kind": "Dial", "u": 0.0, "v": 0.19, "size": 0.10, "face": "attitude"},
        {"name": "RPM2", "kind": "Dial", "u": 0.12, "v": 0.175, "size": 0.065},
        {"name": "EGT", "kind": "Dial", "u": 0.22, "v": 0.175, "size": 0.05},
        {"name": "VVI", "kind": "Dial", "u": -0.15, "v": 0.275, "size": 0.055},
        {"name": "HSI", "kind": "Dial", "u": 0.0, "v": 0.30, "size": 0.09, "face": "compass"},
        {"name": "Fuel", "kind": "Dial", "u": 0.15, "v": 0.275, "size": 0.055},
    ],
}


# ---------------------------------------------------------------------------------------------------
# Builders
# ---------------------------------------------------------------------------------------------------


def nacelle_ring(side, xd, hw, zc, hh, scale=1.0, raked=False, segments=20):
    """A nacelle section: a rounded box. With raked=True the ring follows the intake lip's slope."""
    pts = []
    for k in range(segments):
        ang = 2 * math.pi * k / segments
        c, s = math.cos(ang), math.sin(ang)
        x = side * NACELLE_X + hw * scale * math.copysign(abs(c) ** (2 / 3.2), c)
        z = zc + hh * scale * math.copysign(abs(s) ** (2 / 3.2), s)
        station = xd
        if raked:
            t = (zc + hh - z) / (2 * hh)
            station = kit.lerp(LIP_TOP, LIP_BOTTOM, t)
        pts.append((x, Y(station), z))
    return pts


def build_nacelles(col):
    parts, ducts = [], []
    for side in (1, -1):
        _, hw, zc, hh = NACELLE[0]
        rings = [nacelle_ring(side, 0, hw, zc, hh, 0.88, raked=True), nacelle_ring(side, 0, hw, zc, hh, 1.0, raked=True)]
        for i, (xd, w, z, h) in enumerate(NACELLE):
            rings.append(nacelle_ring(side, xd, w, z, h))
        # The mouth is recessed: the first ring sits inside and behind the lip
        rings[0] = [(p[0], p[1] - 0.15, p[2]) for p in rings[0]]
        parts.append(kit.lofted(rings, True, True))
        mouth = [(p[0], p[1] + 0.01, p[2]) for p in rings[0]]
        ducts.append(kit.lofted([mouth, [(p[0], p[1] + 0.01, p[2]) for p in mouth]], True, True))
    v, f = kit.merge(*parts)
    kit.make_object("Nacelles", v, f, col, "Body")
    v, f = kit.merge(*ducts)
    kit.make_object("IntakeDucts", v, f, col, "Body")


def build_strakes_and_booms(col):
    """Leading-edge extensions from the nose to the wing, and the tail booms carrying the tail."""
    parts = []
    z, th = WING_Z, 0.04
    for side in (1, -1):
        top, bottom, edge = [], [], []
        for hw, xd in LERX_EDGE:
            y = Y(xd)
            top.append((side * 0.40, y, z + th))
            bottom.append((side * 0.40, y, z - th))
            edge.append((side * hw, y, z))
        # Closing the extension's trailing side along the nacelle top, inside the wing root
        n = len(edge)
        verts = top + bottom + edge
        faces = []
        for i in range(n - 1):
            faces.append((i, i + 1, 2 * n + i + 1, 2 * n + i))
            faces.append((n + i, 2 * n + i, 2 * n + i + 1, n + i + 1))
            faces.append((i, n + i, n + i + 1, i + 1))
        faces.append((0, 2 * n, n))
        faces.append((n - 1, 2 * n - 1, 3 * n - 1))
        parts.append((verts, faces))
        # The wide flat centre section between the extension and the wing root, over the nacelle
        y0, y1 = Y(1529), Y(2300)
        parts.append(kit.box((side * (0.40 + kit.WING_ROOT_X) / 2, (y0 + y1) / 2, z), (kit.WING_ROOT_X - 0.40 + 0.1, y0 - y1, th * 2)))
        # Tail boom
        b0, b1 = BOOM
        parts.append(kit.cylinder((side * BOOM_X, Y(b0), STAB_Z + 0.05), (side * BOOM_X, Y(b1), STAB_Z + 0.05), 0.14, 10,
                                  radius1=0.06))
    v, f = kit.merge(*parts)
    kit.make_object("Strakes", v, f, col, "Body")


def build_tail(col_wings, col_body):
    up = (0, 0, 1)
    root_le, root_te = (STAB_ROOT_X, STAB_ROOT_LE, STAB_Z), (STAB_ROOT_X, STAB_ROOT_TE, STAB_Z)
    tip_le, tip_te = (STAB_TIP_X, STAB_TIP_LE, STAB_Z), (STAB_TIP_X, STAB_TIP_TE, STAB_Z)
    pivot_y = STAB_ROOT_LE - (STAB_ROOT_LE - STAB_ROOT_TE) * 0.40
    for side, name in ((1, "R"), (-1, "L")):
        v, f = kit.panel(root_le, root_te, tip_le, tip_te, up, STAB_THICKNESS, 0.0, 1.0, 0, 1, 6, 10)
        if side < 0:
            v, f = kit.mirror_x(v), kit.flip_faces(f)
        # Pitch and roll mixed (tailerons), with the ailerons
        kit.make_object(f"Stabilator{name}", v, f, col_wings, "Wings", "ControlSurface",
                        origin=(side * STAB_ROOT_X, pivot_y, STAB_Z),
                        hinge={"axis": (1, 0, 0), "min": -25, "max": 20, "control": "Elevon" + name})

    h = FIN_TIP_Z - FIN_ROOT_Z
    lean = h * math.tan(FIN_CANT)

    def frac(z):
        return (z - FIN_ROOT_Z) / h

    for side, name in ((1, "R"), (-1, "L")):
        x0, x1 = side * FIN_X, side * (FIN_X + lean)
        normal = (side * math.cos(FIN_CANT), 0, -side * math.sin(FIN_CANT))
        g = ((x0, FIN_ROOT_LE, FIN_ROOT_Z), (x0, FIN_ROOT_TE, FIN_ROOT_Z), (x1, FIN_TIP_LE, FIN_TIP_Z),
             (x1, FIN_TIP_TE, FIN_TIP_Z), normal, FIN_THICKNESS)
        fin = [
            kit.panel(*g, 0.0, RUDDER_HINGE, 0, 1, 8, 10),
            kit.panel(*g, RUDDER_HINGE, 1.0, 0, frac(RUDDER_SPAN[0]), 1, 4),
            kit.panel(*g, RUDDER_HINGE, 1.0, frac(RUDDER_SPAN[1]), 1, 2, 4),
        ]
        v, f = kit.merge(*fin)
        kit.make_object(f"Fin{name}", v, f, col_body, "Body")
        v, f = kit.panel(*g, RUDDER_HINGE, 1.0, frac(RUDDER_SPAN[0]), frac(RUDDER_SPAN[1]), 6, 6)
        a, b = kit.hinge_line(*g[:4], RUDDER_HINGE, frac(RUDDER_SPAN[0]), frac(RUDDER_SPAN[1]))
        kit.make_object(f"Rudder{name}", v, f, col_body, "Body", "ControlSurface", origin=tuple(a.lerp(b, 0.5)),
                        hinge={"axis": tuple(b - a), "min": -25, "max": 25, "control": "Rudder"})


def build_engines(col):
    for side, name in ((1, "R"), (-1, "L")):
        x = side * NACELLE_X
        p0, p1 = (x, NOZZLE_Y0, NOZZLE_Z), (x, NOZZLE_Y1, NOZZLE_Z)
        nv, nf = kit.cylinder(p0, p1, NOZZLE_R + 0.04, 20, radius1=NOZZLE_R, caps=False)
        iv, i_f = kit.cylinder(p0, p1, NOZZLE_R - 0.025, 20, radius1=NOZZLE_R - 0.035, caps=False)
        n = 20
        lip = [(n + i, n + (i + 1) % n, len(nv) + n + (i + 1) % n, len(nv) + n + i) for i in range(n)]
        verts, faces = kit.merge((nv, nf), (iv, kit.flip_faces(i_f)))
        kit.make_object(f"Nozzle{name}", verts, faces + lip, col, "Details", "Nozzle", extra={"engine": name})
        cv, cf = kit.cylinder((x, NOZZLE_Y1 + 0.15, NOZZLE_Z), (x, NOZZLE_Y0 + 0.05, NOZZLE_Z), NOZZLE_R - 0.06, 16,
                              radius1=0.05, caps=True)
        kit.make_object(f"Afterburner{name}", cv, cf, col, "Details", "Afterburner", extra={"engine": name})


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
    v, f = kit.cylinder((0, Y(0), Z(558)), (0, Y(205), Z(542)), 0.022, 8)
    kit.make_object("Pitot", v, f, col, "Details")


def build_gear(col):
    nx, ny, nz = NOSE_WHEEL["at"]
    top = (0, ny + 0.10, 0.05)
    v, f = kit.cylinder(top, (0, ny, nz + 0.12), 0.07, 10)
    kit.make_object("NoseGearStrut", v, f, col, "Details", "Gear", origin=top,
                    hinge={"axis": (1, 0, 0), "min": 0, "max": 95, "control": "Gear"})
    v, f = kit.wheel(NOSE_WHEEL["at"], NOSE_WHEEL["radius"], NOSE_WHEEL["width"])
    kit.make_object("NoseGearWheel", v, f, col, "Details", "GearWheel", origin=NOSE_WHEEL["at"],
                    hinge={"axis": (1, 0, 0), "min": -720, "max": 720, "control": "Wheel"})
    for side, name in ((1, "R"), (-1, "L")):
        v, f = kit.box((side * 0.16, ny + 0.1, -0.05), (0.03, 0.8, 0.26))
        kit.make_object(f"NoseGearDoor{name}", v, f, col, "Details", "GearDoor", origin=(side * 0.14, ny + 0.1, 0.07),
                        hinge={"axis": (0, 1, 0), "min": 0, "max": 85, "control": "GearDoor"})
    mx, my, mz = MAIN_WHEEL["at"]
    for side, name in ((1, "R"), (-1, "L")):
        top = (side * 1.40, my + 0.15, WING_Z - 0.10)
        v, f = kit.cylinder(top, (side * mx, my, mz + 0.10), 0.08, 10)
        kit.make_object(f"MainGearStrut{name}", v, f, col, "Details", "Gear", origin=top,
                        hinge={"axis": (0, 1, 0), "min": 0, "max": 90, "control": "Gear"})
        centre = (side * mx, my, mz)
        v, f = kit.wheel(centre, MAIN_WHEEL["radius"], MAIN_WHEEL["width"])
        kit.make_object(f"MainGearWheel{name}", v, f, col, "Details", "GearWheel", origin=centre,
                        hinge={"axis": (1, 0, 0), "min": -720, "max": 720, "control": "Wheel"})
        v, f = kit.box((side * 1.50, my, WING_Z - 0.40), (0.04, 1.0, 0.55))
        kit.make_object(f"MainGearDoor{name}", v, f, col, "Details", "GearDoor", origin=(side * 1.48, my, WING_Z - 0.12),
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
    build_nacelles(cols["Body"])
    build_strakes_and_booms(cols["Body"])
    kit.build_canopy(cols["Glass"], cols["Body"])
    kit.build_wings(cols["Wings"])
    build_tail(cols["Wings"], cols["Body"])
    build_engines(cols["Details"])
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
