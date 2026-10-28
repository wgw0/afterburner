"""
Afterburner: Su-27S Flanker base mesh generator (Blender 4.x / 5.x). Art only: the Su-27S has no flight
data yet (AircraftData), so this makes the model, skins and cockpit for when it does.

Builds a mid-poly, modular Su-27S at real-world size, measured from a reference drawing, in the same form as
the F-5E (f5e_generate.py, whose helpers this uses): separate objects per part, moving parts with their
origin on the hinge line, four texture sets, a manifest for the Studio assembler, an FBX, and the cockpit
well.

  * the long drooped nose with the radome and the bubble canopy, running back as the dorsal hump and the
    wide, flat centre body over the engines, ending in the tail sting
  * the separated engine nacelles under the body, with their raked box intakes
  * the long leading-edge extensions blending into the wing, and the tail booms beside the engines
  * the swept wing with leading-edge flaps, flaps and ailerons, and wingtip launch rails
  * all-moving tailerons on the elevon controls and twin upright fins with rudders, on the booms
  * twin nozzles with afterburner cones, ejection seat, nose probe, landing gear (struts, wheels, doors)

Run headless:
  blender -b --python tools/blender/su27s_generate.py -- --out <dir> --manifest-luau tools/Manifests/Su27S.luau

Reference: the Commons three-view "Sukhoi Su-27 3-view line drawing.svg" (Malyszkz, public domain), rendered
3840 px wide and rebuilt as a composite 2000 px wide: side view on top (nose left), top view below (turned
nose left), the radome tip at x = 52.4 in both. Stations (xd) are composite pixels aft of it; heights are
side-view rows (row 370, the nozzles' axis, is z = 0); half widths are pixels from the top view's centreline
(row 1133). Both views come out at the same scale: 86.0 px/m, which gives the length 22.0 m against the
published 21.94 m. See docs/art/reference/Su27S/SOURCES.md (kept out of git).
"""

import argparse
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import f5e_generate as kit  # noqa: E402  (shared helpers; its module settings are switched below)

kit.AIRFRAME = "Su27S"
kit.REF_PX_PER_M = 86.0
kit.REF_PITOT_XD = 0.0
kit.REF_Z0_ROW = 370.0
kit.CG_FROM_PITOT = 1123 / 86.0  # 25% of the 4.20 m mean aerodynamic chord
kit.LENGTH = 21.94
kit.SPINE_UPPER_ONLY = True
Y, Z = kit.Y, kit.Z
PX = kit.REF_PX_PER_M


def W(px):
    return px / PX


# (xd, half width px, bottom row, shoulder row, top row, spine half width m, exponent). Under the canopy the
# top is the cockpit sill; behind it the dorsal hump rises over the wide, flat centre body, which bridges
# the nacelles and narrows into the tail sting.
_BODY = [
    (0, 0.5, 360, 354, 354, 0.0, 2.0),  # radome tip
    (100, 44, 378, 300, 300, 0.0, 2.0),
    (200, 53, 390, 275, 275, 0.0, 2.1),
    (270, 54, 395, 262, 262, 0.0, 2.2),
    (360, 56, 393, 250, 250, 0.0, 2.4),  # windscreen base
    (500, 60, 386, 255, 255, 0.0, 2.6),
    (640, 62, 378, 258, 258, 0.0, 2.8),
    (700, 68, 374, 270, 222, 0.40, 2.8),  # the hump rises inside the canopy's rear
    (760, 80, 372, 295, 222, 0.42, 2.9),
    (830, 105, 371, 320, 230, 0.44, 3.1),
    (900, 135, 372, 335, 240, 0.45, 3.4),
    (1000, 150, 372, 338, 255, 0.42, 3.6),
    (1100, 152, 372, 338, 270, 0.40, 3.6),
    (1200, 152, 372, 338, 290, 0.36, 3.6),
    (1300, 150, 372, 338, 305, 0.30, 3.6),
    (1400, 120, 372, 340, 320, 0.20, 3.4),
    (1500, 60, 385, 330, 330, 0.0, 2.6),
    (1600, 40, 390, 312, 312, 0.0, 2.4),  # the tail sting between the nozzles
    (1700, 36, 385, 318, 318, 0.0, 2.2),
    (1800, 22, 375, 335, 335, 0.0, 2.0),
    (1895, 1, 360, 356, 356, 0.0, 2.0),
]
kit.FUSELAGE = [(xd, W(hw), Z(zb), Z(zs), Z(zt), sp, e) for xd, hw, zb, zs, zt, sp, e in _BODY]
kit.FUSELAGE_RINGS = 54
kit.FUSELAGE_SEGMENTS = 36

kit.CANOPY = [
    (360, 0.10, Z(250)),
    (400, 0.30, Z(228)),
    (440, 0.38, Z(210)),
    (470, 0.42, Z(198)),
    (520, 0.44, Z(188)),
    (560, 0.44, Z(186)),
    (610, 0.42, Z(192)),
    (660, 0.36, Z(205)),
    (700, 0.26, Z(216)),
    (730, 0.15, Z(222)),
]
kit.CANOPY_FRAMES = (455, 612)

# Nacelles: (xd, centre x m, half width m, centre z m, half height m), from the raked intake mouth (its top
# at station 760, under the extension, its bottom at 885) back to the engines
NACELLE = [
    (950, 0.98, 0.61, Z(395), 0.58),
    (1000, 0.98, 0.62, Z(400), 0.62),
    (1300, 0.98, 0.64, Z(398), 0.66),
    (1500, 0.98, 0.62, Z(385), 0.62),
    (1620, 0.99, 0.58, 0.0, 0.58),
]
LIP_TOP, LIP_BOTTOM = 760, 885

# Leading-edge extensions: (half width px, xd), from the forward fuselage to the wing's leading edge
GLOVE_EDGE = [(58, 380), (73, 500), (90, 600), (98, 628), (117, 728), (152, 828), (166, 870)]
GLOVE_INNER = 0.45

WING_Z = Z(340)


def wing_le_y(x):
    return Y(870 + (x * PX - 166) * 0.923)


def wing_te_y(x):
    return Y(1340 + (x * PX - 169) * 0.3125)


kit.WING_Z = WING_Z
kit.WING_ROOT_X, kit.WING_TIP_X = W(150), W(594)
kit.WING_ROOT_LE, kit.WING_ROOT_TE = wing_le_y(W(150)), wing_te_y(W(150))
kit.WING_SWEEP_LE = math.atan((wing_le_y(W(150)) - wing_le_y(W(594))) / (W(594) - W(150)))
kit.WING_TIP_CHORD = wing_le_y(W(594)) - wing_te_y(W(594))
kit.WING_THICKNESS = 0.05
kit.LE_FLAP_CHORD = 0.12
kit.TE_HINGE = 0.80
kit.TE_FLAP_SPAN = (1.95, 4.40)
kit.AILERON_SPAN = (4.45, 6.60)
kit.RAIL_Y = (wing_le_y(W(594)) + wing_te_y(W(594))) / 2
kit.RAIL_LENGTH = 2.6

# Tail booms beside the engines: (xd, half width m, half height m) at x = BOOM_X, centred at BOOM_Z
BOOM_X, BOOM_Z = W(175), Z(335)
BOOM = [(1250, 0.08, 0.10), (1350, 0.18, 0.30), (1650, 0.18, 0.30), (1760, 0.06, 0.08)]

STAB_ROOT_X, STAB_TIP_X = W(175), W(390)
STAB_ROOT_LE, STAB_ROOT_TE = Y(1430), Y(1710)
STAB_TIP_LE, STAB_TIP_TE = Y(1663), Y(1740)
STAB_Z = Z(350)
STAB_THICKNESS = 0.045

FIN_X = W(175)
FIN_ROOT_Z, FIN_TIP_Z = Z(305), Z(35)
FIN_ROOT_LE, FIN_ROOT_TE = Y(1340), Y(1595)
FIN_TIP_LE, FIN_TIP_TE = Y(1525), Y(1607)
FIN_THICKNESS = 0.045
RUDDER_HINGE = 0.68
RUDDER_SPAN = (Z(300), Z(128))

NOZZLE_X, NOZZLE_Z, NOZZLE_R = W(85), 0.0, 0.55
NOZZLE_Y0, NOZZLE_Y1 = Y(1620), Y(1720)

GROUND_Z = Z(20) - 5.93  # published height, from the fin tips
NOSE_WHEEL = {"at": (0, Y(664), GROUND_Z + 0.34), "radius": 0.34, "width": 0.18}
MAIN_WHEEL = {"at": (2.17, Y(1170), GROUND_Z + 0.52), "radius": 0.52, "width": 0.30}

kit.HULL = {"size": [3.6, 2.2, 20.0], "at": [0, 0.3, -2.0]}
kit.HITBOXES = {
    "Cockpit": {"size": [1.0, 1.1, 2.6], "at": [0, 1.8, -7.2]},
    "Fuselage": {"size": [3.6, 1.6, 8.0], "at": [0, 0.3, -1.6]},
    "Engine": {"size": [3.2, 1.4, 6.0], "at": [0, -0.1, 4.0]},
    "WingL": {"size": [5.4, 0.4, 4.4], "at": [-4.6, round(WING_Z, 2), 1.2]},
    "WingR": {"size": [5.4, 0.4, 4.4], "at": [4.6, round(WING_Z, 2), 1.2]},
    "Tail": {"size": [8.6, 3.6, 3.8], "at": [0, 1.6, 6.4]},
}
EYE = (0, Y(555), 1.85)
kit.ATTACHMENTS = {
    "CockpitEye": EYE,
    "GunMuzzle": (0.90, Y(700), Z(330)),  # GSh-30-1 in the right extension's root
    "Nozzle1": (-NOZZLE_X, NOZZLE_Y1, NOZZLE_Z),
    "Nozzle2": (NOZZLE_X, NOZZLE_Y1, NOZZLE_Z),
    "WingtipL": (-(kit.WING_TIP_X + 0.05), kit.RAIL_Y, WING_Z),
    "WingtipR": (kit.WING_TIP_X + 0.05, kit.RAIL_Y, WING_Z),
    "FlareDispenser": (-0.3, Y(1750), Z(330)),
    "ChaffDispenser": (0.3, Y(1750), Z(330)),
    "ChaseCam": (0, -24.0, 4.6),
    # Wingtip rails, then the outer and inner wing pylons
    "Hardpoint1": (-(kit.WING_TIP_X + 0.08), kit.RAIL_Y, WING_Z - 0.10),
    "Hardpoint2": (kit.WING_TIP_X + 0.08, kit.RAIL_Y, WING_Z - 0.10),
    "Hardpoint3": (-4.60, Y(1240), WING_Z - 0.30),
    "Hardpoint4": (4.60, Y(1240), WING_Z - 0.30),
    "Hardpoint5": (-3.20, Y(1150), WING_Z - 0.30),
    "Hardpoint6": (3.20, Y(1150), WING_Z - 0.30),
    # Under the intakes, and the tandem pair in the tunnel between the nacelles
    "Hardpoint7": (-0.98, Y(1050), Z(465)),
    "Hardpoint8": (0.98, Y(1050), Z(465)),
    "Hardpoint9": (0, Y(1000), Z(400)),
    "Hardpoint10": (0, Y(1300), Z(400)),
}

# Cockpit interior (cockpit_kit.py, art pipeline §7), after Su-27 cockpit photos: the head-up display on the
# glareshield over the radar and infrared display, the attitude indicator under it with flight instruments
# left, engine instruments (two of each) and the threat display right. Turquoise.
kit.COCKPIT = {
    "well": {"back": EYE[1] - 0.32, "front": EYE[1] + 0.78, "half_width": 0.40, "floor": EYE[2] - 1.00, "flange": 0.06},
    "panel": {"distance": 0.66, "top": -0.18, "bottom": -0.62, "tilt": 12, "half_width": 0.34},
    "coaming": {"overhang": 0.04, "length": 0.32, "drop": 0.06},
    "consoles": {"top": -0.53, "width": 0.12, "aft": -0.35, "fore": 0.42, "throttle": 0.02},
    "stick": "centre",
    "stick_fore": 0.40,
    "sight": "HUD",
    "palette": "Soviet",
    "instruments": [
        {"name": "GMeter", "kind": "Dial", "u": -0.22, "v": 0.075, "size": 0.055, "live": "G"},
        {"name": "Airspeed", "kind": "Dial", "u": -0.12, "v": 0.08, "size": 0.075, "live": "Speed"},
        {"name": "RadarScope", "kind": "Scope", "u": 0.0, "v": 0.09, "size": 0.11, "live": "Radar"},
        {"name": "RPM", "kind": "Dial", "u": 0.12, "v": 0.08, "size": 0.075, "live": "RPM"},
        {"name": "RWR", "kind": "Scope", "u": 0.22, "v": 0.085, "size": 0.07},
        {"name": "AOA", "kind": "Dial", "u": -0.22, "v": 0.165, "size": 0.05},
        {"name": "Altimeter", "kind": "Dial", "u": -0.12, "v": 0.175, "size": 0.075, "live": "Altitude"},
        {"name": "ADI", "kind": "Dial", "u": 0.0, "v": 0.205, "size": 0.10, "face": "attitude"},
        {"name": "RPM2", "kind": "Dial", "u": 0.12, "v": 0.175, "size": 0.065},
        {"name": "EGT", "kind": "Dial", "u": 0.22, "v": 0.175, "size": 0.05},
        {"name": "VVI", "kind": "Dial", "u": -0.15, "v": 0.28, "size": 0.055},
        {"name": "HSI", "kind": "Dial", "u": 0.0, "v": 0.31, "size": 0.09, "face": "compass"},
        {"name": "Fuel", "kind": "Dial", "u": 0.15, "v": 0.28, "size": 0.055},
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
    """The leading-edge extensions ahead of the wing roots, and the tail booms carrying the tail."""
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
        nv, nf = kit.cylinder(p0, p1, NOZZLE_R, 20, radius1=NOZZLE_R - 0.08, caps=False)
        iv, i_f = kit.cylinder(p0, p1, NOZZLE_R - 0.035, 20, radius1=NOZZLE_R - 0.11, caps=False)
        n = 20
        lip = [(n + i, n + (i + 1) % n, len(nv) + n + (i + 1) % n, len(nv) + n + i) for i in range(n)]
        verts, faces = kit.merge((nv, nf), (iv, kit.flip_faces(i_f)))
        kit.make_object(f"Nozzle{name}", verts, faces + lip, col, "Details", "Nozzle", extra={"engine": name})
        cv, cf = kit.cylinder((x, NOZZLE_Y1 + 0.15, NOZZLE_Z), (x, NOZZLE_Y0 + 0.05, NOZZLE_Z), NOZZLE_R - 0.16, 16,
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
    """The nose probe ahead of the radome."""
    v, f = kit.cylinder((0, Y(-30), Z(357)), (0, Y(10), Z(357)), 0.02, 8)
    kit.make_object("Pitot", v, f, col, "Details")


def build_gear(col):
    nx, ny, nz = NOSE_WHEEL["at"]
    belly = Z(385)
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
        top = (side * 1.35, my + 0.30, Z(450))
        v, f = kit.cylinder(top, (side * mx, my, mz + 0.10), 0.08, 10)
        kit.make_object(f"MainGearStrut{name}", v, f, col, "Details", "Gear", origin=top,
                        hinge={"axis": (0, 1, 0), "min": 0, "max": 90, "control": "Gear"})
        centre = (side * mx, my, mz)
        v, f = kit.wheel(centre, MAIN_WHEEL["radius"], MAIN_WHEEL["width"])
        kit.make_object(f"MainGearWheel{name}", v, f, col, "Details", "GearWheel", origin=centre,
                        hinge={"axis": (1, 0, 0), "min": -720, "max": 720, "control": "Wheel"})
        v, f = kit.box((side * 1.30, my, Z(455) - 0.28), (0.04, 1.0, 0.50))
        kit.make_object(f"MainGearDoor{name}", v, f, col, "Details", "GearDoor", origin=(side * 1.30, my, Z(455) - 0.03),
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
