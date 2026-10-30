"""
Afterburner: F-35A Lightning II base mesh generator (Blender 4.x / 5.x). Art only: the F-35A has no flight
data yet (AircraftData), so this makes the model, skins and cockpit for when it does.

Builds a mid-poly, modular F-35A at real-world size, measured from a reference drawing, in the same form as
the F-5E (f5e_generate.py, whose helpers this uses): separate objects per part, moving parts with their
origin on the hinge line, four texture sets, a manifest for the Studio assembler, an FBX, and the cockpit
well.

  * the chined forebody with the radome and the bubble canopy, and the wide body over the single engine
  * the bump intakes either side of the cockpit, running back to the engine
  * the chines from the intakes to the wing roots
  * the trapezoidal wing with leading-edge flaps, flaperons and ailerons, and the tailerons on the elevon
    controls
  * the tail booms either side of the nozzle, carrying twin fins canted out 25 degrees with rudders
  * the single nozzle with its afterburner cone, ejection seat, landing gear (struts, wheels, doors)

Run headless:
  blender -b --python tools/blender/f35a_generate.py -- --out <dir> --manifest-luau tools/Manifests/F35A.luau

Reference: the Commons drawing "Lockheed Martin F-35A Lightning II 3-view drawing.png" (from the programme's
public-domain renders), 1115 px wide: shaded renders, so the outlines are silhouettes. Its side view and its
top view (turned nose left) were rebuilt as a composite 2000 px wide, the nose tip at x = 53. Stations (xd)
are pixels aft of it; heights are side-view rows (row 393, the nozzle's axis, is z = 0); half widths are
pixels from the top view's centreline (row 1213). The scale comes from the published 15.67 m length
(119.3 px/m), which gives an 11.0 m span against the published 10.7 m. See
docs/art/reference/F35A/SOURCES.md (kept out of git).
"""

import argparse
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import f5e_generate as kit  # noqa: E402  (shared helpers; its module settings are switched below)

kit.AIRFRAME = "F35A"
kit.REF_PX_PER_M = 119.3
kit.REF_PITOT_XD = 0.0
kit.REF_Z0_ROW = 393.0
kit.CG_FROM_PITOT = 1119 / 119.3  # 25% of the 3.13 m mean aerodynamic chord
kit.LENGTH = 15.67
kit.SPINE_UPPER_ONLY = True
Y, Z = kit.Y, kit.Z
PX = kit.REF_PX_PER_M


def W(px):
    return px / PX


# (xd, half width px, bottom row, shoulder row, top row, spine half width m, exponent). The forebody is
# chined (a flatter section); under the canopy the top is the sill, behind it the spine rises over the
# wide body. Without a spine the section's top is its shoulder row, so ahead of the windscreen the shoulder is
# the top line: the nose rises into the windscreen.
_BODY = [
    (0, 0.5, 368, 362, 362, 0.0, 2.0),  # radome tip
    (100, 53, 395, 330, 330, 0.0, 1.8),
    (200, 78, 430, 310, 310, 0.0, 1.8),
    (230, 82, 432, 300, 300, 0.0, 1.9),  # windscreen base
    (400, 103, 440, 320, 300, 0.0, 2.2),
    (560, 125, 445, 310, 250, 0.40, 2.6),  # the spine rises inside the canopy's rear
    (700, 155, 455, 310, 240, 0.50, 3.0),
    (900, 190, 460, 312, 248, 0.55, 3.4),
    (1100, 210, 465, 315, 260, 0.50, 3.6),
    (1300, 205, 470, 320, 270, 0.45, 3.6),
    (1400, 185, 470, 330, 282, 0.35, 3.4),
    (1500, 150, 460, 340, 300, 0.20, 3.0),
    (1530, 135, 455, 345, 335, 0.0, 2.8),  # nozzle starts
]
kit.FUSELAGE = [(xd, W(hw), Z(zb), Z(zs), Z(zt), sp, e) for xd, hw, zb, zs, zt, sp, e in _BODY]
kit.FUSELAGE_RINGS = 52
kit.FUSELAGE_SEGMENTS = 36

kit.CANOPY = [
    (xd, w, Z(row)) for xd, w, row in (
        (230, 0.10, 300), (280, 0.30, 270), (320, 0.40, 245), (400, 0.46, 225), (480, 0.46, 222),
        (540, 0.40, 228), (580, 0.30, 238), (610, 0.15, 244),
    )
]
kit.CANOPY_FRAMES = (590,)  # one-piece canopy: only the frame behind the seat

# Intakes: (xd, centre x m, half width m, centre z m, half height m), from the mouth (its bottom at station
# 540, its top raked back to 580) back to the engine
NACELLE = [
    (590, 1.15, 0.22, Z(365), 0.50),
    (800, 1.20, 0.38, Z(380), 0.52),
    (1000, 1.10, 0.48, Z(390), 0.50),
    (1200, 0.90, 0.50, Z(392), 0.46),
    (1400, 0.60, 0.45, Z(393), 0.42),
]
LIP_TOP, LIP_BOTTOM = 580, 540

WING_Z = Z(345)

# Chines: (half width px, xd) from the intakes to the wing's leading edge, and back along the wing root
LERX_EDGE = [(170, 540), (195, 700), (230, 870), (253, 940)]
LERX_INNER = 1.20
LERX_Z0 = WING_Z
LERX_TE = (215, 1500)


def wing_le_y(x):
    return Y(940 + (x * PX - 253) * 0.667)


def wing_te_y(x):
    return Y(1500 - (x * PX - 223) * 0.253)


kit.WING_Z = WING_Z
kit.WING_ROOT_X, kit.WING_TIP_X = W(210), W(643)
kit.WING_ROOT_LE, kit.WING_ROOT_TE = wing_le_y(W(210)), wing_te_y(W(210))
kit.WING_SWEEP_LE = math.atan((wing_le_y(W(210)) - wing_le_y(W(643))) / (W(643) - W(210)))
kit.WING_TIP_CHORD = wing_le_y(W(643)) - wing_te_y(W(643))
kit.WING_THICKNESS = 0.045
kit.LE_FLAP_CHORD = 0.14
kit.TE_HINGE = 0.80
kit.TE_FLAP_SPAN = (1.90, 3.90)  # flaperons
kit.AILERON_SPAN = (3.95, 5.30)
kit.RAIL_Y = (wing_le_y(W(643)) + wing_te_y(W(643))) / 2
kit.RAIL_LENGTH = 0.5

# Tail booms: the fairings either side of the nozzle that carry the fins and the tailerons, (xd, half width m,
# half height m) at x = BOOM_X, centred at BOOM_Z
BOOM_X, BOOM_Z = 1.60, 0.45
BOOM = [(1250, 0.06, 0.05), (1350, 0.24, 0.22), (1500, 0.28, 0.26), (1750, 0.26, 0.22), (1860, 0.08, 0.06)]

STAB_ROOT_X, STAB_TIP_X = BOOM_X, W(443)
STAB_ROOT_LE, STAB_ROOT_TE = Y(1590), Y(1845)
STAB_TIP_LE, STAB_TIP_TE = Y(1680), Y(1795)
STAB_Z = BOOM_Z
STAB_THICKNESS = 0.04

FIN_X, FIN_CANT = BOOM_X - 0.05, math.radians(25)
FIN_ROOT_Z, FIN_TIP_Z = BOOM_Z + 0.20, Z(53)
FIN_ROOT_LE, FIN_ROOT_TE = Y(1320), Y(1655)
FIN_TIP_LE, FIN_TIP_TE = Y(1630), Y(1775)
FIN_THICKNESS = 0.045
RUDDER_HINGE = 0.72
RUDDER_SPAN = (Z(295), Z(150))

NOZZLE_Z, NOZZLE_R = 0.0, 0.62
NOZZLE_Y0, NOZZLE_Y1 = Y(1520), Y(1625)

GROUND_Z = FIN_TIP_Z - 4.38  # published height
NOSE_WHEEL = {"at": (0, Y(500), GROUND_Z + 0.28), "radius": 0.28, "width": 0.16}
MAIN_WHEEL = {"at": (1.60, Y(1150), GROUND_Z + 0.40), "radius": 0.40, "width": 0.22}
BELLY_Z = Z(450)
PITOT = (60, 150, 190, 380)  # (half width px, xd from, xd to, side row): the probes on the chines

kit.HULL = {"size": [3.4, 2.0, 15.0], "at": [0, 0.1, -0.9]}
kit.HITBOXES = {
    "Cockpit": {"size": [1.0, 1.1, 2.4], "at": [0, 1.2, -5.6]},
    "Fuselage": {"size": [3.6, 1.6, 6.5], "at": [0, 0.0, -0.8]},
    "Engine": {"size": [2.2, 1.4, 4.4], "at": [0, 0.0, 3.4]},
    "WingL": {"size": [3.8, 0.4, 4.2], "at": [-3.6, round(WING_Z, 2), 1.4]},
    "WingR": {"size": [3.8, 0.4, 4.2], "at": [3.6, round(WING_Z, 2), 1.4]},
    "Tail": {"size": [7.4, 2.6, 3.4], "at": [0, 1.4, 5.6]},
}
EYE = (0, Y(440), Z(222) - 0.27)
kit.ATTACHMENTS = {
    "CockpitEye": EYE,
    "GunMuzzle": (-1.30, Y(700), Z(300)),  # the GAU-22 above the left intake
    "Nozzle1": (0, NOZZLE_Y1, NOZZLE_Z),
    "WingtipL": (-(kit.WING_TIP_X + 0.05), kit.RAIL_Y, WING_Z),
    "WingtipR": (kit.WING_TIP_X + 0.05, kit.RAIL_Y, WING_Z),
    "FlareDispenser": (-0.8, Y(1350), Z(460)),
    "ChaffDispenser": (0.8, Y(1350), Z(460)),
    "ChaseCam": (0, -19.0, 3.8),
    # The two internal bays (two stations each), and three pylons under each wing
    "Hardpoint1": (-0.75, Y(900), BELLY_Z - 0.12),
    "Hardpoint2": (0.75, Y(900), BELLY_Z - 0.12),
    "Hardpoint3": (-0.40, Y(950), BELLY_Z - 0.12),
    "Hardpoint4": (0.40, Y(950), BELLY_Z - 0.12),
    "Hardpoint5": (-4.70, wing_le_y(4.70) - 0.7, WING_Z - 0.25),
    "Hardpoint6": (4.70, wing_le_y(4.70) - 0.7, WING_Z - 0.25),
    "Hardpoint7": (-3.50, wing_le_y(3.50) - 1.0, WING_Z - 0.25),
    "Hardpoint8": (3.50, wing_le_y(3.50) - 1.0, WING_Z - 0.25),
    "Hardpoint9": (-2.40, wing_le_y(2.40) - 1.3, WING_Z - 0.25),
    "Hardpoint10": (2.40, wing_le_y(2.40) - 1.3, WING_Z - 0.25),
}

# Cockpit interior (cockpit_kit.py, art pipeline §7), after F-35 cockpit photos: the panoramic touchscreen
# across the panel, shown as two large displays side by side (the left one the radar face), with a strip of
# standby instruments under them. The real jet has no head-up display (the helmet does its work); the
# cockpit keeps one for the game's sight. Charcoal, side stick.
kit.COCKPIT = {
    "well": {"back": EYE[1] - 0.32, "front": EYE[1] + 0.74, "half_width": 0.40, "floor": EYE[2] - 1.00, "flange": 0.06},
    "panel": {"distance": 0.65, "top": -0.18, "bottom": -0.60, "tilt": 12, "half_width": 0.34},
    "coaming": {"overhang": 0.04, "length": 0.30, "drop": 0.06},
    "consoles": {"top": -0.50, "width": 0.12, "aft": -0.35, "fore": 0.42, "throttle": 0.02},
    "stick": "side",
    "sight": "HUD",
    "palette": "Modern",
    "instruments": [
        {"name": "RadarScope", "kind": "MFD", "u": -0.155, "v": 0.14, "size": 0.20, "live": "Radar"},
        {"name": "RightMFD", "kind": "MFD", "u": 0.155, "v": 0.14, "size": 0.20},
        {"name": "Airspeed", "kind": "Dial", "u": -0.20, "v": 0.29, "size": 0.04, "live": "Speed"},
        {"name": "Altimeter", "kind": "Dial", "u": -0.12, "v": 0.29, "size": 0.04, "live": "Altitude"},
        {"name": "ADI", "kind": "Dial", "u": 0.0, "v": 0.29, "size": 0.05, "face": "attitude"},
        {"name": "GMeter", "kind": "Dial", "u": 0.12, "v": 0.29, "size": 0.04, "live": "G"},
        {"name": "RPM", "kind": "Dial", "u": 0.20, "v": 0.29, "size": 0.04, "live": "RPM"},
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


def build_booms(col):
    """The tail booms either side of the nozzle, which the fins sit on and the tailerons pivot from."""
    parts = []
    for side in (1, -1):
        rings = [rounded_ring(side * BOOM_X, lambda _z, xd=xd: Y(xd), hw, BOOM_Z, hh, 2.6, 16) for xd, hw, hh in BOOM]
        parts.append(kit.lofted(rings, True, True))
    v, f = kit.merge(*parts)
    kit.make_object("TailBooms", v, f, col, "Body")


def build_engine(col):
    p0, p1 = (0, NOZZLE_Y0, NOZZLE_Z), (0, NOZZLE_Y1, NOZZLE_Z)
    nv, nf = kit.cylinder(p0, p1, NOZZLE_R, 20, radius1=NOZZLE_R - 0.05, caps=False)
    iv, i_f = kit.cylinder(p0, p1, NOZZLE_R - 0.035, 20, radius1=NOZZLE_R - 0.08, caps=False)
    n = 20
    lip = [(n + i, n + (i + 1) % n, len(nv) + n + (i + 1) % n, len(nv) + n + i) for i in range(n)]
    verts, faces = kit.merge((nv, nf), (iv, kit.flip_faces(i_f)))
    kit.make_object("Nozzle", verts, faces + lip, col, "Details", "Nozzle", extra={"engine": "C"})
    cv, cf = kit.cylinder((0, NOZZLE_Y1 + 0.15, NOZZLE_Z), (0, NOZZLE_Y0 - 0.20, NOZZLE_Z), NOZZLE_R - 0.12, 16,
                          radius1=0.05, caps=True)
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
    build_booms(cols["Body"])
    kit.build_canopy(cols["Glass"], cols["Body"])
    kit.build_wings(cols["Wings"])
    build_tail(cols["Wings"], cols["Body"])
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
