"""
Afterburner: the tiling PBR textures for the strait bridge (bridge_generate.py). Four sets, each a seamless
square tile with Color, Roughness, Metalness and Normal maps (OpenGL normals, as Roblox expects):

  Steel     6 m tile    off-white paint (the Severn Bridge's colour): welded plate seams with bolt rows, paint
                        mottling, grime streaks running down, and small rust spots along the seams
  Concrete  8 m tile    board-marked concrete: lift lines, formwork tie holes, rain streaks, darker patches
  Road      22.86 x 24 m  the carriageway: asphalt with aggregate, wheel-path polish, the central reservation,
                        UK motorway markings (solid edge lines, 3 m lane dashes every 12 m) and road studs
  Cable     1.5 m tile  painted cable with the helical wrapping wire

Positions in the maps are metres on the tile, and every noise is periodic over the tile, so the edges meet.
Vertical faces map their height to v, so streaks run down them.

  blender -b --python tools/blender/bridge_textures.py -- --out <dir> [--skin Severn] [--size 1024]
"""

import argparse
import os
import sys

import numpy as np

NAME = "SevernBridge"


def srgb(r, g, b):
    c = np.array([r, g, b], dtype=np.float32) / 255.0
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def to_srgb(c):
    c = np.clip(c, 0, 1)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * c ** (1 / 2.4) - 0.055)


SKINS = {
    # The Severn Bridge as painted: off-white steel, weathered grey concrete
    "Severn": {
        "steel": srgb(216, 212, 200),
        "grime": srgb(120, 116, 104),
        "rust": srgb(132, 78, 46),
        "concrete": srgb(150, 146, 136),
        "concrete_dark": srgb(96, 94, 86),
        "asphalt": srgb(56, 56, 58),
        "line": srgb(226, 226, 220),
        "cable": srgb(200, 198, 188),
    },
    # Weathered: grey paint gone dull, darker concrete
    "Weathered": {
        "steel": srgb(170, 172, 170),
        "grime": srgb(84, 82, 76),
        "rust": srgb(120, 70, 42),
        "concrete": srgb(122, 120, 112),
        "concrete_dark": srgb(74, 72, 66),
        "asphalt": srgb(50, 50, 52),
        "line": srgb(206, 206, 198),
        "cable": srgb(150, 152, 150),
    },
}


# ---------------------------------------------------------------------------------------------------
# Periodic noise on a tile (positions in metres)
# ---------------------------------------------------------------------------------------------------


def _lattice(cells_u, cells_v, seed):
    rng = np.random.default_rng(seed)
    return rng.random((cells_v, cells_u), dtype=np.float32)


def vnoise(u, v, tile_u, tile_v, cell, seed):
    """Value noise, periodic over the tile: cell is the feature size in metres (rounded to divide the tile)."""
    cu, cv = max(1, round(tile_u / cell)), max(1, round(tile_v / cell))
    g = _lattice(cu, cv, seed)
    x, y = u / tile_u * cu, v / tile_v * cv
    x0, y0 = np.floor(x).astype(np.int64), np.floor(y).astype(np.int64)
    fx, fy = x - x0, y - y0
    fx, fy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
    x0, y0 = x0 % cu, y0 % cv
    x1, y1 = (x0 + 1) % cu, (y0 + 1) % cv
    a, b = g[y0, x0], g[y0, x1]
    c, d = g[y1, x0], g[y1, x1]
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy


def fbm(u, v, tile_u, tile_v, cell, octaves, seed):
    total, amp, norm = 0.0, 1.0, 0.0
    for o in range(octaves):
        total = total + vnoise(u, v, tile_u, tile_v, cell / 2 ** o, seed + 17 * o) * amp
        norm += amp
        amp *= 0.5
    return total / norm


def streaks(u, v, tile_u, tile_v, seed, width=0.25):
    """Vertical grime streaks: noise stretched along v (down a face)."""
    cu = max(1, round(tile_u / width))
    g = _lattice(cu, 3, seed)
    x = u / tile_u * cu
    x0 = np.floor(x).astype(np.int64) % cu
    x1 = (x0 + 1) % cu
    f = x - np.floor(x)
    f = f * f * (3 - 2 * f)
    col = g[0, x0] * (1 - f) + g[0, x1] * f
    along = vnoise(u * 0.25, v, tile_u, tile_v, tile_v / 2, seed + 5)
    return np.clip((col - 0.55) * 3.0, 0, 1) * (0.5 + 0.5 * along)


def line(d, width):
    """1 on a line of the given width centred on d = 0, soft-edged."""
    return np.clip(1 - np.abs(d) / (width / 2), 0, 1) ** 0.6


def periodic_distance(x, period):
    return (x + period / 2) % period - period / 2


def normal_from_height(h, metres_per_px, strength=1.0):
    gy, gx = np.gradient(np.pad(h, 1, mode="wrap"))
    gx, gy = gx[1:-1, 1:-1] / metres_per_px * strength, gy[1:-1, 1:-1] / metres_per_px * strength
    n = np.stack([-gx, gy, np.ones_like(h)], axis=-1)  # image rows run down; OpenGL green is up
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return n * 0.5 + 0.5


# ---------------------------------------------------------------------------------------------------
# The four sets: each returns colour (linear), roughness, metalness, height (metres)
# ---------------------------------------------------------------------------------------------------


def steel(u, v, T, s):
    seam_u = line(periodic_distance(u, T / 2), 0.012)
    seam_v = line(periodic_distance(v, T / 2), 0.012)
    seams = np.maximum(seam_u, seam_v)
    # bolt rows either side of the seams, every 15 cm
    bolts_u = (line(periodic_distance(u - 0.06, T / 2), 0.03) + line(periodic_distance(u + 0.06, T / 2), 0.03)) * line(periodic_distance(v, 0.15), 0.03)
    bolts_v = (line(periodic_distance(v - 0.06, T / 2), 0.03) + line(periodic_distance(v + 0.06, T / 2), 0.03)) * line(periodic_distance(u, 0.15), 0.03)
    bolts = np.clip(bolts_u + bolts_v, 0, 1)
    mottle = fbm(u, v, T, T, 1.5, 4, 11)
    grime = streaks(u, v, T, T, 21) * 0.30 + np.clip(fbm(u, v, T, T, 2.0, 3, 31) - 0.55, 0, 1) * 0.8
    rust_mask = np.clip((fbm(u, v, T, T, 0.4, 3, 41) - 0.72) * 6, 0, 1) * np.clip(seams * 2 + bolts, 0, 1)
    rust_mask = np.maximum(rust_mask, np.clip((fbm(u, v, T, T, 0.25, 3, 43) - 0.83) * 8, 0, 1))
    c = s["steel"] * (0.94 + 0.10 * mottle)[..., None]
    c = c * (1 - 0.35 * grime[..., None]) + s["grime"] * (0.35 * grime[..., None])
    c = c * (1 - 0.45 * seams[..., None])
    c = c * (1 - 0.8 * rust_mask[..., None]) + s["rust"] * (0.8 * rust_mask[..., None])
    rough = 0.42 + 0.18 * grime + 0.3 * rust_mask + 0.05 * mottle
    metal = np.zeros_like(u)
    height = -0.0015 * seams + 0.004 * bolts + 0.0004 * mottle
    return c, rough, metal, height


def concrete(u, v, T, s):
    lifts = line(periodic_distance(v, 1.6), 0.02)
    boards = line(periodic_distance(v, 0.2), 0.008) * 0.35
    ties = line(periodic_distance(u - 0.5, 1.0), 0.05) * line(periodic_distance(v - 0.8, 1.6), 0.05)
    blotch = fbm(u, v, T, T, 2.0, 4, 51)
    fine = fbm(u, v, T, T, 0.12, 3, 53)
    rain = streaks(u, v, T, T, 61, 0.35)
    patches = np.clip((fbm(u, v, T, T, 3.0, 3, 71) - 0.5) * 2.5, 0, 1)
    c = s["concrete"] * (0.86 + 0.22 * blotch + 0.08 * fine)[..., None]
    dark = np.clip(0.28 * rain + 0.35 * patches + 0.5 * lifts + 0.7 * ties, 0, 1)
    c = c * (1 - dark[..., None]) + s["concrete_dark"] * dark[..., None]
    rough = 0.82 + 0.1 * fine
    metal = np.zeros_like(u)
    height = -0.003 * lifts - 0.0015 * boards - 0.01 * ties + 0.0015 * fine
    return c, rough, metal, height


def road(u, v, W, L, s):
    """u: metres across the carriageway from its left edge (0..W); v: metres along it."""
    x = u - W / 2  # from the centre line
    ax = np.abs(x)
    aggregate = fbm(u, v, W, L, 0.03, 2, 81)
    patchy = fbm(u, v, W, L, 3.0, 3, 83)
    c = s["asphalt"] * (0.82 + 0.25 * aggregate + 0.12 * patchy)[..., None]
    # Wheel paths: polished and slightly lighter, two per lane
    lanes = (2.3, 5.95)  # lane centres from the reservation edge line
    paths = np.zeros_like(u)
    for lc in lanes:
        for off in (-0.9, 0.9):
            paths += np.clip(1 - np.abs(ax - (1.5 + lc + off)) / 0.45, 0, 1)
    c = c * (1 + 0.10 * paths[..., None])
    # Central reservation (concrete-grey surfacing under the barrier)
    reservation = ax < 0.8
    c = np.where(reservation[..., None], s["concrete"] * (0.8 + 0.2 * aggregate)[..., None], c)
    # Markings: solid lines by the reservation and at the outer edge, a dashed lane line between
    mark = line(ax - 1.0, 0.20) + line(ax - (W / 2 - 0.9), 0.20)
    dash = (periodic_distance(v, 12.0) + 6.0) < 3.0
    mark += line(ax - 4.65, 0.15) * dash
    # Road studs (cat's eyes) every 12 m on the lane line and every 24 m... here every 6 m on the edge lines
    studs = line(periodic_distance(v - 7.5, 12.0), 0.12) * line(ax - 4.65, 0.12)
    mark = np.clip(mark, 0, 1)
    worn = 0.75 + 0.25 * fbm(u, v, W, L, 0.5, 2, 91)
    c = c * (1 - (mark * worn)[..., None]) + s["line"] * (mark * worn)[..., None]
    c = c * (1 - studs[..., None]) + srgb(236, 230, 210) * studs[..., None]
    rough = np.where(reservation, 0.85, 0.88 - 0.18 * paths) - 0.25 * mark
    metal = np.zeros_like(u)
    height = 0.0015 * aggregate + 0.001 * mark + 0.008 * studs
    return c, rough, metal, height


def cable(u, v, Lc, s):
    """u: 0..1 round the cable; v: metres along it (tile Lc). The wrapping wire runs as a fine helix."""
    turns = 40  # wraps per tile length
    phase = (v / Lc * turns + u) % 1.0
    wrap = 0.5 + 0.5 * np.cos(phase * 2 * np.pi)
    grime = fbm(u * Lc, v, Lc, Lc, 0.5, 3, 101)
    c = s["cable"] * (0.86 + 0.08 * wrap + 0.08 * grime)[..., None]
    rough = 0.45 + 0.15 * grime
    metal = np.full_like(u, 0.15)
    height = 0.0012 * wrap
    return c, rough, metal, height


def save_png(path, data, colorspace):
    import bpy

    h, w = data.shape[:2]
    rgb = data if data.ndim == 3 else np.repeat(data[..., None], 3, axis=-1)
    rgba = np.concatenate([rgb[..., :3], np.ones((h, w, 1), np.float32)], axis=-1)
    img = bpy.data.images.new(os.path.basename(path), w, h, alpha=False, float_buffer=False)
    img.colorspace_settings.name = colorspace
    img.pixels.foreach_set(np.clip(rgba[::-1], 0, 1).astype(np.float32).ravel())  # Blender rows run upwards
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(img)


def write_set(out, skin, set_name, colour, rough, metal, height, metres_per_px, strength=1.0):
    base = os.path.join(out, f"{NAME}_{skin}_{set_name}")
    save_png(f"{base}_Color.png", to_srgb(colour).astype(np.float32), "sRGB")
    save_png(f"{base}_Roughness.png", np.clip(rough, 0, 1).astype(np.float32), "Non-Color")
    save_png(f"{base}_Metalness.png", np.clip(metal, 0, 1).astype(np.float32), "Non-Color")
    save_png(f"{base}_Normal.png", normal_from_height(height, metres_per_px, strength).astype(np.float32), "Non-Color")
    print("wrote", base)


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", required=True)
    parser.add_argument("--skin", default="Severn")
    parser.add_argument("--size", type=int, default=1024)
    args = parser.parse_args(argv)
    os.makedirs(args.out, exist_ok=True)
    s, n = SKINS[args.skin], args.size

    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import bridge_generate as bg

    px = (np.arange(n, dtype=np.float32) + 0.5) / n
    U, V = np.meshgrid(px, px)  # V runs down the image; v = 0 at the top row is fine for a tile

    T = bg.TILE["Steel"]
    write_set(args.out, args.skin, "Steel", *steel(U * T, V * T, T, s), T / n, 3.0)
    T = bg.TILE["Concrete"]
    write_set(args.out, args.skin, "Concrete", *concrete(U * T, V * T, T, s), T / n, 3.0)
    W, L = 2 * bg.ROAD_HALF, bg.ROAD_TILE
    write_set(args.out, args.skin, "Road", *road(U * W, V * L, W, L, s), L / n, 2.0)
    Lc = bg.CABLE_TILE
    write_set(args.out, args.skin, "Cable", *cable(U, V * Lc, Lc, s), Lc / n, 1.0)


if __name__ == "__main__":
    main()
