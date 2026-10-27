"""
Afterburner: F-4E Phantom II base mesh generator (Blender 4.x / 5.x).

Builds a mid-poly, modular F-4E at real-world size, measured from a reference drawing, in the same form
as the F-5E (f5e_generate.py, whose helpers this uses): separate objects per part, moving parts with
their origin on the hinge line, four texture sets, a manifest for the Studio assembler, an FBX, and the
cockpit well.

  * the fuselage: radome, the long tandem canopy, the flat dorsal spine, the wide engine bay and the
    tail boom over the nozzles; the M61 gun fairing under the nose
  * big D-section intakes with their splitter plates
  * the low wing: inner panels with leading-edge flaps, flaps and ailerons; outer panels folded up 12
    degrees with their own leading-edge flaps
  * all-moving stabilators with the Phantom's anhedral, the fin and rudder
  * twin nozzles with afterburner cones, ejection seat, pitot, landing gear (struts, wheels, doors)

Run headless:
  blender -b --python tools/blender/f4e_generate.py -- --out <dir> --manifest-luau tools/Manifests/F4E.luau

Reference: the Commons three-view "McDonnell Douglas F-4E Phantom II 3-view.svg" (Kaboldy, CC BY-SA
3.0), rendered 3840 px wide. Side view on top, top view below it, both nose left with the pitot tip at
x = 57; stations (xd) are pixels aft of it. Heights are side-view rows (row 560, the nozzles' axis, is
z = 0); half widths are pixels from the top view's centreline (row 1770). The scale comes from the
published 11.71 m span (153.4 px/m), which also gives the published 5.02 m height. The drawing's length
then comes out 18.6 m against the published 19.2 m; the drawing's shape is kept. See
docs/art/reference/F4E/SOURCES.md (kept out of git).
"""

import argparse
import math
import os
import sys

from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import f5e_generate as kit  # noqa: E402  (shared helpers; its module settings are switched below)

kit.AIRFRAME = "F4E"
kit.REF_PX_PER_M = 153.4
kit.REF_PITOT_XD = 0.0
kit.REF_Z0_ROW = 560.0
kit.CG_FROM_PITOT = 1496 / 153.4  # 25% of the 4.59 m mean aerodynamic chord
kit.LENGTH = round(2800 / 153.4, 2)
kit.SPINE_UPPER_ONLY = True
Y, Z = kit.Y, kit.Z
PX = kit.REF_PX_PER_M


def W(px):
    """Top-view half width in metres."""
    return px / PX


# Fuselage stations: (xd, half width, bottom z, shoulder z, top z, spine half width, exponent)
kit.FUSELAGE = [
    (65, 0.012, -0.29, -0.27, -0.27, 0.0, 2.0),  # radome tip
    (115, W(28), -0.40, -0.065, -0.065, 0.0, 2.0),
    (200, W(55), -0.52, 0.23, 0.23, 0.0, 2.0),
    (300, W(68), -0.55, 0.39, 0.39, 0.0, 2.1),
    (400, W(78), -0.53, 0.50, 0.50, 0.0, 2.2),
    (520, W(85), -0.52, 0.64, 0.64, 0.0, 2.3),  # windscreen base
    (700, W(95), -0.47, 0.83, 0.83, 0.0, 2.5),
    (900, W(100), -0.42, 0.98, 0.98, 0.0, 2.6),
    (1100, 0.72, -0.38, 1.08, 1.08, 0.0, 2.6),
    (1200, 0.85, -0.37, 1.10, 1.40, 0.36, 2.6),  # the spine rises inside the rear canopy
    (1300, 1.05, -0.36, 1.00, 1.51, 0.42, 2.6),
    (1500, 1.20, -0.36, 0.90, 1.51, 0.45, 2.8),
    (1800, 1.22, -0.40, 0.80, 1.51, 0.50, 3.0),
    (2050, 1.20, -0.50, 0.65, 1.51, 0.58, 3.0),  # engine bay
    (2250, 1.15, -0.50, 0.55, 1.50, 0.60, 3.0),
    (2300, 0.58, -0.20, 0.95, 1.48, 0.0, 2.4),  # tail boom over the nozzles
    (2400, 0.50, -0.05, 1.10, 1.45, 0.0, 2.3),
    (2500, W(70), 0.10, 1.40, 1.40, 0.0, 2.2),
    (2700, W(40), 0.59, 1.17, 1.17, 0.0, 2.0),
    (2790, 0.06, 0.88, 1.05, 1.05, 0.0, 2.0),
]
kit.FUSELAGE_RINGS = 64
kit.FUSELAGE_SEGMENTS = 44

# D-section intakes: (xd, outer half width, top z, bottom z)
kit.INTAKES = [
    (890, 1.30, 0.86, -0.42),  # the lip; the splitter plates stand ahead of it
    (950, 1.36, 0.85, -0.42),
    (1050, 1.38, 0.80, -0.42),
    (1150, 1.35, 0.70, -0.40),
    (1300, 1.30, 0.55, -0.36),
]
kit.INTAKE_LIP_SWEEP = 0.10

kit.CANOPY = [
    (520, 0.12, 0.66),
    (560, 0.30, 0.84),
    (620, 0.36, 1.03),
    (700, 0.40, 1.21),
    (800, 0.42, 1.43),
    (860, 0.42, 1.52),
    (950, 0.42, 1.55),
    (1050, 0.42, 1.57),
    (1150, 0.41, 1.55),
    (1240, 0.36, 1.50),
]
kit.CANOPY_FRAMES = (690, 895, 1235)

# Wing: inner panels flat, outer panels folded up 12 degrees at the fold line
WING_Z = Z(598)
WING_ROOT_X, FOLD_X, WING_TIP_X = 0.60, W(615), W(893)
DIHEDRAL = math.radians(12)
WING_THICKNESS = 0.05
LE_FLAP_CHORD = 0.15
TE_HINGE = 0.78
FLAP_SPAN = (1.35, 2.40)
AILERON_SPAN = (2.45, 3.90)


def wing_le_y(x):
    hw = x * PX
    return Y(1160 + (hw - 205) / 0.862 if hw <= 615 else 1636 + (hw - 615) / 0.885)


def wing_te_y(x):
    hw = x * PX
    return Y(1963 + (hw - 185) * 0.2317 if hw <= 610 else 2073 + (hw - 610) * 0.205)


def wing_z(x):
    return WING_Z + max(x - FOLD_X, 0) * math.tan(DIHEDRAL)


# Stabilators, with anhedral: root and tip from the top view, heights from the side view
STAB_ROOT_X, STAB_TIP_X = 0.46, W(380)
STAB_ROOT_LE, STAB_ROOT_TE, STAB_ROOT_Z = Y(2423), Y(2783), Z(425)
STAB_TIP_LE, STAB_TIP_TE, STAB_TIP_Z = Y(2733), Y(2821), Z(578)
STAB_THICKNESS = 0.05

FIN_ROOT_Z, FIN_TIP_Z = 1.49, Z(55)
FIN_ROOT_LE, FIN_ROOT_TE = Y(2083), Y(2803)
FIN_TIP_LE, FIN_TIP_TE = Y(2693), Y(2803)
FIN_THICKNESS = 0.05
RUDDER_HINGE = 0.79
RUDDER_SPAN = (1.55, 2.95)

NOZZLE_X, NOZZLE_Z, NOZZLE_R = 0.72, Z(560), 0.42
NOZZLE_Y0, NOZZLE_Y1 = Y(2180), Y(2285)

GROUND_Z = FIN_TIP_Z - 5.02  # published height
NOSE_WHEEL = {"at": (0, Y(608), GROUND_Z + 0.23), "radius": 0.23, "width": 0.16}
MAIN_WHEEL = {"at": (2.72, Y(1678), GROUND_Z + 0.36), "radius": 0.36, "width": 0.22}

kit.HULL = {"size": [2.6, 1.9, 17.0], "at": [0, 0.4, -0.42]}
kit.HITBOXES = {
    "Cockpit": {"size": [1.0, 1.1, 3.6], "at": [0, 1.1, -3.6]},
    "Fuselage": {"size": [2.6, 1.8, 7.0], "at": [0, 0.4, -1.0]},
    "Engine": {"size": [2.4, 1.6, 5.0], "at": [0, 0.1, 3.9]},
    "WingL": {"size": [5.2, 0.6, 4.0], "at": [-3.2, -0.1, 1.6]},
    "WingR": {"size": [5.2, 0.6, 4.0], "at": [3.2, -0.1, 1.6]},
    "Tail": {"size": [5.0, 3.4, 4.8], "at": [0, 1.6, 6.2]},
}
EYE = (0, Y(830), 1.25)
kit.ATTACHMENTS = {
    "CockpitEye": EYE,
    "GunMuzzle": (0, Y(230), -0.72),  # the M61 in its fairing under the nose
    "Nozzle1": (-NOZZLE_X, NOZZLE_Y1, NOZZLE_Z),
    "Nozzle2": (NOZZLE_X, NOZZLE_Y1, NOZZLE_Z),
    "WingtipL": (-WING_TIP_X, Y(2030), wing_z(WING_TIP_X)),
    "WingtipR": (WING_TIP_X, Y(2030), wing_z(WING_TIP_X)),
    "FlareDispenser": (0, Y(2350), -0.25),
    "ChaffDispenser": (0, Y(2300), -0.30),
    "ChaseCam": (0, -22.0, 4.0),
    "Hardpoint1": (-3.0, Y(1650), WING_Z - 0.30),
    "Hardpoint2": (3.0, Y(1650), WING_Z - 0.30),
    "Hardpoint3": (-0.9, Y(1300), -0.50),  # semi-recessed Sparrows
    "Hardpoint4": (0.9, Y(1300), -0.50),
    "Hardpoint5": (-0.9, Y(1850), -0.55),
    "Hardpoint6": (0.9, Y(1850), -0.55),
    "Hardpoint7": (0, Y(1600), -0.62),
}

# Cockpit interior (cockpit_kit.py, art pipeline §7), after F-4E front-cockpit photos: the LCOSS sight on
# the glareshield, the radar scope at the top of the panel, flight instruments in a T below and to its
# left, engine instruments (two of each) to the right. US grey and black.
kit.COCKPIT = {
    "well": {"back": 3.92, "front": 5.12, "half_width": 0.35, "floor": 0.20, "flange": 0.06},
    "panel": {"distance": 0.68, "top": -0.17, "bottom": -0.62, "tilt": 12, "half_width": 0.32},
    "coaming": {"overhang": 0.04, "length": 0.35, "drop": 0.06},
    "consoles": {"top": -0.55, "width": 0.10, "aft": -0.35, "fore": 0.45, "throttle": 0.02},
    "stick": "centre",
    "stick_fore": 0.40,
    "sight": "Gunsight",
    "sight_body": (0.14, 0.16, 0.09),
    "sight_glass": (0.13, 0.12),
    "palette": "US",
    "instruments": [
        {"name": "RadarScope", "kind": "Scope", "u": 0.0, "v": 0.08, "size": 0.105, "hood": 0.04, "live": "Radar"},
        {"name": "GMeter", "kind": "Dial", "u": -0.215, "v": 0.075, "size": 0.055, "live": "G"},
        {"name": "Airspeed", "kind": "Dial", "u": -0.125, "v": 0.08, "size": 0.08, "live": "Speed"},
        {"name": "RPM", "kind": "Dial", "u": 0.125, "v": 0.08, "size": 0.075, "live": "RPM"},
        {"name": "RPM2", "kind": "Dial", "u": 0.215, "v": 0.075, "size": 0.055},
        {"name": "AOA", "kind": "Dial", "u": -0.215, "v": 0.165, "size": 0.05},
        {"name": "Altimeter", "kind": "Dial", "u": -0.125, "v": 0.18, "size": 0.08, "live": "Altitude"},
        {"name": "ADI", "kind": "Dial", "u": 0.0, "v": 0.205, "size": 0.10, "face": "attitude"},
        {"name": "EGT", "kind": "Dial", "u": 0.125, "v": 0.175, "size": 0.065},
        {"name": "EGT2", "kind": "Dial", "u": 0.215, "v": 0.165, "size": 0.05},
        {"name": "VVI", "kind": "Dial", "u": -0.16, "v": 0.28, "size": 0.06},
        {"name": "HSI", "kind": "Dial", "u": 0.0, "v": 0.315, "size": 0.095, "face": "compass"},
        {"name": "Caution", "kind": "Lights", "u": 0.16, "v": 0.285, "size": 0.10},
    ],
}


# ---------------------------------------------------------------------------------------------------
# Builders
# ---------------------------------------------------------------------------------------------------


def build_gun_and_splitters(col):
    """The M61 fairing under the nose and the intake splitter plates."""
    rings = []
    stations = [(220, 0.04, 0.03), (300, 0.17, 0.13), (450, 0.19, 0.15), (600, 0.18, 0.13), (720, 0.12, 0.06)]
    for xd, hw, hh in stations:
        y = Y(xd)
        zc = -0.66 + (0.0 if xd < 650 else 0.1)
        ring = []
        for i in range(12):
            ang = 2 * math.pi * i / 12
            ring.append((hw * math.cos(ang), y, zc + hh * math.sin(ang)))
        rings.append(ring)
    gun = kit.lofted(rings, True, True)
    parts = [gun]
    for side in (1, -1):
        for xd0, xd1 in ((760, 905),):
            y0, y1 = Y(xd0), Y(xd1)
            x = side * (kit.fuselage_params(830)[0] + 0.04)
            v = [(x - 0.012, y0, -0.30), (x + 0.012, y0, -0.30), (x + 0.012, y1, -0.36), (x - 0.012, y1, -0.36),
                 (x - 0.012, y0 - 0.15, 0.80), (x + 0.012, y0 - 0.15, 0.80), (x + 0.012, y1, 0.86), (x - 0.012, y1, 0.86)]
            f = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
            parts.append((v, f))
    v, f = kit.merge(*parts)
    kit.make_object("GunFairing", v, f, col, "Body")


def build_wings(col):
    up = (0, 0, 1)
    rl = (WING_ROOT_X, wing_le_y(WING_ROOT_X), WING_Z)
    rt = (WING_ROOT_X, wing_te_y(WING_ROOT_X), WING_Z)
    fl = (FOLD_X, wing_le_y(FOLD_X), WING_Z)
    ft = (FOLD_X, wing_te_y(FOLD_X), WING_Z)
    span = FOLD_X - WING_ROOT_X

    def s_of(x):
        return (x - WING_ROOT_X) / span

    # Outer panel, folded up
    tl = (WING_TIP_X, wing_le_y(WING_TIP_X), wing_z(WING_TIP_X))
    tt = (WING_TIP_X, wing_te_y(WING_TIP_X), wing_z(WING_TIP_X))
    outer_n = (-math.sin(DIHEDRAL), 0, math.cos(DIHEDRAL))

    for side, name in ((1, "R"), (-1, "L")):
        def m(v):
            return v if side > 0 else kit.mirror_x(v)

        def mf(f):
            return f if side > 0 else kit.flip_faces(f)

        def mn(v):
            return (v[0] * side, v[1], v[2])

        inner = [
            kit.panel(rl, rt, fl, ft, up, WING_THICKNESS, LE_FLAP_CHORD, TE_HINGE, 0, 1, 8, 10),
            kit.panel(rl, rt, fl, ft, up, WING_THICKNESS, TE_HINGE, 1.0, 0, s_of(FLAP_SPAN[0]), 1, 4),
            kit.panel(rl, rt, fl, ft, up, WING_THICKNESS, TE_HINGE, 1.0, s_of(FLAP_SPAN[1]), s_of(AILERON_SPAN[0]), 1, 4),
            kit.panel(rl, rt, fl, ft, up, WING_THICKNESS, TE_HINGE, 1.0, s_of(AILERON_SPAN[1]), 1, 1, 4),
        ]
        v, f = kit.merge(*inner)
        kit.make_object(f"Wing{name}", m(v), mf(f), col, "Wings")
        v, f = kit.panel(fl, ft, tl, tt, mn(outer_n) if side > 0 else outer_n, WING_THICKNESS * 0.85,
                         LE_FLAP_CHORD, 1.0, 0, 1, 4, 10)
        kit.make_object(f"WingOuter{name}", m(v), mf(f), col, "Wings")

        v, f = kit.panel(rl, rt, fl, ft, up, WING_THICKNESS, 0.0, LE_FLAP_CHORD, 0, 1, 8, 6)
        a, b = kit.hinge_line(rl, rt, fl, ft, LE_FLAP_CHORD, 0, 1)
        kit.make_object(f"LEFlap{name}", m(v), mf(f), col, "Wings", "ControlSurface",
                        origin=tuple(m([tuple(a.lerp(b, 0.5))])[0]),
                        hinge={"axis": tuple(m([tuple(b - a)])[0]), "min": 0, "max": 20, "control": "LEFlap"})
        v, f = kit.panel(fl, ft, tl, tt, outer_n, WING_THICKNESS * 0.85, 0.0, LE_FLAP_CHORD, 0, 1, 4, 6)
        a, b = kit.hinge_line(fl, ft, tl, tt, LE_FLAP_CHORD, 0, 1)
        kit.make_object(f"LEFlapOuter{name}", m(v), mf(f), col, "Wings", "ControlSurface",
                        origin=tuple(m([tuple(a.lerp(b, 0.5))])[0]),
                        hinge={"axis": tuple(m([tuple(b - a)])[0]), "min": 0, "max": 20, "control": "LEFlap"})
        for surface, (x0, x1), lims, control in (
            ("Flap", FLAP_SPAN, (0, 30), "Flap"),
            ("Aileron", AILERON_SPAN, (-20, 20), "Aileron" + name),
        ):
            v, f = kit.panel(rl, rt, fl, ft, up, WING_THICKNESS, TE_HINGE, 1.0, s_of(x0), s_of(x1), 4, 6)
            a, b = kit.hinge_line(rl, rt, fl, ft, TE_HINGE, s_of(x0), s_of(x1))
            kit.make_object(f"{surface}{name}", m(v), mf(f), col, "Wings", "ControlSurface",
                            origin=tuple(m([tuple(a.lerp(b, 0.5))])[0]),
                            hinge={"axis": tuple(m([tuple(b - a)])[0]), "min": lims[0], "max": lims[1], "control": control})


def build_tail(col_wings, col_body):
    root_le, root_te = (STAB_ROOT_X, STAB_ROOT_LE, STAB_ROOT_Z), (STAB_ROOT_X, STAB_ROOT_TE, STAB_ROOT_Z)
    tip_le, tip_te = (STAB_TIP_X, STAB_TIP_LE, STAB_TIP_Z), (STAB_TIP_X, STAB_TIP_TE, STAB_TIP_Z)
    span_dir = Vector(tip_le) - Vector(root_le)
    n = Vector((1, 0, 0)).cross(Vector((0, 1, 0)))  # up
    anh = math.atan2(STAB_ROOT_Z - STAB_TIP_Z, STAB_TIP_X - STAB_ROOT_X)
    normal = (math.sin(anh), 0, math.cos(anh))
    pivot_y = STAB_ROOT_LE - (STAB_ROOT_LE - STAB_ROOT_TE) * 0.40
    del span_dir, n
    for side, name in ((1, "R"), (-1, "L")):
        v, f = kit.panel(root_le, root_te, tip_le, tip_te, normal, STAB_THICKNESS, 0.0, 1.0, 0, 1, 6, 10)
        if side < 0:
            v, f = kit.mirror_x(v), kit.flip_faces(f)
        kit.make_object(f"Stabilator{name}", v, f, col_wings, "Wings", "ControlSurface",
                        origin=(side * STAB_ROOT_X, pivot_y, STAB_ROOT_Z),
                        hinge={"axis": (1, 0, 0), "min": -20, "max": 15, "control": "Stabilator"})

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
    v, f = kit.merge(*fin)
    kit.make_object("Fin", v, f, col_body, "Body")
    v, f = kit.panel(*g, RUDDER_HINGE, 1.0, frac(RUDDER_SPAN[0]), frac(RUDDER_SPAN[1]), 6, 6)
    a, b = kit.hinge_line(*g[:4], RUDDER_HINGE, frac(RUDDER_SPAN[0]), frac(RUDDER_SPAN[1]))
    kit.make_object("Rudder", v, f, col_body, "Body", "ControlSurface", origin=tuple(a.lerp(b, 0.5)),
                    hinge={"axis": tuple(b - a), "min": -25, "max": 25, "control": "Rudder"})


def build_engines(col):
    for side, name in ((1, "R"), (-1, "L")):
        x = side * NOZZLE_X
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
        kit.box((0, ey - 0.05, ez - 0.70), (0.48, 0.50, 0.10)),
        kit.box((0, ey - 0.33, ez - 0.38), (0.48, 0.12, 0.66)),
        kit.box((0, ey - 0.30, ez + 0.04), (0.36, 0.20, 0.26)),
    ]
    v, f = kit.merge(*parts)
    kit.make_object("EjectionSeat", v, f, col, "Details")


def build_pitot(col):
    v, f = kit.cylinder((0, Y(0), Z(605)), (0, Y(70), Z(603)), 0.022, 8)
    kit.make_object("Pitot", v, f, col, "Details")


def build_gear(col):
    nx, ny, nz = NOSE_WHEEL["at"]
    top = (0, ny + 0.10, -0.45)
    v, f = kit.cylinder(top, (0, ny, nz + 0.10), 0.06, 10)
    kit.make_object("NoseGearStrut", v, f, col, "Details", "Gear", origin=top,
                    hinge={"axis": (1, 0, 0), "min": 0, "max": 95, "control": "Gear"})
    v, f = kit.wheel(NOSE_WHEEL["at"], NOSE_WHEEL["radius"], NOSE_WHEEL["width"])
    kit.make_object("NoseGearWheel", v, f, col, "Details", "GearWheel", origin=NOSE_WHEEL["at"],
                    hinge={"axis": (1, 0, 0), "min": -720, "max": 720, "control": "Wheel"})
    for side, name in ((1, "R"), (-1, "L")):
        v, f = kit.box((side * 0.17, ny + 0.1, -0.60), (0.03, 0.8, 0.28))
        kit.make_object(f"NoseGearDoor{name}", v, f, col, "Details", "GearDoor", origin=(side * 0.15, ny + 0.1, -0.47),
                        hinge={"axis": (0, 1, 0), "min": 0, "max": 85, "control": "GearDoor"})
    mx, my, mz = MAIN_WHEEL["at"]
    for side, name in ((1, "R"), (-1, "L")):
        top = (side * mx, my + 0.15, WING_Z - 0.03)
        v, f = kit.cylinder(top, (side * mx, my, mz + 0.10), 0.08, 10)
        kit.make_object(f"MainGearStrut{name}", v, f, col, "Details", "Gear", origin=top,
                        hinge={"axis": (0, 1, 0), "min": 0, "max": 90, "control": "Gear"})
        centre = (side * mx, my, mz)
        v, f = kit.wheel(centre, MAIN_WHEEL["radius"], MAIN_WHEEL["width"])
        kit.make_object(f"MainGearWheel{name}", v, f, col, "Details", "GearWheel", origin=centre,
                        hinge={"axis": (1, 0, 0), "min": -720, "max": 720, "control": "Wheel"})
        v, f = kit.box((side * (mx - 0.25), my, WING_Z - 0.35), (0.04, 1.1, 0.60))
        kit.make_object(f"MainGearDoor{name}", v, f, col, "Details", "GearDoor",
                        origin=(side * (mx - 0.27), my, WING_Z - 0.06),
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
    build_gun_and_splitters(cols["Body"])
    kit.build_canopy(cols["Glass"], cols["Body"])
    build_wings(cols["Wings"])
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
