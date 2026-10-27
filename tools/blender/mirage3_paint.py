"""
Afterburner: paints the Mirage IIIE. Same method as f5e_paint.py (whose baking, noise and output functions
this uses): bake where every texel is on the jet, compute the maps in numpy from the Mirage's panel layout
and a paint scheme, bake the normal map from the height.

  blender -b tools/blender/out/MirageIII_base.blend --python tools/blender/mirage3_paint.py -- \
      --out <absolute dir> [--skin Tactical] [--preview]

Use the .blend whose FBX was imported into Studio: the textures follow its UV layout.
"""

import argparse
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mirage3_generate as mir  # noqa: E402  (sets the shared generator module to the Mirage IIIE)
import f5e_paint as paint  # noqa: E402
import cockpit_kit  # noqa: E402

kit = mir.kit
Y = kit.Y
srgb, smooth, groove, rivets, fbm, cell_tone = paint.srgb, paint.smooth, paint.groove, paint.rivets, paint.fbm, paint.cell_tone

SCHEMES = {
    # Armée de l'Air tactical camouflage: dark green and grey over aluminium-lacquered undersides
    "Tactical": {
        "camo": [srgb(88, 98, 82), srgb(120, 126, 128), srgb(66, 76, 64)],
        "camo_scale": 2.8,
        "underside": srgb(176, 180, 182),
        "underside_metal": True,
        "radome": srgb(44, 48, 46),
        "antiglare": srgb(44, 48, 46),
        "lower": srgb(176, 180, 182),
        "upper": srgb(88, 98, 82),
        "markings": "national",
    },
    # Natural metal, as delivered
    "Silver": {
        "base": srgb(182, 186, 190),
        "metal": True,
        "radome": srgb(40, 42, 44),
        "antiglare": srgb(44, 46, 48),
        "lower": srgb(182, 186, 190),
        "upper": srgb(182, 186, 190),
        "markings": "national",
    },
    # Desert camouflage: sand and brown over light blue
    "Desert": {
        "camo": [srgb(196, 170, 124), srgb(140, 104, 70), srgb(176, 146, 98)],
        "camo_scale": 2.6,
        "underside": srgb(160, 184, 196),
        "radome": srgb(52, 48, 44),
        "antiglare": srgb(52, 48, 44),
        "lower": srgb(160, 184, 196),
        "upper": srgb(196, 170, 124),
        "markings": "lowvis",
    },
    # Two-tone air-superiority grey
    "Grey": {
        "base": srgb(132, 140, 148),
        "radome": srgb(70, 74, 78),
        "antiglare": srgb(60, 64, 68),
        "lower": srgb(162, 168, 174),
        "upper": srgb(118, 126, 134),
        "markings": "lowvis",
    },
}

BLUE = srgb(30, 60, 140)
WHITE = srgb(226, 226, 222)
RED = srgb(186, 34, 40)
LOWVIS = (srgb(96, 100, 104), srgb(150, 154, 158), srgb(120, 124, 128))
METAL = srgb(176, 178, 182)
HOT_METAL = srgb(118, 110, 102)
SOOT = srgb(30, 28, 27)
DUCT = srgb(22, 23, 25)

FRAMES = [400, 520, 700, 868, 1000, 1150, 1300, 1450, 1600, 1750, 1900, 2050, 2200, 2350, 2500, 2620]
SIDE_LINES = [(-0.30, 400, 868), (0.05, 1000, 2620), (-0.45, 1000, 2480)]  # (z, from, to)
SIDE_PANELS = [(420, 500, -0.45, -0.05), (1050, 1150, -0.40, 0.00), (1900, 2000, 0.20, 0.55), (2250, 2350, -0.40, 0.10)]
ROUNDEL_FUSELAGE = (1230, -0.05, 0.27)  # station, z, radius: on the intake fairings
ROUNDEL_WING = (2.95, 0.36)  # |x|, radius: upper and lower surfaces


def roundel(d, r, low):
    """Concentric roundel (blue centre, white, red outside; or three greys). Returns colour, mask."""
    outer = 1 - smooth(r - 0.006, r + 0.006, d)
    inner = 1 - smooth(r * 0.66 - 0.006, r * 0.66 + 0.006, d)
    centre = 1 - smooth(r * 0.33 - 0.006, r * 0.33 + 0.006, d)
    c_out, c_mid, c_in = (LOWVIS if low else (RED, WHITE, BLUE))
    colour = c_out * (outer - inner)[..., None] + c_mid * (inner - centre)[..., None] + c_in * centre[..., None]
    return colour, outer


def wing_fraction(x, y):
    xa = np.abs(x)
    le, te = mir.wing_le_y(xa), mir.wing_te_y(xa)  # both linear, so they take arrays
    return (le - y) / np.maximum(le - te, 1e-3), le - te


def paint_airframe(P, N, part, ids, ao, scheme):
    x, y, z = P[..., 0], P[..., 1], P[..., 2]
    nz = N[..., 2]
    side = np.abs(nz) < 0.6
    down = nz <= -0.6
    shape = x.shape
    on = paint.make_on(part, ids)
    fus, intakes, cones = on("Fuselage"), on("Intakes"), on("InletCones")
    wing = on("WingL", "WingR")
    surf = on("ElevonInL", "ElevonInR", "ElevonOutL", "ElevonOutR")
    fin, rudder, frame, chute = on("Fin"), on("Rudder"), on("CanopyFrame"), on("ChuteFairing")
    body = fus | intakes
    xd = kit.REF_PITOT_XD + (kit.CG_FROM_PITOT - y) * kit.REF_PX_PER_M
    line = np.zeros(shape, np.float32)
    rivet = np.zeros(shape, np.float32)
    w = 0.0045

    for f in FRAMES:
        d = y - Y(f)
        line = np.maximum(line, np.where(body, groove(d, w), 0))
        rivet = np.maximum(rivet, np.where(body, rivets(d, np.where(side, z, x), 0.05, 0.004, offset=0.018), 0))
    for zz, a, b in SIDE_LINES:
        m = body & side & (xd >= a) & (xd <= b)
        line = np.maximum(line, np.where(m, groove(z - zz, w), 0))
    for a, b, z0, z1 in SIDE_PANELS:
        inside = body & side & (xd >= a) & (xd <= b) & (z >= z0) & (z <= z1)
        edge = np.minimum(np.minimum(np.abs(xd - a), np.abs(xd - b)) / kit.REF_PX_PER_M,
                          np.minimum(np.abs(z - z0), np.abs(z - z1)))
        line = np.maximum(line, np.where(inside, groove(edge, w), 0))
    fw, chord = wing_fraction(x, y)
    for sf in (0.12, 0.45, 0.80):  # spars
        d = (fw - sf) * chord
        line = np.maximum(line, np.where(wing, groove(d, w), 0))
        rivet = np.maximum(rivet, np.where(wing, rivets(d, x, 0.05, 0.004, offset=0.016), 0))
    for rx in np.arange(1.2, 4.0, 0.6):  # ribs
        m = wing & (fw > 0.12)
        line = np.maximum(line, np.where(m, groove(np.abs(x) - rx, w), 0))
    for k in range(1, 12):
        line = np.maximum(line, np.where(surf, groove(np.abs(x) - (0.95 + 0.27 * k), w * 0.8), 0))
    for rz in (1.4, 1.9, 2.4):
        line = np.maximum(line, np.where(fin, groove(z - rz, w), 0))

    # Colour
    colour = np.broadcast_to(scheme.get("base", scheme["upper"]), shape + (3,)).copy()
    under = np.where(wing | surf, (nz < 0).astype(np.float32), smooth(-0.15, -0.35, z))
    under = np.where(fin | rudder | chute, 0.0, under)
    if "camo" in scheme:
        camo = paint.camouflage(P, scheme)
        colour = camo * (1 - under[..., None]) + scheme["underside"] * under[..., None]
    elif not scheme.get("metal"):
        t = 1 - under
        colour = scheme["lower"] * (1 - t[..., None]) + scheme["upper"] * t[..., None]
    fidx = np.searchsorted(-np.array([Y(f) for f in FRAMES]), -y)
    cell = np.where(body, fidx * 8 + (x > 0), (np.floor(np.abs(x) / 0.6) * 4 + (x > 0) * 97).astype(np.int64))
    colour *= cell_tone(cell.astype(np.int64), 3, 0.06 if scheme.get("metal") else 0.025)[..., None]

    radome = fus & (xd < 400)
    colour = np.where((radome | cones)[..., None], scheme["radome"], colour)
    ag_half = np.clip((xd - 420) / (535 - 420), 0, 1) * 0.25 + 0.06
    antiglare = fus & (xd >= 420) & (xd <= 538) & (nz > 0.4) & (np.abs(x) < ag_half)
    colour = np.where(antiglare[..., None], scheme["antiglare"], colour)
    lip = intakes & (xd < 890)
    duct = intakes & (N[..., 1] < -0.2) & (xd > 880)
    colour = np.where(lip[..., None], METAL, colour)
    colour = np.where(duct[..., None], DUCT, colour)
    hot = fus & (xd > 2560)
    heat = smooth(2560, 2680, xd)[..., None]
    colour = np.where(hot[..., None], METAL * (1 - heat) + HOT_METAL * heat, colour)

    # Markings: roundels on the intake fairings and both wings, top and bottom; a fin flash on the rudder
    low = scheme.get("markings") == "lowvis"
    st, sz, sr = ROUNDEL_FUSELAGE
    c1, m1 = roundel(np.hypot(y - Y(st), z - sz), sr, low)
    m1 = np.where(intakes & side, m1, 0)
    ix, wr = ROUNDEL_WING
    fw0 = 0.5
    y0 = mir.wing_le_y(ix) - fw0 * (mir.wing_le_y(ix) - mir.wing_te_y(ix))
    c2, m2 = roundel(np.hypot(np.abs(x) - ix, y - y0), wr, low)
    m2 = np.where(wing, m2, 0)
    colour = colour * (1 - m1[..., None]) + c1 * m1[..., None]
    colour = colour * (1 - m2[..., None]) + c2 * m2[..., None]
    marks = (m1 + m2) > 0.5
    if not low:  # tricolour fin flash: blue leading, white, red trailing
        rf = rudder & (z < mir.RUDDER_SPAN[0] + 0.7)
        t = np.clip((Y(2560) - y) / 0.45, 0, 1)
        flash = np.where(t < 1 / 3, 0, np.where(t < 2 / 3, 1, 2))
        for i, c in enumerate((BLUE, WHITE, RED)):
            colour = np.where((rf & (flash == i))[..., None], c, colour)
        marks = marks | rf

    # Soot and grime
    aft = smooth(Y(2500), Y(2700), y)
    streaks = fbm(P, 3.0, 3, seed=11, stretch=(4.0, 0.25, 4.0))
    soot = np.where(fus, aft * (0.25 + 0.45 * streaks) * np.clip(0.6 - z, 0.2, 1.0), 0)
    gun = fus & down & (np.abs(np.abs(x) - 0.30) < 0.15) & (y < Y(1000)) & (y > Y(1250))
    soot = np.maximum(soot, np.where(gun, 0.55 * smooth(Y(1000), Y(1250), y), 0))
    colour = colour * (1 - soot[..., None]) + SOOT * soot[..., None]
    grime = fbm(P, 2.2, 4, seed=21, stretch=(3.0, 0.3, 3.0))
    grime = np.clip((grime - 0.52) * 2.0, 0, 1) * (0.05 + 0.05 * down)
    colour *= (1 - grime - 0.3 * line)[..., None]
    well = fus & cockpit_kit.well_mask(P)  # the cockpit well, seen through the canopy: cockpit-dark
    colour = np.where(well[..., None], srgb(42, 43, 46), colour)
    colour *= (0.55 + 0.45 * np.power(np.clip(ao, 0, 1), 0.8))[..., None]

    metal_paint = bool(scheme.get("metal"))
    rough = (0.38 if metal_paint else 0.56) + 0.08 * (fbm(P, 4.0, 3, seed=41) - 0.5) + 0.12 * grime + 0.12 * line
    metal = np.full(shape, 0.75 if metal_paint else 0.0, np.float32)
    if scheme.get("underside_metal"):  # aluminium lacquer: a little sheen
        metal = np.maximum(metal, 0.35 * under)
        rough = np.where(under > 0.5, 0.45, rough)
    metal = np.where(marks | radome | cones | antiglare | duct | well, 0.0, metal)
    rough = np.where(marks, 0.5, rough)
    rough = np.where(antiglare | well, 0.85, rough)
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
    radial = np.stack([x, np.zeros_like(x), z - mir.NOZZLE_Z], axis=-1)
    inner = (radial * N).sum(-1) < 0
    t = np.clip((mir.NOZZLE_Y0 - y) / (mir.NOZZLE_Y0 - mir.NOZZLE_Y1), 0, 1)
    tint = paint.METAL * (1 - t[..., None] * 0.45) + srgb(84, 78, 118) * (t[..., None] * 0.45)
    colour = np.where((noz & ~inner)[..., None], tint, colour)
    colour = np.where((noz & inner)[..., None], SOOT, colour)
    metal = np.where(noz, np.where(inner, 0.3, 0.9), metal)
    rough = np.where(noz, np.where(inner, 0.85, 0.35), rough)
    petal = np.mod(np.arctan2(z - mir.NOZZLE_Z, x) * 18 / (2 * math.pi), 1.0)
    height = np.where(noz & ~inner, -groove(np.minimum(petal, 1 - petal), 0.06), height)

    ab = on("Afterburner")
    colour = np.where(ab[..., None], srgb(46, 40, 36), colour)
    metal = np.where(ab, 0.7, metal)
    seat = on("EjectionSeat")
    colour = np.where(seat[..., None], srgb(40, 42, 44), colour)
    pitot = on("Pitot")
    colour = np.where(pitot[..., None], METAL, colour)
    metal = np.where(pitot, 0.8, metal)
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
    parser.add_argument("--skin", default="Tactical")
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
