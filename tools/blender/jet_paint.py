"""
Afterburner: the shared skin painter for jets from the Mirage IIIE on. Same method as f5e_paint.py (whose
baking, noise and output functions this uses): bake where every texel is on the jet, compute the maps in
numpy, bake the normal map from the height. A jet's paint script gives its LAYOUT (where its panels,
markings and special areas are) and its SCHEMES, and calls main().

LAYOUT keys (stations are the generator's drawing stations, xd; lengths in metres):
  body          parts painted as fuselage (frames, side lines, panels, roundel)
  frames        fuselage frame stations; side_lines [(z, from, to)]; side_panels [(from, to, z0, z1)]
  wing          (le, te): functions of |x| giving the leading and trailing edge's Blender Y
  wings         wing parts; surfaces: moving wing and tail surfaces; tail: tailplane parts
  spars         chord fractions; ribs (from, to, step) in |x|
  fin, rudder   parts; fin_lines: heights of the fin's panel lines; upper_only: parts never given the
                underside colour (fins, fairings on top)
  radome        xd where the radome ends; dark: other parts painted the radome colour (shock cones);
                ducts: parts painted as dark intake ducts (recessed mouths)
  antiglare     (from, to, half width at from, half width at to)
  lip           (parts, xd): intake lips in bare metal ahead of xd; duct: parts whose aft-facing
                insides are dark
  hot           (from, to): the bare, heat-stained tail end
  gun           (|x|, half width, from, to): gun-port soot under the fuselage, or None
  insignia      "roundel" (with roundel_colours), "star_us", "star_ru" or None
  roundel_fuselage (xd, z, radius, parts); roundel_wing (|x|, radius, chord fraction)
  fin_flash     (parts, top z, xd of its leading edge, length) or None: a tricolour on the rudder
  nozzles       [(x, z)]; nozzle_z; nozzle_y (start, exit); petals
  pitot         colour mode: "metal" or "stripes"
"""

import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import f5e_paint as paint  # noqa: E402
import cockpit_kit  # noqa: E402
import livery_paint  # noqa: E402

kit = paint.gen
srgb, smooth, groove, rivets, fbm, cell_tone = paint.srgb, paint.smooth, paint.groove, paint.rivets, paint.fbm, paint.cell_tone

METAL = srgb(176, 178, 182)
HOT_METAL = srgb(118, 110, 102)
SOOT = srgb(30, 28, 27)
DUCT = srgb(22, 23, 25)
WELL = srgb(42, 43, 46)
LOWVIS = (srgb(96, 100, 104), srgb(150, 154, 158), srgb(120, 124, 128))


def roundel(d, r, colours):
    """Concentric roundel: colours (outer, middle, centre). Returns colour, mask."""
    outer = 1 - smooth(r - 0.006, r + 0.006, d)
    inner = 1 - smooth(r * 0.66 - 0.006, r * 0.66 + 0.006, d)
    centre = 1 - smooth(r * 0.33 - 0.006, r * 0.33 + 0.006, d)
    c_out, c_mid, c_in = colours
    colour = c_out * (outer - inner)[..., None] + c_mid * (inner - centre)[..., None] + c_in * centre[..., None]
    return colour, outer


def star(u, v, r, ring):
    """Five-pointed star (point up +v): returns (star, ring) masks; ring is a border of ring * r."""
    pts = []
    for k in range(10):
        ang = math.pi / 2 + k * math.pi / 5
        rad = r if k % 2 == 0 else r * 0.40
        pts.append((rad * math.cos(ang), rad * math.sin(ang)))
    d = paint.sd_polygon(u, v, pts)
    s = 1 - smooth(-0.006, 0.006, d)
    border = (1 - smooth(r * ring - 0.006, r * ring + 0.006, d)) * (1 - s)
    return s, border


def star_and_bar(u, v, r, low):
    """US national insignia: white star on a blue disc, white bars with a red stripe, blue outline. Low
    visibility: the outline only, in dark grey."""
    if low:
        m = paint.star_and_bar(u, v, r)
        return np.broadcast_to(LOWVIS[0], u.shape + (3,)) * 1.0, m
    blue, white, red = srgb(30, 40, 90), srgb(226, 226, 222), srgb(170, 34, 40)
    pts = []
    for k in range(10):
        ang = math.pi / 2 + k * math.pi / 5
        rad = r if k % 2 == 0 else r * 0.382
        pts.append((rad * math.cos(ang), rad * math.sin(ang)))
    star_m = 1 - smooth(-0.004, 0.004, paint.sd_polygon(u, v, pts))
    disc = 1 - smooth(r - 0.004, r + 0.004, np.hypot(u, v))
    top, bottom = r * 0.309, r * 0.309 - r * 0.5
    d_bars = paint.sd_polygon(u, v, [(-2.0 * r, bottom), (2.0 * r, bottom), (2.0 * r, top), (-2.0 * r, top)])
    w = r * 0.07
    outer = np.maximum(disc, 1 - smooth(-0.004, 0.004, d_bars - w))
    bars = (1 - smooth(-0.004, 0.004, d_bars)) * (1 - disc)
    stripe = bars * (np.abs(v - (top + bottom) / 2) < r * 0.08)
    colour = blue * outer[..., None]
    colour = colour * (1 - bars[..., None]) + white * bars[..., None]
    colour = colour * (1 - stripe[..., None]) + red * stripe[..., None]
    colour = colour * (1 - star_m[..., None]) + white * star_m[..., None]
    return colour, outer


def insignia(L, u, v, r, scheme, low):
    """An insignia centred at (u, v) (metres on the surface): colour and mask."""
    kind = L.get("insignia", "roundel")
    if kind == "roundel":
        colours = LOWVIS if low else L["roundel_colours"]
        return roundel(np.hypot(u, v), r, colours)
    if kind == "star_ru":
        s, b = star(u, v, r, 0.10)
        red, white = (LOWVIS[0], LOWVIS[1]) if low else (srgb(170, 30, 30), srgb(225, 225, 220))
        colour = red * s[..., None] + white * b[..., None]
        return colour, np.clip(s + b, 0, 1)
    if kind == "star_us":
        return star_and_bar(u, v, r, low)
    return np.zeros(u.shape + (3,), np.float32), np.zeros(u.shape, np.float32)


def paint_airframe(L, P, N, part, ids, ao, scheme):
    x, y, z = P[..., 0], P[..., 1], P[..., 2]
    nz = N[..., 2]
    side = np.abs(nz) < 0.6
    down = nz <= -0.6
    shape = x.shape
    on = paint.make_on(part, ids)
    body = on(*L["body"])
    fus = on("Fuselage")
    wing = on(*L["wings"])
    surf = on(*L["surfaces"])
    tail = on(*L.get("tail", []))
    fin, rudder = on(*L["fin"]), on(*L["rudder"])
    upper_only = on(*L.get("upper_only", [])) | fin | rudder
    Y = kit.Y
    xd = kit.REF_PITOT_XD + (kit.CG_FROM_PITOT - y) * kit.REF_PX_PER_M
    line = np.zeros(shape, np.float32)
    rivet = np.zeros(shape, np.float32)
    w = 0.0045

    for f in L["frames"]:
        d = y - Y(f)
        line = np.maximum(line, np.where(body, groove(d, w), 0))
        rivet = np.maximum(rivet, np.where(body, rivets(d, np.where(side, z, x), 0.05, 0.004, offset=0.018), 0))
    for zz, a, b in L.get("side_lines", []):
        m = body & side & (xd >= a) & (xd <= b)
        line = np.maximum(line, np.where(m, groove(z - zz, w), 0))
    for a, b, z0, z1 in L.get("side_panels", []):
        inside = body & side & (xd >= a) & (xd <= b) & (z >= z0) & (z <= z1)
        edge = np.minimum(np.minimum(np.abs(xd - a), np.abs(xd - b)) / kit.REF_PX_PER_M,
                          np.minimum(np.abs(z - z0), np.abs(z - z1)))
        line = np.maximum(line, np.where(inside, groove(edge, w), 0))
    le_fn, te_fn = L["wing"]
    xa = np.abs(x)
    le, te = le_fn(xa), te_fn(xa)
    chord = np.maximum(le - te, 1e-3)
    fw = (le - y) / chord
    for sf in L.get("spars", (0.15, 0.5, 0.75)):
        d = (fw - sf) * chord
        line = np.maximum(line, np.where(wing, groove(d, w), 0))
        rivet = np.maximum(rivet, np.where(wing, rivets(d, x, 0.05, 0.004, offset=0.016), 0))
    r0, r1, step = L.get("ribs", (1.0, 4.0, 0.6))
    for rx in np.arange(r0, r1, step):
        line = np.maximum(line, np.where(wing & (fw > 0.1), groove(xa - rx, w), 0))
    for rx in np.arange(r0, r1, step / 2):
        line = np.maximum(line, np.where(surf | tail, groove(xa - rx, w * 0.8), 0))
    for rz in L.get("fin_lines", []):
        line = np.maximum(line, np.where(fin, groove(z - rz, w), 0))

    # Colour: camouflage or two tones over the underside colour
    colour = np.broadcast_to(scheme.get("base", scheme["upper"]), shape + (3,)).copy()
    flat = wing | surf | tail
    under = np.where(flat, (nz < 0).astype(np.float32), smooth(L.get("under_z", (-0.15, -0.35))[0], L.get("under_z", (-0.15, -0.35))[1], z))
    under = np.where(upper_only, 0.0, under)
    if "camo" in scheme:
        camo = paint.camouflage(P, scheme)
        colour = camo * (1 - under[..., None]) + scheme["underside"] * under[..., None]
    elif not scheme.get("metal"):
        colour = scheme["lower"] * under[..., None] + scheme["upper"] * (1 - under[..., None])
    frames = L["frames"]
    fidx = np.searchsorted(-np.array([Y(f) for f in frames]), -y)
    cell = np.where(body, fidx * 8 + (x > 0), (np.floor(xa / 0.6) * 4 + (x > 0) * 97).astype(np.int64))
    colour *= cell_tone(cell.astype(np.int64), 3, 0.06 if scheme.get("metal") else 0.025)[..., None]

    radome = fus & (xd < L["radome"])
    dark = on(*L.get("dark", []))
    colour = np.where((radome | dark)[..., None], scheme["radome"], colour)
    ducts = on(*L.get("ducts", []))  # recessed intake mouths
    colour = np.where(ducts[..., None], DUCT, colour)
    a0, a1, h0, h1 = L["antiglare"]
    ag_half = np.clip((xd - a0) / max(a1 - a0, 1), 0, 1) * (h1 - h0) + h0
    antiglare = fus & (xd >= a0) & (xd <= a1) & (nz > 0.4) & (xa < ag_half)
    colour = np.where(antiglare[..., None], scheme["antiglare"], colour)
    lip_parts, lip_xd = L.get("lip", ([], 0))
    lip = on(*lip_parts) & (xd < lip_xd)
    duct_parts, duct_xd = L.get("duct", ([], 0))
    duct = on(*duct_parts) & (N[..., 1] < -0.2) & (xd > duct_xd)
    colour = np.where(lip[..., None], METAL, colour)
    colour = np.where(duct[..., None], DUCT, colour)
    h0_, h1_ = L["hot"]
    hot = fus & (xd > h0_)
    heat = smooth(h0_, h1_, xd)[..., None]
    colour = np.where(hot[..., None], METAL * (1 - heat) + HOT_METAL * heat, colour)

    # Markings
    low = scheme.get("markings") == "lowvis"
    marks = np.zeros(shape, bool)
    if L.get("insignia") and scheme.get("markings") != "none":
        if L.get("roundel_fuselage"):
            st, sz, sr, parts = L["roundel_fuselage"]
            c1, m1 = insignia(L, -np.sign(N[..., 0]) * (y - Y(st)), z - sz, sr, scheme, low)
            m1 = np.where(on(*parts) & side, m1, 0)
            colour = colour * (1 - m1[..., None]) + c1 * m1[..., None]
            marks |= m1 > 0.5
        if L.get("roundel_wing"):
            ix, wr, frac = L["roundel_wing"]
            y0 = le_fn(ix) - frac * (le_fn(ix) - te_fn(ix))
            c2, m2 = insignia(L, xa - ix, y - y0, wr, scheme, low)
            m2 = np.where(wing, m2, 0)
            colour = colour * (1 - m2[..., None]) + c2 * m2[..., None]
            marks |= m2 > 0.5
    if L.get("fin_flash") and not low and scheme.get("markings") != "none":
        parts, top, lead, length = L["fin_flash"]
        rf = on(*parts) & (z < top)
        t = np.clip((Y(lead) - y) / length, 0, 1)
        band = np.where(t < 1 / 3, 0, np.where(t < 2 / 3, 1, 2))
        for i, c in enumerate(L.get("flash_colours", L.get("roundel_colours"))[::-1]):
            colour = np.where((rf & (band == i))[..., None], c, colour)
        marks |= rf

    # Soot and grime
    aft = smooth(Y(h0_ - (h1_ - h0_)), Y(h1_), y)
    streaks = fbm(P, 3.0, 3, seed=11, stretch=(4.0, 0.25, 4.0))
    soot = np.where(fus, aft * (0.25 + 0.45 * streaks) * np.clip(0.6 - z, 0.2, 1.0), 0)
    if L.get("gun"):
        gx, gw, g0, g1 = L["gun"]
        gun = fus & (np.abs(xa - gx) < gw) & (y < Y(g0)) & (y > Y(g1)) & (z < 0)
        soot = np.maximum(soot, np.where(gun, 0.55 * smooth(Y(g0), Y(g1), y), 0))
    colour = colour * (1 - soot[..., None]) + SOOT * soot[..., None]
    grime = fbm(P, 2.2, 4, seed=21, stretch=(3.0, 0.3, 3.0))
    grime = np.clip((grime - 0.52) * 2.0, 0, 1) * (0.05 + 0.05 * down)
    colour *= (1 - grime - 0.3 * line)[..., None]
    colour = livery_paint.lines(scheme, colour, line)
    well = fus & cockpit_kit.well_mask(P)  # the cockpit well, seen through the canopy: cockpit-dark
    colour = np.where(well[..., None], WELL, colour)
    colour *= (0.55 + 0.45 * np.power(np.clip(ao, 0, 1), 0.8))[..., None]

    metal_paint = bool(scheme.get("metal"))
    rough0, metal0 = livery_paint.base(scheme, metal_paint)
    rough = rough0 + 0.08 * (fbm(P, 4.0, 3, seed=41) - 0.5) + 0.12 * grime + 0.12 * line
    metal = np.full(shape, metal0, np.float32)
    if scheme.get("underside_metal"):  # aluminium lacquer: a little sheen
        metal = np.maximum(metal, 0.35 * under)
        rough = np.where(under > 0.5, 0.45, rough)
    metal = np.where(marks | radome | dark | antiglare | duct | ducts | well, 0.0, metal)
    rough = np.where(ducts, 0.9, rough)
    rough = np.where(marks, 0.5, rough)
    rough = np.where(antiglare | well, 0.85, rough)
    metal = np.where(lip | hot, 0.85, metal)
    rough = np.where(hot, 0.45, rough)
    rough = np.maximum(rough, soot * 0.85)
    keep = radome | dark | ducts | antiglare | lip | duct | hot | well
    tails = [on(n) for n in L.get("tail", [])]
    colour, rough, metal = livery_paint.trim(scheme, P, N, ao, line, colour, rough, metal, fus, wing | surf, le - y, tails,
                                             fin | rudder, keep, Y(L["radome"]) - 0.3, Y(h0_) + 0.2)
    height = -line - 0.35 * rivet
    return colour, np.clip(rough, 0.05, 1), metal, height


def paint_details(L, P, N, part, ids, ao, scheme):
    x, y, z = P[..., 0], P[..., 1], P[..., 2]
    shape = x.shape
    on = paint.make_on(part, ids)
    colour = np.broadcast_to(scheme["lower"], shape + (3,)).copy()
    rough = np.full(shape, 0.55, np.float32)
    metal = np.zeros(shape, np.float32)
    height = np.zeros(shape, np.float32)

    noz = on("Nozzle", "NozzleL", "NozzleR")
    centres = L["nozzles"]
    cx = np.full(shape, centres[0][0], np.float32)
    cz = np.full(shape, centres[0][1], np.float32)
    for nx, nzc in centres[1:]:
        closer = np.abs(x - nx) < np.abs(x - cx)
        cx, cz = np.where(closer, nx, cx), np.where(closer, nzc, cz)
    radial = np.stack([x - cx, np.zeros_like(x), z - cz], axis=-1)
    inner = (radial * N).sum(-1) < 0
    y0, y1 = L["nozzle_y"]
    t = np.clip((y0 - y) / (y0 - y1), 0, 1)
    tint = paint.METAL * (1 - t[..., None] * 0.45) + srgb(84, 78, 118) * (t[..., None] * 0.45)
    colour = np.where((noz & ~inner)[..., None], tint, colour)
    colour = np.where((noz & inner)[..., None], SOOT, colour)
    metal = np.where(noz, np.where(inner, 0.3, 0.9), metal)
    rough = np.where(noz, np.where(inner, 0.85, 0.35), rough)
    petal = np.mod(np.arctan2(z - cz, x - cx) * L.get("petals", 18) / (2 * math.pi), 1.0)
    height = np.where(noz & ~inner, -groove(np.minimum(petal, 1 - petal), 0.06), height)

    ab = on("Afterburner", "AfterburnerL", "AfterburnerR")
    colour = np.where(ab[..., None], srgb(46, 40, 36), colour)
    metal = np.where(ab, 0.7, metal)
    seat = on("EjectionSeat")
    colour = np.where(seat[..., None], srgb(40, 42, 44), colour)
    pitot = on("Pitot")
    if L.get("pitot") == "stripes":
        colour = np.where(pitot[..., None], np.where((np.mod(y * 4, 1.0) < 0.5)[..., None], srgb(170, 30, 30), srgb(225, 225, 220)), colour)
    else:
        colour = np.where(pitot[..., None], METAL, colour)
        metal = np.where(pitot, 0.8, metal)
    rails = on("WingtipRailL", "WingtipRailR")
    colour = np.where(rails[..., None], scheme["lower"] * 0.8, colour)
    struts = on("NoseGearStrut", "MainGearStrutL", "MainGearStrutR")
    colour = np.where(struts[..., None], srgb(190, 194, 190), colour)
    metal = np.where(struts, 0.6, metal)
    wheels = on("NoseGearWheel", "MainGearWheelL", "MainGearWheelR")
    colour = np.where(wheels[..., None], srgb(28, 28, 28), colour)
    rough = np.where(wheels, 0.9, rough)
    colour *= (0.6 + 0.4 * np.power(np.clip(ao, 0, 1), 0.8))[..., None]
    return colour, np.clip(rough, 0.05, 1), metal, height


def main(L, schemes, default_skin):
    import argparse

    import bpy

    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", required=True)
    parser.add_argument("--skin", default=default_skin)
    parser.add_argument("--preview", action="store_true")
    args = parser.parse_args(argv)
    os.makedirs(args.out, exist_ok=True)
    scheme = livery_paint.with_liveries(schemes)[args.skin]

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
        colour, rough, metal, height = fn(L, P, N, part, ids, ao, scheme)
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
