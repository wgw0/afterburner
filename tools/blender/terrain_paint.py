"""Seamless grass textures for the Strait's terrain (MAP-03), meant to be read from the air.

Plain Python (numpy + Pillow). Each texture is a patchwork of fields in different greens, each with
faint mowing stripes running its own way, dark hedgerow lines along the field edges, and a fine
grass grain. Everything wraps at the tile edge. Used as MaterialVariants on Grass and LeafyGrass with
a large StudsPerTile (tools/SkyBuilder.luau), so the patchwork shows from altitude where Roblox's
grass decoration (a few dozen studs) never does.

    python tools/blender/terrain_paint.py --out tools/blender/out/textures/terrain
"""

import argparse
import os

import numpy as np
from PIL import Image

N = 1024


def periodic_noise(n, cells, seed):
    """Smooth value noise that wraps every n pixels, with `cells` lattice cells across."""
    rng = np.random.default_rng(seed)
    grid = rng.random((cells, cells))
    t = np.arange(n) / n * cells
    i0 = np.floor(t).astype(int)
    f = t - i0
    f = f * f * (3 - 2 * f)
    i1 = (i0 + 1) % cells
    a = grid[i0][:, i0] * (1 - f)[None, :] + grid[i0][:, i1] * f[None, :]
    b = grid[i1][:, i0] * (1 - f)[None, :] + grid[i1][:, i1] * f[None, :]
    return a * (1 - f)[:, None] + b * f[:, None]


def fbm(n, cells, octaves, seed):
    total, amp, norm = 0, 1.0, 0.0
    for o in range(octaves):
        total = total + periodic_noise(n, cells * 2 ** o, seed + o) * amp
        norm += amp
        amp *= 0.5
    return total / norm


def fields(seed, greens):
    rng = np.random.default_rng(seed)
    count = 22
    pts = rng.random((count, 2)) * N
    y, x = np.mgrid[0:N, 0:N].astype(float)
    # Warp the field edges a little so hedgerows wander
    wx = (fbm(N, 4, 3, seed + 1) - 0.5) * 60
    wy = (fbm(N, 4, 3, seed + 2) - 0.5) * 60
    xw, yw = x + wx, y + wy
    best = np.full((N, N), np.inf)
    second = np.full((N, N), np.inf)
    owner = np.zeros((N, N), int)
    for k, (px, py) in enumerate(pts):
        for ox in (-N, 0, N):
            for oy in (-N, 0, N):
                dist = np.hypot(xw - px - ox, yw - py - oy)
                closer = dist < best
                second = np.where(closer, best, np.minimum(second, dist))
                owner = np.where(closer, k, owner)
                best = np.where(closer, dist, best)
    edge = second - best  # 0 on a field boundary
    tone = rng.integers(0, len(greens), count)
    angle = rng.uniform(0, np.pi, count)
    base = np.array(greens, float)[tone[owner]]
    a = angle[owner]
    stripes = 0.5 + 0.5 * np.sin((x * np.cos(a) + y * np.sin(a)) * 2 * np.pi / 14)
    stripe_strength = rng.uniform(0.0, 0.06, count)[owner]
    col = base * (1 + (stripes - 0.5) * 2 * stripe_strength)[..., None]
    # Hedgerows: dark, slightly lumpy lines along the boundaries
    lump = fbm(N, 64, 2, seed + 3)
    hedge = np.clip(1 - edge / (3.0 + 2.5 * lump), 0, 1)
    col = col * (1 - 0.45 * hedge)[..., None] + np.array([34, 52, 26]) * (0.45 * hedge)[..., None]
    # Large tonal drift and fine grain
    drift = fbm(N, 3, 3, seed + 4) - 0.5
    grain = fbm(N, 256, 2, seed + 5) - 0.5
    col = col * (1 + 0.18 * drift + 0.10 * grain)[..., None]
    return np.clip(col, 0, 255).astype(np.uint8)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)
    grass = fields(31, [(112, 138, 66), (124, 146, 70), (100, 128, 60), (136, 150, 78), (116, 140, 64)])
    leafy = fields(57, [(96, 126, 58), (108, 136, 62), (90, 118, 54), (120, 140, 66)])
    Image.fromarray(grass).save(os.path.join(args.out, "Grass_Color.png"))
    Image.fromarray(leafy).save(os.path.join(args.out, "LeafyGrass_Color.png"))
    # A 2 x 2 preview shows whether the tiling joins up
    Image.fromarray(np.tile(grass, (2, 2, 1))).resize((1024, 1024)).save(os.path.join(args.out, "Grass_tiled_preview.png"))
    print("terrain textures written")


if __name__ == "__main__":
    main()
