"""
Overlays a generated jet on its reference three-view, at the drawing's own scale, to check the shape.
Renders the side and top views orthographically with a transparent background, tints the model and
blends it over the matching crop of the drawing. Mismatches show as offsets between the drawing's
lines and the tinted model.

  blender -b tools/blender/out/F5E_base.blend --python tools/blender/overlay_reference.py -- \
      --ref <three-view image> --out <absolute dir>

Calibration (defaults are the F-5E's, matching f5e_generate.py): drawing coordinates are pixels on a
2000 px wide copy of the image. --side-box and --top-box are the view crops (x0,y0,x1,y1).
"""

import argparse
import os
import sys

import bpy
import numpy as np
from mathutils import Matrix, Vector

argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
parser = argparse.ArgumentParser()
parser.add_argument("--ref", required=True)
parser.add_argument("--out", required=True)
parser.add_argument("--prefix", default="F5E")
parser.add_argument("--px-per-m", type=float, default=(1545.8 - 22.9) / 14.45)
parser.add_argument("--pitot-xd", type=float, default=22.9)
parser.add_argument("--pitot-y", type=float, default=8.825, help="Blender Y of the pitot tip")
parser.add_argument("--z0-row", type=float, default=290.0, help="side-view row of Blender Z = 0")
parser.add_argument("--centre-row", type=float, default=921.7, help="top-view row of the centreline")
parser.add_argument("--side-box", default="0,0,1560,470")
parser.add_argument("--top-box", default="0,465,1560,1385")
args = parser.parse_args(argv)

K = args.px_per_m
ref_img = bpy.data.images.load(args.ref)
RW, RH = ref_img.size
S = RW / 2000.0
ref = np.array(ref_img.pixels[:], dtype=np.float32).reshape(RH, RW, 4)[::-1]  # row 0 = top
ref = ref[..., :3] * ref[..., 3:4] + (1 - ref[..., 3:4])


def by(xd):
    return args.pitot_y - (xd - args.pitot_xd) / K


scene = bpy.context.scene
scene.render.engine = "BLENDER_WORKBENCH"
scene.render.film_transparent = True
scene.display.shading.light = "FLAT"
scene.display.shading.color_type = "SINGLE"
scene.display.shading.single_color = (1, 1, 1)
scene.display.shading.show_object_outline = True
scene.display.shading.object_outline_color = (0, 0, 0)
scene.render.image_settings.file_format = "PNG"
scene.render.image_settings.color_mode = "RGBA"
for obj in scene.objects:
    if obj.type != "MESH":
        obj.hide_render = True

cam_data = bpy.data.cameras.new("OverlayCam")
cam_data.type = "ORTHO"
cam = bpy.data.objects.new("OverlayCam", cam_data)
scene.collection.objects.link(cam)
scene.camera = cam


def render_view(name, box, right, up, centre):
    x0, y0, x1, y1 = (float(v) for v in box.split(","))
    w_px, h_px = int((x1 - x0) * S), int((y1 - y0) * S)
    scene.render.resolution_x, scene.render.resolution_y = w_px, h_px
    scene.render.resolution_percentage = 100
    cam_data.ortho_scale = max(x1 - x0, y1 - y0) / K
    back = right.cross(up)
    rot = Matrix((right, up, back)).transposed().to_4x4()
    cam.matrix_world = Matrix.Translation(centre + back * 50) @ rot
    cam_data.clip_end = 200
    path = os.path.join(args.out, f"_{name}_model.png")
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    model_img = bpy.data.images.load(path)
    m = np.array(model_img.pixels[:], dtype=np.float32).reshape(h_px, w_px, 4)[::-1]
    crop = ref[int(y0 * S) : int(y0 * S) + h_px, int(x0 * S) : int(x0 * S) + w_px]
    a = m[..., 3:4] * 0.55
    tint = np.array([0.15, 0.45, 0.95], dtype=np.float32) * (0.55 + 0.45 * m[..., :3])
    out = crop * (1 - a) + tint * a
    # Keep the drawing's lines on top so both outlines stay readable
    lines = crop.mean(axis=2, keepdims=True) < 0.5
    out = np.where(lines, crop * 0.6 + np.array([0.9, 0.1, 0.1]) * 0.4, out)
    img = bpy.data.images.new(f"{name}_overlay", w_px, h_px)
    img.pixels = np.concatenate([out, np.ones((h_px, w_px, 1), np.float32)], axis=2)[::-1].ravel()
    img.filepath_raw = os.path.join(args.out, f"{args.prefix}_overlay_{name}.png")
    img.file_format = "PNG"
    img.save()
    os.remove(path)
    print("wrote", img.filepath_raw)


sx0, sy0, sx1, sy1 = (float(v) for v in args.side_box.split(","))
side_centre = Vector((0, by((sx0 + sx1) / 2), (args.z0_row - (sy0 + sy1) / 2) / K))
render_view("side", args.side_box, Vector((0, -1, 0)), Vector((0, 0, 1)), side_centre)

tx0, ty0, tx1, ty1 = (float(v) for v in args.top_box.split(","))
top_centre = Vector(((args.centre_row - (ty0 + ty1) / 2) / K, by((tx0 + tx1) / 2), 0))
render_view("top", args.top_box, Vector((0, -1, 0)), Vector((1, 0, 0)), top_centre)
