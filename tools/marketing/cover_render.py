"""
Afterburner: the 1920 x 1080 cover (the experience thumbnail). A moment from the trailer's fight (dogfight.py):
the Su-57 large in the foreground, seen from ahead of it as it pumps flares, the F-22A behind it with its
missile going for the flares, the mountains behind. cover_compose.py adds the wordmark.

  blender -b --factory-startup --python tools/marketing/cover_render.py -- --out <png> [--size 1920x1080]
      [--samples 256] [--eevee] [--t 4.95] [--cam along,side,height] [--aim 0.2] [--lens 45]
"""

import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

import dogfight as df  # noqa: E402
import scene as sc  # noqa: E402

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
parser = argparse.ArgumentParser()
parser.add_argument("--out", required=True)
parser.add_argument("--size", default="1920x1080")
parser.add_argument("--samples", type=int, default=256)
parser.add_argument("--eevee", action="store_true", help="a quick look instead of the final Cycles render")
parser.add_argument("--t", type=float, default=4.95)
parser.add_argument("--cam", default="-30,-12,-4",
                    help="camera offset from the Su-57, level: along its heading, to its right, up")
parser.add_argument("--aim", type=float, default=0.2, help="aim this far from the Su-57 towards the F-22A")
parser.add_argument("--lens", type=float, default=45)
args = parser.parse_args(argv)

scene = sc.reset()
sc.build_world(scene)
fight = df.Fight(scene)
fight.pose(args.t)
p, m, _ = sc.frame_of(df.su57, args.t)
UP = Vector((0, 0, 1))
heading = Vector((m.col[1].x, m.col[1].y, 0)).normalized()
along, side, height = (float(v) for v in args.cam.split(","))
cam = sc.camera(scene, args.lens)
sc.aim(cam, p + heading * along + heading.cross(UP) * side + UP * height, p.lerp(df.f22(args.t), args.aim), UP)
sc.look(scene)
(sc.use_eevee if args.eevee else sc.use_cycles)(scene, 64 if args.eevee else args.samples)
w, h = (int(v) for v in args.size.split("x"))
scene.render.resolution_x, scene.render.resolution_y = w, h
scene.render.filepath = args.out
bpy.ops.render.render(write_still=True)
print("rendered", args.out)
