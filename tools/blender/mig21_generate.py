"""
Afterburner: MiG-21bis base mesh generator (Blender 4.x / 5.x).

Builds a mid-poly, modular MiG-21bis at real-world size, measured from reference drawings, in the same
form as the F-5E (see f5e_generate.py, whose helpers this script uses): separate objects per part,
moving parts with their origin on the hinge line, four texture sets, a manifest for the Studio
assembler, and an FBX for the 3D importer.

  * a round fuselage with the nose intake (open duct) and its shock cone, the MiG-21bis's big
    dorsal spine, canopy and frame
  * a 57° delta wing with constant-chord flaps and ailerons, all-moving swept stabilators with
    anti-flutter rods, the swept fin with rudder, the ventral fin
  * single nozzle with afterburner cone, ejection seat, the air-data boom above the intake
  * landing gear (struts, wheels, doors) as separate parts

Run headless:
  blender -b --python tools/blender/mig21_generate.py -- --out <dir> --manifest-luau tools/Manifests/MiG21bis.luau

Reference: the Wikimedia Commons three-view "Mikoyan-Gurevich MiG-21PF 3-view.svg" (2000 px wide copy),
scaled to the MiG-21bis's published span of 7.154 m (it also gives the published height to within 3%).
The drawing is of the earlier PF; the bis's larger dorsal spine is taken from photos (see
docs/art/reference/MiG21bis/SOURCES.md, kept out of git). The planform, fin, nose and tail are the same.
"""

import argparse
import math
import os
import sys

from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import f5e_generate as kit  # noqa: E402  (shared helpers; its module settings are switched below)

kit.AIRFRAME = "MiG21bis"
kit.LENGTH = round((1405 - 15.1) / 103.0, 2)

# Drawing calibration (2000 px wide copy): px per metre from the span, pitot tip, fuselage axis row
kit.REF_PX_PER_M = 103.0
kit.REF_PITOT_XD = 15.1
kit.REF_Z0_ROW = 270.7
kit.CG_FROM_PITOT = 7.43  # 25% of the mean aerodynamic chord (station 780) becomes the origin
Y, Z = kit.Y, kit.Z

# Fuselage stations: (xd, half width, bottom z, shoulder z, top z, spine half width, exponent).
# Round body; the spine rises out of it behind the canopy and runs almost level to the fin (MiG-21bis).
kit.FUSELAGE = [
    (180, 0.45, -0.46, 0.47, 0.47, 0.0, 2.0),  # intake lip
    (240, 0.483, -0.52, 0.51, 0.51, 0.0, 2.0),
    (300, 0.51, -0.55, 0.55, 0.55, 0.0, 2.05),
    (360, 0.528, -0.57, 0.62, 0.62, 0.0, 2.1),  # windscreen base
    (440, 0.548, -0.58, 0.64, 0.64, 0.0, 2.15),
    (540, 0.57, -0.59, 0.65, 0.65, 0.0, 2.2),
    (640, 0.60, -0.59, 0.65, 0.72, 0.32, 2.2),  # spine rises inside the canopy's rear
    (720, 0.62, -0.59, 0.62, 1.02, 0.42, 2.2),
    (800, 0.63, -0.59, 0.60, 1.05, 0.45, 2.2),
    (900, 0.62, -0.58, 0.58, 1.04, 0.45, 2.2),
    (1000, 0.60, -0.57, 0.56, 1.00, 0.42, 2.2),
    (1060, 0.58, -0.56, 0.55, 0.93, 0.36, 2.2),  # fin root
    (1150, 0.555, -0.54, 0.53, 0.76, 0.26, 2.15),
    (1250, 0.55, -0.52, 0.52, 0.60, 0.14, 2.1),
    (1340, 0.53, -0.50, 0.50, 0.50, 0.0, 2.05),
    (1375, 0.51, -0.48, 0.48, 0.48, 0.0, 2.0),  # nozzle
]
kit.FUSELAGE_RINGS = 60
kit.FUSELAGE_SEGMENTS = 44
INLET_DUCT_XD, INLET_DUCT_SCALE = 235, 0.80  # the recessed duct wall behind the lip

# Canopy: (xd, half width at the sill, top z)
kit.CANOPY = [
    (375, 0.08, 0.64),
    (400, 0.28, 0.84),
    (420, 0.36, 0.95),
    (440, 0.39, 1.02),
    (480, 0.41, 1.06),
    (540, 0.42, 1.07),
    (600, 0.41, 1.08),
    (660, 0.39, 1.07),
    (720, 0.33, 1.06),
    (760, 0.22, 1.05),  # into the spine
]
kit.CANOPY_FRAMES = (425, 560)

# Delta wing: 57° leading edge, straight trailing edge, clipped tip
WING_Z = Z(285.0)
WING_ROOT_X, WING_TIP_X = 0.55, 3.577
WING_SWEEP_LE = math.radians(57.1)
WING_TE_Y = Y(1090)
WING_THICKNESS = 0.045


def wing_le_y(x):
    return Y(569) - (x - 0.60) * math.tan(WING_SWEEP_LE)


CONTROL_CHORD = 0.48  # flaps and ailerons: constant-chord strips along the trailing edge
FLAP_SPAN = (0.60, 1.90)
AILERON_SPAN = (1.95, 3.20)

# Stabilators (all-moving), swept, with anti-flutter rods at the tips
STAB_ROOT_X, STAB_TIP_X = 0.45, 1.83
STAB_Z = Z(288.0)
STAB_THICKNESS = 0.045


def stab_le_y(x):
    return Y(1199) - (x - 0.52) * (140 / 85.4)


def stab_te_y(x):
    return Y(1400) - (x - 0.52) / (1.83 - 0.52) * (105 / kit.REF_PX_PER_M)


# Fin and rudder
FIN_ROOT_Z, FIN_TIP_Z = 0.62, Z(21.5)
FIN_ROOT_LE, FIN_ROOT_CHORD = Y(1045), (1395 - 1045) / kit.REF_PX_PER_M
FIN_TIP_LE, FIN_TIP_CHORD = Y(1410), (1540 - 1410) / kit.REF_PX_PER_M
FIN_THICKNESS = 0.045
RUDDER_HINGE = 0.72
RUDDER_SPAN = (0.80, 2.15)

NOZZLE_Z, NOZZLE_R = Z(272.7), 0.47
NOZZLE_Y0, NOZZLE_Y1 = Y(1372), Y(1405)

NOSE_WHEEL = {"at": (0, Y(410), Z(405)), "radius": 0.22, "width": 0.15}
MAIN_WHEEL = {"at": (1.39, Y(880), Z(387)), "radius": 0.40, "width": 0.20}

kit.HULL = {"size": [1.25, 1.25, 12.8], "at": [0, 0, -0.2]}
kit.HITBOXES = {
    "Cockpit": {"size": [0.9, 1.0, 2.4], "at": [0, 0.75, -2.2]},
    "Fuselage": {"size": [1.3, 1.25, 6.4], "at": [0, 0, -3.7]},
    "Engine": {"size": [1.3, 1.2, 6.0], "at": [0, 0, 2.9]},
    "WingL": {"size": [3.0, 0.4, 4.6], "at": [-2.1, round(WING_Z, 2), 0.6]},
    "WingR": {"size": [3.0, 0.4, 4.6], "at": [2.1, round(WING_Z, 2), 0.6]},
    "Tail": {"size": [3.8, 2.6, 4.0], "at": [0, 1.1, 5.3]},
}
kit.ATTACHMENTS = {
    "CockpitEye": (0, Y(545), 0.88),
    "GunMuzzle": (0, Y(640), -0.70),  # GSh-23L in its belly fairing
    "Nozzle1": (0, NOZZLE_Y1, NOZZLE_Z),
    "WingtipL": (-(WING_TIP_X + 0.02), Y(1065), WING_Z),
    "WingtipR": (WING_TIP_X + 0.02, Y(1065), WING_Z),
    "FlareDispenser": (0, Y(1250), -0.42),
    "ChaffDispenser": (0, Y(1200), -0.47),
    "ChaseCam": (0, -20.5, 3.5),
    "Hardpoint1": (-2.0, Y(800), WING_Z - 0.15),
    "Hardpoint2": (2.0, Y(800), WING_Z - 0.15),
    "Hardpoint3": (-2.95, Y(940), WING_Z - 0.15),
    "Hardpoint4": (2.95, Y(940), WING_Z - 0.15),
    "Hardpoint5": (0, Y(800), -0.78),
}


# Cockpit interior (cockpit_kit.py, art pipeline §7), from MiG-21bis cockpit photos (the Finnish MG-136 in
# docs/art/reference/MiG21bis/04_details): the big ASP-PFD sight on top, the RP-22 radar scope with its
# hood under it, flight instruments to the left, engine instruments to the right, the attitude
# indicator and the NPP compass below. Turquoise paint.
kit.COCKPIT = {
    "well": {"back": 1.90, "front": 3.10, "half_width": 0.34, "floor": -0.20, "flange": 0.07},
    "panel": {"distance": 0.68, "top": -0.15, "bottom": -0.60, "tilt": 10, "half_width": 0.33},
    "coaming": {"overhang": 0.04, "length": 0.40, "drop": 0.06},
    "consoles": {"top": -0.56, "width": 0.10, "aft": -0.35, "fore": 0.45, "throttle": 0.02},
    "stick": "centre",
    "stick_fore": 0.40,
    "sight": "Gunsight",
    "sight_body": (0.14, 0.16, 0.10),
    "sight_glass": (0.15, 0.13),
    "palette": "Soviet",
    "instruments": [
        {"name": "RadarScope", "kind": "Scope", "u": 0.0, "v": 0.085, "size": 0.115, "hood": 0.06, "live": "Radar"},
        {"name": "GMeter", "kind": "Dial", "u": -0.27, "v": 0.085, "size": 0.065, "live": "G"},
        {"name": "Airspeed", "kind": "Dial", "u": -0.165, "v": 0.08, "size": 0.09, "live": "Speed"},
        {"name": "RPM", "kind": "Dial", "u": 0.165, "v": 0.08, "size": 0.09, "live": "RPM"},
        {"name": "EGT", "kind": "Dial", "u": 0.27, "v": 0.085, "size": 0.065},
        {"name": "AOA", "kind": "Dial", "u": -0.27, "v": 0.185, "size": 0.06},
        {"name": "Altimeter", "kind": "Dial", "u": -0.165, "v": 0.19, "size": 0.09, "live": "Altitude"},
        {"name": "ADI", "kind": "Dial", "u": 0.0, "v": 0.215, "size": 0.11, "face": "attitude"},
        {"name": "VVI", "kind": "Dial", "u": 0.165, "v": 0.19, "size": 0.08},
        {"name": "RWR", "kind": "Dial", "u": 0.27, "v": 0.185, "size": 0.05},
        {"name": "Clock", "kind": "Dial", "u": -0.17, "v": 0.30, "size": 0.06},
        {"name": "HSI", "kind": "Dial", "u": 0.0, "v": 0.335, "size": 0.10, "face": "compass"},
        {"name": "Fuel", "kind": "Dial", "u": 0.17, "v": 0.30, "size": 0.075},
        {"name": "Caution", "kind": "Lights", "u": 0.265, "v": 0.29, "size": 0.10},
    ],
}


# ---------------------------------------------------------------------------------------------------
# Builders
# ---------------------------------------------------------------------------------------------------


panel_var = kit.panel_var


def build_fuselage(col):
    """The fuselage from the intake lip to the nozzle, with the duct wall folded back inside the lip
    (capped deep in the duct, which is painted dark)."""
    stations = kit.fuselage_stations()
    rings = [[(x, Y(xd), z) for x, z in kit.fuselage_ring(xd)] for xd in stations]
    lip_xd = kit.FUSELAGE[0][0]
    _, zb, zs, _, _, _ = kit.fuselage_params(lip_xd)
    cz = (zs + zb) / 2
    lip = kit.fuselage_ring(lip_xd)

    def inner(scale, xd):
        return [(x * scale, Y(xd), cz + (z - cz) * scale) for x, z in lip]

    rings = [inner(INLET_DUCT_SCALE, INLET_DUCT_XD), inner(0.9, lip_xd + 2)] + rings
    verts, faces = kit.lofted(rings, cap_start=True, cap_end=True)
    kit.make_object("Fuselage", verts, faces, col, "Body")


def build_inlet_cone(col):
    _, zb, zs, _, _, _ = kit.fuselage_params(180)
    cz = (zs + zb) / 2 - 0.04
    tip, base = (0, Y(60), cz), (0, Y(230), cz)
    cv, cf = kit.cylinder(tip, base, 0.004, 24, radius1=0.30, caps=True)
    bv, bf = kit.cylinder(base, (0, Y(275), cz), 0.30, 24, caps=True)
    verts, faces = kit.merge((cv, cf), (bv, bf))
    kit.make_object("InletCone", verts, faces, col, "Body")


def build_wings(col):
    root_le = (WING_ROOT_X, wing_le_y(WING_ROOT_X), WING_Z)
    root_te = (WING_ROOT_X, WING_TE_Y, WING_Z)
    tip_le = (WING_TIP_X, wing_le_y(WING_TIP_X), WING_Z)
    tip_te = (WING_TIP_X, WING_TE_Y, WING_Z)
    span = WING_TIP_X - WING_ROOT_X
    up = (0, 0, 1)

    def s_of(x):
        return (x - WING_ROOT_X) / span

    def chord(s):
        x = kit.lerp(WING_ROOT_X, WING_TIP_X, s)
        return wing_le_y(x) - WING_TE_Y

    def hinge_f(s):
        return 1 - CONTROL_CHORD / chord(s)

    def zero(_s):
        return 0.0

    def one(_s):
        return 1.0

    def hinge_point(s):
        rl, rt, tl, tt = (Vector(p) for p in (root_le, root_te, tip_le, tip_te))
        return rl.lerp(tl, s).lerp(rt.lerp(tt, s), hinge_f(s))

    for side, name in ((1, "R"), (-1, "L")):
        def m(v):
            return v if side > 0 else kit.mirror_x(v)

        def mf(f):
            return f if side > 0 else kit.flip_faces(f)

        geo = (root_le, root_te, tip_le, tip_te, up, WING_THICKNESS)
        box = [
            panel_var(*geo, zero, hinge_f, 0, s_of(AILERON_SPAN[1]), 10, 12),  # wing box ahead of the hinge
            panel_var(*geo, zero, one, s_of(AILERON_SPAN[1]), 1, 3, 12),  # tip, full chord
            panel_var(*geo, hinge_f, one, 0, s_of(FLAP_SPAN[0]), 1, 4),  # strip inboard of the flap
            panel_var(*geo, hinge_f, one, s_of(FLAP_SPAN[1]), s_of(AILERON_SPAN[0]), 1, 4),
        ]
        v, f = kit.merge(*box)
        kit.make_object(f"Wing{name}", m(v), mf(f), col, "Wings")

        for surface, (x0, x1), lims, control in (
            ("Flap", FLAP_SPAN, (0, 25), "Flap"),
            ("Aileron", AILERON_SPAN, (-20, 20), "Aileron" + name),
        ):
            s0, s1 = s_of(x0), s_of(x1)
            v, f = panel_var(*geo, hinge_f, one, s0, s1, 4, 6)
            a, b = hinge_point(s0), hinge_point(s1)
            kit.make_object(f"{surface}{name}", m(v), mf(f), col, "Wings", "ControlSurface",
                            origin=tuple(m([tuple(a.lerp(b, 0.5))])[0]),
                            hinge={"axis": tuple(m([tuple(b - a)])[0]), "min": lims[0], "max": lims[1], "control": control})


def build_tail(col):
    up = (0, 0, 1)
    root_le = (STAB_ROOT_X, stab_le_y(STAB_ROOT_X), STAB_Z)
    root_te = (STAB_ROOT_X, stab_te_y(STAB_ROOT_X), STAB_Z)
    tip_le = (STAB_TIP_X, stab_le_y(STAB_TIP_X), STAB_Z)
    tip_te = (STAB_TIP_X, stab_te_y(STAB_TIP_X), STAB_Z)
    pivot_y = stab_le_y(STAB_ROOT_X) - (stab_le_y(STAB_ROOT_X) - stab_te_y(STAB_ROOT_X)) * 0.40
    for side, name in ((1, "R"), (-1, "L")):
        v, f = kit.panel(root_le, root_te, tip_le, tip_te, up, STAB_THICKNESS, 0.0, 1.0, 0, 1, 6, 10)
        rod = kit.cylinder((STAB_TIP_X - 0.03, tip_le[1] + 0.45, STAB_Z), (STAB_TIP_X - 0.03, tip_le[1] - 0.25, STAB_Z),
                           0.03, 10)
        v, f = kit.merge((v, f), rod)
        if side < 0:
            v, f = kit.mirror_x(v), kit.flip_faces(f)
        kit.make_object(f"Stabilator{name}", v, f, col, "Wings", "ControlSurface", origin=(side * STAB_ROOT_X, pivot_y, STAB_Z),
                        hinge={"axis": (1, 0, 0), "min": -20, "max": 15, "control": "Stabilator"})

    side_n = (1, 0, 0)
    fin_root_le = (0, FIN_ROOT_LE, FIN_ROOT_Z)
    fin_root_te = (0, FIN_ROOT_LE - FIN_ROOT_CHORD, FIN_ROOT_Z)
    fin_tip_le = (0, FIN_TIP_LE, FIN_TIP_Z)
    fin_tip_te = (0, FIN_TIP_LE - FIN_TIP_CHORD, FIN_TIP_Z)
    h = FIN_TIP_Z - FIN_ROOT_Z

    def frac(z):
        return (z - FIN_ROOT_Z) / h

    g = (fin_root_le, fin_root_te, fin_tip_le, fin_tip_te, side_n, FIN_THICKNESS)
    fin = [
        kit.panel(*g, 0.0, RUDDER_HINGE, 0, 1, 8, 10),
        kit.panel(*g, RUDDER_HINGE, 1.0, 0, frac(RUDDER_SPAN[0]), 1, 4),
        kit.panel(*g, RUDDER_HINGE, 1.0, frac(RUDDER_SPAN[1]), 1, 2, 4),
    ]
    v, f = kit.merge(*fin)
    kit.make_object("Fin", v, f, col, "Body")
    v, f = kit.panel(*g, RUDDER_HINGE, 1.0, frac(RUDDER_SPAN[0]), frac(RUDDER_SPAN[1]), 6, 6)
    a, b = kit.hinge_line(*g[:4], RUDDER_HINGE, frac(RUDDER_SPAN[0]), frac(RUDDER_SPAN[1]))
    kit.make_object("Rudder", v, f, col, "Body", "ControlSurface", origin=tuple(a.lerp(b, 0.5)),
                    hinge={"axis": tuple(b - a), "min": -25, "max": 25, "control": "Rudder"})

    # Ventral fin under the rear fuselage
    outline = [(Y(1045), -0.52), (Y(1090), -0.92), (Y(1150), -0.97), (Y(1240), -0.82), (Y(1305), -0.50)]
    half = [0.035, 0.022, 0.02, 0.022, 0.035]
    n = len(outline)
    fv = [(-t, y, z) for (y, z), t in zip(outline, half)] + [(t, y, z) for (y, z), t in zip(outline, half)]
    ff = [tuple(range(n)), tuple(reversed(range(n, 2 * n)))] + [(i, n + i, n + (i + 1) % n, (i + 1) % n) for i in range(n)]
    kit.make_object("VentralFin", fv, ff, col, "Body")


def build_engine(col):
    p0, p1 = (0, NOZZLE_Y0 + 0.05, NOZZLE_Z), (0, NOZZLE_Y1, NOZZLE_Z)
    nv, nf = kit.cylinder(p0, p1, NOZZLE_R + 0.02, 24, radius1=NOZZLE_R, caps=False)
    iv, i_f = kit.cylinder(p0, p1, NOZZLE_R - 0.03, 24, radius1=NOZZLE_R - 0.035, caps=False)
    n = 24
    lip = [(n + i, n + (i + 1) % n, len(nv) + n + (i + 1) % n, len(nv) + n + i) for i in range(n)]
    verts, faces = kit.merge((nv, nf), (iv, kit.flip_faces(i_f)))
    kit.make_object("Nozzle", verts, faces + lip, col, "Details", "Nozzle", extra={"engine": "C"})
    cv, cf = kit.cylinder((0, NOZZLE_Y1 + 0.15, NOZZLE_Z), (0, NOZZLE_Y0 + 0.05, NOZZLE_Z), NOZZLE_R - 0.06, 18,
                          radius1=0.06, caps=True)
    kit.make_object("Afterburner", cv, cf, col, "Details", "Afterburner", extra={"engine": "C"})


def build_seat(col):
    eye_y = Y(545)
    parts = [
        kit.box((0, eye_y - 0.05, 0.08), (0.46, 0.48, 0.10)),
        kit.box((0, eye_y - 0.33, 0.40), (0.46, 0.12, 0.66)),
        kit.box((0, eye_y - 0.30, 0.82), (0.34, 0.20, 0.24)),
    ]
    v, f = kit.merge(*parts)
    kit.make_object("EjectionSeat", v, f, col, "Details")


def build_pitot(col):
    boom = kit.cylinder((0, Y(15.1), Z(231)), (0, Y(205), Z(220)), 0.028, 8)
    base = kit.cylinder((0, Y(205), Z(220)), (0, Y(290), Z(214)), 0.06, 10, radius1=0.09)
    v, f = kit.merge(boom, base)
    kit.make_object("Pitot", v, f, col, "Details")


def build_gear(col):
    nx, ny, nz = NOSE_WHEEL["at"]
    top = (0, ny + 0.12, -0.52)
    v, f = kit.cylinder(top, (0, ny, nz + 0.10), 0.05, 10)
    kit.make_object("NoseGearStrut", v, f, col, "Details", "Gear", origin=top,
                    hinge={"axis": (1, 0, 0), "min": 0, "max": 95, "control": "Gear"})
    v, f = kit.wheel(NOSE_WHEEL["at"], NOSE_WHEEL["radius"], NOSE_WHEEL["width"])
    kit.make_object("NoseGearWheel", v, f, col, "Details", "GearWheel", origin=NOSE_WHEEL["at"],
                    hinge={"axis": (1, 0, 0), "min": -720, "max": 720, "control": "Wheel"})
    for side, name in ((1, "R"), (-1, "L")):
        v, f = kit.box((side * 0.16, ny + 0.1, -0.68), (0.03, 0.7, 0.26))
        kit.make_object(f"NoseGearDoor{name}", v, f, col, "Details", "GearDoor", origin=(side * 0.14, ny + 0.1, -0.55),
                        hinge={"axis": (0, 1, 0), "min": 0, "max": 85, "control": "GearDoor"})
    mx, my, mz = MAIN_WHEEL["at"]
    for side, name in ((1, "R"), (-1, "L")):
        top = (side * 1.25, my + 0.08, WING_Z - 0.06)
        v, f = kit.cylinder(top, (side * (mx - 0.14), my, mz + 0.06), 0.07, 10)
        kit.make_object(f"MainGearStrut{name}", v, f, col, "Details", "Gear", origin=top,
                        hinge={"axis": (0, 1, 0), "min": 0, "max": 90, "control": "Gear"})
        centre = (side * mx, my, mz)
        v, f = kit.wheel(centre, MAIN_WHEEL["radius"], MAIN_WHEEL["width"])
        kit.make_object(f"MainGearWheel{name}", v, f, col, "Details", "GearWheel", origin=centre,
                        hinge={"axis": (1, 0, 0), "min": -720, "max": 720, "control": "Wheel"})
        v, f = kit.box((side * 1.12, my, WING_Z - 0.40), (0.04, 0.95, 0.55))
        kit.make_object(f"MainGearDoor{name}", v, f, col, "Details", "GearDoor", origin=(side * 1.10, my, WING_Z - 0.12),
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

    build_fuselage(cols["Body"])
    build_inlet_cone(cols["Body"])
    kit.build_canopy(cols["Glass"], cols["Body"])
    build_wings(cols["Wings"])
    build_tail(cols["Wings"])
    build_engine(cols["Details"])
    build_seat(cols["Details"])
    build_pitot(cols["Details"])
    build_gear(cols["Gear"])
    kit.add_attachment_empties(cols["Attachments"])

    kit.smooth_all()
    kit.unwrap_sets()
    import cockpit_kit  # after the UVs: the well moves vertices, not UVs, so the skins still fit

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
