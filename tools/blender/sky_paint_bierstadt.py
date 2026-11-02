"""Painted skybox for Desert Range, after Albert Bierstadt (MAP-05, Will): the American West in late light.

Plain Python (numpy + Pillow). Built on sky_paint.py (the Strait's Constable sky: the same canvas, cloud
shading and face cutting) with Bierstadt's palette and drama instead:
  * a luminous golden glow round a low sun, fading through amber and rose to a deep blue zenith;
  * towering storm clouds, their sunward edges blazing gold, their undersides dark and violet;
  * rays of light breaking through the gaps, and a warm golden haze over the horizon.
The sun direction must match Lighting (tools/DesertBuilder.lighting prints it).

    python tools/blender/sky_paint_bierstadt.py --out tools/blender/out/textures/sky_desert --sun -0.9527 0.2822 0.1132
"""

import argparse
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sky_paint as sp  # noqa: E402

sp.SEED = 1868  # Among the Sierra Nevada, California
sp.BASE_SOFTNESS = (0.03, 0.05)  # soft, smoky undersides, not the Strait's flat cumulus bases

# Bierstadt's light: gold at the horizon and round the sun, a deep blue overhead
sp.ZENITH = np.array([70, 98, 140], float)  # a soft, greyed blue
sp.UPPER = np.array([128, 148, 168], float)
sp.LOWER = np.array([214, 168, 120], float)  # amber
sp.HORIZON = np.array([255, 214, 150], float)  # golden haze
sp.GROUND = np.array([214, 176, 128], float)
sp.SUNLIT = np.array([255, 228, 176], float)
sp.WARM = np.array([255, 182, 92], float)  # blazing gold edges
sp.SHADOW = np.array([104, 84, 108], float)  # violet storm shadow
sp.SLATE = np.array([62, 56, 78], float)  # the darkest undersides
sp.SKYLIGHT = np.array([120, 140, 190], float)
sp.BOUNCE = np.array([196, 142, 104], float)  # warm desert light on the undersides


def make_clouds(rng):
    """Towering cumulus and storm heads, bigger and taller than the Strait's, massed near the horizon."""
    clouds = []
    for _ in range(30):
        e_base = 0.06 + 0.5 * rng.random() ** 2.0  # none sitting on the horizon itself
        a0 = rng.uniform(-np.pi, np.pi)
        size = 0.07 + 0.6 * min(e_base, 0.42) + rng.uniform(0.0, 0.05)
        width = size * rng.uniform(1.8, 3.4)
        height = size * rng.uniform(0.6, 1.0)  # tall, but packed solid
        puffs = []
        for _ in range(int(rng.integers(45, 70))):
            x = rng.uniform(-0.5, 0.5)
            r = size * rng.uniform(0.2, 0.42)
            dome = height * (1 - (2 * x) ** 2) * rng.uniform(0.0, 1.0) ** 0.8
            puffs.append((a0 + x * width / np.cos(e_base), e_base + r * 0.4 + dome, r))
        for _ in range(int(rng.integers(12, 26))):
            x = rng.uniform(-0.45, 0.45)
            r = size * rng.uniform(0.05, 0.12)
            dome = height * (1 - (2 * x) ** 2) ** 0.7 * rng.uniform(0.4, 0.95)
            puffs.append((a0 + x * width / np.cos(e_base), e_base + dome + size * 0.05, r))
        mood = 0.25 + 0.75 * rng.random() ** 1.5  # many heavy, dramatic clouds
        clouds.append((e_base, size, mood, puffs))
    return clouds


def sun_glory(d, sun, canvas, clear):
    """The glow round the low sun, and rays breaking through where the clouds part."""
    toward = np.clip(d @ sun, -1, 1)
    up = d[..., 1]
    glow = np.clip(toward, 0, 1)
    out = canvas.copy()
    # A wide golden glow, a tighter white-gold halo and the sun's disc
    out = out + np.array([90, 60, 18]) * (glow ** 8)[..., None]
    out = out + np.array([120, 100, 60]) * (glow ** 60)[..., None]
    out = out + np.array([255, 240, 200]) * (glow ** 900)[..., None]
    # Rays: streaks fanning out from the sun, stronger where the sky is clear of cloud
    side = np.cross(sun, np.array([0, 1, 0], float))
    side /= np.linalg.norm(side)
    upv = np.cross(side, sun)
    angle = np.arctan2(d @ upv, d @ side)
    streaks = sp.fbm(np.cos(angle) * 6, np.sin(angle) * 6, 0.5, 3, sp.SEED + 41)
    rays = sp.smoothstep(0.52, 0.75, streaks) * np.clip(toward, 0, 1) ** 3 * clear
    out = out + np.array([70, 52, 22]) * rays[..., None] * (up > -0.02)[..., None]
    # Golden haze low over the horizon all round, thicker towards the sun
    haze = 1 - sp.smoothstep(0.0, 0.22, np.abs(up))
    out = sp.mix(out, sp.HORIZON, (0.45 + 0.3 * np.clip(toward, 0, 1)) * haze)
    # A warm veil over everything: Bierstadt's light seems to fill the air itself
    veil = 0.12 + 0.25 * np.clip(toward, 0, 1) ** 2
    out = sp.mix(out, np.array([255, 206, 140], float), veil)
    return np.clip(out, 0, 255)


def paint(sun):
    A, E, d = sp.canvas_dirs()
    sky = sp.sky_colour(d, sun)
    clouds = make_clouds(np.random.default_rng(sp.SEED))
    painted = sp.paint_clouds(A, E, d, sky, sun, clouds)
    # How clear each direction is of cloud (rays only show through the gaps)
    clear = 1 - sp.smoothstep(6, 40, np.abs(painted - sky).sum(-1))
    glory = sun_glory(d, sun, painted, clear)
    # Softened like oil paint: a light blur takes the hard edges off the puffs
    from PIL import ImageFilter

    soft = Image.fromarray(np.clip(glory, 0, 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(2.2))
    return np.asarray(soft, float)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--size", type=int, default=1024)
    ap.add_argument("--sun", type=float, nargs=3, default=[-0.9527, 0.2822, 0.1132])
    ap.add_argument("--preview-only", action="store_true")
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)
    sun = np.array(args.sun, float)
    sun /= np.linalg.norm(sun)
    canvas = paint(sun)
    r0, r1 = int(sp.H * (25 / 180)), int(sp.H * (98 / 180))
    band = Image.fromarray(canvas[r0:r1].astype(np.uint8))
    band.resize((2048, int(2048 * (r1 - r0) / sp.W))).save(os.path.join(args.out, "Sky_preview.png"))
    print("preview written")
    if args.preview_only:
        return
    for face in ("Ft", "Bk", "Lf", "Rt", "Up", "Dn"):
        rgb = sp.sample(canvas, sp.face_dirs(face, args.size))
        Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8)).save(os.path.join(args.out, f"Sky_{face}.png"))
        print("face", face)


if __name__ == "__main__":
    main()
