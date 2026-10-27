"""
Afterburner: F-16A Fighting Falcon base mesh generator (Blender 4.x / 5.x).

Builds a mid-poly, modular F-16A at real-world size, measured from a reference drawing, in the same form
as the F-5E (f5e_generate.py, whose helpers this uses): separate objects per part, moving parts with
their origin on the hinge line, four texture sets, a manifest for the Studio assembler, an FBX, and the
cockpit well.

  * the blended fuselage: radome, the frameless bubble canopy, the spine, the chin intake with its
    recessed duct, the long tapering tail
  * strakes: the leading-edge extensions and the side shelves the tailerons sit on
  * the cropped-delta wing with full-span leading-edge flaps and flaperons, wingtip launch rails
  * all-moving tailerons with anhedral, the fin on its base fairing with the rudder, two ventral fins
  * single nozzle with afterburner cone, ejection seat, pitot, landing gear (struts, wheels, doors)

Run headless:
  blender -b --python tools/blender/f16a_generate.py -- --out <dir> --manifest-luau tools/Manifests/F16A.luau

Reference: the Commons three-view "Lockheed F-16A Fighting Falcon 3-view line drawing.svg" (Marek Cel,
CC0), rendered 3840 px wide: side view on top and top view below, both nose left. Stations (xd) are pixels
aft of each view's own pitot tip (side view x = 120, top view x = 134); heights are side-view rows (row
672, the nozzle's axis, is z = 0); half widths are pixels from the top view's centreline (row 1903). The
scale comes from the published 15.03 m length (175.4 px/m); the span over the tip rails then comes out
9.37 m against the published 9.45 m. See docs/art/reference/F16A/SOURCES.md (kept out of git).
"""

import argparse
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import f5e_generate as kit  # noqa: E402  (shared helpers; its module settings are switched below)

kit.AIRFRAME = "F16A"
kit.REF_PX_PER_M = 175.4
kit.REF_PITOT_XD = 0.0
kit.REF_Z0_ROW = 672.0
kit.CG_FROM_PITOT = 1455 / 175.4  # 25% of the 3.38 m mean aerodynamic chord
kit.LENGTH = 15.03
kit.SPINE_UPPER_ONLY = True
Y, Z = kit.Y, kit.Z
PX = kit.REF_PX_PER_M


def W(px):
    return px / PX


kit.FUSELAGE = [
    (85, 0.012, -0.29, -0.25, -0.25, 0.0, 2.0),  # radome tip
    (200, W(43), -0.42, 0.02, 0.02, 0.0, 2.0),
    (300, W(70), -0.43, 0.26, 0.26, 0.0, 2.1),
    (400, W(85), -0.41, 0.41, 0.41, 0.0, 2.3),
    (490, 0.50, -0.39, 0.46, 0.46, 0.0, 2.5),  # canopy front
    (600, 0.50, -0.38, 0.44, 0.44, 0.0, 2.6),
    (800, 0.52, -0.36, 0.47, 0.47, 0.0, 2.7),  # the intake below from here
    (950, 0.56, -0.60, 0.47, 0.47, 0.0, 2.7),
    (1000, 0.60, -0.80, 0.47, 0.88, 0.36, 2.7),  # the spine rises behind the canopy
    (1100, 0.62, -0.91, 0.45, 0.88, 0.42, 2.7),
    (1350, 0.70, -0.93, 0.40, 0.72, 0.45, 2.8),
    (1750, 0.70, -0.93, 0.40, 0.72, 0.45, 2.8),
    (2000, 0.68, -0.80, 0.40, 0.72, 0.45, 2.6),
    (2200, 0.62, -0.72, 0.35, 0.70, 0.40, 2.4),
    (2285, 0.58, -0.67, 0.66, 0.66, 0.0, 2.2),  # nozzle
]
kit.FUSELAGE_RINGS = 64
kit.FUSELAGE_SEGMENTS = 44

kit.CANOPY = [
    (490, 0.10, 0.48),
    (540, 0.30, 0.72),
    (600, 0.38, 0.88),
    (680, 0.42, 1.09),
    (760, 0.43, 1.15),
    (850, 0.42, 1.16),
    (920, 0.38, 1.14),
    (980, 0.30, 1.04),
    (1010, 0.22, 0.95),
]
kit.CANOPY_FRAMES = (965,)  # frameless bubble: only the frame behind the seat

# Chin intake: rounded section, lip at station 800
INTAKE = {"lip": 800, "hw": 0.48, "top": -0.34, "bottom": -0.91, "fade": 1100}

# Strakes: leading-edge extensions (half width m, xd) and the shelves beside the tail (xd from, to)
LERX_EDGE = [(0.48, 480), (0.70, 600), (0.75, 700), (0.82, 800), (0.92, 900), (1.02, 1000), (1.20, 1150), (1.35, 1240)]
SHELF = (1900, 2400, 1.04)

WING_Z = Z(680)


def plan_xd(xd_plan):
    return xd_plan  # the top view's stations are measured from its own pitot tip, at the same scale


def wing_le_y(x):
    return Y(1240 + (x * PX - 236) * 0.80)


def wing_te_y(x):
    return Y(1900 - (x * PX - 185) * 0.004)


kit.WING_Z = WING_Z
kit.WING_ROOT_X, kit.WING_TIP_X = 0.60, W(804)
kit.WING_ROOT_LE, kit.WING_ROOT_TE = wing_le_y(0.60), wing_te_y(0.60)
kit.WING_SWEEP_LE = math.atan((wing_le_y(0.60) - wing_le_y(W(804))) / (W(804) - 0.60))
kit.WING_TIP_CHORD = wing_le_y(W(804)) - wing_te_y(W(804))
kit.WING_THICKNESS = 0.04
kit.LE_FLAP_CHORD = 0.17
kit.TE_HINGE = 0.80
kit.TE_FLAP_SPAN = (1.06, 2.30)  # inboard flaperon (flap and aileron in one; here the flap part)
kit.AILERON_SPAN = (2.34, 3.65)
kit.RAIL_Y = Y(1700)
kit.RAIL_LENGTH = (1940 - 1475) / PX

# Tailerons, with anhedral (the side view shows them sloping down outboard)
STAB_ROOT_X, STAB_TIP_X = 0.95, W(491)
STAB_ROOT_LE, STAB_ROOT_TE, STAB_ROOT_Z = Y(2106), Y(2534), Z(675)
STAB_TIP_LE, STAB_TIP_TE, STAB_TIP_Z = Y(2383), Y(2510), Z(730)
STAB_THICKNESS = 0.045

FIN_ROOT_Z, FIN_TIP_Z = Z(470), Z(97)
FIN_ROOT_LE, FIN_ROOT_TE = Y(2000), Y(2448)
FIN_TIP_LE, FIN_TIP_TE = Y(2420), Y(2625)
FIN_THICKNESS = 0.045
RUDDER_HINGE = 0.62
RUDDER_SPAN = (FIN_ROOT_Z + 0.12, Z(140))

NOZZLE_Z = Z(672)
NOZZLE_R0, NOZZLE_R1 = 0.58, 0.44
NOZZLE_Y0, NOZZLE_Y1 = Y(2285), Y(2550)

GROUND_Z = FIN_TIP_Z - 5.09  # published height
NOSE_WHEEL = {"at": (0, Y(930), GROUND_Z + 0.26), "radius": 0.26, "width": 0.14}
MAIN_WHEEL = {"at": (1.18, Y(1580), GROUND_Z + 0.35), "radius": 0.35, "width": 0.20}

kit.HULL = {"size": [2.0, 1.8, 14.6], "at": [0, -0.1, -1.03]}
kit.HITBOXES = {
    "Cockpit": {"size": [0.9, 1.0, 2.2], "at": [0, 0.6, -3.8]},
    "Fuselage": {"size": [1.8, 1.6, 6.0], "at": [0, -0.1, -1.5]},
    "Engine": {"size": [1.6, 1.4, 4.5], "at": [0, 0, 3.9]},
    "WingL": {"size": [3.8, 0.35, 3.4], "at": [-2.6, round(WING_Z, 2), 1.4]},
    "WingR": {"size": [3.8, 0.35, 3.4], "at": [2.6, round(WING_Z, 2), 1.4]},
    "Tail": {"size": [5.6, 3.0, 3.6], "at": [0, 0.8, 5.0]},
}
EYE = (0, Y(790), 0.95)
kit.ATTACHMENTS = {
    "CockpitEye": EYE,
    "GunMuzzle": (-0.55, Y(800), 0.30),  # the M61's port above the left strake
    "Nozzle1": (0, NOZZLE_Y1, NOZZLE_Z),
    "WingtipL": (-(kit.WING_TIP_X + 0.08), kit.RAIL_Y, WING_Z),
    "WingtipR": (kit.WING_TIP_X + 0.08, kit.RAIL_Y, WING_Z),
    "FlareDispenser": (0, Y(2250), -0.70),
    "ChaffDispenser": (0, Y(2200), -0.74),
    "ChaseCam": (0, -19.5, 3.6),
    "Hardpoint1": (-(kit.WING_TIP_X + 0.08), kit.RAIL_Y, WING_Z - 0.12),
    "Hardpoint2": (kit.WING_TIP_X + 0.08, kit.RAIL_Y, WING_Z - 0.12),
    "Hardpoint3": (-2.7, Y(1650), WING_Z - 0.20),
    "Hardpoint4": (2.7, Y(1650), WING_Z - 0.20),
    "Hardpoint5": (-1.9, Y(1600), WING_Z - 0.20),
    "Hardpoint6": (1.9, Y(1600), WING_Z - 0.20),
    "Hardpoint7": (0, Y(1500), -0.98),
}

# Cockpit interior (cockpit_kit.py, art pipeline §7), after F-16A cockpit photos: the wide HUD, the
# up-front controls under it, the attitude indicator and compass in the middle of a low panel, the radar
# display upper right and the threat display upper left, the side stick on the right console.
kit.COCKPIT = {
    "well": {"back": 3.40, "front": 4.60, "half_width": 0.38, "floor": -0.10, "flange": 0.06},
    "panel": {"distance": 0.65, "top": -0.20, "bottom": -0.62, "tilt": 15, "half_width": 0.34},
    "coaming": {"overhang": 0.04, "length": 0.30, "drop": 0.06},
    "consoles": {"top": -0.50, "width": 0.12, "aft": -0.35, "fore": 0.42, "throttle": 0.0},
    "stick": "side",
    "sight": "HUD",
    "palette": "US",
    "instruments": [
        {"name": "RWR", "kind": "Scope", "u": -0.235, "v": 0.09, "size": 0.075},
        {"name": "Airspeed", "kind": "Dial", "u": -0.12, "v": 0.075, "size": 0.07, "live": "Speed"},
        {"name": "UFC", "kind": "Lights", "u": 0.0, "v": 0.085, "size": 0.12},
        {"name": "Altimeter", "kind": "Dial", "u": 0.12, "v": 0.075, "size": 0.07, "live": "Altitude"},
        {"name": "RadarScope", "kind": "MFD", "u": 0.235, "v": 0.095, "size": 0.10, "live": "Radar"},
        {"name": "GMeter", "kind": "Dial", "u": -0.12, "v": 0.18, "size": 0.06, "live": "G"},
        {"name": "ADI", "kind": "Dial", "u": 0.0, "v": 0.19, "size": 0.10, "face": "attitude"},
        {"name": "VVI", "kind": "Dial", "u": 0.12, "v": 0.18, "size": 0.06},
        {"name": "Fuel", "kind": "Dial", "u": -0.235, "v": 0.21, "size": 0.06},
        {"name": "RPM", "kind": "Dial", "u": 0.235, "v": 0.215, "size": 0.06, "live": "RPM"},
        {"name": "Clock", "kind": "Dial", "u": -0.12, "v": 0.285, "size": 0.05},
        {"name": "HSI", "kind": "Dial", "u": 0.0, "v": 0.30, "size": 0.09, "face": "compass"},
        {"name": "FTIT", "kind": "Dial", "u": 0.235, "v": 0.30, "size": 0.05},
    ],
}


# ---------------------------------------------------------------------------------------------------
# Builders
# ---------------------------------------------------------------------------------------------------


def intake_ring(xd, scale=1.0):
    i = INTAKE
    zc = (i["top"] + i["bottom"]) / 2
    hh = (i["top"] - i["bottom"]) / 2 * scale
    hw = i["hw"] * scale
    pts = []
    for k in range(20):
        ang = 2 * math.pi * k / 20
        c, s = math.cos(ang), math.sin(ang)
        x = hw * math.copysign(abs(c) ** (2 / 3.0), c)
        z = zc + hh * math.copysign(abs(s) ** (2 / 3.0), s)
        pts.append((x, Y(xd), z))
    return pts


def build_intake(col):
    """The chin intake: a rounded box under the forward fuselage, faired into the belly. Its recessed
    mouth is a separate dark part."""
    i = INTAKE
    rings = [intake_ring(i["lip"] + 25, 0.88), intake_ring(i["lip"] + 2, 0.90), intake_ring(i["lip"])]
    rings += [intake_ring(xd) for xd in (850, 950, 1050, i["fade"])]
    kit.make_object("Intake", *kit.lofted(rings, True, True), col, "Body")
    duct = kit.lofted([intake_ring(i["lip"] + 23, 0.87), intake_ring(i["lip"] + 24, 0.87)], True, True)
    kit.make_object("IntakeDuct", *duct, col, "Body")


def build_strakes(col):
    """Leading-edge extensions from the canopy to the wing, and the shelves beside the tail."""
    parts = []
    z, th = WING_Z, 0.03
    for side in (1, -1):
        top, bottom, edge = [], [], []
        for hw, xd in LERX_EDGE:
            y = Y(xd)
            inner = 0.42
            top.append((side * inner, y, z + th))
            bottom.append((side * inner, y, z - th))
            edge.append((side * hw, y, z))
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
        x0, x1, hw = SHELF
        y0, y1 = Y(x0), Y(x1)
        parts.append(kit.box((side * (0.55 + hw) / 2, (y0 + y1) / 2, STAB_ROOT_Z), (hw - 0.55, y0 - y1, 0.06)))
    v, f = kit.merge(*parts)
    kit.make_object("Strakes", v, f, col, "Body")


def build_tail(col_wings, col_body):
    root_le, root_te = (STAB_ROOT_X, STAB_ROOT_LE, STAB_ROOT_Z), (STAB_ROOT_X, STAB_ROOT_TE, STAB_ROOT_Z)
    tip_le, tip_te = (STAB_TIP_X, STAB_TIP_LE, STAB_TIP_Z), (STAB_TIP_X, STAB_TIP_TE, STAB_TIP_Z)
    anh = math.atan2(STAB_ROOT_Z - STAB_TIP_Z, STAB_TIP_X - STAB_ROOT_X)
    normal = (math.sin(anh), 0, math.cos(anh))
    pivot_y = STAB_ROOT_LE - (STAB_ROOT_LE - STAB_ROOT_TE) * 0.40
    for side, name in ((1, "R"), (-1, "L")):
        v, f = kit.panel(root_le, root_te, tip_le, tip_te, normal, STAB_THICKNESS, 0.0, 1.0, 0, 1, 6, 10)
        if side < 0:
            v, f = kit.mirror_x(v), kit.flip_faces(f)
        # Tailerons: pitch, and roll together with the flaperons
        kit.make_object(f"Stabilator{name}", v, f, col_wings, "Wings", "ControlSurface",
                        origin=(side * STAB_ROOT_X, pivot_y, STAB_ROOT_Z),
                        hinge={"axis": (1, 0, 0), "min": -25, "max": 25, "control": "Elevon" + name})

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
        # The fin's base fairing on the spine
        kit.box((0, (Y(2000) + Y(2450)) / 2, (Z(470) + Z(548)) / 2), (0.36, Y(2000) - Y(2450), Z(470) - Z(548) + 0.04)),
    ]
    outline = [(Y(1780), Z(548)), (Y(2000), Z(470)), (Y(2000), Z(548))]
    half = [0.04, 0.04, 0.04]
    n = len(outline)
    fv = [(-t, y, z) for (y, z), t in zip(outline, half)] + [(t, y, z) for (y, z), t in zip(outline, half)]
    ff = [tuple(range(n)), tuple(reversed(range(n, 2 * n)))] + [(i, n + i, n + (i + 1) % n, (i + 1) % n) for i in range(n)]
    fin.append((fv, ff))
    v, f = kit.merge(*fin)
    kit.make_object("Fin", v, f, col_body, "Body")
    v, f = kit.panel(*g, RUDDER_HINGE, 1.0, frac(RUDDER_SPAN[0]), frac(RUDDER_SPAN[1]), 6, 6)
    a, b = kit.hinge_line(*g[:4], RUDDER_HINGE, frac(RUDDER_SPAN[0]), frac(RUDDER_SPAN[1]))
    kit.make_object("Rudder", v, f, col_body, "Body", "ControlSurface", origin=tuple(a.lerp(b, 0.5)),
                    hinge={"axis": tuple(b - a), "min": -25, "max": 25, "control": "Rudder"})

    parts = []
    outline = [(Y(1835), Z(790)), (Y(1900), Z(905)), (Y(2080), Z(875)), (Y(2080), Z(805))]
    for side in (1, -1):
        cant = math.radians(15)
        pts = []
        for y, z in outline:
            depth = Z(790) - z
            pts.append((side * (0.45 + max(depth, 0) * math.tan(cant)), y, z))
        t = 0.02
        n = len(pts)
        fv = [(p[0] - t, p[1], p[2]) for p in pts] + [(p[0] + t, p[1], p[2]) for p in pts]
        ff = [tuple(range(n)), tuple(reversed(range(n, 2 * n)))] + [(i, n + i, n + (i + 1) % n, (i + 1) % n) for i in range(n)]
        parts.append((fv, ff))
    v, f = kit.merge(*parts)
    kit.make_object("VentralFins", v, f, col_body, "Body")


def build_engine(col):
    p0, p1 = (0, NOZZLE_Y0, NOZZLE_Z), (0, NOZZLE_Y1, NOZZLE_Z)
    nv, nf = kit.cylinder(p0, p1, NOZZLE_R0, 24, radius1=NOZZLE_R1, caps=False)
    iv, i_f = kit.cylinder(p0, p1, NOZZLE_R0 - 0.05, 24, radius1=NOZZLE_R1 - 0.035, caps=False)
    n = 24
    lip = [(n + i, n + (i + 1) % n, len(nv) + n + (i + 1) % n, len(nv) + n + i) for i in range(n)]
    verts, faces = kit.merge((nv, nf), (iv, kit.flip_faces(i_f)))
    kit.make_object("Nozzle", verts, faces + lip, col, "Details", "Nozzle", extra={"engine": "C"})
    cv, cf = kit.cylinder((0, NOZZLE_Y1 + 0.2, NOZZLE_Z), (0, NOZZLE_Y0 + 0.05, NOZZLE_Z), NOZZLE_R1 - 0.05, 18,
                          radius1=0.06, caps=True)
    kit.make_object("Afterburner", cv, cf, col, "Details", "Afterburner", extra={"engine": "C"})


def build_seat(col):
    _, ey, ez = EYE
    parts = [
        kit.box((0, ey - 0.02, ez - 0.70), (0.46, 0.48, 0.10)),
        kit.box((0, ey - 0.36, ez - 0.36), (0.46, 0.12, 0.70)),
        kit.box((0, ey - 0.34, ez + 0.08), (0.34, 0.20, 0.24)),
    ]
    v, f = kit.merge(*parts)
    kit.make_object("EjectionSeat", v, f, col, "Details")


def build_pitot(col):
    v, f = kit.cylinder((0, Y(0), Z(722)), (0, Y(90), Z(718)), 0.02, 8)
    kit.make_object("Pitot", v, f, col, "Details")


def build_gear(col):
    nx, ny, nz = NOSE_WHEEL["at"]
    top = (0, ny + 0.10, INTAKE["bottom"] + 0.05)
    v, f = kit.cylinder(top, (0, ny, nz + 0.10), 0.06, 10)
    kit.make_object("NoseGearStrut", v, f, col, "Details", "Gear", origin=top,
                    hinge={"axis": (1, 0, 0), "min": 0, "max": 95, "control": "Gear"})
    v, f = kit.wheel(NOSE_WHEEL["at"], NOSE_WHEEL["radius"], NOSE_WHEEL["width"])
    kit.make_object("NoseGearWheel", v, f, col, "Details", "GearWheel", origin=NOSE_WHEEL["at"],
                    hinge={"axis": (1, 0, 0), "min": -720, "max": 720, "control": "Wheel"})
    for side, name in ((1, "R"), (-1, "L")):
        v, f = kit.box((side * 0.16, ny + 0.1, INTAKE["bottom"] - 0.12), (0.03, 0.7, 0.24))
        kit.make_object(f"NoseGearDoor{name}", v, f, col, "Details", "GearDoor",
                        origin=(side * 0.14, ny + 0.1, INTAKE["bottom"] - 0.01),
                        hinge={"axis": (0, 1, 0), "min": 0, "max": 85, "control": "GearDoor"})
    mx, my, mz = MAIN_WHEEL["at"]
    for side, name in ((1, "R"), (-1, "L")):
        top = (side * 0.62, my + 0.12, -0.85)
        v, f = kit.cylinder(top, (side * (mx - 0.12), my, mz + 0.08), 0.08, 10)
        kit.make_object(f"MainGearStrut{name}", v, f, col, "Details", "Gear", origin=top,
                        hinge={"axis": (0, 1, 0), "min": 0, "max": 90, "control": "Gear"})
        centre = (side * mx, my, mz)
        v, f = kit.wheel(centre, MAIN_WHEEL["radius"], MAIN_WHEEL["width"])
        kit.make_object(f"MainGearWheel{name}", v, f, col, "Details", "GearWheel", origin=centre,
                        hinge={"axis": (1, 0, 0), "min": -720, "max": 720, "control": "Wheel"})
        v, f = kit.box((side * 0.72, my, -1.05), (0.04, 1.0, 0.40))
        kit.make_object(f"MainGearDoor{name}", v, f, col, "Details", "GearDoor", origin=(side * 0.70, my, -0.87),
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
    build_intake(cols["Body"])
    build_strakes(cols["Body"])
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
