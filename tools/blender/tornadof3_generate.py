"""
Afterburner: Tornado F3 base mesh generator (Blender 4.x / 5.x). Art only: the Tornado F3 has no flight data
yet (AircraftData), so this makes the model, skins and cockpit for when it does.

Builds a mid-poly, modular Tornado F3 at real-world size, measured from a reference drawing, in the same form
as the F-5E (f5e_generate.py, whose helpers this uses): separate objects per part, moving parts with their
origin on the hinge line, four texture sets, a manifest for the Studio assembler, an FBX, and the cockpit
well.

  * the long radome and the tandem canopy, the dorsal spine and the wide rear fuselage over the engines
  * the raked box intakes beside the cockpits, running back into the rear fuselage
  * the fixed wing gloves, and the variable-sweep wings set at 25 degrees, with slats, flaps and the outer
    surfaces on the aileron controls
  * all-moving tailerons on the elevon controls, the tall single fin with its rudder and tip pod
  * twin nozzles with afterburner cones, ejection seats, nose probe, landing gear (struts, wheels, doors)

Run headless:
  blender -b --python tools/blender/tornadof3_generate.py -- --out <dir> --manifest-luau tools/Manifests/TornadoF3.luau

Reference: the Commons three-view "Panavia Tornado IDS 3-view line drawing.svg" (public domain), rendered
3840 px wide and rebuilt as a composite 2000 px wide: side view on top (nose left), top view below (turned
nose left), the probe tip at x = 53.1 in both. Stations (xd) are composite pixels aft of it; heights are
side-view rows (row 445, the nozzles' axis, is z = 0); half widths are pixels from the top view's centreline
(row 1494). The scale comes from the span with the wings at 25 degrees (13.91 m, 110.8 px/m), which gives
the IDS's length 16.9 m against the published 16.72 m.

The drawing is the IDS. The F3 (the air defence variant) has a longer radome and a fuselage plug behind the
rear cockpit: stations are mapped through stretch() below, which adds 0.60 m to the radome and spreads 1.36 m
over the plug, giving 18.84 m against the published 18.68 m. Set TORNADO_IDS=1 to build the drawing's IDS
proportions (for the overlay check). See docs/art/reference/TornadoF3/SOURCES.md (kept out of git).
"""

import argparse
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import f5e_generate as kit  # noqa: E402  (shared helpers; its module settings are switched below)

PX = 110.8
RADOME_JOINT, RADOME_EXTRA = 235, 0.0 if os.environ.get("TORNADO_IDS") else 0.60 * PX
PLUG = (760, 900, 0.0 if os.environ.get("TORNADO_IDS") else 1.36 * PX)


def stretch(xd):
    """IDS drawing station -> F3 station: the radome grows forward, the plug opens behind the cockpits."""
    if xd < RADOME_JOINT:
        return xd * (RADOME_JOINT + RADOME_EXTRA) / RADOME_JOINT
    xd += RADOME_EXTRA
    p0, p1, extra = PLUG
    p0, p1 = p0 + RADOME_EXTRA, p1 + RADOME_EXTRA
    if xd <= p0:
        return xd
    if xd <= p1:
        return p0 + (xd - p0) * (p1 - p0 + extra) / (p1 - p0)
    return xd + extra


kit.AIRFRAME = "TornadoF3"
kit.REF_PX_PER_M = PX
kit.REF_PITOT_XD = 0.0
kit.REF_Z0_ROW = 445.0
kit.CG_FROM_PITOT = stretch(1085) / PX  # 25% of the 2.0 m mean aerodynamic chord, wings at 25 degrees
kit.LENGTH = stretch(1870) / PX
kit.SPINE_UPPER_ONLY = True
Z = kit.Z


def Y(xd):
    return kit.Y(stretch(xd))


def W(px):
    return px / PX


# (xd, half width px, bottom row, shoulder row, top row, spine half width m, exponent); under the canopy the
# top is the cockpit sill, behind it a dorsal spine runs back over the wide rear fuselage
_BODY = [
    (65, 1, 507, 503, 503, 0.0, 2.0),  # radome tip
    (100, 15, 522, 488, 488, 0.0, 2.0),
    (150, 30, 533, 470, 470, 0.0, 2.0),
    (200, 44, 543, 455, 455, 0.0, 2.1),
    (235, 52, 549, 446, 446, 0.0, 2.2),  # radome joint
    (300, 64, 555, 422, 422, 0.0, 2.4),
    (340, 67, 556, 414, 414, 0.0, 2.5),  # windscreen base
    (450, 80, 556, 410, 410, 0.0, 2.7),
    (600, 84, 556, 402, 402, 0.0, 2.8),
    (700, 85, 555, 400, 345, 0.32, 2.8),  # the spine rises inside the canopy's rear
    (760, 85, 554, 400, 336, 0.34, 2.8),
    (900, 88, 550, 400, 340, 0.34, 2.9),
    (1000, 110, 549, 400, 344, 0.32, 3.0),
    (1100, 135, 548, 400, 348, 0.30, 3.2),
    (1300, 140, 540, 395, 352, 0.28, 3.2),
    (1450, 135, 525, 390, 354, 0.24, 3.0),
    (1550, 120, 500, 385, 360, 0.15, 2.8),
    (1600, 110, 490, 395, 395, 0.0, 2.6),  # nozzles start
]
kit.FUSELAGE = [(stretch(xd), W(hw), Z(zb), Z(zs), Z(zt), sp, e) for xd, hw, zb, zs, zt, sp, e in _BODY]
kit.FUSELAGE_RINGS = 56
kit.FUSELAGE_SEGMENTS = 36

kit.CANOPY = [
    (stretch(xd), w, Z(row)) for xd, w, row in (
        (340, 0.10, 414), (380, 0.30, 385), (430, 0.42, 352), (480, 0.45, 336), (560, 0.46, 328),
        (620, 0.45, 328), (680, 0.40, 331), (720, 0.30, 334), (750, 0.18, 336),
    )
]
kit.CANOPY_FRAMES = (stretch(430), stretch(592))  # windscreen bow, and the frame between the cockpits

# Intakes: (xd, centre x m, half width m, centre z m, half height m), from the raked mouth (its top at
# station 600, its bottom at 660) back into the rear fuselage
NACELLE = [
    (680, 1.13, 0.44, Z(462), 0.52),
    (800, 1.12, 0.45, Z(465), 0.52),
    (1000, 1.00, 0.45, Z(470), 0.50),
    (1200, 0.90, 0.42, Z(470), 0.45),
    (1400, 0.80, 0.40, Z(465), 0.40),
]
LIP_TOP, LIP_BOTTOM = 600, 660

# Gloves: (half width px, xd), the outline from the intake to the wing root's trailing edge
GLOVE_EDGE = [(174, 790), (200, 840), (225, 875), (244, 925), (250, 1060), (244, 1178)]
GLOVE_INNER = 1.10

WING_Z = Z(405)


def wing_le_y(x):
    return Y(925 + (x * PX - 244) * 0.458)


def wing_te_y(x):
    return Y(1178 + (x * PX - 244) * 0.264)


kit.WING_Z = WING_Z
kit.WING_ROOT_X, kit.WING_TIP_X = W(244), W(750)
kit.WING_ROOT_LE, kit.WING_ROOT_TE = wing_le_y(W(244)), wing_te_y(W(244))
kit.WING_SWEEP_LE = math.atan((wing_le_y(W(244)) - wing_le_y(W(750))) / (W(750) - W(244)))
kit.WING_TIP_CHORD = wing_le_y(W(750)) - wing_te_y(W(750))
kit.WING_THICKNESS = 0.05
kit.LE_FLAP_CHORD = 0.12
kit.TE_HINGE = 0.75
kit.TE_FLAP_SPAN = (2.30, 4.80)
kit.AILERON_SPAN = (4.85, 6.70)
kit.RAIL_Y = (wing_le_y(W(750)) + wing_te_y(W(750))) / 2
kit.RAIL_LENGTH = 0.6

STAB_ROOT_X, STAB_TIP_X = W(140), W(384)
STAB_ROOT_LE, STAB_ROOT_TE = Y(1330), Y(1660)
STAB_TIP_LE, STAB_TIP_TE = Y(1640), Y(1750)
STAB_Z = Z(450)
STAB_THICKNESS = 0.045

FIN_ROOT_Z, FIN_TIP_Z = Z(355), Z(60)
FIN_ROOT_LE, FIN_ROOT_TE = Y(1227), Y(1645)
FIN_TIP_LE, FIN_TIP_TE = Y(1609), Y(1842)
FIN_THICKNESS = 0.05
RUDDER_HINGE = 0.72
RUDDER_SPAN = (Z(350), Z(160))

NOZZLE_X, NOZZLE_Z, NOZZLE_R = W(80), 0.0, 0.42
NOZZLE_Y0, NOZZLE_Y1 = Y(1600), Y(1645)

GROUND_Z = Z(687)
NOSE_WHEEL = {"at": (0, Y(483), GROUND_Z + 0.24), "radius": 0.24, "width": 0.14}
MAIN_WHEEL = {"at": (1.55, Y(1069), GROUND_Z + 0.40), "radius": 0.40, "width": 0.22}

kit.HULL = {"size": [2.6, 1.8, 17.6], "at": [0, 0.0, -1.6]}
kit.HITBOXES = {
    "Cockpit": {"size": [0.9, 1.0, 3.6], "at": [0, 0.8, -6.0]},
    "Fuselage": {"size": [2.8, 1.5, 7.0], "at": [0, 0.0, -1.2]},
    "Engine": {"size": [2.6, 1.2, 5.0], "at": [0, 0.0, 4.0]},
    "WingL": {"size": [4.8, 0.4, 2.6], "at": [-4.6, round(WING_Z, 2), 0.6]},
    "WingR": {"size": [4.8, 0.4, 2.6], "at": [4.6, round(WING_Z, 2), 0.6]},
    "Tail": {"size": [7.0, 3.6, 3.6], "at": [0, 1.6, 5.8]},
}
EYE = (0, Y(545), 0.86)
kit.ATTACHMENTS = {
    "CockpitEye": EYE,
    "GunMuzzle": (-0.55, Y(560), Z(520)),  # the single Mauser BK-27 under the left side of the nose
    "Nozzle1": (-NOZZLE_X, NOZZLE_Y1, NOZZLE_Z),
    "Nozzle2": (NOZZLE_X, NOZZLE_Y1, NOZZLE_Z),
    "WingtipL": (-(kit.WING_TIP_X + 0.05), kit.RAIL_Y, WING_Z),
    "WingtipR": (kit.WING_TIP_X + 0.05, kit.RAIL_Y, WING_Z),
    "FlareDispenser": (-0.6, Y(1550), Z(500)),
    "ChaffDispenser": (0.6, Y(1550), Z(500)),
    "ChaseCam": (0, -21.5, 4.2),
    # Two missile rails on each wing pylon
    "Hardpoint1": (-3.30, Y(1080), WING_Z - 0.35),
    "Hardpoint2": (3.30, Y(1080), WING_Z - 0.35),
    "Hardpoint3": (-2.90, Y(1060), WING_Z - 0.35),
    "Hardpoint4": (2.90, Y(1060), WING_Z - 0.35),
    # The four semi-recessed stations under the fuselage, in two pairs
    "Hardpoint5": (-0.45, Y(800), Z(560)),
    "Hardpoint6": (0.45, Y(800), Z(560)),
    "Hardpoint7": (-0.45, Y(1150), Z(552)),
    "Hardpoint8": (0.45, Y(1150), Z(552)),
}

# Cockpit interior (cockpit_kit.py, art pipeline §7), after Tornado F3 front-cockpit photos: the head-up
# display on the glareshield over the moving-map/radar repeater, the attitude indicator in the middle with
# flight instruments left and engine instruments (two of each) right. Grey.
kit.COCKPIT = {
    "well": {"back": EYE[1] - 0.32, "front": EYE[1] + 0.74, "half_width": 0.38, "floor": EYE[2] - 1.00, "flange": 0.06},
    "panel": {"distance": 0.65, "top": -0.18, "bottom": -0.62, "tilt": 12, "half_width": 0.32},
    "coaming": {"overhang": 0.04, "length": 0.30, "drop": 0.06},
    "consoles": {"top": -0.52, "width": 0.11, "aft": -0.35, "fore": 0.42, "throttle": 0.02},
    "stick": "centre",
    "stick_fore": 0.40,
    "sight": "HUD",
    "palette": "US",
    "instruments": [
        {"name": "RWR", "kind": "Scope", "u": -0.21, "v": 0.085, "size": 0.07},
        {"name": "Airspeed", "kind": "Dial", "u": -0.11, "v": 0.08, "size": 0.07, "live": "Speed"},
        {"name": "RadarScope", "kind": "MFD", "u": 0.0, "v": 0.09, "size": 0.11, "live": "Radar"},
        {"name": "RPM", "kind": "Dial", "u": 0.11, "v": 0.08, "size": 0.065, "live": "RPM"},
        {"name": "RPM2", "kind": "Dial", "u": 0.21, "v": 0.08, "size": 0.065},
        {"name": "GMeter", "kind": "Dial", "u": -0.21, "v": 0.18, "size": 0.055, "live": "G"},
        {"name": "Altimeter", "kind": "Dial", "u": -0.11, "v": 0.18, "size": 0.07, "live": "Altitude"},
        {"name": "ADI", "kind": "Dial", "u": 0.0, "v": 0.205, "size": 0.10, "face": "attitude"},
        {"name": "EGT", "kind": "Dial", "u": 0.11, "v": 0.18, "size": 0.055},
        {"name": "EGT2", "kind": "Dial", "u": 0.21, "v": 0.18, "size": 0.055},
        {"name": "VVI", "kind": "Dial", "u": -0.13, "v": 0.28, "size": 0.055},
        {"name": "HSI", "kind": "Dial", "u": 0.0, "v": 0.31, "size": 0.09, "face": "compass"},
        {"name": "Fuel", "kind": "Dial", "u": 0.13, "v": 0.28, "size": 0.055},
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


def build_gloves(col):
    """The fixed wing gloves: a plate from the intakes out to the wing roots, back to the trailing edge."""
    parts = []
    z, th = WING_Z, 0.05
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
        parts.append((verts, faces))
    v, f = kit.merge(*parts)
    kit.make_object("Gloves", v, f, col, "Body")


def build_tail(col_wings, col_body):
    up = (0, 0, 1)
    root_le, root_te = (STAB_ROOT_X, STAB_ROOT_LE, STAB_Z), (STAB_ROOT_X, STAB_ROOT_TE, STAB_Z)
    tip_le, tip_te = (STAB_TIP_X, STAB_TIP_LE, STAB_Z), (STAB_TIP_X, STAB_TIP_TE, STAB_Z)
    pivot_y = STAB_ROOT_LE - (STAB_ROOT_LE - STAB_ROOT_TE) * 0.40
    for side, name in ((1, "R"), (-1, "L")):
        v, f = kit.panel(root_le, root_te, tip_le, tip_te, up, STAB_THICKNESS, 0.0, 1.0, 0, 1, 6, 10)
        if side < 0:
            v, f = kit.mirror_x(v), kit.flip_faces(f)
        # Pitch and roll mixed (tailerons), with the outer wing surfaces
        kit.make_object(f"Stabilator{name}", v, f, col_wings, "Wings", "ControlSurface",
                        origin=(side * STAB_ROOT_X, pivot_y, STAB_Z),
                        hinge={"axis": (1, 0, 0), "min": -25, "max": 15, "control": "Elevon" + name})

    h = FIN_TIP_Z - FIN_ROOT_Z

    def frac(z):
        return (z - FIN_ROOT_Z) / h

    g = ((0, FIN_ROOT_LE, FIN_ROOT_Z), (0, FIN_ROOT_TE, FIN_ROOT_Z), (0, FIN_TIP_LE, FIN_TIP_Z), (0, FIN_TIP_TE, FIN_TIP_Z),
         (1, 0, 0), FIN_THICKNESS)
    fin = [
        kit.panel(*g, 0.0, RUDDER_HINGE, 0, 1, 8, 10),
        kit.panel(*g, RUDDER_HINGE, 1.0, 0, frac(RUDDER_SPAN[0]), 1, 4),
        kit.panel(*g, RUDDER_HINGE, 1.0, frac(RUDDER_SPAN[1]), 1, 2, 4),
        # The pod on the fin tip
        kit.cylinder((0, Y(1575), Z(82)), (0, Y(1850), Z(82)), 0.11, 10, radius1=0.08),
    ]
    v, f = kit.merge(*fin)
    kit.make_object("Fin", v, f, col_body, "Body")
    v, f = kit.panel(*g, RUDDER_HINGE, 1.0, frac(RUDDER_SPAN[0]), frac(RUDDER_SPAN[1]), 6, 6)
    a, b = kit.hinge_line(*g[:4], RUDDER_HINGE, frac(RUDDER_SPAN[0]), frac(RUDDER_SPAN[1]))
    kit.make_object("Rudder", v, f, col_body, "Body", "ControlSurface", origin=tuple(a.lerp(b, 0.5)),
                    hinge={"axis": tuple(b - a), "min": -30, "max": 30, "control": "Rudder"})


def build_engines(col):
    for side, name in ((1, "R"), (-1, "L")):
        x = side * NOZZLE_X
        p0, p1 = (x, NOZZLE_Y0, NOZZLE_Z), (x, NOZZLE_Y1, NOZZLE_Z)
        nv, nf = kit.cylinder(p0, p1, NOZZLE_R, 20, radius1=NOZZLE_R - 0.02, caps=False)
        iv, i_f = kit.cylinder(p0, p1, NOZZLE_R - 0.035, 20, radius1=NOZZLE_R - 0.055, caps=False)
        n = 20
        lip = [(n + i, n + (i + 1) % n, len(nv) + n + (i + 1) % n, len(nv) + n + i) for i in range(n)]
        verts, faces = kit.merge((nv, nf), (iv, kit.flip_faces(i_f)))
        kit.make_object(f"Nozzle{name}", verts, faces + lip, col, "Details", "Nozzle", extra={"engine": name})
        cv, cf = kit.cylinder((x, NOZZLE_Y1 + 0.15, NOZZLE_Z), (x, NOZZLE_Y0 - 0.20, NOZZLE_Z), NOZZLE_R - 0.10, 16,
                              radius1=0.05, caps=True)
        kit.make_object(f"Afterburner{name}", cv, cf, col, "Details", "Afterburner", extra={"engine": name})


def build_seats(col):
    """Front and rear ejection seats, as one part."""
    parts = []
    for ey, ez in ((EYE[1], EYE[2]), (Y(650), EYE[2] + 0.06)):
        parts += [
            kit.box((0, ey - 0.05, ez - 0.70), (0.46, 0.48, 0.10)),
            kit.box((0, ey - 0.33, ez - 0.38), (0.46, 0.12, 0.66)),
            kit.box((0, ey - 0.30, ez + 0.04), (0.34, 0.20, 0.24)),
        ]
    v, f = kit.merge(*parts)
    kit.make_object("EjectionSeat", v, f, col, "Details")


def build_pitot(col):
    v, f = kit.cylinder((0, Y(0), Z(510)), (0, Y(66), Z(505)), 0.025, 8)
    kit.make_object("Pitot", v, f, col, "Details")


def build_gear(col):
    nx, ny, nz = NOSE_WHEEL["at"]
    belly = Z(556)
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
        top = (side * 0.95, my + 0.25, Z(530))
        v, f = kit.cylinder(top, (side * mx, my, mz + 0.10), 0.08, 10)
        kit.make_object(f"MainGearStrut{name}", v, f, col, "Details", "Gear", origin=top,
                        hinge={"axis": (0, 1, 0), "min": 0, "max": 90, "control": "Gear"})
        centre = (side * mx, my, mz)
        v, f = kit.wheel(centre, MAIN_WHEEL["radius"], MAIN_WHEEL["width"])
        kit.make_object(f"MainGearWheel{name}", v, f, col, "Details", "GearWheel", origin=centre,
                        hinge={"axis": (1, 0, 0), "min": -720, "max": 720, "control": "Wheel"})
        v, f = kit.box((side * 1.00, my, Z(540) - 0.28), (0.04, 0.9, 0.50))
        kit.make_object(f"MainGearDoor{name}", v, f, col, "Details", "GearDoor", origin=(side * 1.00, my, Z(540) - 0.03),
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
    build_gloves(cols["Body"])
    kit.build_canopy(cols["Glass"], cols["Body"])
    kit.build_wings(cols["Wings"])
    build_tail(cols["Wings"], cols["Body"])
    build_engines(cols["Details"])
    build_seats(cols["Details"])
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
