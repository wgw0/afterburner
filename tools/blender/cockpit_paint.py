"""
Afterburner: paints a cockpit interior, by the same method as the skins (f5e_paint.py, whose baking and
output functions this uses): bake where every texel is, then compute the maps in numpy from the
cockpit's layout (cockpit_kit.py and the jet's COCKPIT spec).

  blender -b <out>/<Id>_cockpit.blend --python tools/blender/cockpit_paint.py -- --airframe <Id> \
      --out <absolute dir>

One texture set, Cockpit, 1024 px: <Id>_Cockpit_<Map>.png (Color, Normal, Roughness, Metalness).
Painted: instrument faces with their scales and needles (the live ones are left as plain dark faces,
since the game draws their gauges over them), the attitude ball and compass card, caution-light panel,
placards, panel seams and screws; console panels with switches and knobs; the tub's ribs and the
non-slip floor; the flat-black glareshield; mirrors; grime and ambient occlusion. The HUD glass stays
plain glass.
"""

import argparse
import importlib
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import cockpit_generate  # noqa: E402

srgb = None  # set in main (from f5e_paint, which imports the kit)

# Colours by era and origin, as they look (sRGB)
PALETTES = {
    # US: dark gull grey tub and consoles (FS 36231), black panels and glareshield
    "US": {"tub": (92, 98, 102), "panel": (40, 42, 44), "console": (44, 46, 48), "coaming": (26, 26, 28),
           "frame": (70, 74, 78), "face": (14, 14, 15), "mark": (226, 226, 216), "label": (200, 200, 190)},
    # Soviet and Russian: the turquoise cockpit (MiG-21bis onwards)
    "Soviet": {"tub": (74, 148, 150), "panel": (66, 136, 140), "console": (66, 136, 140), "coaming": (28, 30, 30),
               "frame": (74, 148, 150), "face": (16, 16, 16), "mark": (226, 226, 216), "label": (220, 220, 210)},
    # French: dark grey and black
    "French": {"tub": (64, 66, 70), "panel": (36, 37, 40), "console": (40, 41, 44), "coaming": (24, 24, 26),
               "frame": (58, 60, 64), "face": (14, 14, 15), "mark": (226, 226, 216), "label": (200, 200, 190)},
    # Modern glass cockpits: charcoal everything
    "Modern": {"tub": (58, 60, 63), "panel": (34, 35, 37), "console": (38, 39, 41), "coaming": (22, 22, 24),
               "frame": (52, 54, 57), "face": (8, 9, 10), "mark": (210, 210, 200), "label": (190, 190, 180)},
}
SCOPE_GREEN = (14, 34, 20)
LIGHTS = [(120, 92, 30), (40, 92, 40), (110, 40, 34)]  # amber, green and red caution lights, unlit


def col(rgb):
    return srgb(*rgb)


def blend(colour, mask, value):
    m = np.clip(mask, 0, 1)[..., None]
    return colour * (1 - m) + value * m


def hash01(i):
    return ((i * 2654435761) % 4294967296) / 4294967296.0


def paint_panel(P, on_panel, pal, ck, colour, rough, metal, height):
    """Instruments in the panel's own (u, v) coordinates."""
    top, down, _, _ = ck.panel_frame()
    rel = P - np.array(top, np.float32)
    u = rel[..., 0]
    v = (rel * np.array(down, np.float32)).sum(-1)
    face, mark, label = col(pal["face"]), col(pal["mark"]), col(pal["label"])
    smooth, groove = paint.smooth, paint.groove
    for k, inst in enumerate(ck.spec()["instruments"]):
        du, dv = u - inst["u"], v - inst["v"]
        kind, size = inst["kind"], inst["size"]
        r = size / 2
        live = bool(inst.get("live"))
        if kind == "Dial":
            d = np.hypot(du, dv)
            inside = on_panel & (d < r + 0.0005)
            colour = np.where(inside[..., None], face, colour)
            rough = np.where(inside, 0.22, rough)
            ang = np.arctan2(du, -dv)  # 0 at the top, clockwise
            if not live:
                kind_face = inst.get("face")
                if kind_face == "attitude":  # sky over ground, horizon bar, aircraft symbol
                    sky = inside & (dv < 0.004 * np.sin(du * 40))
                    colour = np.where(sky[..., None], col((150, 152, 150)), colour)
                    horizon = inside & (np.abs(dv) < 0.0015)
                    symbol = inside & (np.abs(dv - 0.003) < 0.0015) & (np.abs(du) > 0.012) & (np.abs(du) < 0.03)
                    colour = np.where((horizon | symbol)[..., None], mark, colour)
                    colour = np.where((symbol & (np.abs(du) > 0))[..., None], col((230, 150, 40)), colour)
                elif kind_face == "compass":  # compass card: fine ticks all round, a lubber line
                    ring = inside & (d > 0.70 * r) & (d < 0.92 * r)
                    tick = np.mod(ang * 36 / (2 * math.pi), 1.0) < 0.12
                    colour = np.where((ring & tick)[..., None], mark, colour)
                    lubber = inside & (np.abs(du) < 0.0012) & (dv < -0.4 * r) & (dv > -0.95 * r)
                    colour = np.where(lubber[..., None], mark, colour)
                    plane = inside & (((np.abs(du) < 0.0015) & (np.abs(dv) < 0.25 * r))
                                      | ((np.abs(dv + 0.05 * r) < 0.0015) & (np.abs(du) < 0.2 * r)))
                    colour = np.where(plane[..., None], col((230, 150, 40)), colour)
                else:  # a scale round 270°, the major marks longer, and a needle
                    rel_ang = np.mod(ang + 0.75 * math.pi, 2 * math.pi)  # 0 at the scale's start
                    on_scale = rel_ang < 1.5 * math.pi
                    major = np.mod(rel_ang * 10 / (1.5 * math.pi) + 0.03, 1.0) < 0.06
                    minor = np.mod(rel_ang * 50 / (1.5 * math.pi) + 0.08, 1.0) < 0.16
                    ticks = inside & on_scale & (((d > 0.68 * r) & major) | ((d > 0.80 * r) & minor)) & (d < 0.92 * r)
                    colour = np.where(ticks[..., None], mark, colour)
                    a0 = -0.75 * math.pi + 1.5 * math.pi * (0.15 + 0.6 * hash01(k + 7))
                    nx, ny = math.sin(a0), -math.cos(a0)
                    along = du * nx + dv * ny
                    across = np.abs(du * ny - dv * nx)
                    needle = inside & (along > -0.08 * r) & (along < 0.72 * r) & (across < 0.004 * (1 - along / r) + 0.0008)
                    colour = np.where(needle[..., None], mark, colour)
            # Bezel: the ring's top and screws at the corners
            bezel = on_panel & (d >= r + 0.0005) & (d < r + 0.009)
            colour = np.where(bezel[..., None], col((30, 31, 33)), colour)
            rough = np.where(bezel, 0.5, rough)
            for sx in (-1, 1):
                for sy in (-1, 1):
                    s = np.hypot(du - sx * 0.62 * size, dv - sy * 0.62 * size)
                    screw = on_panel & (s < 0.0035)
                    colour = np.where(screw[..., None], col((70, 72, 74)), colour)
                    height = np.where(screw, height + 0.6 * (1 - smooth(0.0025, 0.0035, s)), height)
                    metal = np.where(screw, 0.6, metal)
        elif kind in ("Scope", "MFD"):
            h = size / 2
            inside = on_panel & (np.abs(du) < h) & (np.abs(dv) < h)
            screen = col(SCOPE_GREEN) if kind == "Scope" else col((10, 12, 14))
            colour = np.where(inside[..., None], screen, colour)
            rough = np.where(inside, 0.12, rough)
            if kind == "Scope" and not live:
                grid = inside & ((np.abs(np.mod(du + h, size / 4) - size / 8) > size / 8 - 0.0008)
                                 | (np.abs(np.mod(dv + h, size / 4) - size / 8) > size / 8 - 0.0008))
                colour = np.where(grid[..., None], col((30, 70, 40)), colour)
            frame = on_panel & ~inside & (np.abs(du) < h + 0.013) & (np.abs(dv) < h + 0.013)
            colour = np.where(frame[..., None], col((30, 31, 33)), colour)
            if kind == "MFD":  # push buttons round the frame
                for edge in range(4):
                    t = np.where(edge % 2 == 0, du, dv)
                    n = np.where(edge % 2 == 0, dv, du) * (1 if edge < 2 else -1)
                    btn = frame & (np.abs(n - (h + 0.007)) < 0.004) & (np.abs(np.mod(t + h, size / 5) - size / 10) < 0.006)
                    colour = np.where(btn[..., None], col((70, 70, 66)), colour)
                    height = np.where(btn, height + 0.5, height)
        elif kind == "Lights":  # caution panel: a grid of unlit capsules
            w, hh = size / 2, size * 0.18
            inside = on_panel & (np.abs(du) < w) & (np.abs(dv) < hh)
            ci = np.floor((du + w) / (size / 4)).astype(np.int64)
            ri = np.floor((dv + hh) / (size * 0.12)).astype(np.int64)
            cell = (ci * 3 + ri) % 3
            for c_i, c in enumerate(LIGHTS):
                colour = np.where((inside & (cell == c_i))[..., None], col(c), colour)
            gap = inside & ((np.mod(du + w, size / 4) < 0.0015) | (np.mod(dv + hh, size * 0.12) < 0.0015))
            colour = np.where(gap[..., None], col((10, 10, 10)), colour)
            rough = np.where(inside, 0.2, rough)
        # Placard under the instrument
        ext = r if kind == "Dial" else (size / 2 if kind != "Lights" else size * 0.18)
        plac = on_panel & (np.abs(du) < 0.3 * size) & (np.abs(dv - (ext + 0.016)) < 0.003)
        colour = np.where(plac[..., None], label, colour)
        rough = np.where(plac, 0.5, rough)
    # Panel module seams: vertical lines between the instrument columns, and one across
    hw = ck.panel_half_width()
    for x in (-0.205, 0.205):
        if abs(x) < hw - 0.02:
            height = np.where(on_panel, height - groove(u - x, 0.0012), height)
    height = np.where(on_panel, height - groove(v - 0.255, 0.0012), height)
    return colour, rough, metal, height


def paint_cockpit(P, N, part, ids, ao, pal, ck):
    x, y, z = P[..., 0], P[..., 1], P[..., 2]
    nz = N[..., 2]
    shape = x.shape
    on = paint.make_on(part, ids)
    smooth, groove, fbm = paint.smooth, paint.groove, paint.fbm
    colour = np.broadcast_to(col(pal["tub"]), shape + (3,)).copy()
    rough = np.full(shape, 0.7, np.float32)
    metal = np.zeros(shape, np.float32)
    height = np.zeros(shape, np.float32)

    tub, panel, coaming = on("Tub"), on("Panel"), on("Coaming")
    consoles = on("ConsoleL", "ConsoleR")
    frame, sight, stick = on("CanopyFrameInner"), on("Gunsight"), on("Stick")
    w = ck.spec()["well"]
    e = ck.eye()

    # Tub: frames (ribs) down the walls, a darker non-slip floor
    wall = tub & (np.abs(N[..., 0]) > 0.7)
    for k in range(-12, 12):
        height = np.where(wall, height - groove(y - (e.y + 0.14 * k), 0.003) * 0.8, height)
    floor = tub & (nz > 0.7) & (z < w["floor"] + 0.05)
    grit = fbm(P, 60.0, 2, seed=5)
    colour = np.where(floor[..., None], col(pal["tub"]) * (0.55 + 0.1 * grit[..., None]), colour)
    rough = np.where(floor, 0.95, rough)

    # Panel base, then the instruments
    colour = np.where(panel[..., None], col(pal["panel"]), colour)
    rough = np.where(panel, 0.75, rough)
    colour, rough, metal, height = paint_panel(P, panel, pal, ck, colour, rough, metal, height)

    # Consoles: removable panels with switches, knobs and labels on top
    colour = np.where(consoles[..., None], col(pal["tub"]), colour)
    top = consoles & (nz > 0.7)
    colour = np.where(top[..., None], col(pal["console"]), colour)
    rough = np.where(top, 0.75, rough)
    row = np.floor((y - e.y) / 0.085).astype(np.int64)
    fy = np.mod(y - e.y, 0.085)
    seam = top & (fy < 0.0015)
    height = np.where(seam, height - 1.0, height)
    for slot in range(4):
        sx = np.sign(x) * (w["half_width"] - 0.03 - slot * 0.024)
        h_ = hash01(row * 7 + slot * 13 + (x > 0) * 101)
        d = np.hypot(x - sx, fy - 0.045)
        knob = top & (h_ > 0.55) & (d < 0.009)
        toggle = top & (h_ <= 0.55) & (h_ > 0.15) & (d < 0.0045)
        colour = np.where(knob[..., None], col((20, 20, 20)), colour)
        colour = np.where(toggle[..., None], col((190, 190, 186)), colour)
        height = np.where(knob | toggle, height + 1.0, height)
        metal = np.where(toggle, 0.7, metal)
        lab = top & (h_ > 0.15) & (np.abs(fy - 0.07) < 0.0018) & (np.abs(x - sx) < 0.009)
        colour = np.where(lab[..., None], col(pal["label"]), colour)

    # Throttle grip and stick grip: black
    grip = (consoles & (z > e.z + ck.spec()["consoles"]["top"] + 0.05)) | (stick & (z > e.z - 0.41))
    colour = np.where(grip[..., None], col((24, 24, 24)), colour)
    rough = np.where(grip, 0.6, rough)
    boot = stick & (z < w["floor"] + 0.1)
    colour = np.where(boot[..., None], col((22, 22, 22)), colour)
    rough = np.where(boot, 0.9, rough)
    shaft = stick & ~grip & ~boot
    colour = np.where(shaft[..., None], col((120, 122, 124)), colour)
    metal = np.where(shaft, 0.6, metal)

    # Glareshield: flat black; gunsight body dark
    colour = np.where(coaming[..., None], col(pal["coaming"]), colour)
    rough = np.where(coaming, 0.92, rough)
    colour = np.where(sight[..., None], col((34, 35, 37)), colour)
    rough = np.where(sight, 0.6, rough)

    # Canopy frames: the frame colour with rivets; mirrors glossy
    colour = np.where(frame[..., None], col(pal["frame"]), colour)
    riv = np.mod(np.arctan2(z - 0.4, x) * 40 / math.pi, 1.0)
    height = np.where(frame, height - 0.5 * (np.abs(riv - 0.5) < 0.06), height)
    bow_y = ck.kit.Y(ck.kit.CANOPY_FRAMES[0])
    mirror = frame & (N[..., 1] < -0.8) & (y < bow_y - ck.MIRROR_AFT + 0.01) & (y > bow_y - ck.MIRROR_AFT - 0.01)
    height = np.where(mirror, 0, height)
    colour = np.where(mirror[..., None], col((200, 205, 210)), colour)
    metal = np.where(mirror, 1.0, metal)
    rough = np.where(mirror, 0.08, rough)

    # Wear and occlusion
    grime = np.clip((fbm(P, 9.0, 4, seed=31) - 0.5) * 2.0, 0, 1)
    colour *= (1 - 0.12 * grime)[..., None]
    rough = rough + 0.06 * grime
    colour *= (0.45 + 0.55 * np.power(np.clip(ao, 0, 1), 0.9))[..., None]
    return colour, np.clip(rough, 0.05, 1), metal, height


def main():
    global srgb, paint
    import bpy

    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--airframe", required=True)
    parser.add_argument("--out", required=True)
    args = parser.parse_args(argv)
    os.makedirs(args.out, exist_ok=True)
    importlib.import_module(cockpit_generate.GENERATORS[args.airframe])
    import cockpit_kit as ck
    import f5e_paint

    paint = f5e_paint
    srgb = f5e_paint.srgb
    pal = PALETTES[ck.spec().get("palette", "US")]

    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.render.bake.margin_type = "EXTEND"
    world = scene.world or bpy.data.worlds.new("World")
    scene.world = world
    world.light_settings.distance = 0.12  # AO reach: cockpit-sized

    size = 1024
    maps, ids, objs = paint.bake_maps("Cockpit", size * paint.SUPERSAMPLE)
    P, N, part, ao, valid = maps["P"], maps["N"], maps["ID"], maps["AO"], maps["valid"]
    colour, rough, metal, height = paint_cockpit(P, N, part, ids, ao, pal, ck)
    colour = np.where(valid[..., None], colour, col(pal["tub"]))
    rough, metal, height = np.where(valid, rough, 0.7), np.where(valid, metal, 0), np.where(valid, height, 0)
    base = os.path.join(args.out, f"{args.airframe}_Cockpit")
    paint.save_png(base + "_Color.png", paint.to_srgb(paint.downsample(colour)), "sRGB")
    paint.save_png(base + "_Roughness.png", paint.downsample(rough), "Non-Color")
    paint.save_png(base + "_Metalness.png", paint.downsample(metal), "Non-Color")
    paint.bake_normal("Cockpit", objs, height.astype(np.float32), size, base + "_Normal.png")
    print(f"painted {args.airframe} cockpit: {size}px, {len(objs)} parts")


paint = None

if __name__ == "__main__":
    main()
