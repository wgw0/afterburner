"""
Afterburner: F-14A Tomcat base mesh generator (Blender 4.x / 5.x). Art only: the F-14A has no flight data
yet (AircraftData), so this makes the model, skins and cockpit for when it does.

Builds a mid-poly, modular F-14A at real-world size, measured from a reference drawing, in the same form as
the F-5E (f5e_generate.py, whose helpers this uses): separate objects per part, moving parts with their
origin on the hinge line, four texture sets, a manifest for the Studio assembler, an FBX, and the cockpit
well.

  * the forward fuselage with the radome and the long tandem canopy, and the flat centre body (the
    "pancake") between the engines, ending in the beavertail
  * the separated engine nacelles with their box intakes
  * the fixed wing gloves, and the swing wings set at a 35-degree sweep (origin on the pivot), with
    slats and flaps
  * all-moving tailerons on the elevon controls, twin fins canted out with rudders, ventral fins
  * twin nozzles with afterburner cones, ejection seat, pitot, landing gear (struts, wheels, doors)

Run headless:
  blender -b --python tools/blender/f14a_generate.py -- --out <dir> --manifest-luau tools/Manifests/F14A.luau

Reference: the Commons drawing "F-14D.jpg" (Niyansfarn, CC BY 3.0), 3028 px wide; its top view (nose
left, pitot tip at x = 271, centreline row 1392) and side view (nose left, pitot tip at x = 328) are at
the same scale. Stations (xd) are pixels aft of each view's pitot tip; heights are side-view rows (row
4047, the nozzles' axis, is z = 0); half widths are pixels from the top view's centreline. The scale
comes from the published 19.10 m length (121.2 px/m), which gives the swept span 11.54 m against the
published 11.65 m. The drawing is the F-14D: the F-14A's airframe is the same apart from the chin pod,
which is left smaller. The drawing's wings are fully swept: the swept wing is measured and turned 30
degrees forward about its pivot (half width 2.72 m, published). See docs/art/reference/F14A/SOURCES.md
(kept out of git).
"""

import argparse
import math
import os
import sys

from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import f5e_generate as kit  # noqa: E402  (shared helpers; its module settings are switched below)

kit.AIRFRAME = "F14A"
kit.REF_PX_PER_M = 121.2
kit.REF_PITOT_XD = 0.0
kit.REF_Z0_ROW = 4047.0
kit.CG_FROM_PITOT = 1450 / 121.2  # just ahead of the wing pivots
kit.LENGTH = 19.10
kit.SPINE_UPPER_ONLY = True
Y, Z = kit.Y, kit.Z
PX = kit.REF_PX_PER_M


def W(px):
    return px / PX


def ZI(img_row):
    """Height from a row of the side-view crop the measurements were read from (crop top = row 3550)."""
    return (497 - img_row) / PX


kit.FUSELAGE = [
    (40, 0.012, -0.07, -0.03, -0.03, 0.0, 2.0),  # radome tip
    (100, W(37), ZI(525), ZI(465), ZI(465), 0.0, 2.0),
    (200, W(64), ZI(538), ZI(425), ZI(425), 0.0, 2.0),
    (300, W(77), ZI(545), ZI(405), ZI(405), 0.0, 2.1),
    (400, W(84), ZI(548), ZI(395), ZI(395), 0.0, 2.3),  # windscreen base
    (500, W(89), ZI(548), 1.05, 1.05, 0.0, 2.5),
    (700, W(94), ZI(540), 1.13, 1.13, 0.0, 2.6),
    (900, 0.80, ZI(532), 1.17, 1.17, 0.0, 2.6),
    (1040, 0.85, ZI(530), 1.15, 1.54, 0.40, 2.6),  # the spine rises in the canopy's rear
    (1200, 0.90, 0.10, 1.00, 1.38, 0.42, 2.8),
    (1500, 0.92, 0.20, 0.85, 1.00, 0.40, 3.2),  # the centre body between the nacelles
    (1800, 0.90, 0.22, 0.80, 0.92, 0.0, 3.4),
    (2100, 0.82, 0.25, 0.75, 0.80, 0.0, 3.4),
    (2290, 0.55, 0.30, 0.50, 0.50, 0.0, 3.0),  # beavertail
]
kit.FUSELAGE_RINGS = 60
kit.FUSELAGE_SEGMENTS = 40

kit.CANOPY = [
    (400, 0.10, 0.84),
    (450, 0.32, 1.10),
    (500, 0.40, 1.36),
    (600, 0.44, 1.64),
    (700, 0.45, 1.75),
    (800, 0.45, 1.71),
    (900, 0.44, 1.66),
    (1000, 0.40, 1.58),
    (1050, 0.32, 1.54),
]
kit.CANOPY_FRAMES = (500, 830, 1050)

# Engine nacelles: (xd, half width, centre z, half height) around x = NACELLE_X; box intakes at station 790
NACELLE_X = 1.30
NACELLE = [(790, 0.39, 0.16, 0.60), (1000, 0.42, 0.10, 0.58), (1400, 0.45, 0.0, 0.55), (1900, 0.50, 0.0, 0.52),
           (2150, 0.52, 0.0, 0.52), (2190, 0.50, 0.0, 0.50)]
NOZZLE_X, NOZZLE_Z, NOZZLE_R = 1.25, 0.0, 0.48
NOZZLE_Y0, NOZZLE_Y1 = Y(2190), Y(2240)

# Gloves: (half width m, xd), the outline of each fixed glove from its nose to its trailing edge
GLOVE_Z = ZI(410)
GLOVE = [(0.92, 790), (W(207), 809), (W(282), 1129), (W(352), 1250), (W(427), 1369), (3.40, 1500), (2.30, 1700),
         (0.92, 1700)]

# Swing wing: measured fully swept, turned forward to 35 degrees about the pivot
WING_Z = GLOVE_Z
PIVOT = (2.72, Y(1330))
TURN = math.radians(-30)
SWEPT = {"root_x": 2.72, "root_le": Y(1276), "root_te": Y(1886), "tip_le": (W(697), Y(2069)), "tip_te": (W(622), Y(2229))}
WING_THICKNESS = 0.05
SLAT_CHORD, SLAT_SPAN = 0.14, (0.05, 1.0)
FLAP_HINGE, FLAP_SPAN = 0.78, (0.05, 0.80)


def turned(p):
    x, y, z = p
    px, py = PIVOT
    c, s = math.cos(TURN), math.sin(TURN)
    return (px + (x - px) * c + (y - py) * s, py - (x - px) * s + (y - py) * c, z)


STAB_ROOT_X, STAB_TIP_X = 2.0, W(600)
STAB_ROOT_LE, STAB_ROOT_TE = Y(1850), Y(2269)
STAB_TIP_LE, STAB_TIP_TE = Y(2204), Y(2314)
STAB_Z = ZI(478)
STAB_THICKNESS = 0.05

FIN_X, FIN_CANT = W(200), math.radians(5)
FIN_ROOT_Z, FIN_TIP_Z = ZI(385), ZI(90)
FIN_ROOT_LE, FIN_ROOT_TE = Y(1862), Y(2222)
FIN_TIP_LE, FIN_TIP_TE = Y(2172), Y(2317)
FIN_THICKNESS = 0.05
RUDDER_HINGE = 0.73
RUDDER_SPAN = (1.0, 3.0)

GROUND_Z = FIN_TIP_Z - 4.88  # published height
NOSE_WHEEL = {"at": (0, Y(560), GROUND_Z + 0.28), "radius": 0.28, "width": 0.16}
MAIN_WHEEL = {"at": (2.50, Y(1330), GROUND_Z + 0.48), "radius": 0.48, "width": 0.26}

TIP = turned((SWEPT["tip_le"][0], (SWEPT["tip_le"][1] + SWEPT["tip_te"][1]) / 2, WING_Z))

kit.HULL = {"size": [3.6, 1.9, 18.0], "at": [0, 0.3, -1.6]}
kit.HITBOXES = {
    "Cockpit": {"size": [1.0, 1.1, 3.4], "at": [0, 1.2, -6.0]},
    "Fuselage": {"size": [3.4, 1.6, 7.0], "at": [0, 0.3, -1.5]},
    "Engine": {"size": [3.4, 1.4, 6.0], "at": [0, 0.0, 4.0]},
    "WingL": {"size": [5.6, 0.4, 4.0], "at": [-5.0, round(WING_Z, 2), 0.4]},
    "WingR": {"size": [5.6, 0.4, 4.0], "at": [5.0, round(WING_Z, 2), 0.4]},
    "Tail": {"size": [9.0, 3.0, 4.0], "at": [0, 1.3, 6.6]},
}
EYE = (0, Y(640), 1.40)
kit.ATTACHMENTS = {
    "CockpitEye": EYE,
    "GunMuzzle": (-0.55, Y(380), -0.10),  # the M61's port on the left side of the nose
    "Nozzle1": (-NOZZLE_X, NOZZLE_Y1, NOZZLE_Z),
    "Nozzle2": (NOZZLE_X, NOZZLE_Y1, NOZZLE_Z),
    "WingtipL": (-TIP[0], TIP[1], TIP[2]),
    "WingtipR": (TIP[0], TIP[1], TIP[2]),
    "FlareDispenser": (0, Y(2150), 0.20),
    "ChaffDispenser": (0, Y(2100), 0.20),
    "ChaseCam": (0, -24.0, 4.4),
    "Hardpoint1": (-2.0, Y(1150), GLOVE_Z - 0.20),  # glove pylons
    "Hardpoint2": (2.0, Y(1150), GLOVE_Z - 0.20),
    "Hardpoint3": (-0.55, Y(1150), -0.20),  # under the centre body: Phoenix or Sparrow stations
    "Hardpoint4": (0.55, Y(1150), -0.20),
    "Hardpoint5": (-0.55, Y(1650), 0.05),
    "Hardpoint6": (0.55, Y(1650), 0.05),
    "Hardpoint7": (-2.3, Y(1150), GLOVE_Z - 0.35),  # the glove pylons' Sidewinder rails
    "Hardpoint8": (2.3, Y(1150), GLOVE_Z - 0.35),
}

# Cockpit interior (cockpit_kit.py, art pipeline §7), after F-14A front-cockpit photos: the HUD on the
# glareshield, the vertical display indicator in the middle with the horizontal situation display below
# it, flight instruments left and right, engine instruments far right. US grey and black.
kit.COCKPIT = {
    "well": {"back": Y(690), "front": Y(530), "half_width": 0.42, "floor": 0.45, "flange": 0.06},
    "panel": {"distance": 0.66, "top": -0.17, "bottom": -0.62, "tilt": 12, "half_width": 0.36},
    "coaming": {"overhang": 0.04, "length": 0.32, "drop": 0.06},
    "consoles": {"top": -0.53, "width": 0.11, "aft": -0.35, "fore": 0.42, "throttle": 0.02},
    "stick": "centre",
    "stick_fore": 0.40,
    "sight": "HUD",
    "palette": "US",
    "instruments": [
        {"name": "GMeter", "kind": "Dial", "u": -0.26, "v": 0.085, "size": 0.055, "live": "G"},
        {"name": "Airspeed", "kind": "Dial", "u": -0.165, "v": 0.08, "size": 0.07, "live": "Speed"},
        {"name": "VDI", "kind": "MFD", "u": 0.0, "v": 0.10, "size": 0.13, "live": "Radar"},
        {"name": "Altimeter", "kind": "Dial", "u": 0.165, "v": 0.08, "size": 0.07, "live": "Altitude"},
        {"name": "RPM", "kind": "Dial", "u": 0.26, "v": 0.085, "size": 0.055, "live": "RPM"},
        {"name": "AOA", "kind": "Dial", "u": -0.26, "v": 0.18, "size": 0.05},
        {"name": "VVI", "kind": "Dial", "u": -0.165, "v": 0.185, "size": 0.06},
        {"name": "EGT", "kind": "Dial", "u": 0.165, "v": 0.185, "size": 0.06},
        {"name": "RPM2", "kind": "Dial", "u": 0.26, "v": 0.18, "size": 0.05},
        {"name": "HSD", "kind": "MFD", "u": 0.0, "v": 0.28, "size": 0.11},
        {"name": "Fuel", "kind": "Dial", "u": -0.20, "v": 0.29, "size": 0.06},
        {"name": "Caution", "kind": "Lights", "u": 0.20, "v": 0.29, "size": 0.10},
    ],
}


# ---------------------------------------------------------------------------------------------------
# Builders
# ---------------------------------------------------------------------------------------------------


def nacelle_ring(side, xd, hw, zc, hh, scale=1.0, segments=20):
    pts = []
    for k in range(segments):
        ang = 2 * math.pi * k / segments
        c, s = math.cos(ang), math.sin(ang)
        x = side * NACELLE_X + hw * scale * math.copysign(abs(c) ** (2 / 3.5), c)
        z = zc + hh * scale * math.copysign(abs(s) ** (2 / 3.5), s)
        pts.append((x, Y(xd), z))
    return pts


def build_nacelles(col):
    parts, ducts = [], []
    for side in (1, -1):
        xd0, hw, zc, hh = NACELLE[0]
        rings = [nacelle_ring(side, xd0 + 20, hw, zc, hh, 0.86), nacelle_ring(side, xd0 + 1, hw, zc, hh, 0.92)]
        rings += [nacelle_ring(side, xd, w, z, h) for xd, w, z, h in NACELLE]
        parts.append(kit.lofted(rings, True, True))
        mouth = nacelle_ring(side, xd0 + 19, hw, zc, hh, 0.85)
        ducts.append(kit.lofted([mouth, nacelle_ring(side, xd0 + 18, hw, zc, hh, 0.85)], True, True))
    v, f = kit.merge(*parts)
    kit.make_object("Nacelles", v, f, col, "Body")
    v, f = kit.merge(*ducts)
    kit.make_object("IntakeDucts", v, f, col, "Body")


def build_gloves(col):
    parts = []
    th = 0.10
    for side in (1, -1):
        outline = [(side * hw, Y(xd)) for hw, xd in GLOVE]
        if side < 0:
            outline = list(reversed(outline))
        n = len(outline)
        top = [(x, y, GLOVE_Z + th / 2) for x, y in outline]
        bottom = [(x, y, GLOVE_Z - th / 2) for x, y in outline]
        centre_t = (sum(p[0] for p in top) / n, sum(p[1] for p in top) / n, GLOVE_Z + th / 2)
        centre_b = (centre_t[0], centre_t[1], GLOVE_Z - th / 2)
        verts = top + bottom + [centre_t, centre_b]
        faces = [(2 * n, i, (i + 1) % n) for i in range(n)]
        faces += [(2 * n + 1, n + (i + 1) % n, n + i) for i in range(n)]
        faces += [(i, n + i, n + (i + 1) % n, (i + 1) % n) for i in range(n)]
        parts.append((verts, faces))
    v, f = kit.merge(*parts)
    kit.make_object("Gloves", v, f, col, "Body")


def build_wings(col):
    up = (0, 0, 1)
    rl = (SWEPT["root_x"], SWEPT["root_le"], WING_Z)
    rt = (SWEPT["root_x"], SWEPT["root_te"], WING_Z)
    tl = (SWEPT["tip_le"][0], SWEPT["tip_le"][1], WING_Z)
    tt = (SWEPT["tip_te"][0], SWEPT["tip_te"][1], WING_Z)
    pivot = (PIVOT[0], PIVOT[1], WING_Z)

    def tv(v):
        return [turned(p) for p in v]

    for side, name in ((1, "R"), (-1, "L")):
        def m(v):
            return v if side > 0 else kit.mirror_x(v)

        def mf(f):
            return f if side > 0 else kit.flip_faces(f)

        geo = (rl, rt, tl, tt, up, WING_THICKNESS)
        box = [
            kit.panel(*geo, SLAT_CHORD, FLAP_HINGE, 0, 1, 8, 10),
            kit.panel(*geo, 0.0, SLAT_CHORD, 0, SLAT_SPAN[0], 1, 4),
            kit.panel(*geo, FLAP_HINGE, 1.0, 0, FLAP_SPAN[0], 1, 4),
            kit.panel(*geo, FLAP_HINGE, 1.0, FLAP_SPAN[1], 1, 2, 4),
        ]
        v, f = kit.merge(*box)
        kit.make_object(f"Wing{name}", m(tv(v)), mf(f), col, "Wings", origin=tuple(m([turned(pivot)])[0]))
        for part, (f0, f1), (s0, s1), lims, control in (
            ("LEFlap", (0.0, SLAT_CHORD), SLAT_SPAN, (0, 20), "LEFlap"),
            ("Flap", (FLAP_HINGE, 1.0), FLAP_SPAN, (0, 35), "Flap"),
        ):
            v, f = kit.panel(*geo, f0, f1, s0, s1, 6, 6)
            hinge_f = f1 if part == "LEFlap" else f0
            a, b = kit.hinge_line(rl, rt, tl, tt, hinge_f, s0, s1)
            a, b = Vector(turned(tuple(a))), Vector(turned(tuple(b)))
            kit.make_object(f"{part}{name}", m(tv(v)), mf(f), col, "Wings", "ControlSurface",
                            origin=tuple(m([tuple(a.lerp(b, 0.5))])[0]),
                            hinge={"axis": tuple(m([tuple(b - a)])[0]), "min": lims[0], "max": lims[1], "control": control})


def build_tail(col_wings, col_body):
    up = (0, 0, 1)
    root_le, root_te = (STAB_ROOT_X, STAB_ROOT_LE, STAB_Z), (STAB_ROOT_X, STAB_ROOT_TE, STAB_Z)
    tip_le, tip_te = (STAB_TIP_X, STAB_TIP_LE, STAB_Z), (STAB_TIP_X, STAB_TIP_TE, STAB_Z)
    pivot_y = STAB_ROOT_LE - (STAB_ROOT_LE - STAB_ROOT_TE) * 0.45
    for side, name in ((1, "R"), (-1, "L")):
        v, f = kit.panel(root_le, root_te, tip_le, tip_te, up, STAB_THICKNESS, 0.0, 1.0, 0, 1, 6, 10)
        if side < 0:
            v, f = kit.mirror_x(v), kit.flip_faces(f)
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

    parts = []
    outline = [(Y(1682), -0.50), (Y(1700), -1.10), (Y(1900), -0.98), (Y(1902), -0.45)]
    for side in (1, -1):
        x = side * NACELLE_X
        t = 0.025
        n = len(outline)
        fv = [(x - t, y, z) for y, z in outline] + [(x + t, y, z) for y, z in outline]
        ff = [tuple(range(n)), tuple(reversed(range(n, 2 * n)))] + [(i, n + i, n + (i + 1) % n, (i + 1) % n) for i in range(n)]
        parts.append((fv, ff))
    v, f = kit.merge(*parts)
    kit.make_object("VentralFins", v, f, col_body, "Body")


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
    v, f = kit.cylinder((0, Y(0), ZI(503)), (0, Y(45), ZI(503)), 0.02, 8)
    kit.make_object("Pitot", v, f, col, "Details")


def build_gear(col):
    nx, ny, nz = NOSE_WHEEL["at"]
    top = (0, ny + 0.10, ZI(548) + 0.05)
    v, f = kit.cylinder(top, (0, ny, nz + 0.12), 0.07, 10)
    kit.make_object("NoseGearStrut", v, f, col, "Details", "Gear", origin=top,
                    hinge={"axis": (1, 0, 0), "min": 0, "max": 95, "control": "Gear"})
    v, f = kit.wheel(NOSE_WHEEL["at"], NOSE_WHEEL["radius"], NOSE_WHEEL["width"])
    kit.make_object("NoseGearWheel", v, f, col, "Details", "GearWheel", origin=NOSE_WHEEL["at"],
                    hinge={"axis": (1, 0, 0), "min": -720, "max": 720, "control": "Wheel"})
    for side, name in ((1, "R"), (-1, "L")):
        v, f = kit.box((side * 0.18, ny + 0.1, ZI(548) - 0.12), (0.03, 0.8, 0.26))
        kit.make_object(f"NoseGearDoor{name}", v, f, col, "Details", "GearDoor", origin=(side * 0.16, ny + 0.1, ZI(548)),
                        hinge={"axis": (0, 1, 0), "min": 0, "max": 85, "control": "GearDoor"})
    mx, my, mz = MAIN_WHEEL["at"]
    for side, name in ((1, "R"), (-1, "L")):
        top = (side * 2.0, my + 0.15, GLOVE_Z - 0.05)
        v, f = kit.cylinder(top, (side * mx, my, mz + 0.12), 0.09, 10)
        kit.make_object(f"MainGearStrut{name}", v, f, col, "Details", "Gear", origin=top,
                        hinge={"axis": (0, 1, 0), "min": 0, "max": 90, "control": "Gear"})
        centre = (side * mx, my, mz)
        v, f = kit.wheel(centre, MAIN_WHEEL["radius"], MAIN_WHEEL["width"])
        kit.make_object(f"MainGearWheel{name}", v, f, col, "Details", "GearWheel", origin=centre,
                        hinge={"axis": (1, 0, 0), "min": -720, "max": 720, "control": "Wheel"})
        v, f = kit.box((side * 2.1, my, GLOVE_Z - 0.40), (0.04, 1.2, 0.60))
        kit.make_object(f"MainGearDoor{name}", v, f, col, "Details", "GearDoor", origin=(side * 2.08, my, GLOVE_Z - 0.10),
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
    build_gloves(cols["Body"])
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
