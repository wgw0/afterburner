"""
Afterburner: F/A-18C Hornet base mesh generator (Blender 4.x / 5.x). Art only: the F/A-18C has no flight
data yet (AircraftData), so this makes the model, skins and cockpit for when it does.

Builds a mid-poly, modular F/A-18C at real-world size, measured from a reference drawing, in the same form as
the F-5E (f5e_generate.py, whose helpers this uses): separate objects per part, moving parts with their
origin on the hinge line, four texture sets, a manifest for the Studio assembler, an FBX, and the cockpit
well.

  * the forward fuselage with the radome and the bubble canopy, the dorsal spine, and the wide engine bay
  * the long leading-edge extensions from the windscreen to the wing
  * the D-shaped intakes under the extensions, running back into the engine bay
  * the trapezoidal wing with big leading-edge flaps, flaps and ailerons, and wingtip launch rails
  * all-moving tailerons on the elevon controls, twin fins canted out with rudders
  * twin nozzles with afterburner cones, ejection seat, pitot, landing gear (struts, wheels, doors)

Run headless:
  blender -b --python tools/blender/fa18c_generate.py -- --out <dir> --manifest-luau tools/Manifests/FA18C.luau

Reference: NASA's three-view of the F/A-18 on Commons ("Проекции F A 18 hornet.gif", public domain), 2865
px wide, rebuilt as a composite: side view on top (nose left), top view below, mirrored nose left, the
radome tip at x = 60 in both. Stations (xd) are pixels aft of it; heights are composite side-view rows (row
372, the nozzles' axis, is z = 0); half widths are pixels from the top view's centreline (row 1365). The
scale comes from the published 17.07 m length (107.8 px/m); the span over the wingtips then comes out
11.54 m against the published 11.43 m. See docs/art/reference/FA18C/SOURCES.md (kept out of git).
"""

import argparse
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import f5e_generate as kit  # noqa: E402  (shared helpers; its module settings are switched below)

kit.AIRFRAME = "FA18C"
kit.REF_PX_PER_M = 107.8
kit.REF_PITOT_XD = 0.0
kit.REF_Z0_ROW = 372.0
kit.CG_FROM_PITOT = 1154 / 107.8  # 25% of the 3.24 m mean aerodynamic chord
kit.LENGTH = 17.07
kit.SPINE_UPPER_ONLY = True
Y, Z = kit.Y, kit.Z
PX = kit.REF_PX_PER_M


def W(px):
    return px / PX


# (xd, half width px, bottom row, shoulder row, top row, spine half width m, exponent); under the canopy the
# top is the cockpit sill, behind it a dorsal spine runs back between the extensions
_BODY = [
    (0, 0.5, 400, 396, 396, 0.0, 2.0),  # radome tip
    (50, 22, 412, 375, 375, 0.0, 2.0),
    (100, 37, 418, 355, 355, 0.0, 2.0),
    (200, 53, 435, 330, 330, 0.0, 2.1),
    (300, 60, 436, 310, 310, 0.0, 2.3),
    (385, 62, 436, 290, 290, 0.0, 2.5),  # windscreen base
    (500, 63, 434, 286, 286, 0.0, 2.7),
    (700, 64, 432, 279, 279, 0.0, 2.8),
    (780, 64, 432, 300, 255, 0.30, 2.8),  # the spine rises inside the canopy's rear
    (900, 66, 434, 310, 247, 0.32, 2.8),
    (1000, 75, 440, 312, 250, 0.32, 2.9),
    (1100, 95, 443, 312, 255, 0.30, 3.0),
    (1200, 108, 445, 310, 270, 0.26, 3.0),
    (1300, 113, 445, 305, 290, 0.20, 3.0),
    (1450, 115, 442, 303, 303, 0.0, 3.0),
    (1600, 112, 430, 306, 306, 0.0, 3.0),
    (1700, 106, 422, 315, 315, 0.0, 2.9),
    (1770, 100, 418, 322, 322, 0.0, 2.8),  # nozzles start
]
kit.FUSELAGE = [(xd, W(hw), Z(zb), Z(zs), Z(zt), sp, e) for xd, hw, zb, zs, zt, sp, e in _BODY]
kit.FUSELAGE_RINGS = 52
kit.FUSELAGE_SEGMENTS = 36

kit.CANOPY = [
    (385, 0.10, Z(288)),
    (430, 0.30, Z(265)),
    (470, 0.38, Z(240)),
    (505, 0.42, Z(225)),  # windscreen bow
    (560, 0.44, Z(215)),
    (620, 0.44, Z(213)),
    (690, 0.42, Z(222)),
    (740, 0.36, Z(238)),
    (785, 0.24, Z(250)),
]
kit.CANOPY_FRAMES = (505, 700)

# Intakes under the extensions: (xd, centre x m, half width m, centre z m, half height m), from the mouth
# back into the engine bay
NACELLE = [
    (1000, W(88), 0.22, Z(400), 0.44),
    (1100, 0.80, 0.25, Z(400), 0.44),
    (1300, 0.70, 0.30, -0.22, 0.40),
    (1450, 0.60, 0.30, -0.18, 0.35),
]
LIP_TOP, LIP_BOTTOM = 985, 1000

# Leading-edge extensions: (half width px, xd) from the windscreen to the wing's leading edge
LERX_EDGE = [(55, 388), (75, 400), (102, 500), (107, 590), (117, 690), (140, 790), (153, 890), (158, 980)]
LERX_INNER = 0.40
LERX_Z0 = Z(322)

WING_Z = Z(340)


def wing_le_y(x):
    return Y(980 + (x * PX - 158) * 0.501)


def wing_te_y(x):
    return Y(1418 - (x * PX - 110) * 0.008)


kit.WING_Z = WING_Z
kit.WING_ROOT_X, kit.WING_TIP_X = W(110), W(622)
kit.WING_ROOT_LE, kit.WING_ROOT_TE = wing_le_y(W(110)), wing_te_y(W(110))
kit.WING_SWEEP_LE = math.atan((wing_le_y(W(110)) - wing_le_y(W(622))) / (W(622) - W(110)))
kit.WING_TIP_CHORD = wing_le_y(W(622)) - wing_te_y(W(622))
kit.WING_THICKNESS = 0.05
kit.LE_FLAP_CHORD = 0.22
kit.TE_HINGE = 0.70
kit.TE_FLAP_SPAN = (1.10, 3.90)
kit.AILERON_SPAN = (3.95, 5.70)
kit.RAIL_Y = (wing_le_y(W(622)) + wing_te_y(W(622))) / 2
kit.RAIL_LENGTH = 1.6

STAB_ROOT_X, STAB_TIP_X = W(105), W(345)
STAB_ROOT_LE, STAB_ROOT_TE = Y(1487), Y(1785)
STAB_TIP_LE, STAB_TIP_TE = Y(1785), Y(1920)
STAB_Z = Z(378)
STAB_THICKNESS = 0.045

FIN_X, FIN_CANT = W(100), math.radians(18)
FIN_ROOT_Z, FIN_TIP_Z = Z(312), Z(60)
FIN_ROOT_LE, FIN_ROOT_TE = Y(1300), Y(1605)
FIN_TIP_LE, FIN_TIP_TE = Y(1540), Y(1669)
FIN_THICKNESS = 0.045
RUDDER_HINGE = 0.78
RUDDER_SPAN = (Z(295), Z(160))

NOZZLE_X, NOZZLE_Z = W(54), 0.0
NOZZLE_R0, NOZZLE_R1 = 0.42, 0.30
NOZZLE_Y0, NOZZLE_Y1 = Y(1765), Y(1840)

GROUND_Z = Z(588)
NOSE_WHEEL = {"at": (0, Y(620), GROUND_Z + 0.28), "radius": 0.28, "width": 0.16}
MAIN_WHEEL = {"at": (1.55, Y(1235), GROUND_Z + 0.39), "radius": 0.39, "width": 0.22}

kit.HULL = {"size": [2.4, 1.8, 15.6], "at": [0, 0.1, -1.6]}
kit.HITBOXES = {
    "Cockpit": {"size": [0.9, 1.0, 2.4], "at": [0, 1.1, -5.0]},
    "Fuselage": {"size": [2.4, 1.5, 6.5], "at": [0, 0.1, -1.0]},
    "Engine": {"size": [2.2, 1.1, 4.2], "at": [0, 0.0, 4.4]},
    "WingL": {"size": [4.6, 0.4, 3.2], "at": [-3.5, round(WING_Z, 2), 1.6]},
    "WingR": {"size": [4.6, 0.4, 3.2], "at": [3.5, round(WING_Z, 2), 1.6]},
    "Tail": {"size": [6.6, 2.8, 3.4], "at": [0, 1.2, 5.4]},
}
EYE = (0, Y(610), 1.20)
kit.ATTACHMENTS = {
    "CockpitEye": EYE,
    "GunMuzzle": (0, Y(5), Z(380)),  # M61 in the nose, ahead of the radome's top
    "Nozzle1": (-NOZZLE_X, NOZZLE_Y1, NOZZLE_Z),
    "Nozzle2": (NOZZLE_X, NOZZLE_Y1, NOZZLE_Z),
    "WingtipL": (-(kit.WING_TIP_X + 0.05), kit.RAIL_Y, WING_Z),
    "WingtipR": (kit.WING_TIP_X + 0.05, kit.RAIL_Y, WING_Z),
    "FlareDispenser": (-0.7, Y(1500), -0.55),
    "ChaffDispenser": (0.7, Y(1500), -0.55),
    "ChaseCam": (0, -20.5, 4.0),
    # Wingtip rails, then the outer and inner wing pylons
    "Hardpoint1": (-(kit.WING_TIP_X + 0.08), kit.RAIL_Y, WING_Z - 0.10),
    "Hardpoint2": (kit.WING_TIP_X + 0.08, kit.RAIL_Y, WING_Z - 0.10),
    "Hardpoint3": (-3.90, Y(1250), WING_Z - 0.30),
    "Hardpoint4": (3.90, Y(1250), WING_Z - 0.30),
    "Hardpoint5": (-2.50, Y(1180), WING_Z - 0.30),
    "Hardpoint6": (2.50, Y(1180), WING_Z - 0.30),
    # The fuselage stations on the intakes' lower corners, and the centreline
    "Hardpoint7": (-0.80, Y(1150), Z(450)),
    "Hardpoint8": (0.80, Y(1150), Z(450)),
    "Hardpoint9": (0, Y(1300), Z(450)),
}

# Cockpit interior (cockpit_kit.py, art pipeline §7), after F/A-18C cockpit photos: the head-up display on
# the glareshield, the up-front control panel under it between the two digital displays, the map display
# below it, standby instruments along the bottom. US grey, centre stick.
kit.COCKPIT = {
    "well": {"back": EYE[1] - 0.32, "front": EYE[1] + 0.74, "half_width": 0.38, "floor": EYE[2] - 1.00, "flange": 0.06},
    "panel": {"distance": 0.65, "top": -0.18, "bottom": -0.62, "tilt": 12, "half_width": 0.34},
    "coaming": {"overhang": 0.04, "length": 0.30, "drop": 0.06},
    "consoles": {"top": -0.52, "width": 0.12, "aft": -0.35, "fore": 0.42, "throttle": 0.02},
    "stick": "centre",
    "stick_fore": 0.40,
    "sight": "HUD",
    "palette": "US",
    "instruments": [
        {"name": "LeftDDI", "kind": "MFD", "u": -0.215, "v": 0.10, "size": 0.12, "live": "Radar"},
        {"name": "UFC", "kind": "Lights", "u": 0.0, "v": 0.09, "size": 0.09},
        {"name": "RightDDI", "kind": "MFD", "u": 0.215, "v": 0.10, "size": 0.12},
        {"name": "MPCD", "kind": "MFD", "u": 0.0, "v": 0.205, "size": 0.12},
        {"name": "Airspeed", "kind": "Dial", "u": -0.25, "v": 0.23, "size": 0.05, "live": "Speed"},
        {"name": "Altimeter", "kind": "Dial", "u": -0.175, "v": 0.23, "size": 0.05, "live": "Altitude"},
        {"name": "RPM", "kind": "Dial", "u": -0.105, "v": 0.285, "size": 0.04, "live": "RPM"},
        {"name": "ADI", "kind": "Dial", "u": 0.175, "v": 0.23, "size": 0.05, "face": "attitude"},
        {"name": "GMeter", "kind": "Dial", "u": 0.25, "v": 0.23, "size": 0.05, "live": "G"},
        {"name": "Clock", "kind": "Dial", "u": 0.105, "v": 0.285, "size": 0.04},
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
    """The leading-edge extensions: thin plates from the windscreen sloping down into the wing roots."""
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
        y_te = Y(1400)
        top.append((side * LERX_INNER, y_te, WING_Z + th))
        bottom.append((side * LERX_INNER, y_te, WING_Z - th))
        edge.append((side * W(118), y_te, WING_Z))
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
    for side in (1, -1):
        parts.append(kit.cylinder((side * W(48), Y(240), Z(390)), (side * W(56), Y(290), Z(390)), 0.018, 8))
    v, f = kit.merge(*parts)
    kit.make_object("Pitot", v, f, col, "Details")


def build_gear(col):
    nx, ny, nz = NOSE_WHEEL["at"]
    belly = Z(434)
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
        top = (side * 0.95, my + 0.30, Z(430))
        v, f = kit.cylinder(top, (side * mx, my, mz + 0.10), 0.08, 10)
        kit.make_object(f"MainGearStrut{name}", v, f, col, "Details", "Gear", origin=top,
                        hinge={"axis": (0, 1, 0), "min": 0, "max": 90, "control": "Gear"})
        centre = (side * mx, my, mz)
        v, f = kit.wheel(centre, MAIN_WHEEL["radius"], MAIN_WHEEL["width"])
        kit.make_object(f"MainGearWheel{name}", v, f, col, "Details", "GearWheel", origin=centre,
                        hinge={"axis": (1, 0, 0), "min": -720, "max": 720, "control": "Wheel"})
        v, f = kit.box((side * 1.06, my, Z(430) - 0.30), (0.04, 0.9, 0.50))
        kit.make_object(f"MainGearDoor{name}", v, f, col, "Details", "GearDoor", origin=(side * 1.06, my, Z(430) - 0.05),
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
