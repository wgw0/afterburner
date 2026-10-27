"""
Afterburner: MiG-23MLD base mesh generator (Blender 4.x / 5.x).

Builds a mid-poly, modular MiG-23MLD at real-world size, measured from a reference drawing, in the same
form as the F-5E (f5e_generate.py, whose helpers this uses): separate objects per part, moving parts with
their origin on the hinge line, four texture sets, a manifest for the Studio assembler, an FBX, and the
cockpit well.

  * the fuselage: radome, canopy, dorsal spine running into the long dorsal fin, the big side intakes
    with splitter plates, the GSh-23L gun pack under the belly
  * the fixed wing gloves with their dogtooth, and the swing wings set at the 45-degree combat sweep
    (origin on the pivot), with leading-edge slats and trailing-edge flaps
  * all-moving tailerons: they roll the jet as well as pitch it, so they use the elevon controls
  * the fin and rudder with the fin-root fairing, the ventral fin
  * single nozzle with afterburner cone, ejection seat, pitot, landing gear (struts, wheels, doors)

Run headless:
  blender -b --python tools/blender/mig23_generate.py -- --out <dir> --manifest-luau tools/Manifests/MiG23MLD.luau

Reference: the Commons three-view "Mikoyan-Gurevich MiG-23MF 3-view.svg" (Kaboldy, CC BY-SA 3.0),
rendered 3840 px wide: side view on top and top view below, both nose left with the pitot tip at x = 22.
Stations (xd) are pixels aft of it; heights are side-view rows (row 500, the nozzle's axis, is z = 0);
half widths are pixels from the top view's centreline (row 1980). The scale comes from the MiG-23MLD's
published 16.70 m length (180 px/m); the spread span then comes out 13.3 m against the published 13.97 m.
The top view shows one wing spread (16 degrees) and one fully swept: the spread wing is measured and
turned 29 degrees about its pivot. The MF and MLD share the airframe's shape at this level of detail. See
docs/art/reference/MiG23MLD/SOURCES.md (kept out of git).
"""

import argparse
import math
import os
import sys

from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import f5e_generate as kit  # noqa: E402  (shared helpers; its module settings are switched below)

kit.AIRFRAME = "MiG23MLD"
kit.REF_PX_PER_M = 180.0
kit.REF_PITOT_XD = 0.0
kit.REF_Z0_ROW = 500.0
kit.CG_FROM_PITOT = 1720 / 180.0  # just ahead of the wing pivot
kit.LENGTH = 16.70
kit.SPINE_UPPER_ONLY = True
Y, Z = kit.Y, kit.Z
PX = kit.REF_PX_PER_M


def W(px):
    return px / PX


kit.FUSELAGE = [
    (205, 0.012, -0.24, -0.20, -0.20, 0.0, 2.0),  # radome tip
    (300, W(45), -0.42, 0.067, 0.067, 0.0, 2.0),
    (400, W(55), -0.49, 0.19, 0.19, 0.0, 2.0),
    (520, W(65), -0.54, 0.28, 0.28, 0.0, 2.1),  # radome joint
    (600, W(70), -0.56, 0.33, 0.33, 0.0, 2.2),
    (680, W(75), -0.56, 0.39, 0.39, 0.0, 2.4),  # windscreen base
    (800, W(77), -0.57, 0.38, 0.38, 0.0, 2.5),
    (950, W(79), -0.58, 0.38, 0.38, 0.0, 2.5),
    (1000, 0.50, -0.58, 0.40, 0.81, 0.35, 2.5),  # the spine rises inside the canopy's rear
    (1100, 0.60, -0.58, 0.45, 0.80, 0.38, 2.5),
    (1300, 0.75, -0.58, 0.55, 0.80, 0.42, 2.5),
    (1600, 0.85, -0.58, 0.65, 0.79, 0.45, 2.6),
    (1800, 0.86, -0.58, 0.70, 0.79, 0.40, 2.6),
    (2000, 0.83, -0.58, 0.78, 0.78, 0.0, 2.5),
    (2250, 0.76, -0.62, 0.76, 0.76, 0.0, 2.4),
    (2400, 0.73, -0.63, 0.70, 0.70, 0.0, 2.3),
    (2600, 0.66, -0.60, 0.68, 0.68, 0.0, 2.2),
    (2800, 0.60, -0.52, 0.62, 0.62, 0.0, 2.1),  # nozzle
]
kit.FUSELAGE_RINGS = 62
kit.FUSELAGE_SEGMENTS = 44

kit.INTAKES = [
    (1060, 0.88, 0.75, -0.40),  # the lip; the splitter plates stand ahead of it
    (1120, 0.92, 0.76, -0.43),
    (1222, 0.94, 0.76, -0.45),
    (1500, 0.90, 0.72, -0.46),
    (1750, 0.86, 0.70, -0.45),
]
kit.INTAKE_LIP_SWEEP = 0.10

kit.CANOPY = [
    (680, 0.10, 0.40),
    (720, 0.28, 0.55),
    (780, 0.34, 0.70),
    (830, 0.37, 0.79),
    (880, 0.38, 0.81),
    (950, 0.38, 0.81),
    (1000, 0.34, 0.81),
    (1040, 0.28, 0.80),
]
kit.CANOPY_FRAMES = (830, 990)

# Wing: measured spread (16 degrees), turned to the 45-degree combat sweep about the pivot
WING_Z = Z(410)
PIVOT = (W(268), Y(1747))
SWEEP_TURN = math.radians(29)
WING_ROOT_X, WING_TIP_X = 1.45, W(1182)
WING_THICKNESS = 0.045


def spread_le_y(x):
    return Y(1597 + (x * PX - 320) * 0.326)


def spread_te_y(x):
    return Y(2050 + (x * PX - 257) * (2053 - 2050) / (1182 - 257))


def swept(p):
    """A point of the spread wing (Blender x, y, z), turned back to the combat sweep about the pivot."""
    x, y, z = p
    px, py = PIVOT
    c, s = math.cos(SWEEP_TURN), math.sin(SWEEP_TURN)
    return (px + (x - px) * c + (y - py) * s, py - (x - px) * s + (y - py) * c, z)


SLAT_CHORD, SLAT_SPAN = 0.15, (0.45, 1.0)
FLAP_HINGE, FLAP_SPAN = 0.75, (0.05, 0.80)

# Gloves: fixed, with the dogtooth at their leading edge. (half width m, xd)
GLOVE = [(0.92, 1222), (W(320), 1597), (W(340), 1700), (W(290), 1990), (0.92, 1990)]

# Tailerons: root at the fuselage, the raked tip approximated by its mid chord
STAB_ROOT_X, STAB_TIP_X = 0.65, 2.45
STAB_ROOT_LE, STAB_ROOT_TE = Y(2386), Y(2893)
STAB_TIP_LE, STAB_TIP_TE = Y(2848), Y(2925)
STAB_Z = Z(445)
STAB_THICKNESS = 0.045

FIN_ROOT_Z, FIN_TIP_Z = 0.76, Z(28)
FIN_ROOT_LE, FIN_ROOT_TE = Y(1934), Y(2862)
FIN_TIP_LE, FIN_TIP_TE = Y(2798), Y(2918)
FIN_THICKNESS = 0.05
RUDDER_HINGE = 0.80
RUDDER_SPAN = (1.00, 2.17)

NOZZLE_Z, NOZZLE_R = Z(500), 0.55
NOZZLE_Y0, NOZZLE_Y1 = Y(2790), Y(2858)

NOSE_WHEEL = {"at": (0, Y(874), -1.30), "radius": 0.27, "width": 0.16}
MAIN_WHEEL = {"at": (1.33, Y(1866), -1.17), "radius": 0.39, "width": 0.24}

TIP = swept((WING_TIP_X, (spread_le_y(WING_TIP_X) + spread_te_y(WING_TIP_X)) / 2, WING_Z))

kit.HULL = {"size": [2.0, 1.6, 15.2], "at": [0, 0.1, -0.9]}
kit.HITBOXES = {
    "Cockpit": {"size": [0.9, 1.0, 2.4], "at": [0, 0.4, -4.6]},
    "Fuselage": {"size": [1.9, 1.5, 6.0], "at": [0, 0.1, -2.0]},
    "Engine": {"size": [1.7, 1.5, 5.0], "at": [0, 0.1, 4.0]},
    "WingL": {"size": [4.6, 0.4, 3.6], "at": [-3.3, round(WING_Z, 2), 1.6]},
    "WingR": {"size": [4.6, 0.4, 3.6], "at": [3.3, round(WING_Z, 2), 1.6]},
    "Tail": {"size": [5.0, 2.6, 3.4], "at": [0, 0.7, 6.5]},
}
EYE = (0, Y(935), 0.64)
kit.ATTACHMENTS = {
    "CockpitEye": EYE,
    "GunMuzzle": (0, Y(1150), -0.72),  # GSh-23L under the belly
    "Nozzle1": (0, NOZZLE_Y1, NOZZLE_Z),
    "WingtipL": (-TIP[0], TIP[1], TIP[2]),
    "WingtipR": (TIP[0], TIP[1], TIP[2]),
    "FlareDispenser": (0, Y(2450), -0.62),
    "ChaffDispenser": (0, Y(2400), -0.64),
    "ChaseCam": (0, -21.0, 3.8),
    "Hardpoint1": (-1.55, Y(1500), WING_Z - 0.15),  # glove pylons
    "Hardpoint2": (1.55, Y(1500), WING_Z - 0.15),
    "Hardpoint3": (-0.62, Y(1350), -0.50),  # under the intakes
    "Hardpoint4": (0.62, Y(1350), -0.50),
    "Hardpoint5": (0, Y(1650), -0.65),
}

# Cockpit interior (cockpit_kit.py, art pipeline §7), after MiG-23 cockpit photos: the ASP-23 sight on the
# glareshield, the Sapfir-23 radar scope under it, flight instruments left, engine instruments right.
kit.COCKPIT = {
    "well": {"back": Y(985), "front": 5.12, "half_width": 0.32, "floor": -0.32, "flange": 0.06},
    "panel": {"distance": 0.65, "top": -0.15, "bottom": -0.58, "tilt": 10, "half_width": 0.30},
    "coaming": {"overhang": 0.04, "length": 0.32, "drop": 0.06},
    "consoles": {"top": -0.52, "width": 0.09, "aft": -0.35, "fore": 0.42, "throttle": 0.02},
    "stick": "centre",
    "stick_fore": 0.38,
    "sight": "Gunsight",
    "sight_body": (0.13, 0.15, 0.09),
    "sight_glass": (0.13, 0.11),
    "palette": "Soviet",
    "instruments": [
        {"name": "RadarScope", "kind": "Scope", "u": 0.0, "v": 0.08, "size": 0.10, "hood": 0.05, "live": "Radar"},
        {"name": "GMeter", "kind": "Dial", "u": -0.205, "v": 0.075, "size": 0.055, "live": "G"},
        {"name": "Airspeed", "kind": "Dial", "u": -0.12, "v": 0.08, "size": 0.075, "live": "Speed"},
        {"name": "RPM", "kind": "Dial", "u": 0.12, "v": 0.08, "size": 0.075, "live": "RPM"},
        {"name": "EGT", "kind": "Dial", "u": 0.205, "v": 0.075, "size": 0.055},
        {"name": "AOA", "kind": "Dial", "u": -0.205, "v": 0.16, "size": 0.05},
        {"name": "Altimeter", "kind": "Dial", "u": -0.12, "v": 0.17, "size": 0.075, "live": "Altitude"},
        {"name": "ADI", "kind": "Dial", "u": 0.0, "v": 0.195, "size": 0.10, "face": "attitude"},
        {"name": "VVI", "kind": "Dial", "u": 0.12, "v": 0.17, "size": 0.065},
        {"name": "Sweep", "kind": "Dial", "u": 0.205, "v": 0.16, "size": 0.05},
        {"name": "Clock", "kind": "Dial", "u": -0.15, "v": 0.27, "size": 0.05},
        {"name": "HSI", "kind": "Dial", "u": 0.0, "v": 0.30, "size": 0.09, "face": "compass"},
        {"name": "Caution", "kind": "Lights", "u": 0.15, "v": 0.275, "size": 0.09},
    ],
}


# ---------------------------------------------------------------------------------------------------
# Builders
# ---------------------------------------------------------------------------------------------------


def slab(outline, z, thickness):
    """A flat plate from a convex outline [(x, y)], thickness along z. Closed."""
    n = len(outline)
    top = [(x, y, z + thickness / 2) for x, y in outline]
    bottom = [(x, y, z - thickness / 2) for x, y in outline]
    faces = [tuple(range(n)), tuple(reversed(range(n, 2 * n)))]
    faces += [(i, n + i, n + (i + 1) % n, (i + 1) % n) for i in range(n)]
    return top + bottom, faces


def build_body_extras(col):
    """Gloves, splitter plates and the gun pack, all fixed parts of the Body set."""
    parts = []
    for side in (1, -1):
        outline = [(side * hw, Y(xd)) for hw, xd in GLOVE]
        if side < 0:
            outline = list(reversed(outline))
        parts.append(slab(outline, WING_Z, 0.10))
        x = side * (kit.fuselage_params(1040)[0] + 0.04)
        y0, y1 = Y(1000), Y(1110)
        v = [(x - 0.012, y0, -0.36), (x + 0.012, y0, -0.36), (x + 0.012, y1, -0.40), (x - 0.012, y1, -0.40),
             (x - 0.012, y0, 0.76), (x + 0.012, y0, 0.76), (x + 0.012, y1, 0.78), (x - 0.012, y1, 0.78)]
        f = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
        parts.append((v, f))
    parts.append(kit.box((0, (Y(1100) + Y(1450)) / 2, -0.66), (0.34, Y(1100) - Y(1450), 0.16)))
    parts.append(kit.cylinder((0, Y(1100), -0.70), (0, Y(1150), -0.70), 0.03, 8))
    v, f = kit.merge(*parts)
    kit.make_object("Gloves", v, f, col, "Body")


def build_wings(col):
    up = (0, 0, 1)
    rl = (WING_ROOT_X, spread_le_y(WING_ROOT_X), WING_Z)
    rt = (WING_ROOT_X, spread_te_y(WING_ROOT_X), WING_Z)
    tl = (WING_TIP_X, spread_le_y(WING_TIP_X), WING_Z)
    tt = (WING_TIP_X, spread_te_y(WING_TIP_X), WING_Z)
    pivot = (PIVOT[0], PIVOT[1], WING_Z)

    def sw(v):
        return [swept(p) for p in v]

    for side, name in ((1, "R"), (-1, "L")):
        def m(v):
            return v if side > 0 else kit.mirror_x(v)

        def mf(f):
            return f if side > 0 else kit.flip_faces(f)

        geo = (rl, rt, tl, tt, up, WING_THICKNESS)
        box = [
            kit.panel(*geo, 0.0, FLAP_HINGE, 0, SLAT_SPAN[0], 4, 10),
            kit.panel(*geo, SLAT_CHORD, FLAP_HINGE, SLAT_SPAN[0], 1, 6, 8),
            kit.panel(*geo, FLAP_HINGE, 1.0, 0, FLAP_SPAN[0], 1, 4),
            kit.panel(*geo, FLAP_HINGE, 1.0, FLAP_SPAN[1], 1, 2, 4),
        ]
        v, f = kit.merge(*box)
        # The wing's origin is on its pivot, so a sweep could be animated later
        kit.make_object(f"Wing{name}", m(sw(v)), mf(f), col, "Wings", origin=tuple(m([swept(pivot)])[0]))
        for part, (f0, f1), (s0, s1), lims, control in (
            ("LEFlap", (0.0, SLAT_CHORD), SLAT_SPAN, (0, 20), "LEFlap"),
            ("Flap", (FLAP_HINGE, 1.0), FLAP_SPAN, (0, 40), "Flap"),
        ):
            v, f = kit.panel(*geo, f0, f1, s0, s1, 4, 6)
            hinge_f = f1 if part == "LEFlap" else f0
            a, b = kit.hinge_line(rl, rt, tl, tt, hinge_f, s0, s1)
            a, b = Vector(swept(tuple(a))), Vector(swept(tuple(b)))
            kit.make_object(f"{part}{name}", m(sw(v)), mf(f), col, "Wings", "ControlSurface",
                            origin=tuple(m([tuple(a.lerp(b, 0.5))])[0]),
                            hinge={"axis": tuple(m([tuple(b - a)])[0]), "min": lims[0], "max": lims[1], "control": control})


def build_tail(col_wings, col_body):
    up = (0, 0, 1)
    root_le, root_te = (STAB_ROOT_X, STAB_ROOT_LE, STAB_Z), (STAB_ROOT_X, STAB_ROOT_TE, STAB_Z)
    tip_le, tip_te = (STAB_TIP_X, STAB_TIP_LE, STAB_Z), (STAB_TIP_X, STAB_TIP_TE, STAB_Z)
    pivot_y = STAB_ROOT_LE - (STAB_ROOT_LE - STAB_ROOT_TE) * 0.40
    for side, name in ((1, "R"), (-1, "L")):
        v, f = kit.panel(root_le, root_te, tip_le, tip_te, up, STAB_THICKNESS, 0.0, 1.0, 0, 1, 6, 10)
        if side < 0:
            v, f = kit.mirror_x(v), kit.flip_faces(f)
        # Tailerons: pitch and roll mixed, like elevons
        kit.make_object(f"Stabilator{name}", v, f, col_wings, "Wings", "ControlSurface",
                        origin=(side * STAB_ROOT_X, pivot_y, STAB_Z),
                        hinge={"axis": (1, 0, 0), "min": -25, "max": 20, "control": "Elevon" + name})

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
        kit.cylinder((0, Y(2480), Z(345)), (0, Y(2970), Z(345)), 0.10, 10, radius1=0.04),  # fin-root fairing
    ]
    # Long dorsal fillet from the spine into the fin's leading edge
    outline = [(Y(1700), 0.78), (Y(2000), 1.00), (Y(2238), Z(245)), (Y(2238) - 0.6, FIN_ROOT_Z)]
    half = [0.04, 0.035, 0.03, 0.045]
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

    outline = [(Y(2298), -0.62), (Y(2498), -1.25), (Y(2668), -1.25), (Y(2678), -1.00), (Y(2650), -0.58)]
    half = [0.035, 0.025, 0.02, 0.025, 0.035]
    n = len(outline)
    fv = [(-t, y, z) for (y, z), t in zip(outline, half)] + [(t, y, z) for (y, z), t in zip(outline, half)]
    ff = [tuple(range(n)), tuple(reversed(range(n, 2 * n)))] + [(i, n + i, n + (i + 1) % n, (i + 1) % n) for i in range(n)]
    kit.make_object("VentralFin", fv, ff, col_body, "Body")


def build_engine(col):
    p0, p1 = (0, NOZZLE_Y0, NOZZLE_Z), (0, NOZZLE_Y1, NOZZLE_Z)
    nv, nf = kit.cylinder(p0, p1, NOZZLE_R + 0.05, 24, radius1=NOZZLE_R, caps=False)
    iv, i_f = kit.cylinder(p0, p1, NOZZLE_R - 0.02, 24, radius1=NOZZLE_R - 0.035, caps=False)
    n = 24
    lip = [(n + i, n + (i + 1) % n, len(nv) + n + (i + 1) % n, len(nv) + n + i) for i in range(n)]
    verts, faces = kit.merge((nv, nf), (iv, kit.flip_faces(i_f)))
    kit.make_object("Nozzle", verts, faces + lip, col, "Details", "Nozzle", extra={"engine": "C"})
    cv, cf = kit.cylinder((0, NOZZLE_Y1 + 0.15, NOZZLE_Z), (0, NOZZLE_Y0 + 0.05, NOZZLE_Z), NOZZLE_R - 0.06, 18,
                          radius1=0.06, caps=True)
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
    v, f = kit.cylinder((0, Y(0), Z(548)), (0, Y(205), Z(541)), 0.022, 8)
    kit.make_object("Pitot", v, f, col, "Details")


def build_gear(col):
    nx, ny, nz = NOSE_WHEEL["at"]
    top = (0, ny + 0.10, -0.50)
    v, f = kit.cylinder(top, (0, ny, nz + 0.10), 0.06, 10)
    kit.make_object("NoseGearStrut", v, f, col, "Details", "Gear", origin=top,
                    hinge={"axis": (1, 0, 0), "min": 0, "max": 95, "control": "Gear"})
    v, f = kit.wheel(NOSE_WHEEL["at"], NOSE_WHEEL["radius"], NOSE_WHEEL["width"])
    kit.make_object("NoseGearWheel", v, f, col, "Details", "GearWheel", origin=NOSE_WHEEL["at"],
                    hinge={"axis": (1, 0, 0), "min": -720, "max": 720, "control": "Wheel"})
    for side, name in ((1, "R"), (-1, "L")):
        v, f = kit.box((side * 0.16, ny + 0.1, -0.66), (0.03, 0.7, 0.26))
        kit.make_object(f"NoseGearDoor{name}", v, f, col, "Details", "GearDoor", origin=(side * 0.14, ny + 0.1, -0.54),
                        hinge={"axis": (0, 1, 0), "min": 0, "max": 85, "control": "GearDoor"})
    mx, my, mz = MAIN_WHEEL["at"]
    for side, name in ((1, "R"), (-1, "L")):
        top = (side * 0.80, my + 0.15, -0.45)  # the MiG-23's main gear folds into the fuselage
        v, f = kit.cylinder(top, (side * (mx - 0.14), my, mz + 0.10), 0.08, 10)
        kit.make_object(f"MainGearStrut{name}", v, f, col, "Details", "Gear", origin=top,
                        hinge={"axis": (0, 1, 0), "min": 0, "max": 90, "control": "Gear"})
        centre = (side * mx, my, mz)
        v, f = kit.wheel(centre, MAIN_WHEEL["radius"], MAIN_WHEEL["width"])
        kit.make_object(f"MainGearWheel{name}", v, f, col, "Details", "GearWheel", origin=centre,
                        hinge={"axis": (1, 0, 0), "min": -720, "max": 720, "control": "Wheel"})
        v, f = kit.box((side * 0.78, my, -0.72), (0.04, 1.0, 0.44))
        kit.make_object(f"MainGearDoor{name}", v, f, col, "Details", "GearDoor", origin=(side * 0.76, my, -0.52),
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
    build_body_extras(cols["Body"])
    kit.build_canopy(cols["Glass"], cols["Body"])
    build_wings(cols["Wings"])
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
