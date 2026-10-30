"""
Afterburner: Eurofighter Typhoon base mesh generator (Blender 4.x / 5.x). Art only: the Typhoon has no flight
data yet (AircraftData), so this makes the model, skins and cockpit for when it does.

Builds a mid-poly, modular Typhoon at real-world size, measured from a reference drawing, in the same form as
the F-5E (f5e_generate.py, whose helpers this uses): separate objects per part, moving parts with their
origin on the hinge line, four texture sets, a manifest for the Studio assembler, an FBX, and the cockpit
well.

  * the fuselage with the radome, the bubble canopy and the spine, widening over the twin engines
  * the chin intake under the fuselage, with its splitter, running back under the wing roots
  * the all-moving canards on the elevon controls, beside the cockpit
  * the cropped delta wing with leading-edge flaps and two elevons a side, and wingtip pods
  * the single fin with its rudder, twin nozzles with afterburner cones, ejection seat, nose probe,
    landing gear (struts, wheels, doors)

Run headless:
  blender -b --python tools/blender/typhoon_generate.py -- --out <dir> --manifest-luau tools/Manifests/Typhoon.luau

Reference: the Commons drawing "Eurofighter Typhoon line drawing.svg" (Inductiveload, public domain),
rendered 3840 px wide and rebuilt as a composite 2000 px wide: its side view on top and its top view below,
both nose left, the nose tip at x = 55.6. Stations (xd) are pixels aft of it; heights are side-view rows
(row 442, the nozzles' axis, is z = 0); half widths are pixels from the top view's centreline (row 1399.5).
The scale comes from the published 15.96 m length (118.1 px/m), which gives a 10.9 m span against the
published 10.95 m. See docs/art/reference/Typhoon/SOURCES.md (kept out of git).
"""

import argparse
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import f5e_generate as kit  # noqa: E402  (shared helpers; its module settings are switched below)

kit.AIRFRAME = "Typhoon"
kit.REF_PX_PER_M = 118.1
kit.REF_PITOT_XD = 0.0
kit.REF_Z0_ROW = 442.0
kit.CG_FROM_PITOT = 1117 / 118.1  # 25% of the 4.72 m mean aerodynamic chord
kit.LENGTH = 15.96
kit.SPINE_UPPER_ONLY = True
Y, Z = kit.Y, kit.Z
PX = kit.REF_PX_PER_M


def W(px):
    return px / PX


# (xd, half width px, bottom row, shoulder row, top row, spine half width m, exponent); under the canopy the
# top is the cockpit sill, behind it the spine runs back to the fin
_BODY = [
    (0, 0.5, 440, 436, 436, 0.0, 2.0),  # radome tip
    (100, 27, 460, 400, 400, 0.0, 2.0),
    (200, 50, 468, 368, 368, 0.0, 2.1),
    (260, 58, 470, 355, 355, 0.0, 2.3),  # windscreen base
    (400, 75, 468, 345, 345, 0.0, 2.5),
    (500, 82, 466, 342, 342, 0.0, 2.6),
    (600, 92, 466, 335, 335, 0.0, 2.8),
    (700, 100, 468, 335, 302, 0.30, 3.0),  # the spine rises inside the canopy's rear
    (800, 120, 470, 345, 305, 0.32, 3.2),
    (900, 140, 472, 360, 318, 0.32, 3.4),
    (1100, 148, 474, 365, 335, 0.30, 3.5),
    (1300, 150, 476, 365, 347, 0.26, 3.5),
    (1500, 145, 474, 362, 357, 0.10, 3.3),
    (1620, 132, 478, 372, 362, 0.0, 3.0),
    (1720, 115, 485, 380, 368, 0.0, 2.8),  # nozzles start
]
kit.FUSELAGE = [(xd, W(hw), Z(zb), Z(zs), Z(zt), sp, e) for xd, hw, zb, zs, zt, sp, e in _BODY]
kit.FUSELAGE_RINGS = 52
kit.FUSELAGE_SEGMENTS = 36

kit.CANOPY = [
    (xd, w, Z(row)) for xd, w, row in (
        (260, 0.10, 355), (320, 0.30, 330), (380, 0.38, 305), (425, 0.42, 285), (520, 0.44, 263),
        (600, 0.42, 268), (680, 0.36, 283), (735, 0.26, 295), (760, 0.15, 300),
    )
]
kit.CANOPY_FRAMES = (425, 640)  # windscreen bow, and the frame behind the seat

# The chin intake: (xd, half width m, centre row, half height m), from the raked mouth (its top at station
# 500, its bottom at 560) back under the wing roots
INTAKE = [(575, 0.80, 505, 0.36), (700, 0.82, 507, 0.38), (900, 0.82, 505, 0.36), (1100, 0.80, 500, 0.33),
          (1300, 0.74, 492, 0.30), (1450, 0.62, 482, 0.24)]
LIP_TOP, LIP_BOTTOM = 500, 560

# Canards: root and tip (half width px, leading-edge xd, trailing-edge xd)
CANARD_ROOT, CANARD_TIP = (70, 290, 470), (230, 455, 515)
CANARD_Z = Z(418)

WING_Z = Z(440)  # a third of the way up the body's side (the bottom, 474, put it under the body)


def wing_le_y(x):
    return Y(737 + (x * PX - 140) * 1.262)


def wing_te_y(x):
    return Y(1545 - (x * PX - 150) * 0.05)


kit.WING_Z = WING_Z
# The root is carried in from the drawing's 140 px along the edges so its front meets the narrower forebody
kit.WING_ROOT_X, kit.WING_TIP_X = W(110), W(630)
kit.WING_ROOT_LE, kit.WING_ROOT_TE = wing_le_y(W(110)), wing_te_y(W(110))
kit.WING_SWEEP_LE = math.atan((wing_le_y(W(140)) - wing_le_y(W(630))) / (W(630) - W(140)))
kit.WING_TIP_CHORD = wing_le_y(W(630)) - wing_te_y(W(630))
kit.WING_THICKNESS = 0.04
kit.LE_FLAP_CHORD = 0.10
kit.TE_HINGE = 0.80
kit.TE_FLAP_SPAN = (1.30, 3.20)  # inner elevon
kit.AILERON_SPAN = (3.25, 5.20)  # outer elevon
kit.RAIL_Y = (wing_le_y(W(630)) + wing_te_y(W(630))) / 2
kit.RAIL_LENGTH = 1.5

FIN_ROOT_Z, FIN_TIP_Z = Z(355), Z(30)
FIN_ROOT_LE, FIN_ROOT_TE = Y(1319), Y(1720)
FIN_TIP_LE, FIN_TIP_TE = Y(1750), Y(1862)
FIN_THICKNESS = 0.045
RUDDER_HINGE = 0.80
RUDDER_SPAN = (Z(350), Z(100))

NOZZLE_X, NOZZLE_Z, NOZZLE_R = W(60), 0.0, 0.42
NOZZLE_Y0, NOZZLE_Y1 = Y(1720), Y(1785)

GROUND_Z = Z(676)
NOSE_WHEEL = {"at": (0, Y(641), GROUND_Z + 0.22), "radius": 0.22, "width": 0.14}
MAIN_WHEEL = {"at": (1.20, Y(1134), GROUND_Z + 0.34), "radius": 0.34, "width": 0.20}

kit.HULL = {"size": [2.4, 1.8, 15.0], "at": [0, 0.0, -0.8]}
kit.HITBOXES = {
    "Cockpit": {"size": [0.9, 1.0, 2.4], "at": [0, 1.0, -4.8]},
    "Fuselage": {"size": [2.6, 1.6, 6.5], "at": [0, -0.1, -0.6]},
    "Engine": {"size": [2.2, 1.2, 4.0], "at": [0, 0.0, 4.0]},
    "WingL": {"size": [4.2, 0.3, 4.6], "at": [-3.0, round(WING_Z, 2), 2.2]},
    "WingR": {"size": [4.2, 0.3, 4.6], "at": [3.0, round(WING_Z, 2), 2.2]},
    "Tail": {"size": [0.6, 2.8, 3.4], "at": [0, 1.9, 5.4]},
}
EYE = (0, Y(540), Z(263) - 0.27)
kit.ATTACHMENTS = {
    "CockpitEye": EYE,
    "GunMuzzle": (0.70, Y(1000), Z(480)),  # the BK-27 in the right wing root
    "Nozzle1": (-NOZZLE_X, NOZZLE_Y1, NOZZLE_Z),
    "Nozzle2": (NOZZLE_X, NOZZLE_Y1, NOZZLE_Z),
    "WingtipL": (-(kit.WING_TIP_X + 0.06), kit.RAIL_Y, WING_Z),
    "WingtipR": (kit.WING_TIP_X + 0.06, kit.RAIL_Y, WING_Z),
    "FlareDispenser": (-0.4, Y(1650), Z(480)),
    "ChaffDispenser": (0.4, Y(1650), Z(480)),
    "ChaseCam": (0, -19.5, 3.6),
    # Three pylons under each wing, four semi-recessed under the intake trunk, and the centreline
    "Hardpoint1": (-4.40, wing_le_y(4.40) - 0.9, WING_Z - 0.20),
    "Hardpoint2": (4.40, wing_le_y(4.40) - 0.9, WING_Z - 0.20),
    "Hardpoint3": (-3.30, wing_le_y(3.30) - 1.2, WING_Z - 0.25),
    "Hardpoint4": (3.30, wing_le_y(3.30) - 1.2, WING_Z - 0.25),
    "Hardpoint5": (-2.20, wing_le_y(2.20) - 1.5, WING_Z - 0.25),
    "Hardpoint6": (2.20, wing_le_y(2.20) - 1.5, WING_Z - 0.25),
    "Hardpoint7": (-0.70, Y(800), Z(548)),
    "Hardpoint8": (0.70, Y(800), Z(548)),
    "Hardpoint9": (-0.70, Y(1150), Z(540)),
    "Hardpoint10": (0.70, Y(1150), Z(540)),
    "Hardpoint11": (0, Y(1000), Z(548)),
}

# Cockpit interior (cockpit_kit.py, art pipeline §7), after Typhoon cockpit photos: the head-up display over
# the up-front controls, three colour displays across the panel (the middle one the radar), with standby
# instruments. Charcoal, centre stick.
kit.COCKPIT = {
    "well": {"back": EYE[1] - 0.32, "front": EYE[1] + 0.74, "half_width": 0.38, "floor": EYE[2] - 1.00, "flange": 0.06},
    "panel": {"distance": 0.64, "top": -0.18, "bottom": -0.60, "tilt": 12, "half_width": 0.33},
    "coaming": {"overhang": 0.04, "length": 0.30, "drop": 0.06},
    "consoles": {"top": -0.50, "width": 0.11, "aft": -0.35, "fore": 0.40, "throttle": 0.02},
    "stick": "centre",
    "stick_fore": 0.40,
    "sight": "HUD",
    "palette": "Modern",
    "instruments": [
        {"name": "UFC", "kind": "Lights", "u": 0.0, "v": 0.075, "size": 0.09},
        {"name": "LeftMFD", "kind": "MFD", "u": -0.215, "v": 0.17, "size": 0.12},
        {"name": "RadarScope", "kind": "MFD", "u": 0.0, "v": 0.19, "size": 0.12, "live": "Radar"},
        {"name": "RightMFD", "kind": "MFD", "u": 0.215, "v": 0.17, "size": 0.12},
        {"name": "Airspeed", "kind": "Dial", "u": -0.13, "v": 0.075, "size": 0.05, "live": "Speed"},
        {"name": "Altimeter", "kind": "Dial", "u": -0.235, "v": 0.075, "size": 0.05, "live": "Altitude"},
        {"name": "GMeter", "kind": "Dial", "u": 0.13, "v": 0.075, "size": 0.045, "live": "G"},
        {"name": "RPM", "kind": "Dial", "u": 0.235, "v": 0.075, "size": 0.045, "live": "RPM"},
        {"name": "ADI", "kind": "Dial", "u": 0.0, "v": 0.30, "size": 0.06, "face": "attitude"},
    ],
}


# ---------------------------------------------------------------------------------------------------
# Builders
# ---------------------------------------------------------------------------------------------------


def intake_ring(xd_of, hw, zc, hh, e=4.0, segments=20):
    pts = []
    for k in range(segments):
        ang = 2 * math.pi * k / segments
        c, s = math.cos(ang), math.sin(ang)
        x = hw * math.copysign(abs(c) ** (2 / e), c)
        z = zc + hh * math.copysign(abs(s) ** (2 / e), s)
        pts.append((x, xd_of(z), z))
    return pts


def build_intakes(col):
    """The chin intake: a rounded box under the fuselage, its mouth raked, with a splitter down the middle."""
    xd0, hw0, row0, hh0 = INTAKE[0]
    zc0 = Z(row0)

    def lip(z):
        return Y(kit.lerp(LIP_TOP, LIP_BOTTOM, (zc0 + hh0 - z) / (2 * hh0)))

    rings = [intake_ring(lip, hw0 * 0.86, zc0, hh0 * 0.86), intake_ring(lip, hw0, zc0, hh0)]
    for xd, hw, row, hh in INTAKE:
        rings.append(intake_ring(lambda _z, xd=xd: Y(xd), hw, Z(row), hh))
    rings[0] = [(p[0], p[1] - 0.18, p[2]) for p in rings[0]]
    splitter = kit.box((0, Y(620), zc0), (0.06, Y(LIP_TOP) - Y(760), hh0 * 1.8))
    v, f = kit.merge(kit.lofted(rings, True, True), splitter)
    kit.make_object("Intakes", v, f, col, "Body")
    mouth = [(p[0], p[1] + 0.01, p[2]) for p in rings[0]]
    v, f = kit.lofted([mouth, [(p[0], p[1] + 0.01, p[2]) for p in mouth]], True, True)
    kit.make_object("IntakeDucts", v, f, col, "Body")


def build_canards(col):
    """The all-moving canards, origin on their spigots."""
    (r_hw, r_le, r_te), (t_hw, t_le, t_te) = CANARD_ROOT, CANARD_TIP
    root_le, root_te = (W(r_hw), Y(r_le), CANARD_Z), (W(r_hw), Y(r_te), CANARD_Z)
    tip_le, tip_te = (W(t_hw), Y(t_le), CANARD_Z), (W(t_hw), Y(t_te), CANARD_Z)
    pivot_y = Y(r_le) - (Y(r_le) - Y(r_te)) * 0.45
    for side, name in ((1, "R"), (-1, "L")):
        v, f = kit.panel(root_le, root_te, tip_le, tip_te, (0, 0, 1), 0.045, 0.0, 1.0, 0, 1, 4, 6)
        if side < 0:
            v, f = kit.mirror_x(v), kit.flip_faces(f)
        kit.make_object(f"Canard{name}", v, f, col, "Wings", "ControlSurface", origin=(side * W(r_hw), pivot_y, CANARD_Z),
                        hinge={"axis": (1, 0, 0), "min": -20, "max": 20, "control": "Elevon" + name})


def build_fin(col):
    h = FIN_TIP_Z - FIN_ROOT_Z

    def frac(z):
        return (z - FIN_ROOT_Z) / h

    g = ((0, FIN_ROOT_LE, FIN_ROOT_Z), (0, FIN_ROOT_TE, FIN_ROOT_Z), (0, FIN_TIP_LE, FIN_TIP_Z), (0, FIN_TIP_TE, FIN_TIP_Z),
         (1, 0, 0), FIN_THICKNESS)
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
                    hinge={"axis": tuple(b - a), "min": -30, "max": 30, "control": "Rudder"})


def build_engines(col):
    for side, name in ((1, "R"), (-1, "L")):
        x = side * NOZZLE_X
        p0, p1 = (x, NOZZLE_Y0, NOZZLE_Z), (x, NOZZLE_Y1, NOZZLE_Z)
        nv, nf = kit.cylinder(p0, p1, NOZZLE_R, 20, radius1=NOZZLE_R - 0.05, caps=False)
        iv, i_f = kit.cylinder(p0, p1, NOZZLE_R - 0.035, 20, radius1=NOZZLE_R - 0.08, caps=False)
        n = 20
        lip = [(n + i, n + (i + 1) % n, len(nv) + n + (i + 1) % n, len(nv) + n + i) for i in range(n)]
        verts, faces = kit.merge((nv, nf), (iv, kit.flip_faces(i_f)))
        kit.make_object(f"Nozzle{name}", verts, faces + lip, col, "Details", "Nozzle", extra={"engine": name})
        cv, cf = kit.cylinder((x, NOZZLE_Y1 + 0.15, NOZZLE_Z), (x, NOZZLE_Y0 - 0.20, NOZZLE_Z), NOZZLE_R - 0.12, 16,
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
    v, f = kit.cylinder((0, Y(-45), Z(438)), (0, Y(5), Z(437)), 0.025, 8)
    kit.make_object("Pitot", v, f, col, "Details")


def build_gear(col):
    nx, ny, nz = NOSE_WHEEL["at"]
    belly = Z(468)
    top = (0, ny + 0.10, belly + 0.08)
    v, f = kit.cylinder(top, (0, ny, nz + 0.12), 0.06, 10)
    kit.make_object("NoseGearStrut", v, f, col, "Details", "Gear", origin=top,
                    hinge={"axis": (1, 0, 0), "min": 0, "max": 95, "control": "Gear"})
    v, f = kit.wheel(NOSE_WHEEL["at"], NOSE_WHEEL["radius"], NOSE_WHEEL["width"])
    kit.make_object("NoseGearWheel", v, f, col, "Details", "GearWheel", origin=NOSE_WHEEL["at"],
                    hinge={"axis": (1, 0, 0), "min": -720, "max": 720, "control": "Wheel"})
    for side, name in ((1, "R"), (-1, "L")):
        v, f = kit.box((side * 0.14, ny + 0.1, belly - 0.12), (0.03, 0.6, 0.22))
        kit.make_object(f"NoseGearDoor{name}", v, f, col, "Details", "GearDoor", origin=(side * 0.12, ny + 0.1, belly),
                        hinge={"axis": (0, 1, 0), "min": 0, "max": 85, "control": "GearDoor"})
    mx, my, mz = MAIN_WHEEL["at"]
    for side, name in ((1, "R"), (-1, "L")):
        top = (side * 0.95, my + 0.20, Z(500))
        v, f = kit.cylinder(top, (side * mx, my, mz + 0.10), 0.07, 10)
        kit.make_object(f"MainGearStrut{name}", v, f, col, "Details", "Gear", origin=top,
                        hinge={"axis": (0, 1, 0), "min": 0, "max": 90, "control": "Gear"})
        centre = (side * mx, my, mz)
        v, f = kit.wheel(centre, MAIN_WHEEL["radius"], MAIN_WHEEL["width"])
        kit.make_object(f"MainGearWheel{name}", v, f, col, "Details", "GearWheel", origin=centre,
                        hinge={"axis": (1, 0, 0), "min": -720, "max": 720, "control": "Wheel"})
        v, f = kit.box((side * 0.98, my, Z(500) - 0.25), (0.04, 0.8, 0.45))
        kit.make_object(f"MainGearDoor{name}", v, f, col, "Details", "GearDoor", origin=(side * 0.98, my, Z(500) - 0.03),
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
    kit.build_canopy(cols["Glass"], cols["Body"])
    kit.build_wings(cols["Wings"])
    build_canards(cols["Wings"])
    build_fin(cols["Body"])
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
