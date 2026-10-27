"""
Afterburner: paints the MiG-21bis. Same method as f5e_paint.py (whose baking, noise and output functions
this uses): bake where every texel is on the jet, compute the maps in numpy from the MiG-21's panel
layout and a paint scheme, bake the normal map from the height.

  blender -b tools/blender/out/MiG21bis_base.blend --python tools/blender/mig21_paint.py -- \
      --out <absolute dir> [--skin Silver] [--preview]

Use the .blend whose FBX was imported into Studio: the textures follow its UV layout.
"""

import argparse
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mig21_generate as mig  # noqa: E402  (sets the shared generator module to the MiG-21bis)
import f5e_paint as paint  # noqa: E402

kit = mig.kit
Y = kit.Y
srgb, smooth, groove, rivets, fbm, cell_tone = paint.srgb, paint.smooth, paint.groove, paint.rivets, paint.fbm, paint.cell_tone

SCHEMES = {
    # Natural-metal lacquer: the classic Soviet finish
    "Silver": {
        "base": srgb(178, 182, 186),
        "metal": True,
        "radome": srgb(62, 74, 66),
        "antiglare": srgb(40, 44, 46),
        "lower": srgb(178, 182, 186),
        "upper": srgb(178, 182, 186),
    },
    # Light-grey interceptor
    "Grey": {
        "base": srgb(150, 156, 162),
        "radome": srgb(70, 80, 74),
        "antiglare": srgb(52, 56, 60),
        "lower": srgb(162, 168, 172),
        "upper": srgb(140, 146, 152),
    },
    # 1980s Soviet tactical camouflage over light blue undersides
    "Tactical": {
        "camo": [srgb(186, 160, 112), srgb(104, 116, 66), srgb(62, 78, 52)],
        "camo_scale": 2.4,
        "underside": srgb(150, 182, 200),
        "radome": srgb(58, 70, 56),
        "antiglare": srgb(44, 46, 40),
        "lower": srgb(150, 182, 200),
        "upper": srgb(104, 116, 66),
    },
}

RED = srgb(170, 30, 30)
WHITE = srgb(225, 225, 220)
METAL = srgb(176, 178, 182)
HOT_METAL = srgb(120, 112, 104)
SOOT = srgb(30, 28, 27)
DUCT = srgb(22, 23, 25)

FRAMES = [230, 300, 360, 440, 560, 720, 800, 900, 1000, 1080, 1150, 1250, 1300, 1345]
SIDE_LINES = [(0.0, 300, 1345), (-0.36, 300, 1080), (0.40, 720, 1300)]
SIDE_PANELS = [(250, 340, -0.30, 0.10), (600, 700, -0.40, -0.05), (1100, 1180, -0.20, 0.20)]
STAR_FIN = (1300, 1.35, 0.30)  # station, z, radius
STAR_WING = (2.45, 0.32)  # |x|, radius: upper and lower surfaces of both wings


def star_mask(u, v, r):
    """Five-pointed star (point up +v) with a white border: returns (red, white) masks."""
    pts = []
    for k in range(10):
        ang = math.pi / 2 + k * math.pi / 5
        rad = r if k % 2 == 0 else r * 0.40
        pts.append((rad * math.cos(ang), rad * math.sin(ang)))
    d = paint.sd_polygon(u, v, pts)
    red = 1 - smooth(-0.006, 0.006, d)
    white = (1 - smooth(r * 0.10 - 0.006, r * 0.10 + 0.006, d)) * (1 - red)
    return red, white


def wing_fraction(x, y):
    xa = np.abs(x)
    le = mig.Y(569) - (xa - 0.60) * math.tan(mig.WING_SWEEP_LE)
    return (le - y) / np.maximum(le - mig.WING_TE_Y, 1e-3), le - mig.WING_TE_Y


def paint_airframe(P, N, part, ids, ao, scheme):
    x, y, z = P[..., 0], P[..., 1], P[..., 2]
    nz = N[..., 2]
    side = np.abs(nz) < 0.6
    up, down = nz >= 0.6, nz <= -0.6
    shape = x.shape
    on = paint.make_on(part, ids)
    fus, cone = on("Fuselage"), on("InletCone")
    wing = on("WingL", "WingR")
    surf = on("FlapL", "FlapR", "AileronL", "AileronR")
    stab = on("StabilatorL", "StabilatorR")
    fin, rudder, ventral, frame = on("Fin"), on("Rudder"), on("VentralFin"), on("CanopyFrame")
    xd = paint.gen.REF_PITOT_XD + (paint.gen.CG_FROM_PITOT - y) * paint.gen.REF_PX_PER_M
    line = np.zeros(shape, np.float32)
    rivet = np.zeros(shape, np.float32)
    w = 0.0045

    for f in FRAMES:
        d = y - Y(f)
        line = np.maximum(line, np.where(fus, groove(d, w), 0))
        rivet = np.maximum(rivet, np.where(fus, rivets(d, np.where(side, z, x), 0.05, 0.004, offset=0.018), 0))
    for zz, a, b in SIDE_LINES:
        m = fus & side & (xd >= a) & (xd <= b)
        line = np.maximum(line, np.where(m, groove(z - zz, w), 0))
    for a, b, z0, z1 in SIDE_PANELS:
        inside = fus & side & (xd >= a) & (xd <= b) & (z >= z0) & (z <= z1)
        edge = np.minimum(np.minimum(np.abs(xd - a), np.abs(xd - b)) / paint.gen.REF_PX_PER_M,
                          np.minimum(np.abs(z - z0), np.abs(z - z1)))
        line = np.maximum(line, np.where(inside, groove(edge, w), 0))
    fw, chord = wing_fraction(x, y)
    for sf in (0.15, 0.72):
        d = (fw - sf) * chord
        line = np.maximum(line, np.where(wing, groove(d, w), 0))
        rivet = np.maximum(rivet, np.where(wing, rivets(d, x, 0.05, 0.004, offset=0.016), 0))
    for rx in np.arange(1.0, 3.4, 0.55):
        m = wing & (fw > 0.15) & (fw < 0.72)
        line = np.maximum(line, np.where(m, groove(np.abs(x) - rx, w), 0))
    for rx in (1.3, 2.5):  # wing fences, drawn as raised strips
        line = np.maximum(line, np.where(wing & up & (fw < 0.8), groove(np.abs(x) - rx, 0.012) * 0.5, 0))
    for k in range(1, 9):
        line = np.maximum(line, np.where(surf, groove(np.abs(x) - (0.6 + 0.33 * k), w * 0.8), 0))
    for rz in (1.0, 1.5, 2.0):
        line = np.maximum(line, np.where(fin, groove(z - rz, w), 0))

    # Colour
    colour = np.broadcast_to(scheme["base"] if "base" in scheme else scheme["upper"], shape + (3,)).copy()
    if "camo" in scheme:
        camo = paint.camouflage(P, scheme)
        under = np.where(wing | surf | stab, (nz < 0).astype(np.float32), smooth(-0.10, -0.25, z))
        under = np.where(fin | rudder, 0.0, under)
        colour = camo * (1 - under[..., None]) + scheme["underside"] * under[..., None]
    elif not scheme.get("metal"):
        t = np.where(wing | surf | stab, (nz > 0).astype(np.float32), smooth(-0.15, 0.05, z))
        t = np.where(fin | rudder | frame, 1.0, t)
        colour = scheme["lower"] * (1 - t[..., None]) + scheme["upper"] * t[..., None]
    fidx = np.searchsorted(-np.array([Y(f) for f in FRAMES]), -y)
    cell = np.where(fus, fidx * 8 + (x > 0), (np.floor(np.abs(x) / 0.55) * 4 + (x > 0) * 97).astype(np.int64))
    colour *= cell_tone(cell.astype(np.int64), 3, 0.06 if scheme.get("metal") else 0.025)[..., None]

    colour = np.where(cone[..., None], scheme["radome"], colour)
    ag_half = np.clip((xd - 260) / (375 - 260), 0, 1) * 0.28 + 0.05
    antiglare = fus & (xd >= 260) & (xd <= 378) & (nz > 0.4) & (np.abs(x) < ag_half)
    colour = np.where(antiglare[..., None], scheme["antiglare"], colour)
    lip = fus & (xd < 200)
    duct = fus & (xd >= 182) & (N[..., 1] > -0.2) & (np.hypot(x, z) < 0.43)
    colour = np.where(lip[..., None], METAL, colour)
    colour = np.where(duct[..., None], DUCT, colour)
    # Bare, heat-stained tail end
    hot = fus & (xd > 1300)
    heat = smooth(1300, 1375, xd)[..., None]
    colour = np.where(hot[..., None], METAL * (1 - heat) + HOT_METAL * heat, colour)

    # Red stars: fin sides, both wings top and bottom
    st, sz, sr = STAR_FIN
    red, white = star_mask(-np.sign(N[..., 0]) * (y - Y(st)), z - sz, sr)
    red, white = np.where(fin, red, 0), np.where(fin, white, 0)
    ix, wr = STAR_WING
    y0 = mig.Y(569) - (ix - 0.60) * math.tan(mig.WING_SWEEP_LE) - 0.5 * (
        mig.Y(569) - (ix - 0.60) * math.tan(mig.WING_SWEEP_LE) - mig.WING_TE_Y)
    r2, w2 = star_mask(np.abs(x) - ix, y - y0, wr)
    red, white = np.maximum(red, np.where(wing, r2, 0)), np.maximum(white, np.where(wing, w2, 0))
    colour = colour * (1 - white[..., None]) + WHITE * white[..., None]
    colour = colour * (1 - red[..., None]) + RED * red[..., None]

    # Soot and grime
    aft = smooth(Y(1290), Y(1380), y)
    streaks = fbm(P, 3.0, 3, seed=11, stretch=(4.0, 0.25, 4.0))
    soot = np.where(fus | ventral, aft * (0.25 + 0.45 * streaks) * np.clip(0.6 - z, 0.2, 1.0), 0)
    gun = fus & down & (np.abs(x) < 0.12) & (y < Y(640)) & (y > Y(760))
    soot = np.maximum(soot, np.where(gun, 0.6 * smooth(Y(640), Y(760), y), 0))
    colour = colour * (1 - soot[..., None]) + SOOT * soot[..., None]
    grime = fbm(P, 2.2, 4, seed=21, stretch=(3.0, 0.3, 3.0))
    grime = np.clip((grime - 0.52) * 2.0, 0, 1) * (0.05 + 0.05 * down)
    colour *= (1 - grime - 0.3 * line)[..., None]
    colour *= (0.55 + 0.45 * np.power(np.clip(ao, 0, 1), 0.8))[..., None]

    metal_paint = bool(scheme.get("metal"))
    rough = (0.38 if metal_paint else 0.56) + 0.08 * (fbm(P, 4.0, 3, seed=41) - 0.5) + 0.12 * grime + 0.12 * line
    metal = np.full(shape, 0.75 if metal_paint else 0.0, np.float32)
    painted_marks = (red + white) > 0.5
    metal = np.where(painted_marks | cone | antiglare | duct, 0.0, metal)
    rough = np.where(painted_marks, 0.5, rough)
    rough = np.where(antiglare, 0.8, rough)
    metal = np.where(lip | hot, 0.85, metal)
    rough = np.where(hot, 0.45, rough)
    rough = np.maximum(rough, soot * 0.85)
    height = -line - 0.35 * rivet
    return colour, np.clip(rough, 0.05, 1), metal, height


def paint_details(P, N, part, ids, ao, scheme):
    x, y, z = P[..., 0], P[..., 1], P[..., 2]
    shape = x.shape
    on = paint.make_on(part, ids)
    colour = np.broadcast_to(scheme["lower"], shape + (3,)).copy()
    rough = np.full(shape, 0.55, np.float32)
    metal = np.zeros(shape, np.float32)
    height = np.zeros(shape, np.float32)

    noz = on("Nozzle")
    radial = np.stack([x, np.zeros_like(x), z - mig.NOZZLE_Z], axis=-1)
    inner = (radial * N).sum(-1) < 0
    t = np.clip((mig.NOZZLE_Y0 - y) / (mig.NOZZLE_Y0 - mig.NOZZLE_Y1), 0, 1)
    tint = paint.METAL * (1 - t[..., None] * 0.45) + srgb(84, 78, 118) * (t[..., None] * 0.45)
    colour = np.where((noz & ~inner)[..., None], tint, colour)
    colour = np.where((noz & inner)[..., None], SOOT, colour)
    metal = np.where(noz, np.where(inner, 0.3, 0.9), metal)
    rough = np.where(noz, np.where(inner, 0.85, 0.35), rough)
    petal = np.mod(np.arctan2(z - mig.NOZZLE_Z, x) * 20 / (2 * math.pi), 1.0)
    height = np.where(noz & ~inner, -groove(np.minimum(petal, 1 - petal), 0.06), height)

    ab = on("Afterburner")
    colour = np.where(ab[..., None], srgb(46, 40, 36), colour)
    metal = np.where(ab, 0.7, metal)
    seat = on("EjectionSeat")
    colour = np.where(seat[..., None], srgb(40, 44, 40), colour)
    pitot = on("Pitot")
    colour = np.where(pitot[..., None], np.where((np.mod(y * 4, 1.0) < 0.5)[..., None], RED, WHITE), colour)
    struts = on("NoseGearStrut", "MainGearStrutL", "MainGearStrutR")
    colour = np.where(struts[..., None], srgb(190, 194, 190), colour)
    metal = np.where(struts, 0.6, metal)
    wheels = on("NoseGearWheel", "MainGearWheelL", "MainGearWheelR")
    colour = np.where(wheels[..., None], srgb(28, 28, 28), colour)
    rough = np.where(wheels, 0.9, rough)
    colour *= (0.6 + 0.4 * np.power(np.clip(ao, 0, 1), 0.8))[..., None]
    return colour, np.clip(rough, 0.05, 1), metal, height


def main():
    import bpy

    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", required=True)
    parser.add_argument("--skin", default="Silver")
    parser.add_argument("--preview", action="store_true")
    args = parser.parse_args(argv)
    os.makedirs(args.out, exist_ok=True)
    scheme = SCHEMES[args.skin]

    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.render.bake.margin_type = "EXTEND"
    world = scene.world or bpy.data.worlds.new("World")
    scene.world = world
    world.light_settings.distance = 0.35

    written = {}
    for set_name, size in paint.SETS.items():
        maps, ids, objs = paint.bake_maps(set_name, size * paint.SUPERSAMPLE)
        P, N, part, ao, valid = maps["P"], maps["N"], maps["ID"], maps["AO"], maps["valid"]
        fn = paint_details if set_name == "Details" else paint_airframe
        colour, rough, metal, height = fn(P, N, part, ids, ao, scheme)
        colour = np.where(valid[..., None], colour, scheme["upper"])
        rough, metal, height = np.where(valid, rough, 0.6), np.where(valid, metal, 0), np.where(valid, height, 0)
        base = os.path.join(args.out, f"{kit.AIRFRAME}_{args.skin}_{set_name}")
        paths = {m: f"{base}_{m}.png" for m in ("Color", "Roughness", "Metalness", "Normal")}
        paint.save_png(paths["Color"], paint.to_srgb(paint.downsample(colour)), "sRGB")
        paint.save_png(paths["Roughness"], paint.downsample(rough), "Non-Color")
        paint.save_png(paths["Metalness"], paint.downsample(metal), "Non-Color")
        paint.bake_normal(set_name, objs, height.astype(np.float32), size, paths["Normal"])
        written[set_name] = paths
        print(f"painted {set_name}: {size}px, {len(objs)} parts")

    if args.preview:
        for set_name, paths in written.items():
            paint.apply_preview_material(set_name, paths)
        paint.render_preview(args.out, f"{kit.AIRFRAME}_{args.skin}")


if __name__ == "__main__":
    main()
