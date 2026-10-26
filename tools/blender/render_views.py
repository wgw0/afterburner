"""
Renders reference views of a generated jet (top, side, front, three-quarter) with the Workbench engine,
for checking proportions against reference images.

  blender -b tools/blender/out/F5E_base.blend --python tools/blender/render_views.py -- --out tools/blender/out
"""

import argparse
import math
import os
import sys

import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
parser = argparse.ArgumentParser()
parser.add_argument("--out", default="out")
parser.add_argument("--prefix", default="F5E")
args = parser.parse_args(argv)

scene = bpy.context.scene
scene.render.engine = "BLENDER_WORKBENCH"
scene.render.resolution_x, scene.render.resolution_y = 1600, 1000
shading = scene.display.shading
shading.light = "STUDIO"
shading.color_type = "MATERIAL"
shading.show_cavity = True
shading.show_object_outline = True
shading.show_specular_highlight = True
scene.display.shading.background_type = "VIEWPORT" if hasattr(shading, "background_type") else None
scene.world = scene.world or bpy.data.worlds.new("World")

for obj in [o for o in scene.objects if o.type == "EMPTY"]:
    obj.hide_render = True

cam_data = bpy.data.cameras.new("RefCam")
cam = bpy.data.objects.new("RefCam", cam_data)
scene.collection.objects.link(cam)
scene.camera = cam

VIEWS = {
    "top": (Vector((0, 0, 30)), Vector((0, 0, 0)), True, 26),
    "side": (Vector((30, 0, 0.5)), Vector((0, 0, 0.5)), True, 17),
    "front": (Vector((0, 30, 0.6)), Vector((0, 0, 0.6)), True, 10),
    "threequarter": (Vector((11, 13, 6)), Vector((0, -0.5, 0.2)), False, 0),
}

for name, (eye, target, ortho, scale) in VIEWS.items():
    cam_data.type = "ORTHO" if ortho else "PERSP"
    if ortho:
        cam_data.ortho_scale = scale
    else:
        cam_data.lens = 45
    cam.location = eye
    direction = target - eye
    cam.rotation_euler = direction.to_track_quat("-Z", "Y" if name != "top" else "Y").to_euler()
    scene.render.filepath = os.path.join(args.out, f"{args.prefix}_{name}.png")
    bpy.ops.render.render(write_still=True)
    print("rendered", scene.render.filepath)
