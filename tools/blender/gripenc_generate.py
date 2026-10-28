"""
Afterburner: Gripen C base mesh generator (Blender 4.x / 5.x). Art only: the Gripen C has no flight data yet
(AircraftData), so this makes the model, skins and cockpit for when it does.

Builds a mid-poly, modular Gripen C at real-world size, measured from a reference drawing, in the same form
as the F-5E (f5e_generate.py, whose helpers this uses): separate objects per part, moving parts with their
origin on the hinge line, four texture sets, a manifest for the Studio assembler, an FBX, and the cockpit
well.

  * the slim fuselage with the radome, the one-piece canopy and the dorsal spine
  * the D-shaped intakes beside the cockpit, faired into the fuselage
  * the all-moving canards on the elevon controls, close-coupled ahead of the wing
  * the cropped delta wing with leading-edge flaps and two elevons a side, and wingtip launch rails
  * the single fin with its rudder, one nozzle with its afterburner cone, ejection seat, nose probe,
    landing gear (struts, wheels, doors)

Run headless:
  blender -b --python tools/blender/gripenc_generate.py -- --out <dir> --manifest-luau tools/Manifests/GripenC.luau

Reference: the Commons three-view "Saab JAS 39 Gripen 3-view.svg" (Kaboldy, CC BY-SA 3.0), rendered 3840 px
wide, mirrored nose left and scaled to 2000 px: side view on top, top view below, the probe tip at x = 18 in
both. Stations (xd) are pixels aft of it; heights are side-view rows (row 287, the nozzle's axis, is z = 0);
half widths are pixels from the top view's centreline (row 923.5). The scale comes from the published span
over the wingtip rails (8.4 m, 101.9 px/m), which gives the length 14.2 m against the published 14.1 m.
See docs/art/reference/GripenC/SOURCES.md (kept out of git).
"""

import argparse
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import f5e_generate as kit  # noqa: E402  (shared helpers; its module settings are switched below)

kit.AIRFRAME = "GripenC"
kit.REF_PX_PER_M = 101.9
kit.REF_PITOT_XD = 0.0
kit.REF_Z0_ROW = 287.0
kit.CG_FROM_PITOT = 951 / 101.9  # 25% of the 3.65 m mean aerodynamic chord
kit.LENGTH = 14.1
kit.SPINE_UPPER_ONLY = True
Y, Z = kit.Y, kit.Z
PX = kit.REF_PX_PER_M


def W(px):
    return px / PX


# (xd, half width px, bottom row, shoulder row, top row, spine half width m, exponent); under the canopy the
# top is the cockpit sill, behind it the dorsal spine runs back to the fin
_BODY = [
    (90, 1, 330, 326, 326, 0.0, 2.0),  # radome tip
    (150, 25, 340, 300, 300, 0.0, 2.0),
    (200, 38, 345, 283, 283, 0.0, 2.1),
    (300, 46, 352, 258, 258, 0.0, 2.4),  # windscreen base
    (450, 52, 352, 252, 252, 0.0, 2.6),
    (600, 60, 355, 240, 240, 0.0, 2.8),
    (720, 80, 356, 236, 222, 0.30, 3.0),  # the spine rises inside the canopy's rear
    (800, 95, 358, 250, 218, 0.34, 3.2),
    (1000, 103, 356, 255, 220, 0.34, 3.2),
    (1100, 103, 352, 255, 222, 0.30, 3.2),
    (1200, 92, 345, 258, 225, 0.24, 3.0),
    (1300, 76, 335, 245, 232, 0.12, 2.6),
    (1360, 62, 330, 240, 240, 0.0, 2.4),  # nozzle starts
]
kit.FUSELAGE = [(xd, W(hw), Z(zb), Z(zs), Z(zt), sp, e) for xd, hw, zb, zs, zt, sp, e in _BODY]
kit.FUSELAGE_RINGS = 52
kit.FUSELAGE_SEGMENTS = 36

kit.CANOPY = [
    (xd, w, Z(row)) for xd, w, row in (
        (300, 0.10, 258), (350, 0.28, 236), (400, 0.38, 212), (430, 0.42, 198), (500, 0.43, 199),
        (600, 0.40, 207), (700, 0.32, 213), (760, 0.18, 217),
    )
]
kit.CANOPY_FRAMES = (400, 600)  # windscreen bow, and the frame behind the seat

# Intakes: (xd, centre x m, half width m, centre z m, half height m), from the raked mouth (its top at
# station 480, its bottom at 515) back into the fuselage
NACELLE = [
    (530, 0.70, 0.16, Z(302), 0.37),
    (650, 0.70, 0.18, Z(305), 0.37),
    (800, 0.66, 0.20, Z(310), 0.36),
    (950, 0.56, 0.20, Z(312), 0.32),
]
LIP_TOP, LIP_BOTTOM = 480, 515

# Canards: root and tip (half width px, leading-edge xd, trailing-edge xd)
CANARD_ROOT, CANARD_TIP = (90, 545, 705), (225, 720, 765)
CANARD_Z = Z(278)

WING_Z = Z(292)


def wing_le_y(x):
    return Y(760 + (x * PX - 95) * 1.10)


def wing_te_y(x):
    return Y(1240 - (x * PX - 100) * 0.026)


kit.WING_Z = WING_Z
kit.WING_ROOT_X, kit.WING_TIP_X = W(98), W(403)
kit.WING_ROOT_LE, kit.WING_ROOT_TE = wing_le_y(W(98)), wing_te_y(W(98))
kit.WING_SWEEP_LE = math.atan((wing_le_y(W(98)) - wing_le_y(W(403))) / (W(403) - W(98)))
kit.WING_TIP_CHORD = wing_le_y(W(403)) - wing_te_y(W(403))
kit.WING_THICKNESS = 0.04
kit.LE_FLAP_CHORD = 0.10
kit.TE_HINGE = 0.80
kit.TE_FLAP_SPAN = (1.00, 2.40)  # inner elevon
kit.AILERON_SPAN = (2.45, 3.90)  # outer elevon
kit.RAIL_Y = (wing_le_y(W(403)) + wing_te_y(W(403))) / 2
kit.RAIL_LENGTH = 2.6

FIN_ROOT_Z, FIN_TIP_Z = Z(222), Z(22)
FIN_ROOT_LE, FIN_ROOT_TE = Y(1150), Y(1367)
FIN_TIP_LE, FIN_TIP_TE = Y(1290), Y(1355)
FIN_THICKNESS = 0.045
RUDDER_HINGE = 0.60
RUDDER_SPAN = (Z(215), Z(95))

NOZZLE_Z, NOZZLE_R = 0.0, 0.44
NOZZLE_Y0, NOZZLE_Y1 = Y(1360), Y(1450)

GROUND_Z = Z(475)
NOSE_WHEEL = {"at": (0, Y(442), GROUND_Z + 0.19), "radius": 0.19, "width": 0.12}
MAIN_WHEEL = {"at": (1.20, Y(957), GROUND_Z + 0.33), "radius": 0.33, "width": 0.18}

kit.HULL = {"size": [2.0, 1.6, 13.0], "at": [0, 0.0, -0.8]}
kit.HITBOXES = {
    "Cockpit": {"size": [0.9, 1.0, 2.4], "at": [0, 0.6, -4.5]},
    "Fuselage": {"size": [2.0, 1.4, 6.0], "at": [0, 0.0, -0.8]},
    "Engine": {"size": [1.6, 1.2, 3.8], "at": [0, 0.0, 3.0]},
    "WingL": {"size": [3.2, 0.3, 4.0], "at": [-2.4, round(WING_Z, 2), 1.4]},
    "WingR": {"size": [3.2, 0.3, 4.0], "at": [2.4, round(WING_Z, 2), 1.4]},
    "Tail": {"size": [0.6, 2.2, 2.4], "at": [0, 1.6, 3.6]},
}
EYE = (0, Y(480), 0.62)
kit.ATTACHMENTS = {
    "CockpitEye": EYE,
    "GunMuzzle": (-0.45, Y(620), Z(330)),  # the BK-27 under the left side of the fuselage
    "Nozzle1": (0, NOZZLE_Y1, NOZZLE_Z),
    "WingtipL": (-(kit.WING_TIP_X + 0.06), kit.RAIL_Y, WING_Z),
    "WingtipR": (kit.WING_TIP_X + 0.06, kit.RAIL_Y, WING_Z),
    "FlareDispenser": (-0.3, Y(1300), Z(340)),
    "ChaffDispenser": (0.3, Y(1300), Z(340)),
    "ChaseCam": (0, -18.0, 3.4),
    # Wingtip rails, then the outer and inner wing pylons, and the centreline
    "Hardpoint1": (-(kit.WING_TIP_X + 0.08), kit.RAIL_Y, WING_Z - 0.10),
    "Hardpoint2": (kit.WING_TIP_X + 0.08, kit.RAIL_Y, WING_Z - 0.10),
    "Hardpoint3": (-3.00, Y(1110), WING_Z - 0.25),
    "Hardpoint4": (3.00, Y(1110), WING_Z - 0.25),
    "Hardpoint5": (-2.00, Y(1020), WING_Z - 0.25),
    "Hardpoint6": (2.00, Y(1020), WING_Z - 0.25),
    "Hardpoint7": (0, Y(900), Z(375)),
}

# Cockpit interior (cockpit_kit.py, art pipeline §7), after Gripen C cockpit photos: the wide-angle HUD on the
# glareshield and three colour displays across the panel (the middle one the radar), with standby
# instruments under them. Charcoal, centre stick.
kit.COCKPIT = {
    "well": {"back": EYE[1] - 0.32, "front": EYE[1] + 0.72, "half_width": 0.36, "floor": EYE[2] - 1.00, "flange": 0.06},
    "panel": {"distance": 0.64, "top": -0.18, "bottom": -0.60, "tilt": 12, "half_width": 0.32},
    "coaming": {"overhang": 0.04, "length": 0.30, "drop": 0.06},
    "consoles": {"top": -0.50, "width": 0.11, "aft": -0.35, "fore": 0.40, "throttle": 0.02},
    "stick": "centre",
    "stick_fore": 0.40,
    "sight": "HUD",
    "palette": "Modern",
    "instruments": [
        {"name": "LeftMFD", "kind": "MFD", "u": -0.21, "v": 0.13, "size": 0.12},
        {"name": "RadarScope", "kind": "MFD", "u": 0.0, "v": 0.13, "size": 0.13, "live": "Radar"},
        {"name": "RightMFD", "kind": "MFD", "u": 0.21, "v": 0.13, "size": 0.12},
        {"name": "Airspeed", "kind": "Dial", "u": -0.21, "v": 0.27, "size": 0.05, "live": "Speed"},
        {"name": "Altimeter", "kind": "Dial", "u": -0.13, "v": 0.27, "size": 0.05, "live": "Altitude"},
        {"name": "ADI", "kind": "Dial", "u": 0.0, "v": 0.28, "size": 0.07, "face": "attitude"},
        {"name": "GMeter", "kind": "Dial", "u": 0.13, "v": 0.27, "size": 0.045, "live": "G"},
        {"name": "RPM", "kind": "Dial", "u": 0.21, "v": 0.27, "size": 0.045, "live": "RPM"},
    ],
}


# ---------------------------------------------------------------------------------------------------
# Builders
# ---------------------------------------------------------------------------------------------------


def rounded_ring(cx, y_of, hw, zc, hh, e=2.8, segments=18):
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
        rings = [rounded_ring(side * cx0, lip, hw0 * 0.80, zc0, hh0 * 0.88), rounded_ring(side * cx0, lip, hw0, zc0, hh0)]
        for xd, cx, hw, zc, hh in NACELLE:
            rings.append(rounded_ring(side * cx, lambda z, xd=xd: Y(xd), hw, zc, hh))
        # The mouth is recessed: the first ring sits inside and behind the lip
        rings[0] = [(p[0], p[1] - 0.15, p[2]) for p in rings[0]]
        parts.append(kit.lofted(rings, True, True))
        mouth = [(p[0], p[1] + 0.01, p[2]) for p in rings[0]]
        ducts.append(kit.lofted([mouth, [(p[0], p[1] + 0.01, p[2]) for p in mouth]], True, True))
    v, f = kit.merge(*parts)
    kit.make_object("Intakes", v, f, col, "Body")
    v, f = kit.merge(*ducts)
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
    v, f = kit.cylinder((0, Y(0), Z(332)), (0, Y(92), Z(328)), 0.025, 8)
    kit.make_object("Pitot", v, f, col, "Details")


def build_gear(col):
    nx, ny, nz = NOSE_WHEEL["at"]
    belly = Z(352)
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
        top = (side * 0.80, my + 0.20, Z(345))
        v, f = kit.cylinder(top, (side * mx, my, mz + 0.10), 0.07, 10)
        kit.make_object(f"MainGearStrut{name}", v, f, col, "Details", "Gear", origin=top,
                        hinge={"axis": (0, 1, 0), "min": 0, "max": 90, "control": "Gear"})
        centre = (side * mx, my, mz)
        v, f = kit.wheel(centre, MAIN_WHEEL["radius"], MAIN_WHEEL["width"])
        kit.make_object(f"MainGearWheel{name}", v, f, col, "Details", "GearWheel", origin=centre,
                        hinge={"axis": (1, 0, 0), "min": -720, "max": 720, "control": "Wheel"})
        v, f = kit.box((side * 0.92, my, Z(352) - 0.25), (0.04, 0.8, 0.45))
        kit.make_object(f"MainGearDoor{name}", v, f, col, "Details", "GearDoor", origin=(side * 0.92, my, Z(352) - 0.03),
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
