"""
Afterburner: F-22A Raptor base mesh generator (Blender 4.x / 5.x). Art only: the F-22A has no flight data yet
(AircraftData), so this makes the model, skins and cockpit for when it does.

Builds a mid-poly, modular F-22A at real-world size, measured from a reference drawing, in the same form as the
F-5E (f5e_generate.py, whose helpers this uses): separate objects per part, moving parts with their origin on
the hinge line, four texture sets, a manifest for the Studio assembler, an FBX, and the cockpit well.

  * the chined forebody with the radome and the frameless bubble canopy, and the wide, flat centre body
  * the raked caret intakes either side of the cockpit, running back to the engines
  * the chines from the intakes to the wing roots
  * the diamond wing (swept leading edge, forward-swept trailing edge) with leading-edge flaps, flaperons and
    ailerons, and the tailerons on the elevon controls
  * twin fins canted out 28 degrees with rudders, twin nozzles with afterburner cones, ejection seat, landing
    gear (struts, wheels, doors)

Run headless:
  blender -b --python tools/blender/f22a_generate.py -- --out <dir> --manifest-luau tools/Manifests/F22A.luau

Reference: the Commons three-view "Lockheed Martin F-22A Raptor 3-view.png" (ZakuTalk, CC BY-SA 2.0), 2048 px
wide, rebuilt as a composite 2000 px wide: its side view on top and its top view below, both nose left with
the nose tip at x = 95. The drawing's two views are not at quite the same scale (the side view is 2.2%
shorter), so stations and half widths are the top view's (pixels aft of the nose tip, and from its
centreline, row 1135.5), and side-view readings go through side() and side_z(), which scale them by 1.022.
Side-view row 322 (the nozzles' axis) is z = 0. The scale comes from the published 18.92 m length
(95.8 px/m), which gives a 13.8 m span against the published 13.56 m. See
docs/art/reference/F22A/SOURCES.md (kept out of git).
"""

import argparse
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import f5e_generate as kit  # noqa: E402  (shared helpers; its module settings are switched below)

kit.AIRFRAME = "F22A"
kit.REF_PX_PER_M = 95.8
kit.REF_PITOT_XD = 0.0
kit.REF_Z0_ROW = 322.0
kit.CG_FROM_PITOT = 1069 / 95.8  # 25% of the 4.31 m mean aerodynamic chord
kit.LENGTH = 18.92
kit.SPINE_UPPER_ONLY = True
Y = kit.Y
PX = kit.REF_PX_PER_M
SIDE = 1.022  # the side view's scale relative to the top view's


def W(px):
    return px / PX


def side(xd):
    """A side-view station as a top-view station."""
    return xd * SIDE


def Z(row):
    """Height from a side-view row."""
    return (322 - row) * SIDE / PX


# (side xd, half width px (top view), bottom row, shoulder row, top row, spine half width m, exponent). The
# forebody is chined (a wide, flat section); under the canopy the top is the sill, behind it the wide, flat
# centre body bridges the intakes with the spine on top.
_BODY = [
    (0, 0.5, 345, 341, 341, 0.0, 2.0),  # radome tip
    (100, 47, 380, 330, 300, 0.0, 1.6),
    (200, 70, 395, 330, 268, 0.0, 1.6),
    (250, 74, 398, 330, 255, 0.0, 1.7),  # windscreen base
    (350, 80, 400, 300, 250, 0.0, 2.0),
    (500, 95, 402, 300, 240, 0.0, 2.4),
    (560, 120, 404, 300, 228, 0.42, 2.8),  # the spine rises inside the canopy's rear
    (700, 165, 405, 300, 245, 0.55, 3.4),
    (800, 185, 405, 300, 250, 0.58, 3.6),
    (1000, 195, 405, 300, 255, 0.58, 3.6),
    (1200, 190, 400, 300, 258, 0.55, 3.6),
    (1300, 170, 395, 300, 270, 0.48, 3.4),
    (1400, 145, 380, 300, 285, 0.30, 3.0),
    (1470, 125, 362, 300, 296, 0.0, 2.8),  # nozzles start
]
kit.FUSELAGE = [(side(xd), W(hw), Z(zb), Z(zs), Z(zt), sp, e) for xd, hw, zb, zs, zt, sp, e in _BODY]
kit.FUSELAGE_RINGS = 52
kit.FUSELAGE_SEGMENTS = 36

kit.CANOPY = [
    (side(xd), w, Z(row)) for xd, w, row in (
        (250, 0.10, 255), (300, 0.35, 225), (350, 0.45, 205), (400, 0.48, 196), (450, 0.48, 196),
        (500, 0.42, 205), (540, 0.28, 218), (570, 0.12, 225),
    )
]
kit.CANOPY_FRAMES = (side(525),)  # frameless bubble: only the frame behind the seat

# Intakes: (xd, centre x m, half width m, centre z m, half height m), from the raked caret mouth (its top at
# side station 460, its bottom at 590) back to the engines
NACELLE = [
    (side(600), 1.48, 0.50, Z(355), 0.46),
    (800, 1.45, 0.55, Z(358), 0.50),
    (1000, 1.30, 0.62, Z(360), 0.48),
    (1200, 1.10, 0.62, Z(355), 0.45),
    (1400, 0.90, 0.55, Z(345), 0.40),
    (side(1470), 0.78, 0.48, Z(330), 0.38),
]
LIP_TOP, LIP_BOTTOM = side(460), side(590)

WING_Z = Z(305)

# Chines: (half width px, xd) from the intakes to the wing's leading edge, and back along the wing root
LERX_EDGE = [(190, 540), (200, 650), (215, 750), (235, 830), (246, 858)]
LERX_INNER = 1.10
LERX_Z0 = WING_Z
LERX_TE = (205, 1500)


def wing_le_y(x):
    return Y(858 + (x * PX - 246) * 0.852)


def wing_te_y(x):
    return Y(1513 - (x * PX - 200) * 0.31)


kit.WING_Z = WING_Z
kit.WING_ROOT_X, kit.WING_TIP_X = W(200), W(640)
kit.WING_ROOT_LE, kit.WING_ROOT_TE = wing_le_y(W(200)), wing_te_y(W(200))
kit.WING_SWEEP_LE = math.atan((wing_le_y(W(200)) - wing_le_y(W(640))) / (W(640) - W(200)))
kit.WING_TIP_CHORD = wing_le_y(W(640)) - wing_te_y(W(640))
kit.WING_THICKNESS = 0.04
kit.LE_FLAP_CHORD = 0.14
kit.TE_HINGE = 0.80
kit.TE_FLAP_SPAN = (2.20, 4.40)  # flaperons
kit.AILERON_SPAN = (4.45, 6.40)
kit.RAIL_Y = (wing_le_y(W(640)) + wing_te_y(W(640))) / 2
kit.RAIL_LENGTH = 0.5

STAB_ROOT_X, STAB_TIP_X = W(130), W(433)
STAB_ROOT_LE, STAB_ROOT_TE = Y(1525), Y(1720)
STAB_TIP_LE, STAB_TIP_TE = Y(1645), Y(1763)
STAB_Z = Z(305)
STAB_THICKNESS = 0.04

FIN_X, FIN_CANT = W(150), math.radians(28)
FIN_ROOT_Z, FIN_TIP_Z = Z(292), Z(31)
FIN_ROOT_LE, FIN_ROOT_TE = Y(side(1247)), Y(side(1638))
FIN_TIP_LE, FIN_TIP_TE = Y(side(1367)), Y(side(1418))
FIN_THICKNESS = 0.045
RUDDER_HINGE = 0.72
RUDDER_SPAN = (Z(285), Z(150))

NOZZLE_X, NOZZLE_Z = W(70), 0.0
NOZZLE_R0, NOZZLE_R1 = 0.42, 0.38
NOZZLE_Y0, NOZZLE_Y1 = Y(side(1480)), Y(side(1590))

GROUND_Z = FIN_TIP_Z - 5.08  # published height
NOSE_WHEEL = {"at": (0, Y(531), GROUND_Z + 0.30), "radius": 0.30, "width": 0.16}
MAIN_WHEEL = {"at": (1.65, Y(1110), GROUND_Z + 0.45), "radius": 0.45, "width": 0.24}
BELLY_Z = Z(402)
PITOT = (40, 160, 200, 335)  # (half width px, xd from, xd to, side row): the probes on the chines

kit.HULL = {"size": [3.6, 2.0, 18.0], "at": [0, 0.1, -1.2]}
kit.HITBOXES = {
    "Cockpit": {"size": [1.0, 1.1, 2.6], "at": [0, 1.2, -6.4]},
    "Fuselage": {"size": [3.6, 1.6, 7.5], "at": [0, 0.0, -1.0]},
    "Engine": {"size": [2.8, 1.2, 5.0], "at": [0, 0.0, 4.4]},
    "WingL": {"size": [4.8, 0.4, 5.0], "at": [-4.2, round(WING_Z, 2), 1.6]},
    "WingR": {"size": [4.8, 0.4, 5.0], "at": [4.2, round(WING_Z, 2), 1.6]},
    "Tail": {"size": [9.0, 3.0, 4.0], "at": [0, 1.4, 6.2]},
}
EYE = (0, Y(side(420)), Z(196) - 0.27)
kit.ATTACHMENTS = {
    "CockpitEye": EYE,
    "GunMuzzle": (1.45, Y(780), Z(300)),  # the M61 in the right wing root
    "Nozzle1": (-NOZZLE_X, NOZZLE_Y1, NOZZLE_Z),
    "Nozzle2": (NOZZLE_X, NOZZLE_Y1, NOZZLE_Z),
    "WingtipL": (-(kit.WING_TIP_X + 0.05), kit.RAIL_Y, WING_Z),
    "WingtipR": (kit.WING_TIP_X + 0.05, kit.RAIL_Y, WING_Z),
    "FlareDispenser": (-0.8, Y(1350), Z(395)),
    "ChaffDispenser": (0.8, Y(1350), Z(395)),
    "ChaseCam": (0, -22.0, 4.2),
    # The main weapons bay (three a side) and the two side bays in the intakes
    "Hardpoint1": (-0.35, Y(800), BELLY_Z - 0.15),
    "Hardpoint2": (0.35, Y(800), BELLY_Z - 0.15),
    "Hardpoint3": (-0.75, Y(850), BELLY_Z - 0.15),
    "Hardpoint4": (0.75, Y(850), BELLY_Z - 0.15),
    "Hardpoint5": (-0.35, Y(950), BELLY_Z - 0.15),
    "Hardpoint6": (0.35, Y(950), BELLY_Z - 0.15),
    "Hardpoint7": (-1.95, Y(700), Z(380)),
    "Hardpoint8": (1.95, Y(700), Z(380)),
}

# Cockpit interior (cockpit_kit.py, art pipeline §7), after F-22 cockpit photos: the wide head-up display over
# the up-front controls, the large square primary display in the middle (the radar face) between two smaller
# displays, and two more below. Charcoal, side stick.
kit.COCKPIT = {
    "well": {"back": EYE[1] - 0.32, "front": EYE[1] + 0.74, "half_width": 0.40, "floor": EYE[2] - 1.00, "flange": 0.06},
    "panel": {"distance": 0.65, "top": -0.18, "bottom": -0.62, "tilt": 12, "half_width": 0.34},
    "coaming": {"overhang": 0.04, "length": 0.30, "drop": 0.06},
    "consoles": {"top": -0.50, "width": 0.12, "aft": -0.35, "fore": 0.42, "throttle": 0.02},
    "stick": "side",
    "sight": "HUD",
    "palette": "Modern",
    "instruments": [
        {"name": "UFC", "kind": "Lights", "u": 0.0, "v": 0.075, "size": 0.10},
        {"name": "LeftMFD", "kind": "MFD", "u": -0.22, "v": 0.12, "size": 0.10},
        {"name": "RadarScope", "kind": "MFD", "u": 0.0, "v": 0.20, "size": 0.15, "live": "Radar"},
        {"name": "RightMFD", "kind": "MFD", "u": 0.22, "v": 0.12, "size": 0.10},
        {"name": "Airspeed", "kind": "Dial", "u": -0.25, "v": 0.235, "size": 0.045, "live": "Speed"},
        {"name": "Altimeter", "kind": "Dial", "u": -0.17, "v": 0.235, "size": 0.045, "live": "Altitude"},
        {"name": "GMeter", "kind": "Dial", "u": 0.17, "v": 0.235, "size": 0.045, "live": "G"},
        {"name": "RPM", "kind": "Dial", "u": 0.25, "v": 0.235, "size": 0.045, "live": "RPM"},
        {"name": "ADI", "kind": "Dial", "u": -0.21, "v": 0.30, "size": 0.05, "face": "attitude"},
    ],
}


# ---------------------------------------------------------------------------------------------------
# Builders
# ---------------------------------------------------------------------------------------------------


def rounded_ring(cx, y_of, hw, zc, hh, e=3.2, segments=20):
    """A rounded-box section centred at (cx, zc); y_of(z) gives the station at each height."""
    pts = []
    for k in range(segments):
        ang = 2 * math.pi * k / segments
        c, s = math.cos(ang), math.sin(ang)
        x = cx + hw * math.copysign(abs(c) ** (2 / e), c)
        z = zc + hh * math.copysign(abs(s) ** (2 / e), s)
        pts.append((x, y_of(z), z))
    return pts


def build_intakes(col):
    parts, ducts = [], []
    xd0, cx0, hw0, zc0, hh0 = NACELLE[0]

    def lip(z):
        return Y(kit.lerp(LIP_TOP, LIP_BOTTOM, (zc0 + hh0 - z) / (2 * hh0)))

    for side in (1, -1):
        rings = [rounded_ring(side * cx0, lip, hw0 * 0.82, zc0, hh0 * 0.88, 2.6),
                 rounded_ring(side * cx0, lip, hw0, zc0, hh0, 2.6)]
        for xd, cx, hw, zc, hh in NACELLE:
            rings.append(rounded_ring(side * cx, lambda z, xd=xd: Y(xd), hw, zc, hh, 2.6))
        # The mouth is recessed: the first ring sits inside and behind the lip
        rings[0] = [(p[0], p[1] - 0.18, p[2]) for p in rings[0]]
        parts.append(kit.lofted(rings, True, True))
        mouth = [(p[0], p[1] + 0.01, p[2]) for p in rings[0]]
        ducts.append(kit.lofted([mouth, [(p[0], p[1] + 0.01, p[2]) for p in mouth]], True, True))
    v, f = kit.merge(*parts)
    kit.make_object("Nacelles", v, f, col, "Body")
    v, f = kit.merge(*ducts)
    kit.make_object("IntakeDucts", v, f, col, "Body")


def build_lerx(col):
    """The chines: thin plates from the intakes out to the wing roots, and back along them."""
    parts = []
    th = 0.04
    x0, x1 = LERX_EDGE[0][1], LERX_EDGE[-1][1]
    for side in (1, -1):
        top, bottom, edge = [], [], []
        for hw, xd in LERX_EDGE:
            y = Y(xd)
            z = kit.lerp(LERX_Z0, WING_Z, (xd - x0) / (x1 - x0))
            top.append((side * LERX_INNER, y, z + th))
            bottom.append((side * LERX_INNER, y, z - th))
            edge.append((side * W(hw), y, z))
        # Carried back over the wing root to the trailing edge, inside the wing
        y_te = Y(LERX_TE[1])
        top.append((side * LERX_INNER, y_te, WING_Z + th))
        bottom.append((side * LERX_INNER, y_te, WING_Z - th))
        edge.append((side * W(LERX_TE[0]), y_te, WING_Z))
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
    v, f = kit.merge(*parts)
    kit.make_object("Strakes", v, f, col, "Body")


def build_tail(col_wings, col_body):
    up = (0, 0, 1)
    root_le, root_te = (STAB_ROOT_X, STAB_ROOT_LE, STAB_Z), (STAB_ROOT_X, STAB_ROOT_TE, STAB_Z)
    tip_le, tip_te = (STAB_TIP_X, STAB_TIP_LE, STAB_Z), (STAB_TIP_X, STAB_TIP_TE, STAB_Z)
    pivot_y = STAB_ROOT_LE - (STAB_ROOT_LE - STAB_ROOT_TE) * 0.45
    for side, name in ((1, "R"), (-1, "L")):
        v, f = kit.panel(root_le, root_te, tip_le, tip_te, up, STAB_THICKNESS, 0.0, 1.0, 0, 1, 6, 10)
        if side < 0:
            v, f = kit.mirror_x(v), kit.flip_faces(f)
        # Pitch and roll mixed (tailerons), with the ailerons
        kit.make_object(f"Stabilator{name}", v, f, col_wings, "Wings", "ControlSurface",
                        origin=(side * STAB_ROOT_X, pivot_y, STAB_Z),
                        hinge={"axis": (1, 0, 0), "min": -24, "max": 10, "control": "Elevon" + name})

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
                        hinge={"axis": tuple(b - a), "min": -30, "max": 30, "control": "Rudder"})


def build_engines(col):
    for side, name in ((1, "R"), (-1, "L")):
        x = side * NOZZLE_X
        p0, p1 = (x, NOZZLE_Y0, NOZZLE_Z), (x, NOZZLE_Y1, NOZZLE_Z)
        nv, nf = kit.cylinder(p0, p1, NOZZLE_R0, 20, radius1=NOZZLE_R1, caps=False)
        iv, i_f = kit.cylinder(p0, p1, NOZZLE_R0 - 0.035, 20, radius1=NOZZLE_R1 - 0.03, caps=False)
        n = 20
        lip = [(n + i, n + (i + 1) % n, len(nv) + n + (i + 1) % n, len(nv) + n + i) for i in range(n)]
        verts, faces = kit.merge((nv, nf), (iv, kit.flip_faces(i_f)))
        kit.make_object(f"Nozzle{name}", verts, faces + lip, col, "Details", "Nozzle", extra={"engine": name})
        cv, cf = kit.cylinder((x, NOZZLE_Y1 + 0.15, NOZZLE_Z), (x, NOZZLE_Y0 + 0.05, NOZZLE_Z), NOZZLE_R1 - 0.05, 16,
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
    """The two pitot probes on the sides of the nose, ahead of the windscreen."""
    parts = []
    for s in (1, -1):
        hw, x0, x1, row = PITOT
        parts.append(kit.cylinder((s * W(hw), Y(x0), Z(row)), (s * W(hw + 8), Y(x1), Z(row)), 0.018, 8))
    v, f = kit.merge(*parts)
    kit.make_object("Pitot", v, f, col, "Details")


def build_gear(col):
    nx, ny, nz = NOSE_WHEEL["at"]
    belly = BELLY_Z
    top = (0, ny + 0.10, belly + 0.08)
    v, f = kit.cylinder(top, (0, ny, nz + 0.12), 0.07, 10)
    kit.make_object("NoseGearStrut", v, f, col, "Details", "Gear", origin=top,
                    hinge={"axis": (1, 0, 0), "min": 0, "max": 95, "control": "Gear"})
    v, f = kit.wheel(NOSE_WHEEL["at"], NOSE_WHEEL["radius"], NOSE_WHEEL["width"])
    kit.make_object("NoseGearWheel", v, f, col, "Details", "GearWheel", origin=NOSE_WHEEL["at"],
                    hinge={"axis": (1, 0, 0), "min": -720, "max": 720, "control": "Wheel"})
    for side, name in ((1, "R"), (-1, "L")):
        v, f = kit.box((side * 0.16, ny + 0.1, belly - 0.13), (0.03, 0.8, 0.26))
        kit.make_object(f"NoseGearDoor{name}", v, f, col, "Details", "GearDoor", origin=(side * 0.14, ny + 0.1, belly),
                        hinge={"axis": (0, 1, 0), "min": 0, "max": 85, "control": "GearDoor"})
    mx, my, mz = MAIN_WHEEL["at"]
    for side, name in ((1, "R"), (-1, "L")):
        top = (side * 1.20, my + 0.30, BELLY_Z)
        v, f = kit.cylinder(top, (side * mx, my, mz + 0.10), 0.08, 10)
        kit.make_object(f"MainGearStrut{name}", v, f, col, "Details", "Gear", origin=top,
                        hinge={"axis": (0, 1, 0), "min": 0, "max": 90, "control": "Gear"})
        centre = (side * mx, my, mz)
        v, f = kit.wheel(centre, MAIN_WHEEL["radius"], MAIN_WHEEL["width"])
        kit.make_object(f"MainGearWheel{name}", v, f, col, "Details", "GearWheel", origin=centre,
                        hinge={"axis": (1, 0, 0), "min": -720, "max": 720, "control": "Wheel"})
        v, f = kit.box((side * 1.30, my, BELLY_Z - 0.30), (0.04, 0.9, 0.50))
        kit.make_object(f"MainGearDoor{name}", v, f, col, "Details", "GearDoor", origin=(side * 1.30, my, BELLY_Z - 0.05),
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
    build_intakes(cols["Body"])
    build_lerx(cols["Body"])
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
