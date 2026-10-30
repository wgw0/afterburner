"""
Afterburner: Rafale C base mesh generator (Blender 4.x / 5.x). Art only: the Rafale C has no flight data yet
(AircraftData), so this makes the model, skins and cockpit for when it does.

Builds a mid-poly, modular Rafale C at real-world size, measured from a reference drawing, in the same form as
the F-5E (f5e_generate.py, whose helpers this uses): separate objects per part, moving parts with their
origin on the hinge line, four texture sets, a manifest for the Studio assembler, an FBX, and the cockpit
well.

  * the fuselage with the radome, the single-seat canopy and the spine, widening over the twin engines
  * the intakes under the canard roots, either side of the cockpit
  * the all-moving canards on the elevon controls, close-coupled ahead of the wing
  * the cropped delta wing with leading-edge flaps and two elevons a side, and wingtip rails
  * the single fin with its rudder and tip pod, twin nozzles with afterburner cones, ejection seat, nose
    probe, the fixed refuelling probe, landing gear (struts, wheels, doors)

Run headless:
  blender -b --python tools/blender/rafalec_generate.py -- --out <dir> --manifest-luau tools/Manifests/RafaleC.luau

Reference: Kaboldy's Commons three-view of the Rafale (CC BY-SA 3.0), rendered 3840 px wide, cropped inside
its border and scaled to 2000 px: side view on top, top view below, both nose left with the nose tip at
x = 24. Stations (xd) are pixels aft of it; heights are side-view rows (row 447, the nozzles' axis, is
z = 0); half widths are pixels from the top view's centreline (row 1434.5). The scale comes from the
published 15.27 m length (127.5 px/m), which gives a 10.8 m span against the published 10.9 m. The drawing
is the two-seat Rafale B: the C's single-seat canopy is shorter, with a spine behind it. See
docs/art/reference/RafaleC/SOURCES.md (kept out of git).
"""

import argparse
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import f5e_generate as kit  # noqa: E402  (shared helpers; its module settings are switched below)

kit.AIRFRAME = "RafaleC"
kit.REF_PX_PER_M = 127.5
kit.REF_PITOT_XD = 0.0
kit.REF_Z0_ROW = 447.0
kit.CG_FROM_PITOT = 1270 / 127.5  # 25% of the 3.84 m mean aerodynamic chord
kit.LENGTH = 15.27
kit.SPINE_UPPER_ONLY = True
Y, Z = kit.Y, kit.Z
PX = kit.REF_PX_PER_M


def W(px):
    return px / PX


# (xd, half width px, bottom row, shoulder row, top row, spine half width m, exponent); under the canopy the
# top is the cockpit sill, behind it the spine runs back to the fin
_BODY = [
    (0, 0.5, 483, 479, 479, 0.0, 2.0),  # radome tip
    (100, 34, 490, 448, 448, 0.0, 2.0),
    (200, 52, 498, 418, 418, 0.0, 2.1),
    (300, 66, 505, 395, 395, 0.0, 2.3),  # windscreen base
    (450, 100, 508, 388, 388, 0.0, 2.6),
    (550, 130, 510, 384, 384, 0.0, 2.8),
    (650, 158, 512, 382, 382, 0.0, 3.0),
    (720, 165, 515, 394, 300, 0.30, 3.2),  # the spine rises inside the canopy's rear
    (800, 166, 516, 400, 304, 0.34, 3.3),
    (900, 167, 516, 400, 318, 0.34, 3.4),
    (1000, 167, 517, 402, 336, 0.32, 3.4),
    (1100, 167, 518, 404, 345, 0.30, 3.4),
    (1300, 167, 520, 404, 349, 0.24, 3.4),
    (1500, 160, 512, 400, 348, 0.16, 3.3),
    (1700, 145, 500, 390, 352, 0.08, 3.0),
    (1770, 136, 496, 392, 362, 0.0, 2.8),  # nozzles start
]
kit.FUSELAGE = [(xd, W(hw), Z(zb), Z(zs), Z(zt), sp, e) for xd, hw, zb, zs, zt, sp, e in _BODY]
kit.FUSELAGE_RINGS = 52
kit.FUSELAGE_SEGMENTS = 36

kit.CANOPY = [
    (xd, w, Z(row)) for xd, w, row in (
        (300, 0.10, 395), (350, 0.30, 370), (400, 0.38, 335), (450, 0.42, 300), (520, 0.44, 282),
        (600, 0.43, 282), (660, 0.38, 290), (720, 0.28, 300), (760, 0.15, 304),
    )
]
kit.CANOPY_FRAMES = (450, 640)  # windscreen bow, and the frame behind the seat

# Intakes: (xd, centre x m, half width m, centre z m, half height m), from the raked mouth (its top at
# station 650, its bottom at 700) back to the engines
NACELLE = [
    (720, 1.10, 0.26, Z(488), 0.41),
    (900, 1.05, 0.30, Z(490), 0.40),
    (1100, 0.90, 0.32, Z(488), 0.38),
    (1300, 0.78, 0.32, Z(480), 0.35),
    (1500, 0.74, 0.30, Z(465), 0.30),
]
LIP_TOP, LIP_BOTTOM = 650, 700

# Canards: root and tip (half width px, leading-edge xd, trailing-edge xd). The drawing's root (180 px) is
# outside the body's side (about 160 px at this height), so the root is carried in to 150 px along its edges.
CANARD_ROOT, CANARD_TIP = (150, 651, 826), (335, 806, 886)
CANARD_Z = Z(425)

WING_Z = Z(465)


def wing_le_y(x):
    return Y(991 + (x * PX - 239) * 1.045)


def wing_te_y(x):
    return Y(1651 - (x * PX - 200) * 0.069)


kit.WING_Z = WING_Z
# The drawing's root (200 px) is outside the body's side (about 167 px at the wing), so the root is carried in
# to 150 px along the leading and trailing edges
kit.WING_ROOT_X, kit.WING_TIP_X = W(150), W(690)
kit.WING_ROOT_LE, kit.WING_ROOT_TE = wing_le_y(W(150)), wing_te_y(W(150))
kit.WING_SWEEP_LE = math.atan((wing_le_y(W(200)) - wing_le_y(W(690))) / (W(690) - W(200)))
kit.WING_TIP_CHORD = wing_le_y(W(690)) - wing_te_y(W(690))
kit.WING_THICKNESS = 0.04
kit.LE_FLAP_CHORD = 0.10
kit.TE_HINGE = 0.82
kit.TE_FLAP_SPAN = (1.60, 3.40)  # inner elevon
kit.AILERON_SPAN = (3.45, 5.30)  # outer elevon
kit.RAIL_Y = (wing_le_y(W(690)) + wing_te_y(W(690))) / 2
kit.RAIL_LENGTH = 1.6

FIN_ROOT_Z, FIN_TIP_Z = Z(350), Z(100)
FIN_ROOT_LE, FIN_ROOT_TE = Y(1340), Y(1795)
FIN_TIP_LE, FIN_TIP_TE = Y(1740), Y(1910)
FIN_THICKNESS = 0.045
RUDDER_HINGE = 0.78
RUDDER_SPAN = (Z(345), Z(110))

NOZZLE_X, NOZZLE_Z, NOZZLE_R = W(94), 0.0, 0.40
NOZZLE_Y0, NOZZLE_Y1 = Y(1770), Y(1810)

GROUND_Z = Z(688)
NOSE_WHEEL = {"at": (0, Y(620), GROUND_Z + 0.19), "radius": 0.19, "width": 0.12}
MAIN_WHEEL = {"at": (1.35, Y(1226), GROUND_Z + 0.38), "radius": 0.38, "width": 0.20}

kit.HULL = {"size": [2.8, 1.8, 14.4], "at": [0, 0.0, -0.6]}
kit.HITBOXES = {
    "Cockpit": {"size": [0.9, 1.0, 2.4], "at": [0, 0.9, -5.4]},
    "Fuselage": {"size": [2.8, 1.5, 6.5], "at": [0, -0.1, -0.8]},
    "Engine": {"size": [2.6, 1.2, 4.0], "at": [0, 0.0, 3.6]},
    "WingL": {"size": [4.0, 0.3, 4.6], "at": [-3.3, round(WING_Z, 2), 1.6]},
    "WingR": {"size": [4.0, 0.3, 4.6], "at": [3.3, round(WING_Z, 2), 1.6]},
    "Tail": {"size": [0.6, 2.4, 3.6], "at": [0, 1.6, 4.4]},
}
EYE = (0, Y(540), Z(282) - 0.27)
kit.ATTACHMENTS = {
    "CockpitEye": EYE,
    "GunMuzzle": (0.85, Y(760), Z(470)),  # the 30 mm cannon in the right intake's flank
    "Nozzle1": (-NOZZLE_X, NOZZLE_Y1, NOZZLE_Z),
    "Nozzle2": (NOZZLE_X, NOZZLE_Y1, NOZZLE_Z),
    "WingtipL": (-(kit.WING_TIP_X + 0.06), kit.RAIL_Y, WING_Z),
    "WingtipR": (kit.WING_TIP_X + 0.06, kit.RAIL_Y, WING_Z),
    "FlareDispenser": (-0.5, Y(1650), Z(505)),
    "ChaffDispenser": (0.5, Y(1650), Z(505)),
    "ChaseCam": (0, -18.5, 3.6),
    # Wingtip rails, three pylons under each wing, two under the intakes and the centreline
    "Hardpoint1": (-(kit.WING_TIP_X + 0.08), kit.RAIL_Y, WING_Z - 0.10),
    "Hardpoint2": (kit.WING_TIP_X + 0.08, kit.RAIL_Y, WING_Z - 0.10),
    "Hardpoint3": (-4.30, wing_le_y(4.30) - 0.9, WING_Z - 0.25),
    "Hardpoint4": (4.30, wing_le_y(4.30) - 0.9, WING_Z - 0.25),
    "Hardpoint5": (-3.20, wing_le_y(3.20) - 1.2, WING_Z - 0.25),
    "Hardpoint6": (3.20, wing_le_y(3.20) - 1.2, WING_Z - 0.25),
    "Hardpoint7": (-2.20, wing_le_y(2.20) - 1.5, WING_Z - 0.25),
    "Hardpoint8": (2.20, wing_le_y(2.20) - 1.5, WING_Z - 0.25),
    "Hardpoint9": (-1.05, Y(1000), Z(540)),
    "Hardpoint10": (1.05, Y(1000), Z(540)),
    "Hardpoint11": (0, Y(1150), Z(525)),
}

# Cockpit interior (cockpit_kit.py, art pipeline §7), after Rafale cockpit photos: the wide head-up display
# over a head-level display, two colour displays either side and the radar display in the middle, with
# standby instruments. Charcoal, side stick.
kit.COCKPIT = {
    "well": {"back": EYE[1] - 0.32, "front": EYE[1] + 0.74, "half_width": 0.38, "floor": EYE[2] - 1.00, "flange": 0.06},
    "panel": {"distance": 0.64, "top": -0.18, "bottom": -0.60, "tilt": 12, "half_width": 0.33},
    "coaming": {"overhang": 0.04, "length": 0.30, "drop": 0.06},
    "consoles": {"top": -0.50, "width": 0.12, "aft": -0.35, "fore": 0.40, "throttle": 0.02},
    "stick": "side",
    "sight": "HUD",
    "palette": "Modern",
    "instruments": [
        {"name": "LeftMFD", "kind": "MFD", "u": -0.215, "v": 0.17, "size": 0.12},
        {"name": "RadarScope", "kind": "MFD", "u": 0.0, "v": 0.10, "size": 0.12, "live": "Radar"},
        {"name": "RightMFD", "kind": "MFD", "u": 0.215, "v": 0.17, "size": 0.12},
        {"name": "Airspeed", "kind": "Dial", "u": -0.215, "v": 0.06, "size": 0.045, "live": "Speed"},
        {"name": "Altimeter", "kind": "Dial", "u": -0.13, "v": 0.06, "size": 0.045, "live": "Altitude"},
        {"name": "GMeter", "kind": "Dial", "u": 0.13, "v": 0.06, "size": 0.045, "live": "G"},
        {"name": "RPM", "kind": "Dial", "u": 0.215, "v": 0.06, "size": 0.045, "live": "RPM"},
        {"name": "ADI", "kind": "Dial", "u": 0.0, "v": 0.24, "size": 0.07, "face": "attitude"},
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
        # The pod on the fin tip
        kit.box((0, (Y(1725) + Y(1935)) / 2, Z(82)), (0.14, Y(1725) - Y(1935), 0.26)),
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
    """The nose probe, and the fixed refuelling probe on the right, ahead of the windscreen."""
    parts = [kit.cylinder((0, Y(-30), Z(481)), (0, Y(5), Z(481)), 0.022, 8)]
    x = W(60)
    parts += [
        kit.cylinder((x, Y(320), Z(388)), (x, Y(280), Z(322)), 0.04, 8),
        kit.cylinder((x, Y(280), Z(322)), (x, Y(225), Z(322)), 0.04, 8),
        kit.cylinder((x, Y(225), Z(322)), (x, Y(210), Z(322)), 0.04, 8, radius1=0.06),
    ]
    v, f = kit.merge(*parts)
    kit.make_object("Pitot", v, f, col, "Details")


def build_gear(col):
    nx, ny, nz = NOSE_WHEEL["at"]
    belly = Z(510)
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
        top = (side * 1.00, my + 0.20, Z(510))
        v, f = kit.cylinder(top, (side * mx, my, mz + 0.10), 0.07, 10)
        kit.make_object(f"MainGearStrut{name}", v, f, col, "Details", "Gear", origin=top,
                        hinge={"axis": (0, 1, 0), "min": 0, "max": 90, "control": "Gear"})
        centre = (side * mx, my, mz)
        v, f = kit.wheel(centre, MAIN_WHEEL["radius"], MAIN_WHEEL["width"])
        kit.make_object(f"MainGearWheel{name}", v, f, col, "Details", "GearWheel", origin=centre,
                        hinge={"axis": (1, 0, 0), "min": -720, "max": 720, "control": "Wheel"})
        v, f = kit.box((side * 1.10, my, Z(520) - 0.25), (0.04, 0.8, 0.45))
        kit.make_object(f"MainGearDoor{name}", v, f, col, "Details", "GearDoor", origin=(side * 1.10, my, Z(520) - 0.03),
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
