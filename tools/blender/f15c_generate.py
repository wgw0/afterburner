"""
Afterburner: F-15C Eagle base mesh generator (Blender 4.x / 5.x). Art only: the F-15C has no flight data
yet (AircraftData), so this makes the model, skins and cockpit for when it does.

Builds a mid-poly, modular F-15C at real-world size, measured from a reference drawing, in the same form as
the F-5E (f5e_generate.py, whose helpers this uses): separate objects per part, moving parts with their
origin on the hinge line, four texture sets, a manifest for the Studio assembler, an FBX, and the cockpit
well.

  * the forward fuselage with the radome and the high bubble canopy, running back as a central spine
    between the engines
  * the box intakes beside the cockpit, running back into the engine nacelles
  * the fixed leading-edge gloves, and the cropped-delta wing with flaps and ailerons
  * the tail booms beside the engines, carrying the all-moving tailerons (on the elevon controls) and the
    twin upright fins with rudders
  * twin nozzles with afterburner cones, ejection seat, side pitots, landing gear (struts, wheels, doors)

Run headless:
  blender -b --python tools/blender/f15c_generate.py -- --out <dir> --manifest-luau tools/Manifests/F15C.luau

Reference: the Commons drawing of the F-15A (Kaboldy, DraftSight SVG, CC BY-SA 4.0), rendered 3840 px wide
and mirrored nose left: side view on top and top view below, the radome tip at x = 73 in both. Stations (xd)
are pixels aft of it; heights are side-view rows (row 640, the nozzles' axis, is z = 0); half widths are
pixels from the top view's centreline (row 1853). The scale comes from the published 19.43 m length
(144.5 px/m); the span then comes out 13.07 m against the published 13.05 m. The F-15C's airframe is the
F-15A's. See docs/art/reference/F15C/SOURCES.md (kept out of git).
"""

import argparse
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import f5e_generate as kit  # noqa: E402  (shared helpers; its module settings are switched below)

kit.AIRFRAME = "F15C"
kit.REF_PX_PER_M = 144.5
kit.REF_PITOT_XD = 0.0
kit.REF_Z0_ROW = 640.0
kit.CG_FROM_PITOT = 1699 / 144.5  # 25% of the 4.46 m mean aerodynamic chord
kit.LENGTH = 19.43
kit.SPINE_UPPER_ONLY = True
Y, Z = kit.Y, kit.Z
PX = kit.REF_PX_PER_M


def W(px):
    return px / PX


# The forward fuselage, then the central body between the nacelles. Read as (xd, half width px, bottom row,
# shoulder row, top row, spine half width m, exponent); under the canopy the top is the cockpit sill.
_BODY = [
    (0, 0.5, 632, 628, 628, 0.0, 2.0),  # radome tip
    (50, 19, 645, 602, 602, 0.0, 2.0),
    (100, 35, 653, 577, 577, 0.0, 2.0),
    (200, 60, 667, 545, 545, 0.0, 2.1),
    (300, 75, 675, 520, 520, 0.0, 2.3),
    (400, 85, 677, 495, 495, 0.0, 2.5),
    (460, 89, 677, 478, 478, 0.0, 2.6),  # windscreen base
    (600, 93, 676, 477, 477, 0.0, 2.8),
    (800, 93, 674, 463, 463, 0.0, 3.0),
    (1000, 92, 676, 450, 450, 0.0, 3.0),
    (1060, 91, 678, 450, 430, 0.38, 3.0),  # the spine rises inside the canopy's rear
    (1150, 110, 682, 490, 432, 0.40, 3.4),
    (1300, 118, 683, 518, 468, 0.38, 3.6),
    (1500, 116, 683, 518, 497, 0.34, 3.6),
    (1800, 108, 683, 518, 510, 0.30, 3.6),
    (2100, 75, 680, 535, 535, 0.0, 3.2),
    (2300, 20, 670, 545, 545, 0.0, 2.4),
    (2500, 8, 650, 570, 570, 0.0, 2.2),  # tail end between the nozzles
]
kit.FUSELAGE = [(xd, W(hw), Z(zb), Z(zs), Z(zt), sp, e) for xd, hw, zb, zs, zt, sp, e in _BODY]
kit.FUSELAGE_RINGS = 52
kit.FUSELAGE_SEGMENTS = 36

kit.CANOPY = [
    (460, 0.10, Z(478)),
    (500, 0.30, Z(455)),
    (550, 0.40, Z(426)),
    (590, 0.45, Z(403)),  # windscreen bow
    (650, 0.47, Z(385)),
    (720, 0.47, Z(375)),
    (800, 0.46, Z(378)),
    (900, 0.43, Z(388)),
    (1000, 0.38, Z(405)),
    (1080, 0.30, Z(420)),
    (1120, 0.20, Z(428)),
]
kit.CANOPY_FRAMES = (590, 818)

# Nacelles: (xd, centre x m, half width m, centre z m, half height m), from the box intake mouth to the
# engines, which meet at the centreline. The intake lip is raked: its top at station 770, its bottom at 860.
NACELLE = [
    (860, 1.11, 0.36, 0.30, 0.57),
    (1000, 1.10, 0.41, 0.32, 0.61),
    (1300, 1.03, 0.48, 0.17, 0.63),
    (1800, 0.91, 0.56, 0.17, 0.63),
    (2100, 0.78, 0.62, 0.10, 0.52),
    (2300, 0.73, 0.60, 0.04, 0.38),
    (2420, 0.73, 0.45, -0.02, 0.36),
]
LIP_TOP, LIP_BOTTOM = 770, 860

# Gloves: the curved leading edge ahead of the wing root, (half width px, xd)
GLOVE_EDGE = [(212, 900), (219, 987), (232, 1080), (250, 1170), (268, 1250), (286, 1322)]
GLOVE_INNER = 1.30

WING_Z = Z(530)


def wing_le_y(x):
    return Y(1322 + (x * PX - 286) * 1.0046)


def wing_te_y(x):
    return Y(2150 + (x * PX - 210) * 0.110)


kit.WING_Z = WING_Z
kit.WING_ROOT_X, kit.WING_TIP_X = W(210), W(920)
kit.WING_ROOT_LE, kit.WING_ROOT_TE = wing_le_y(W(210)), wing_te_y(W(210))
kit.WING_SWEEP_LE = math.atan((wing_le_y(W(210)) - wing_le_y(W(920))) / (W(920) - W(210)))
kit.WING_TIP_CHORD = wing_le_y(W(920)) - wing_te_y(W(920))
kit.WING_THICKNESS = 0.05
kit.LE_FLAP_CHORD = 0.06  # the F-15 has fixed leading edges: a thin strip, as on the F-14's gloves
kit.TE_HINGE = 0.78
kit.TE_FLAP_SPAN = (1.55, 3.85)
kit.AILERON_SPAN = (3.95, 5.85)
kit.RAIL_Y = (wing_le_y(W(920)) + wing_te_y(W(920))) / 2
kit.RAIL_LENGTH = 0.9

# Tail booms beside the engines: (xd, half width m, half height m) at x = BOOM_X, centred at BOOM_Z
BOOM_X, BOOM_Z = W(248), 0.35
BOOM = [(1900, 0.10, 0.10), (2050, 0.25, 0.28), (2200, 0.30, 0.32), (2560, 0.28, 0.28), (2700, 0.12, 0.10)]

STAB_ROOT_X, STAB_TIP_X = W(282), W(620)
STAB_ROOT_LE, STAB_ROOT_TE = Y(2319), Y(2737)
STAB_TIP_LE, STAB_TIP_TE = Y(2650), Y(2819)
STAB_Z = Z(610)
STAB_THICKNESS = 0.045

FIN_X = W(258)
FIN_ROOT_Z, FIN_TIP_Z = Z(548), Z(100)
FIN_ROOT_LE, FIN_ROOT_TE = Y(2171), Y(2598)
FIN_TIP_LE, FIN_TIP_TE = Y(2491), Y(2623)
FIN_THICKNESS = 0.045
RUDDER_HINGE = 0.75
RUDDER_SPAN = (Z(510), Z(295))

NOZZLE_X, NOZZLE_Z, NOZZLE_R = 0.73, -0.02, 0.37
NOZZLE_Y0, NOZZLE_Y1 = Y(2410), Y(2594)

GROUND_Z = Z(80) - 5.63  # published height, from the top of the fin-tip pods
NOSE_WHEEL = {"at": (0, Y(918), GROUND_Z + 0.28), "radius": 0.28, "width": 0.16}
MAIN_WHEEL = {"at": (1.37, Y(1700), GROUND_Z + 0.42), "radius": 0.42, "width": 0.24}

kit.HULL = {"size": [3.2, 2.0, 17.8], "at": [0, 0.2, -1.8]}
kit.HITBOXES = {
    "Cockpit": {"size": [1.0, 1.1, 2.6], "at": [0, 1.45, -6.4]},
    "Fuselage": {"size": [3.0, 1.6, 7.5], "at": [0, 0.25, -1.6]},
    "Engine": {"size": [2.8, 1.2, 5.5], "at": [0, 0.0, 3.8]},
    "WingL": {"size": [4.8, 0.4, 4.0], "at": [-4.2, round(WING_Z, 2), 0.6]},
    "WingR": {"size": [4.8, 0.4, 4.0], "at": [4.2, round(WING_Z, 2), 0.6]},
    "Tail": {"size": [8.6, 3.4, 3.4], "at": [0, 1.5, 6.6]},
}
EYE = (0, Y(740), 1.52)
kit.ATTACHMENTS = {
    "CockpitEye": EYE,
    "GunMuzzle": (1.45, Y(1150), 0.80),  # M61 in the right wing root
    "Nozzle1": (-NOZZLE_X, NOZZLE_Y1, NOZZLE_Z),
    "Nozzle2": (NOZZLE_X, NOZZLE_Y1, NOZZLE_Z),
    "WingtipL": (-(kit.WING_TIP_X + 0.05), kit.RAIL_Y, WING_Z),
    "WingtipR": (kit.WING_TIP_X + 0.05, kit.RAIL_Y, WING_Z),
    "FlareDispenser": (-0.9, Y(2300), -0.35),
    "ChaffDispenser": (0.9, Y(2300), -0.35),
    "ChaseCam": (0, -22.5, 4.4),
    # Wing pylons, a missile rail each side
    "Hardpoint1": (-3.20, Y(1720), WING_Z - 0.30),
    "Hardpoint2": (3.20, Y(1720), WING_Z - 0.30),
    "Hardpoint3": (-2.65, Y(1720), WING_Z - 0.30),
    "Hardpoint4": (2.65, Y(1720), WING_Z - 0.30),
    # The four fuselage stations on the nacelles' lower corners
    "Hardpoint5": (-1.30, Y(1250), -0.40),
    "Hardpoint6": (1.30, Y(1250), -0.40),
    "Hardpoint7": (-1.25, Y(1950), -0.45),
    "Hardpoint8": (1.25, Y(1950), -0.45),
    "Hardpoint9": (0, Y(1600), -0.50),
}

# Cockpit interior (cockpit_kit.py, art pipeline §7), after F-15C cockpit photos: the head-up display on the
# glareshield, the radar display upper left, the attitude indicator in the middle, flight instruments
# round it, engine instruments and the threat display right. US grey, centre stick.
kit.COCKPIT = {
    "well": {"back": EYE[1] - 0.32, "front": EYE[1] + 0.76, "half_width": 0.40, "floor": EYE[2] - 1.00, "flange": 0.06},
    "panel": {"distance": 0.66, "top": -0.18, "bottom": -0.62, "tilt": 12, "half_width": 0.34},
    "coaming": {"overhang": 0.04, "length": 0.32, "drop": 0.06},
    "consoles": {"top": -0.52, "width": 0.12, "aft": -0.35, "fore": 0.42, "throttle": 0.02},
    "stick": "centre",
    "stick_fore": 0.40,
    "sight": "HUD",
    "palette": "US",
    "instruments": [
        {"name": "RadarScope", "kind": "MFD", "u": -0.225, "v": 0.095, "size": 0.10, "live": "Radar"},
        {"name": "Airspeed", "kind": "Dial", "u": -0.11, "v": 0.075, "size": 0.07, "live": "Speed"},
        {"name": "Armament", "kind": "Lights", "u": 0.0, "v": 0.085, "size": 0.12},
        {"name": "Altimeter", "kind": "Dial", "u": 0.11, "v": 0.075, "size": 0.07, "live": "Altitude"},
        {"name": "TEWS", "kind": "Scope", "u": 0.225, "v": 0.09, "size": 0.075},
        {"name": "GMeter", "kind": "Dial", "u": -0.11, "v": 0.18, "size": 0.06, "live": "G"},
        {"name": "ADI", "kind": "Dial", "u": 0.0, "v": 0.19, "size": 0.10, "face": "attitude"},
        {"name": "VVI", "kind": "Dial", "u": 0.11, "v": 0.18, "size": 0.06},
        {"name": "RPM", "kind": "Dial", "u": 0.225, "v": 0.205, "size": 0.06, "live": "RPM"},
        {"name": "AOA", "kind": "Dial", "u": -0.225, "v": 0.215, "size": 0.05},
        {"name": "Clock", "kind": "Dial", "u": -0.11, "v": 0.285, "size": 0.05},
        {"name": "HSI", "kind": "Dial", "u": 0.0, "v": 0.30, "size": 0.09, "face": "compass"},
        {"name": "Fuel", "kind": "Dial", "u": 0.225, "v": 0.30, "size": 0.05},
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


def build_nacelles(col):
    parts, ducts = [], []
    xd0, cx0, hw0, zc0, hh0 = NACELLE[0]

    def lip(z):
        return Y(kit.lerp(LIP_TOP, LIP_BOTTOM, (zc0 + hh0 - z) / (2 * hh0)))

    for side in (1, -1):
        rings = [rounded_ring(side * cx0, lip, hw0 * 0.86, zc0, hh0 * 0.90), rounded_ring(side * cx0, lip, hw0, zc0, hh0)]
        for xd, cx, hw, zc, hh in NACELLE:
            rings.append(rounded_ring(side * cx, lambda z, xd=xd: Y(xd), hw, zc, hh))
        # The mouth is recessed: the first ring sits inside and behind the lip
        rings[0] = [(p[0], p[1] - 0.20, p[2]) for p in rings[0]]
        parts.append(kit.lofted(rings, True, True))
        mouth = [(p[0], p[1] + 0.01, p[2]) for p in rings[0]]
        ducts.append(kit.lofted([mouth, [(p[0], p[1] + 0.01, p[2]) for p in mouth]], True, True))
    v, f = kit.merge(*parts)
    kit.make_object("Nacelles", v, f, col, "Body")
    v, f = kit.merge(*ducts)
    kit.make_object("IntakeDucts", v, f, col, "Body")


def build_gloves_and_booms(col):
    """The fixed leading-edge gloves ahead of the wing roots, and the tail booms carrying the tail."""
    parts = []
    z, th = WING_Z, 0.04
    for side in (1, -1):
        top, bottom, edge = [], [], []
        for hw, xd in GLOVE_EDGE:
            y = Y(xd)
            top.append((side * GLOVE_INNER, y, z + th))
            bottom.append((side * GLOVE_INNER, y, z - th))
            edge.append((side * W(hw), y, z))
        n = len(edge)
        verts = top + bottom + edge
        faces = []
        for i in range(n - 1):
            faces.append((i, i + 1, 2 * n + i + 1, 2 * n + i))
            faces.append((n + i, 2 * n + i, 2 * n + i + 1, n + i + 1))
            faces.append((i, n + i, n + i + 1, i + 1))
        faces.append((0, 2 * n, n))
        faces.append((n - 1, 2 * n - 1, 3 * n - 1))
        if side < 0:
            faces = kit.flip_faces(faces)
        parts.append((verts, faces))
        rings = [rounded_ring(side * BOOM_X, lambda _z, xd=xd: Y(xd), hw, BOOM_Z, hh, 2.6, 16) for xd, hw, hh in BOOM]
        parts.append(kit.lofted(rings, True, True))
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

    def frac(z):
        return (z - FIN_ROOT_Z) / h

    for side, name in ((1, "R"), (-1, "L")):
        x = side * FIN_X
        normal = (side, 0, 0)
        g = ((x, FIN_ROOT_LE, FIN_ROOT_Z), (x, FIN_ROOT_TE, FIN_ROOT_Z), (x, FIN_TIP_LE, FIN_TIP_Z),
             (x, FIN_TIP_TE, FIN_TIP_Z), normal, FIN_THICKNESS)
        fin = [
            kit.panel(*g, 0.0, RUDDER_HINGE, 0, 1, 8, 10),
            kit.panel(*g, RUDDER_HINGE, 1.0, 0, frac(RUDDER_SPAN[0]), 1, 4),
            kit.panel(*g, RUDDER_HINGE, 1.0, frac(RUDDER_SPAN[1]), 1, 2, 4),
            # The pod on each fin tip
            kit.cylinder((x, Y(2470), FIN_TIP_Z + 0.06), (x, Y(2645), FIN_TIP_Z + 0.06), 0.07, 8, radius1=0.05),
        ]
        v, f = kit.merge(*fin)
        kit.make_object(f"Fin{name}", v, f, col_body, "Body")
        v, f = kit.panel(*g, RUDDER_HINGE, 1.0, frac(RUDDER_SPAN[0]), frac(RUDDER_SPAN[1]), 6, 6)
        a, b = kit.hinge_line(*g[:4], RUDDER_HINGE, frac(RUDDER_SPAN[0]), frac(RUDDER_SPAN[1]))
        kit.make_object(f"Rudder{name}", v, f, col_body, "Body", "ControlSurface", origin=tuple(a.lerp(b, 0.5)),
                        hinge={"axis": tuple(b - a), "min": -25, "max": 25, "control": "Rudder"})


def build_engines(col):
    for side, name in ((1, "R"), (-1, "L")):
        x = side * NOZZLE_X
        p0, p1 = (x, NOZZLE_Y0, NOZZLE_Z), (x, NOZZLE_Y1, NOZZLE_Z)
        nv, nf = kit.cylinder(p0, p1, NOZZLE_R - 0.04, 20, radius1=NOZZLE_R, caps=False)
        iv, i_f = kit.cylinder(p0, p1, NOZZLE_R - 0.07, 20, radius1=NOZZLE_R - 0.035, caps=False)
        n = 20
        lip = [(n + i, n + (i + 1) % n, len(nv) + n + (i + 1) % n, len(nv) + n + i) for i in range(n)]
        verts, faces = kit.merge((nv, nf), (iv, kit.flip_faces(i_f)))
        kit.make_object(f"Nozzle{name}", verts, faces + lip, col, "Details", "Nozzle", extra={"engine": name})
        cv, cf = kit.cylinder((x, NOZZLE_Y1 + 0.15, NOZZLE_Z), (x, NOZZLE_Y0 + 0.05, NOZZLE_Z), NOZZLE_R - 0.10, 16,
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
    """The two pitot probes on the sides of the nose (the F-15 has none on the radome)."""
    parts = []
    for side in (1, -1):
        parts.append(kit.cylinder((side * W(70), Y(425), Z(630)), (side * W(84), Y(475), Z(630)), 0.02, 8))
    v, f = kit.merge(*parts)
    kit.make_object("Pitot", v, f, col, "Details")


def build_gear(col):
    nx, ny, nz = NOSE_WHEEL["at"]
    belly = Z(676)
    top = (0, ny + 0.10, belly + 0.08)
    v, f = kit.cylinder(top, (0, ny, nz + 0.12), 0.07, 10)
    kit.make_object("NoseGearStrut", v, f, col, "Details", "Gear", origin=top,
                    hinge={"axis": (1, 0, 0), "min": 0, "max": 95, "control": "Gear"})
    v, f = kit.wheel(NOSE_WHEEL["at"], NOSE_WHEEL["radius"], NOSE_WHEEL["width"])
    kit.make_object("NoseGearWheel", v, f, col, "Details", "GearWheel", origin=NOSE_WHEEL["at"],
                    hinge={"axis": (1, 0, 0), "min": -720, "max": 720, "control": "Wheel"})
    for side, name in ((1, "R"), (-1, "L")):
        v, f = kit.box((side * 0.18, ny + 0.1, belly - 0.13), (0.03, 0.8, 0.26))
        kit.make_object(f"NoseGearDoor{name}", v, f, col, "Details", "GearDoor", origin=(side * 0.16, ny + 0.1, belly),
                        hinge={"axis": (0, 1, 0), "min": 0, "max": 85, "control": "GearDoor"})
    mx, my, mz = MAIN_WHEEL["at"]
    for side, name in ((1, "R"), (-1, "L")):
        top = (side * 1.15, my + 0.15, -0.30)
        v, f = kit.cylinder(top, (side * mx, my, mz + 0.10), 0.08, 10)
        kit.make_object(f"MainGearStrut{name}", v, f, col, "Details", "Gear", origin=top,
                        hinge={"axis": (0, 1, 0), "min": 0, "max": 90, "control": "Gear"})
        centre = (side * mx, my, mz)
        v, f = kit.wheel(centre, MAIN_WHEEL["radius"], MAIN_WHEEL["width"])
        kit.make_object(f"MainGearWheel{name}", v, f, col, "Details", "GearWheel", origin=centre,
                        hinge={"axis": (1, 0, 0), "min": -720, "max": 720, "control": "Wheel"})
        v, f = kit.box((side * 1.00, my, -0.72), (0.04, 1.0, 0.50))
        kit.make_object(f"MainGearDoor{name}", v, f, col, "Details", "GearDoor", origin=(side * 1.00, my, -0.47),
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
    build_gloves_and_booms(cols["Body"])
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
