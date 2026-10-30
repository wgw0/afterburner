"""
Afterburner: the trailer's frames. Fifteen seconds of the scripted fight (dogfight.py) in four shots, rendered
with EEVEE to numbered PNGs; trailer_compose.py adds the wordmark and makes the MP4.

  blender -b --factory-startup --python tools/marketing/trailer_render.py -- --out <dir>
      [--size 1920x1080] [--fps 30] [--samples 48] [--frames 1-450] [--cycles]
"""

import argparse
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

import dogfight as df  # noqa: E402
import scene as sc  # noqa: E402

LENGTH = 15.0
UP = Vector((0, 0, 1))


def smooth(a, b, k):
    k = max(0.0, min(1.0, k))
    k = k * k * (3 - 2 * k)
    return a + (b - a) * k


def shot(t):
    """Where the camera is at time t: (location, target, up, lens)."""
    if t < 3.5:
        # A: flying alongside, just ahead of the Su-57 and outside its turn, looking back past it at the F-22A
        p, m, _ = sc.frame_of(df.su57, t)
        fwd = m.col[1]
        outward = Vector((p.x, p.y, 0)).normalized()
        loc = p + fwd * smooth(34, 24, t / 3.5) + outward * 26 + Vector((0, 0, -5))
        target = p - fwd * 22
        return loc, target, UP, 30
    if t < 7.5:
        # B: the chase cam, behind and above the F-22A, part-rolled with it, looking at the Su-57
        p, m, _ = sc.frame_of(df.f22, t)
        right, fwd, up = m.col[0], m.col[1], m.col[2]
        loc = p - fwd * 32 + up * 3.2 + right * 1.5
        target = df.su57(t)
        return loc, target, up.lerp(UP, 0.55).normalized(), 35
    if t < 9.8:
        # C: the F-22A goes past close by, afterburners lit
        tp = 9.1
        p, m, _ = sc.frame_of(df.f22, tp)
        outward = Vector((p.x, p.y, 0)).normalized()
        loc = p + outward * 26 + Vector((0, 0, -9))
        target = df.f22(t) + sc.frame_of(df.f22, t)[1].col[1] * 4
        return loc, target, UP, 32
    # D: off the F-22A's shoulder, outside the turn, as the pair pull away; the frame tilts up to leave sky
    # for the wordmark
    k = (t - 9.8) / (LENGTH - 9.8)
    p, m, _ = sc.frame_of(df.f22, t)
    fwd = m.col[1]
    flat = Vector((fwd.x, fwd.y, 0)).normalized()
    outward = Vector((p.x, p.y, 0)).normalized()
    loc = p - flat * smooth(45, 170, k) + outward * smooth(14, 50, k) + Vector((0, 0, 3))
    target = p.lerp(df.su57(t), 0.3) + Vector((0, 0, smooth(0, 28, k)))
    return loc, target, UP, 35


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", required=True)
    parser.add_argument("--size", default="1920x1080")
    parser.add_argument("--fps", type=int, default=30)
    parser.add_argument("--samples", type=int, default=48)
    parser.add_argument("--frames", default=None, help="first-last, 1-based; or a comma list")
    parser.add_argument("--cycles", action="store_true")
    args = parser.parse_args(argv)

    scene = sc.reset()
    sc.build_world(scene)
    fight = df.Fight(scene)
    cam = sc.camera(scene)
    sc.look(scene)
    (sc.use_cycles if args.cycles else sc.use_eevee)(scene, args.samples)
    w, h = (int(v) for v in args.size.split("x"))
    scene.render.resolution_x, scene.render.resolution_y = w, h
    scene.render.image_settings.file_format = "PNG"
    os.makedirs(args.out, exist_ok=True)

    total = int(LENGTH * args.fps)
    if args.frames and "," in args.frames:
        frames = [int(f) for f in args.frames.split(",")]
    elif args.frames:
        a, b = (int(f) for f in args.frames.split("-"))
        frames = range(a, b + 1)
    else:
        frames = range(1, total + 1)
    for f in frames:
        t = (f - 1) / args.fps
        fight.pose(t)
        loc, target, up, lens = shot(t)
        sc.aim(cam, loc, target, up)
        cam.data.lens = lens
        scene.render.filepath = os.path.join(args.out, f"frame_{f:04d}.png")
        bpy.ops.render.render(write_still=True)
        print(f"frame {f}/{total} t={t:.2f}", flush=True)


main()
