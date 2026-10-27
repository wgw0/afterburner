"""Painted skybox for the Strait, after John Constable's cloud studies (MAP-03 lighting).

Plain Python (numpy + Pillow), no Blender needed. Writes the six Roblox skybox faces plus a panorama
preview to --out. Cumulus are heaps of round puffs on flat bases, smaller and hazier toward the
horizon. Each puff is shaded as a sphere against the real sun direction: warm lit sides, grey-violet
shadow, bright rims when the sun is behind, blue sky light on the tops and warm bounce underneath.
A thin cirrus layer drifts overhead; the sky runs from a warm, hazy horizon to a soft blue zenith;
the paint has a faint brush texture. Everything is painted on an equirectangular canvas, then cut
into the six faces. The sun direction must match Lighting (tools/SkyBuilder.luau prints it) so the
clouds are lit from the side the sun is on.

Face orientation (measured in Studio with labelled test faces): looking along -Z shows SkyboxFt
upright, +X is SkyboxLf, -X SkyboxRt, +Z SkyboxBk, all unmirrored; SkyboxUp has its image top toward
+X and its image left toward +Z.

    python tools/blender/sky_paint.py --out tools/blender/out/textures/sky --sun -0.7341 0.4905 0.4695
"""

import argparse
import os

import numpy as np
from PIL import Image

SEED = 1821  # The Hay Wain


# Noise --------------------------------------------------------------------------------------------

def _hash(ix, iy, iz, seed):
    h = (ix * 374761393 + iy * 668265263 + iz * 2147483647 + seed * 144269504) & 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
    h = h ^ (h >> 16)
    return (h & 0xFFFF) / 65535.0


def value_noise(x, y, z, seed=0):
    """Smooth 3D value noise in 0..1."""
    ix, iy, iz = np.floor(x).astype(np.int64), np.floor(y).astype(np.int64), np.floor(z).astype(np.int64)
    fx, fy, fz = x - ix, y - iy, z - iz
    ux, uy, uz = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy), fz * fz * (3 - 2 * fz)
    out = 0.0
    for dx in (0, 1):
        wx = ux if dx else 1 - ux
        for dy in (0, 1):
            wy = uy if dy else 1 - uy
            for dz in (0, 1):
                wz = uz if dz else 1 - uz
                out = out + wx * wy * wz * _hash(ix + dx, iy + dy, iz + dz, seed)
    return out


def fbm(x, y, z, octaves, seed, billow=False):
    total, amp, norm = 0.0, 1.0, 0.0
    for o in range(octaves):
        n = value_noise(x, y, z, seed + o * 31)
        if billow:
            n = 1 - np.abs(2 * n - 1)
        total = total + n * amp
        norm += amp
        amp *= 0.5
        x, y, z = x * 2.03 + 17.1, y * 2.03 + 3.7, z * 2.03 + 9.3
    return total / norm


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def mix(a, b, t):
    return a + (b - a) * np.asarray(t)[..., None]


# The sky ------------------------------------------------------------------------------------------

ZENITH = np.array([86, 126, 188], float)
UPPER = np.array([124, 160, 204], float)
LOWER = np.array([184, 200, 214], float)
HORIZON = np.array([228, 224, 208], float)  # warm haze
GROUND = np.array([206, 206, 196], float)
SUNLIT = np.array([255, 249, 236], float)
WARM = np.array([255, 226, 186], float)  # low sun on the sunward sides
SHADOW = np.array([118, 116, 138], float)  # grey-violet
SLATE = np.array([86, 90, 108], float)  # the heavy clouds' shadows
SKYLIGHT = np.array([150, 170, 205], float)  # blue light on shadowed tops
BOUNCE = np.array([170, 158, 146], float)  # warm light from the land on the undersides

W, H = 4096, 2048  # canvas: azimuth -pi..pi across, elevation +pi/2..-pi/2 down


def canvas_dirs():
    az = (np.arange(W) + 0.5) / W * 2 * np.pi - np.pi
    el = np.pi / 2 - (np.arange(H) + 0.5) / H * np.pi
    A, E = np.meshgrid(az, el)
    return A, E, np.stack([np.cos(E) * np.sin(A), np.sin(E), -np.cos(E) * np.cos(A)], -1)


def sky_colour(d, sun):
    up = d[..., 1]
    sky = mix(HORIZON, LOWER, smoothstep(0.0, 0.12, up))
    sky = mix(sky, UPPER, smoothstep(0.10, 0.45, up))
    sky = mix(sky, ZENITH, smoothstep(0.40, 1.0, up))
    toward_sun = np.clip(d @ sun, 0, 1)
    sky = sky + np.array([28, 18, 2]) * ((toward_sun ** 6) * (1 - smoothstep(0.1, 0.6, up)))[..., None]
    sky = mix(sky, GROUND, smoothstep(0.0, -0.04, up))
    # Thin cirrus streaks on a high layer
    h2 = np.maximum(up, 0) + 0.12
    cx, cz = d[..., 0] / h2 * 0.35, d[..., 2] / h2 * 0.35
    streak = fbm(cx * 0.6 + cz * 1.6, cz * 0.25 - cx * 0.1, 3.3, 5, SEED + 5)
    cirrus = smoothstep(0.6, 0.82, streak) * 0.3 * smoothstep(0.1, 0.45, up)
    return mix(sky, np.array([242, 241, 238], float), cirrus)


def make_clouds(rng):
    """Cumulus heaps: (base elevation, size, mood 0..1, puffs as (azimuth, elevation, radius))."""
    clouds = []
    for _ in range(55):
        e_base = 0.012 + 0.75 * rng.random() ** 2.0
        a0 = rng.uniform(-np.pi, np.pi)
        size = 0.035 + 0.5 * min(e_base, 0.45) + rng.uniform(-0.01, 0.03)  # nearer clouds (higher up) look bigger
        width = size * rng.uniform(1.8, 3.6)
        height = size * rng.uniform(0.35, 0.8)
        puffs = []
        for _ in range(int(rng.integers(18, 34))):
            x = rng.uniform(-0.5, 0.5)
            r = size * rng.uniform(0.12, 0.32)
            dome = height * (1 - (2 * x) ** 2) * rng.uniform(0.2, 1.0)
            puffs.append((a0 + x * width / np.cos(e_base), e_base + r * 0.5 + dome, r))
        # Small lumps crowding the upper edge break the big round outlines
        for _ in range(int(rng.integers(10, 22))):
            x = rng.uniform(-0.45, 0.45)
            r = size * rng.uniform(0.05, 0.12)
            dome = height * (1 - (2 * x) ** 2) * rng.uniform(0.35, 0.8)
            puffs.append((a0 + x * width / np.cos(e_base), e_base + dome + size * 0.04, r))
        mood = rng.random() ** 2  # most clouds bright; some heavy and grey
        clouds.append((e_base, size, mood, puffs))
    return clouds


def paint_clouds(A, E, d, sky, sun, clouds):
    """Paints each cumulus onto the sky, distant (small) ones first. A cloud's puffs merge into one
    smooth surface (a soft maximum of their sphere heights), which is lit from its slope."""
    out = sky.copy()
    step = np.pi / H
    stroke_all = fbm(d[..., 0] * 9 + d[..., 1] * 3, d[..., 1] * 30, d[..., 2] * 9, 3, SEED + 9) - 0.5
    for e_base, size, mood, puffs in sorted(clouds, key=lambda c: c[1]):
        top = max(ec + r for (_, ec, r) in puffs)
        row0 = max(int((np.pi / 2 - top) / step) - 2, 0)
        row1 = min(int((np.pi / 2 - (e_base - 0.01)) / step) + 2, H)
        az = [ac for (ac, _, _) in puffs]
        a_mid = np.angle(np.mean(np.exp(1j * np.array(az))))
        span = max(abs((ac - a_mid + np.pi) % (2 * np.pi) - np.pi) + r / max(np.cos(ec), 0.2)
                   for (ac, ec, r) in puffs)
        c0 = int((a_mid - span + np.pi) / (2 * np.pi) * W) - 2
        c1 = int((a_mid + span + np.pi) / (2 * np.pi) * W) + 3
        cols = np.arange(c0, c1) % W
        a = A[row0:row1][:, cols]
        e = E[row0:row1][:, cols]
        dd = d[row0:row1][:, cols]
        tau = 0.06 * size
        acc = np.zeros(a.shape)
        cover = np.zeros(a.shape)
        k = 3.0 / size
        warp_x = (fbm(a * k, e * k, 1.5, 2, SEED + 23) - 0.5) * 0.7  # bends outlines, in puff radii
        warp_y = (fbm(a * k, e * k, 6.5, 2, SEED + 24) - 0.5) * 0.7
        fray = fbm(a * k * 4, e * k * 4, 2.5, 3, SEED + 25) - 0.5  # wispy fringes
        for (ac, ec, r) in puffs:
            dx = ((a - ac + np.pi) % (2 * np.pi) - np.pi) * np.cos(e) / r + warp_x
            dy = (e - ec) / r * 1.12 + warp_y
            q = dx * dx + dy * dy
            h = r * np.clip(1 - q, 0, 1) ** 1.5  # a soft dome that meets its neighbours without a crease
            inside = q < 1
            acc[inside] += np.exp(h[inside] / tau) - 1  # zero at the puff's edge, so no crease
            cover = np.maximum(cover, smoothstep(1.15, 0.55, q))
        cut = smoothstep(e_base - 0.002, e_base + 0.005, e)  # the flat base
        alpha = smoothstep(0.05, 0.8, cover + 0.5 * fray) * cut
        if alpha.max() < 0.01:
            continue
        hm = tau * np.log1p(acc)
        # Slope of the height field gives the surface normal (x right, y up, z toward the viewer)
        gy, gx = np.gradient(hm, step, (2 * np.pi / W))
        gx = gx / np.maximum(np.cos(e), 0.2)
        n = np.stack([-gx, gy, np.ones_like(hm)], -1)  # rows run downward, so up is +gy
        n /= np.linalg.norm(n, axis=-1, keepdims=True)
        nx, ny, nz = n[..., 0], n[..., 1], n[..., 2]

        right = np.stack([np.cos(a), np.zeros_like(a), np.sin(a)], -1)
        upv = np.cross(right, dd)
        Lx, Ly, Lz = right @ sun, upv @ sun, -(dd @ sun)
        diffuse = np.clip((nx * Lx + ny * Ly + nz * Lz + 0.25) / 1.25, 0, 1)
        rim = np.clip(-Lz, 0, 1) * (1 - nz) ** 2 * 1.4  # the sun behind a cloud lights its edges
        sky_fill = np.clip(ny, 0, 1) * (1 - diffuse)
        bounce = np.clip(-ny, 0, 1) * (1 - diffuse)
        above_base = (e - e_base) / (0.35 * size)
        base_dark = 1 - smoothstep(0.0, 1.0, above_base)  # flat bases sit in shadow
        stroke = stroke_all[row0:row1][:, cols]
        fleck = fbm(dd[..., 0] * 45, dd[..., 1] * 45, dd[..., 2] * 45, 2, SEED + 10) - 0.5

        glow = np.clip(-Lz, 0, 1) * (1 - alpha * 0.6) * 0.5  # sun through the thin parts
        brush = fbm(a * 140 + e * 60, e * 300 - a * 30, size * 7, 3, SEED + 22) - 0.5  # dragged strokes
        light = 0.38 - 0.25 * mood + 0.7 * diffuse + rim + glow - (0.5 + 0.3 * mood) * base_dark
        light = np.clip(light + 0.2 * stroke + 0.16 * brush, 0, 1)
        col = mix(mix(SHADOW, SLATE, mood), SUNLIT, light)
        col = mix(col, SKYLIGHT, 0.4 * sky_fill)
        col = mix(col, BOUNCE, 0.35 * bounce)
        warm = light * np.clip(Lx * nx + Lz * nz, 0, 1) * (1 - smoothstep(0.2, 0.7, sun[1]))
        col = mix(col, WARM, 0.45 * warm)
        col = col + 24 * (np.clip(fleck * 5, 0, 1) * (light > 0.82))[..., None]  # impasto flecks
        haze = 1 - smoothstep(0.0, 0.22, e)  # low, distant clouds melt into the haze
        col = mix(col, HORIZON * 0.98, 0.6 * haze)
        sub = out[row0:row1][:, cols]
        out[row0:row1, cols] = mix(sub, col, alpha)
    out = out * (1 + 0.03 * stroke_all)[..., None]
    return np.clip(out, 0, 255)


def paint(sun):
    A, E, d = canvas_dirs()
    sky = sky_colour(d, sun)
    clouds = make_clouds(np.random.default_rng(SEED))
    return paint_clouds(A, E, d, sky, sun, clouds)


# Faces --------------------------------------------------------------------------------------------

def face_dirs(face, n):
    u = (np.arange(n) + 0.5) / n
    uu, vv = np.meshgrid(u, u)  # uu: left to right, vv: top to bottom
    a, b = 2 * uu - 1, 1 - 2 * vv
    one = np.ones_like(a)
    if face == "Ft":
        d = (a, b, -one)
    elif face == "Bk":
        d = (-a, b, one)
    elif face == "Lf":
        d = (one, b, a)
    elif face == "Rt":
        d = (-one, b, -a)
    elif face == "Up":
        d = (1 - 2 * vv, one, 1 - 2 * uu)
    else:  # Dn: below the horizon, never really seen
        d = (a, -one, b)
    v = np.stack(d, -1)
    return v / np.linalg.norm(v, axis=-1, keepdims=True)


def sample(canvas, d):
    """Bilinear lookup of the canvas in directions d."""
    az = np.arctan2(d[..., 0], -d[..., 2])
    el = np.arcsin(np.clip(d[..., 1], -1, 1))
    x = (az + np.pi) / (2 * np.pi) * W - 0.5
    y = (np.pi / 2 - el) / np.pi * H - 0.5
    x0 = np.floor(x).astype(int)
    y0 = np.clip(np.floor(y).astype(int), 0, H - 2)
    tx = (x - x0)[..., None]
    ty = np.clip(y - y0, 0, 1)[..., None]
    x1 = (x0 + 1) % W
    x0 = x0 % W
    top = canvas[y0, x0] * (1 - tx) + canvas[y0, x1] * tx
    bot = canvas[y0 + 1, x0] * (1 - tx) + canvas[y0 + 1, x1] * tx
    return top * (1 - ty) + bot * ty


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--size", type=int, default=1024)
    ap.add_argument("--sun", type=float, nargs=3, default=[-0.7341, 0.4905, 0.4695])
    ap.add_argument("--preview-only", action="store_true")
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)
    sun = np.array(args.sun, float)
    sun /= np.linalg.norm(sun)

    canvas = paint(sun)
    # Preview: the band from 60 degrees up to 8 below the horizon, all the way round
    r0, r1 = int(H * (30 / 180)), int(H * (98 / 180))
    band = Image.fromarray(canvas[r0:r1].astype(np.uint8))
    band.resize((2048, int(2048 * (r1 - r0) / W))).save(os.path.join(args.out, "Sky_preview.png"))
    print("preview written")
    if args.preview_only:
        return
    for face in ("Ft", "Bk", "Lf", "Rt", "Up", "Dn"):
        rgb = sample(canvas, face_dirs(face, args.size))
        Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8)).save(os.path.join(args.out, f"Sky_{face}.png"))
        print("face", face)


if __name__ == "__main__":
    main()
