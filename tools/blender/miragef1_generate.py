"""
Afterburner: Mirage F1C base mesh generator (Blender 4.x / 5.x).

Builds a mid-poly, modular Mirage F1C at real-world size in the same form as the F-5E (f5e_generate.py,
whose helpers and wing builder this uses): separate objects per part, moving parts with their origin on
the hinge line, four texture sets, a manifest for the Studio assembler, an FBX, and the cockpit well.

  * the fuselage: pointed radome, the cockpit, the flat dorsal spine from the canopy to the fin
  * half-round side intakes with half-cone centre bodies, canopy and frame
  * the shoulder-mounted swept wing (47.5 degrees) with full-span leading-edge flaps, flaps and
    ailerons, wingtip launch rails
  * all-moving swept stabilators, the fin and rudder, two ventral fins
  * single nozzle with afterburner cone, ejection seat, pitot, landing gear (struts, wheels, doors)

Run headless:
  blender -b --python tools/blender/miragef1_generate.py -- --out <dir> --manifest-luau tools/Manifests/MirageF1.luau

Reference: the public-domain Commons three-view "Dassault Mirage F1 3-view line drawing.png" (574 px). It
is small and approximate, so it gives the outline and the published figures set the scale. Stations (xd)
are pixels aft of the radome tip in its side view (nose left, tip at x = 249); heights are its rows
(row 286 is z = 0). The side view's 290 px are the published 15.30 m (18.95 px/m). The top view is
drawn at a slightly smaller scale: its stations are stretched 1.021 to match the side view's, and its
half widths are scaled so the wing, without its tip rails, spans the published 8.20 m (20 px/m). Photos
fill in what the drawing can't show. See docs/art/reference/MirageF1/SOURCES.md (kept out of git).
"""

import argparse
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import f5e_generate as kit  # noqa: E402  (shared helpers; its module settings are switched below)

kit.AIRFRAME = "MirageF1"
kit.REF_PX_PER_M = 18.95
kit.REF_PITOT_XD = 0.0
kit.REF_Z0_ROW = 286.0
kit.CG_FROM_PITOT = 153.4 / 18.95  # 25% of the 3.31 m mean aerodynamic chord
kit.LENGTH = 15.30
kit.SPINE_UPPER_ONLY = True
Y, Z = kit.Y, kit.Z
PLAN_STRETCH, PLAN_PX_PER_M = 1.021, 20.0

# Fuselage stations: (xd, half width, bottom z, shoulder z, top z, spine half width, exponent)
kit.FUSELAGE = [
    (0, 0.012, -0.50, -0.44, -0.44, 0.0, 2.0),  # radome tip
    (6, 0.10, -0.53, -0.42, -0.42, 0.0, 2.0),
    (12, 0.15, -0.55, -0.32, -0.32, 0.0, 2.0),
    (18, 0.20, -0.58, -0.26, -0.26, 0.0, 2.0),
    (24, 0.25, -0.60, -0.21, -0.21, 0.0, 2.0),
    (36, 0.30, -0.64, -0.05, -0.05, 0.0, 2.1),
    (48, 0.36, -0.68, 0.05, 0.05, 0.0, 2.3),
    (56, 0.40, -0.69, 0.11, 0.11, 0.0, 2.5),  # windscreen base
    (70, 0.41, -0.70, 0.12, 0.12, 0.0, 2.5),
    (86, 0.42, -0.71, 0.13, 0.13, 0.0, 2.5),
    (96, 0.46, -0.72, 0.16, 0.66, 0.30, 2.5),  # the spine rises inside the canopy's rear
    (104, 0.52, -0.72, 0.22, 0.74, 0.33, 2.5),
    (120, 0.62, -0.72, 0.35, 0.74, 0.40, 2.4),
    (150, 0.72, -0.73, 0.55, 0.74, 0.45, 2.4),
    (180, 0.76, -0.74, 0.74, 0.74, 0.0, 2.6),
    (205, 0.74, -0.74, 0.74, 0.74, 0.0, 2.6),
    (225, 0.70, -0.70, 0.72, 0.72, 0.0, 2.5),
    (245, 0.66, -0.62, 0.70, 0.70, 0.0, 2.4),
    (262, 0.62, -0.52, 0.66, 0.66, 0.0, 2.3),
    (274, 0.57, -0.45, 0.58, 0.58, 0.0, 2.2),  # nozzle
]
kit.FUSELAGE_RINGS = 60
kit.FUSELAGE_SEGMENTS = 44

kit.INTAKES = [
    (100, 0.86, 0.32, -0.42),
    (110, 0.88, 0.33, -0.46),
    (130, 0.88, 0.30, -0.48),
    (155, 0.84, 0.20, -0.46),
    (180, 0.80, 0.05, -0.36),
]
kit.INTAKE_LIP_SWEEP = 0.15
SOURIS = {"tip": 95, "base": 103, "radius": 0.18, "x": 0.66, "z": -0.05}

kit.CANOPY = [
    (54, 0.10, 0.12),
    (58, 0.22, 0.30),
    (63, 0.30, 0.50),
    (68, 0.34, 0.66),
    (72, 0.35, 0.73),
    (80, 0.36, 0.745),
    (90, 0.35, 0.745),
    (97, 0.32, 0.74),
    (100, 0.28, 0.74),
]
kit.CANOPY_FRAMES = (72, 98)


def wing_le_y(x):
    return Y(PLAN_STRETCH * (125 + (x * PLAN_PX_PER_M - 19.5) / 0.919))


def wing_te_y(x):
    return Y(PLAN_STRETCH * (204 + (x * PLAN_PX_PER_M - 14.5) * 18 / 67.5))


# Shoulder wing, built by the kit's wing builder (leading-edge flaps, flaps, ailerons, tip rails)
kit.WING_Z = Z(281)
kit.WING_ROOT_X, kit.WING_TIP_X = 0.45, 4.10
kit.WING_ROOT_LE, kit.WING_ROOT_TE = wing_le_y(0.45), wing_te_y(0.45)
kit.WING_SWEEP_LE = math.atan((wing_le_y(0.45) - wing_le_y(4.10)) / (4.10 - 0.45))
kit.WING_TIP_CHORD = wing_le_y(4.10) - wing_te_y(4.10)
kit.WING_THICKNESS = 0.05
kit.LE_FLAP_CHORD = 0.15
kit.TE_HINGE = 0.75
kit.TE_FLAP_SPAN = (0.85, 2.55)
kit.AILERON_SPAN = (2.60, 3.90)
kit.RAIL_Y = (wing_le_y(4.10) + wing_te_y(4.10)) / 2 + 0.2
kit.RAIL_LENGTH = 1.7

# All-moving stabilators (top view, stretched to side-view stations) at the side view's tailplane line
STAB_ROOT_X, STAB_TIP_X = 0.60, 2.30
STAB_ROOT_LE, STAB_ROOT_TE = Y(234.8), Y(283.8)
STAB_TIP_LE, STAB_TIP_TE = Y(273.6), Y(289.0)
STAB_Z = Z(287.5)
STAB_THICKNESS = 0.045

FIN_ROOT_Z, FIN_TIP_Z = 0.72, Z(231.7)
FIN_ROOT_LE, FIN_ROOT_TE = Y(207.7), Y(274.0)
FIN_TIP_LE, FIN_TIP_TE = Y(274.0), Y(288.5)
FIN_THICKNESS = 0.045
RUDDER_HINGE = 0.80
RUDDER_SPAN = (0.85, 2.40)

NOZZLE_Z, NOZZLE_R = Z(285), 0.45
NOZZLE_Y0, NOZZLE_Y1 = Y(272), Y(285)

GROUND_Z = FIN_TIP_Z - 4.50  # published height
NOSE_WHEEL = {"at": (0, Y(60), GROUND_Z + 0.24), "radius": 0.24, "width": 0.14}
MAIN_WHEEL = {"at": (1.25, Y(175), GROUND_Z + 0.32), "radius": 0.32, "width": 0.20}

kit.HULL = {"size": [1.7, 1.5, 15.0], "at": [0, 0, -0.58]}
kit.HITBOXES = {
    "Cockpit": {"size": [0.9, 1.0, 2.2], "at": [0, 0.35, -3.6]},
    "Fuselage": {"size": [1.8, 1.5, 6.5], "at": [0, 0, -1.3]},
    "Engine": {"size": [1.5, 1.4, 4.5], "at": [0, 0, 4.2]},
    "WingL": {"size": [3.6, 0.4, 3.4], "at": [-2.35, round(kit.WING_Z, 2), 1.5]},
    "WingR": {"size": [3.6, 0.4, 3.4], "at": [2.35, round(kit.WING_Z, 2), 1.5]},
    "Tail": {"size": [4.8, 2.6, 3.0], "at": [0, 0.9, 5.6]},
}
EYE = (0, Y(86), 0.52)
kit.ATTACHMENTS = {
    "CockpitEye": EYE,
    "GunMuzzle": (0, Y(70), -0.55),  # the two DEFA 553s in the lower nose
    "Nozzle1": (0, NOZZLE_Y1, NOZZLE_Z),
    "WingtipL": (-(kit.WING_TIP_X + 0.08), kit.RAIL_Y, kit.WING_Z),
    "WingtipR": (kit.WING_TIP_X + 0.08, kit.RAIL_Y, kit.WING_Z),
    "FlareDispenser": (0, Y(250), -0.62),
    "ChaffDispenser": (0, Y(240), -0.66),
    "ChaseCam": (0, -20.5, 3.5),
    "Hardpoint1": (-(kit.WING_TIP_X + 0.08), kit.RAIL_Y, kit.WING_Z - 0.12),
    "Hardpoint2": (kit.WING_TIP_X + 0.08, kit.RAIL_Y, kit.WING_Z - 0.12),
    "Hardpoint3": (-2.0, Y(185), kit.WING_Z - 0.15),
    "Hardpoint4": (2.0, Y(185), kit.WING_Z - 0.15),
    "Hardpoint5": (0, Y(170), -0.80),
}

# Cockpit interior (cockpit_kit.py, art pipeline §7), after Mirage F1C cockpit photos: the sight on the
# glareshield over the Cyrano IV radar scope, flight instruments left, engine instruments right.
kit.COCKPIT = {
    "well": {"back": 3.12, "front": 4.35, "half_width": 0.30, "floor": -0.42, "flange": 0.06},
    "panel": {"distance": 0.65, "top": -0.16, "bottom": -0.58, "tilt": 10, "half_width": 0.30},
    "coaming": {"overhang": 0.04, "length": 0.30, "drop": 0.06},
    "consoles": {"top": -0.52, "width": 0.09, "aft": -0.35, "fore": 0.42, "throttle": 0.02},
    "stick": "centre",
    "stick_fore": 0.38,
    "sight": "Gunsight",
    "sight_body": (0.12, 0.14, 0.08),
    "sight_glass": (0.12, 0.10),
    "palette": "French",
    "instruments": [
        {"name": "RadarScope", "kind": "Scope", "u": 0.0, "v": 0.08, "size": 0.10, "hood": 0.04, "live": "Radar"},
        {"name": "GMeter", "kind": "Dial", "u": -0.215, "v": 0.075, "size": 0.055, "live": "G"},
        {"name": "Airspeed", "kind": "Dial", "u": -0.125, "v": 0.08, "size": 0.08, "live": "Speed"},
        {"name": "RPM", "kind": "Dial", "u": 0.125, "v": 0.08, "size": 0.08, "live": "RPM"},
        {"name": "EGT", "kind": "Dial", "u": 0.215, "v": 0.075, "size": 0.055},
        {"name": "AOA", "kind": "Dial", "u": -0.215, "v": 0.16, "size": 0.05},
        {"name": "Altimeter", "kind": "Dial", "u": -0.125, "v": 0.175, "size": 0.08, "live": "Altitude"},
        {"name": "ADI", "kind": "Dial", "u": 0.0, "v": 0.195, "size": 0.10, "face": "attitude"},
        {"name": "VVI", "kind": "Dial", "u": 0.125, "v": 0.175, "size": 0.07},
        {"name": "Fuel", "kind": "Dial", "u": 0.215, "v": 0.16, "size": 0.05},
        {"name": "Clock", "kind": "Dial", "u": -0.16, "v": 0.28, "size": 0.05},
        {"name": "HSI", "kind": "Dial", "u": 0.0, "v": 0.30, "size": 0.09, "face": "compass"},
        {"name": "Caution", "kind": "Lights", "u": 0.16, "v": 0.28, "size": 0.10},
    ],
}


# ---------------------------------------------------------------------------------------------------
# Builders
# ---------------------------------------------------------------------------------------------------


def build_souris(col):
    parts = []
    for side in (1, -1):
        x = side * SOURIS["x"]
        tip, base = (x, Y(SOURIS["tip"]), SOURIS["z"]), (x, Y(SOURIS["base"]), SOURIS["z"])
        parts.append(kit.cylinder(tip, base, 0.004, 20, radius1=SOURIS["radius"], caps=True))
        parts.append(kit.cylinder(base, (x, Y(SOURIS["base"] + 6), SOURIS["z"]), SOURIS["radius"], 20, caps=True))
    v, f = kit.merge(*parts)
    kit.make_object("InletCones", v, f, col, "Body")


def build_tail(col_wings, col_body):
    up = (0, 0, 1)
    root_le, root_te = (STAB_ROOT_X, STAB_ROOT_LE, STAB_Z), (STAB_ROOT_X, STAB_ROOT_TE, STAB_Z)
    tip_le, tip_te = (STAB_TIP_X, STAB_TIP_LE, STAB_Z), (STAB_TIP_X, STAB_TIP_TE, STAB_Z)
    pivot_y = STAB_ROOT_LE - (STAB_ROOT_LE - STAB_ROOT_TE) * 0.35
    for side, name in ((1, "R"), (-1, "L")):
        v, f = kit.panel(root_le, root_te, tip_le, tip_te, up, STAB_THICKNESS, 0.0, 1.0, 0, 1, 6, 10)
        if side < 0:
            v, f = kit.mirror_x(v), kit.flip_faces(f)
        kit.make_object(f"Stabilator{name}", v, f, col_wings, "Wings", "ControlSurface",
                        origin=(side * STAB_ROOT_X, pivot_y, STAB_Z),
                        hinge={"axis": (1, 0, 0), "min": -20, "max": 15, "control": "Stabilator"})

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
    ]
    v, f = kit.merge(*fin)
    kit.make_object("Fin", v, f, col_body, "Body")
    v, f = kit.panel(*g, RUDDER_HINGE, 1.0, frac(RUDDER_SPAN[0]), frac(RUDDER_SPAN[1]), 6, 6)
    a, b = kit.hinge_line(*g[:4], RUDDER_HINGE, frac(RUDDER_SPAN[0]), frac(RUDDER_SPAN[1]))
    kit.make_object("Rudder", v, f, col_body, "Body", "ControlSurface", origin=tuple(a.lerp(b, 0.5)),
                    hinge={"axis": tuple(b - a), "min": -25, "max": 25, "control": "Rudder"})

    # Two ventral fins under the rear fuselage, canted out
    parts = []
    outline = [(Y(226), -0.60), (Y(236), -0.98), (Y(258), -0.92), (Y(262), -0.52)]
    for side in (1, -1):
        cant = math.radians(20)
        pts = []
        for y, z in outline:
            depth = -0.55 - z  # below the fuselage side
            x = side * (0.32 + max(depth, 0) * math.tan(cant))
            pts.append((x, y, z))
        t = 0.02
        n = len(pts)
        fv = [(p[0] - t, p[1], p[2]) for p in pts] + [(p[0] + t, p[1], p[2]) for p in pts]
        ff = [tuple(range(n)), tuple(reversed(range(n, 2 * n)))] + [(i, n + i, n + (i + 1) % n, (i + 1) % n) for i in range(n)]
        parts.append((fv, ff))
    v, f = kit.merge(*parts)
    kit.make_object("VentralFins", v, f, col_body, "Body")


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
    v, f = kit.cylinder((0, Y(-10), Z(295)), (0, Y(1), Z(295)), 0.02, 8)
    kit.make_object("Pitot", v, f, col, "Details")


def build_gear(col):
    nx, ny, nz = NOSE_WHEEL["at"]
    top = (0, ny + 0.10, -0.60)
    v, f = kit.cylinder(top, (0, ny, nz + 0.10), 0.05, 10)
    kit.make_object("NoseGearStrut", v, f, col, "Details", "Gear", origin=top,
                    hinge={"axis": (1, 0, 0), "min": 0, "max": 95, "control": "Gear"})
    v, f = kit.wheel(NOSE_WHEEL["at"], NOSE_WHEEL["radius"], NOSE_WHEEL["width"])
    kit.make_object("NoseGearWheel", v, f, col, "Details", "GearWheel", origin=NOSE_WHEEL["at"],
                    hinge={"axis": (1, 0, 0), "min": -720, "max": 720, "control": "Wheel"})
    for side, name in ((1, "R"), (-1, "L")):
        v, f = kit.box((side * 0.15, ny + 0.1, -0.74), (0.03, 0.7, 0.26))
        kit.make_object(f"NoseGearDoor{name}", v, f, col, "Details", "GearDoor", origin=(side * 0.13, ny + 0.1, -0.62),
                        hinge={"axis": (0, 1, 0), "min": 0, "max": 85, "control": "GearDoor"})
    mx, my, mz = MAIN_WHEEL["at"]
    for side, name in ((1, "R"), (-1, "L")):
        top = (side * 0.70, my + 0.10, -0.55)  # the F1's main gear folds into the fuselage
        v, f = kit.cylinder(top, (side * (mx - 0.12), my, mz + 0.08), 0.07, 10)
        kit.make_object(f"MainGearStrut{name}", v, f, col, "Details", "Gear", origin=top,
                        hinge={"axis": (0, 1, 0), "min": 0, "max": 90, "control": "Gear"})
        centre = (side * mx, my, mz)
        v, f = kit.wheel(centre, MAIN_WHEEL["radius"], MAIN_WHEEL["width"])
        kit.make_object(f"MainGearWheel{name}", v, f, col, "Details", "GearWheel", origin=centre,
                        hinge={"axis": (1, 0, 0), "min": -720, "max": 720, "control": "Wheel"})
        v, f = kit.box((side * 0.66, my, -0.80), (0.04, 0.95, 0.40))
        kit.make_object(f"MainGearDoor{name}", v, f, col, "Details", "GearDoor", origin=(side * 0.64, my, -0.62),
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
    build_souris(cols["Body"])
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
