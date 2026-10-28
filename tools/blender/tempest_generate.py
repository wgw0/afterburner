"""
Afterburner: Tempest-class concept base mesh generator (Blender 4.x / 5.x). Art only: the Tempest has no flight
data yet (AircraftData), so this makes the model, skins and cockpit for when it does.

The Tempest is a fictionalised sixth-generation concept, not a real aircraft, so it is designed here rather
than measured: its stations are in centimetres from the nose tip (1 px = 1 cm), heights are rows on the same
scale (row 295, the nozzles' axis, is z = 0) and half widths are centimetres from the centreline. It follows
the general shape of the published sixth-generation concepts without copying any one of them, and carries
no manufacturer names or logos.

  * a long chined forebody with a large bubble canopy, blending into a wide, flat body
  * caret intakes under the leading-edge extensions, running back to two engines
  * a broad tailless delta wing with a forward-swept trailing edge (leading-edge flaps, and inboard and
    outboard elevons on the elevon controls)
  * twin fins canted out 35 degrees with rudders, twin nozzles with afterburner cones, ejection seat, landing
    gear (struts, wheels, doors)

Run headless:
  blender -b --python tools/blender/tempest_generate.py -- --out <dir> --manifest-luau tools/Manifests/Tempest.luau
"""

import argparse
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import f5e_generate as kit  # noqa: E402  (shared helpers; its module settings are switched below)

kit.AIRFRAME = "Tempest"
kit.REF_PX_PER_M = 100.0
kit.REF_PITOT_XD = 0.0
kit.REF_Z0_ROW = 295.0
kit.CG_FROM_PITOT = 10.97  # 25% of the 6.29 m mean aerodynamic chord
kit.LENGTH = 17.5
kit.SPINE_UPPER_ONLY = True
Y, Z = kit.Y, kit.Z
PX = kit.REF_PX_PER_M


def W(px):
    return px / PX


# (xd, half width cm, bottom row, shoulder row, top row, spine half width m, exponent). The forebody is
# chined (a flat section); under the canopy the top is the sill, behind it the spine runs over the wide,
# flat body.
_BODY = [
    (0, 0.5, 297, 293, 293, 0.0, 2.0),  # nose tip
    (100, 40, 325, 270, 270, 0.0, 1.6),
    (200, 62, 345, 245, 245, 0.0, 1.7),
    (300, 78, 355, 230, 230, 0.0, 1.9),  # windscreen base
    (450, 92, 362, 225, 225, 0.0, 2.2),
    (600, 110, 365, 222, 222, 0.0, 2.6),
    (700, 150, 365, 240, 165, 0.42, 3.0),  # the spine rises inside the canopy's rear
    (850, 220, 362, 255, 180, 0.50, 3.6),
    (1000, 260, 360, 260, 195, 0.50, 4.0),
    (1200, 260, 355, 262, 210, 0.45, 4.2),
    (1400, 230, 345, 262, 222, 0.35, 4.0),
    (1600, 170, 330, 265, 240, 0.15, 3.4),
    (1660, 140, 325, 268, 255, 0.0, 3.0),  # nozzles start
]
kit.FUSELAGE = [(xd, W(hw), Z(zb), Z(zs), Z(zt), sp, e) for xd, hw, zb, zs, zt, sp, e in _BODY]
kit.FUSELAGE_RINGS = 54
kit.FUSELAGE_SEGMENTS = 36

kit.CANOPY = [
    (xd, w, Z(row)) for xd, w, row in (
        (300, 0.10, 230), (360, 0.32, 195), (420, 0.44, 160), (500, 0.48, 140), (580, 0.47, 138),
        (640, 0.40, 148), (690, 0.28, 160), (720, 0.15, 168),
    )
]
kit.CANOPY_FRAMES = (640,)  # frameless bubble: only the frame behind the seat

# Intakes: (xd, centre x m, half width m, centre z m, half height m), from the caret mouth (its top at station
# 680, its bottom at 720) back to the engines
NACELLE = [
    (720, 1.20, 0.38, Z(330), 0.36),
    (900, 1.20, 0.45, Z(335), 0.38),
    (1100, 1.05, 0.48, Z(330), 0.38),
    (1350, 0.90, 0.48, Z(315), 0.36),
    (1600, 0.90, 0.45, Z(300), 0.40),
]
LIP_TOP, LIP_BOTTOM = 680, 720

WING_Z = Z(265)

# Leading-edge extensions: (half width cm, xd) from the forebody's chines to the wing, and back along the body
LERX_EDGE = [(100, 300), (160, 500), (220, 650), (250, 750)]
LERX_INNER = 0.90
LERX_Z0 = Z(262)
LERX_TE = (250, 1650)


def wing_le_y(x):
    return Y(750 + (x * PX - 250) * 1.19)


def wing_te_y(x):
    return Y(1650 - (x * PX - 250) * 0.50)


kit.WING_Z = WING_Z
kit.WING_ROOT_X, kit.WING_TIP_X = W(250), W(650)
kit.WING_ROOT_LE, kit.WING_ROOT_TE = wing_le_y(W(250)), wing_te_y(W(250))
kit.WING_SWEEP_LE = math.atan((wing_le_y(W(250)) - wing_le_y(W(650))) / (W(650) - W(250)))
kit.WING_TIP_CHORD = wing_le_y(W(650)) - wing_te_y(W(650))
kit.WING_THICKNESS = 0.04
kit.LE_FLAP_CHORD = 0.10
kit.TE_HINGE = 0.82
kit.TE_FLAP_SPAN = (2.70, 4.60)  # inboard elevons
kit.AILERON_SPAN = (4.65, 6.30)  # outboard elevons
kit.RAIL_Y = (wing_le_y(W(650)) + wing_te_y(W(650))) / 2
kit.RAIL_LENGTH = 0.5

FIN_X, FIN_CANT = W(200), math.radians(35)
FIN_ROOT_Z, FIN_TIP_Z = Z(250), Z(100)
FIN_ROOT_LE, FIN_ROOT_TE = Y(1300), Y(1680)
FIN_TIP_LE, FIN_TIP_TE = Y(1530), Y(1710)
FIN_THICKNESS = 0.045
RUDDER_HINGE = 0.72
RUDDER_SPAN = (Z(245), Z(130))

NOZZLE_X, NOZZLE_Z = W(90), 0.0
NOZZLE_R0, NOZZLE_R1 = 0.50, 0.46
NOZZLE_Y0, NOZZLE_Y1 = Y(1650), Y(1750)

GROUND_Z = Z(495)
NOSE_WHEEL = {"at": (0, Y(450), GROUND_Z + 0.35), "radius": 0.35, "width": 0.18}
MAIN_WHEEL = {"at": (1.50, Y(1150), GROUND_Z + 0.45), "radius": 0.45, "width": 0.24}
BELLY_Z = Z(362)
PITOT = (40, 120, 160, 300)  # (half width cm, xd from, xd to, row): the probes on the chines

kit.HULL = {"size": [4.2, 2.0, 16.8], "at": [0, 0.3, -0.8]}
kit.HITBOXES = {
    "Cockpit": {"size": [1.0, 1.1, 2.6], "at": [0, 1.2, -5.6]},
    "Fuselage": {"size": [5.0, 1.4, 8.0], "at": [0, 0.3, -0.2]},
    "Engine": {"size": [3.0, 1.2, 5.0], "at": [0, 0.0, 4.0]},
    "WingL": {"size": [4.0, 0.4, 6.0], "at": [-4.5, round(WING_Z, 2), 0.8]},
    "WingR": {"size": [4.0, 0.4, 6.0], "at": [4.5, round(WING_Z, 2), 0.8]},
    "Tail": {"size": [5.2, 2.0, 4.0], "at": [0, 1.2, 4.6]},
}
EYE = (0, Y(500), Z(140) - 0.27)
kit.ATTACHMENTS = {
    "CockpitEye": EYE,
    "GunMuzzle": (1.10, Y(700), Z(260)),  # the cannon in the right extension's root
    "Nozzle1": (-NOZZLE_X, NOZZLE_Y1, NOZZLE_Z),
    "Nozzle2": (NOZZLE_X, NOZZLE_Y1, NOZZLE_Z),
    "WingtipL": (-(kit.WING_TIP_X + 0.05), kit.RAIL_Y, WING_Z),
    "WingtipR": (kit.WING_TIP_X + 0.05, kit.RAIL_Y, WING_Z),
    "FlareDispenser": (-0.6, Y(1600), Z(330)),
    "ChaffDispenser": (0.6, Y(1600), Z(330)),
    "ChaseCam": (0, -21.0, 4.0),
    # The large internal bay (three stations a side) and the two side bays
    "Hardpoint1": (-0.35, Y(900), BELLY_Z - 0.12),
    "Hardpoint2": (0.35, Y(900), BELLY_Z - 0.12),
    "Hardpoint3": (-0.75, Y(950), BELLY_Z - 0.12),
    "Hardpoint4": (0.75, Y(950), BELLY_Z - 0.12),
    "Hardpoint5": (-0.35, Y(1050), BELLY_Z - 0.12),
    "Hardpoint6": (0.35, Y(1050), BELLY_Z - 0.12),
    "Hardpoint7": (-1.90, Y(800), Z(330)),
    "Hardpoint8": (1.90, Y(800), Z(330)),
}

# Cockpit interior (cockpit_kit.py, art pipeline §7): a wide single display across the panel (two large faces,
# the left one the radar), with a slim head-up display for the game's sight and a strip of standby
# instruments. Charcoal, side stick.
kit.COCKPIT = {
    "well": {"back": EYE[1] - 0.32, "front": EYE[1] + 0.76, "half_width": 0.42, "floor": EYE[2] - 1.00, "flange": 0.06},
    "panel": {"distance": 0.66, "top": -0.18, "bottom": -0.62, "tilt": 12, "half_width": 0.36},
    "coaming": {"overhang": 0.04, "length": 0.30, "drop": 0.06},
    "consoles": {"top": -0.50, "width": 0.12, "aft": -0.35, "fore": 0.42, "throttle": 0.02},
    "stick": "side",
    "sight": "HUD",
    "palette": "Modern",
    "instruments": [
        {"name": "RadarScope", "kind": "MFD", "u": -0.17, "v": 0.14, "size": 0.21, "live": "Radar"},
        {"name": "RightMFD", "kind": "MFD", "u": 0.17, "v": 0.14, "size": 0.21},
        {"name": "Airspeed", "kind": "Dial", "u": -0.21, "v": 0.30, "size": 0.04, "live": "Speed"},
        {"name": "Altimeter", "kind": "Dial", "u": -0.13, "v": 0.30, "size": 0.04, "live": "Altitude"},
        {"name": "ADI", "kind": "Dial", "u": 0.0, "v": 0.30, "size": 0.05, "face": "attitude"},
        {"name": "GMeter", "kind": "Dial", "u": 0.13, "v": 0.30, "size": 0.04, "live": "G"},
        {"name": "RPM", "kind": "Dial", "u": 0.21, "v": 0.30, "size": 0.04, "live": "RPM"},
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


def build_fins(col_body):
    """The twin canted fins with their rudders (the Tempest is tailless)."""
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


def elevons():
    """Tailless: the wing's trailing-edge surfaces (built as flaps and ailerons) are elevons."""
    for entry in kit.PARTS:
        name = entry["name"]
        if name[:-1] in ("Flap", "Aileron") and name[-1] in "LR" and "hinge" in entry:
            entry["hinge"]["control"] = "Elevon" + name[-1]
            entry["hinge"]["min"], entry["hinge"]["max"] = -25, 25


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
    kit.build_canopy(cols["Glass"], cols["Body"])
    kit.build_wings(cols["Wings"])
    elevons()
    build_fins(cols["Body"])
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
