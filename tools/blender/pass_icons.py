"""
Afterburner: the jet renders for the game pass icons (tools/passes/pass_icons.py lays them out): the F-16A in a
camo from a chosen angle, on a transparent background, cropped to the jet.

  blender -b tools/blender/out/F16A_base.blend --python tools/blender/pass_icons.py -- \
      --textures <dir with F16A_<Camo>_<Set>_<Map>.png> --out <dir>

Writes PassJet_<Shot>.png, 1024 x 1024 at most, one per SHOTS entry.
"""

import argparse
import math
import os
import sys

import bpy
import numpy as np
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import f16a_paint  # noqa: E402,F401  (sets the shared generator module to the F-16A)
import f5e_paint as paint  # noqa: E402

SETS = ("Body", "Wings", "Details")
SIZE = 1024
# name: (camo, camera position, look-at point, roll in degrees about the view)
SHOTS = {
    "VIP": ("VIPGold", (17.0, 12.0, -4.5), (0, 0.8, 0.4), -24),  # from below the nose, banking hard
    "LineupA": ("VIPGold", (18.0, 15.0, 6.0), (0, 0.0, 0.2), -12),
    "LineupB": ("ArcticSplinter", (18.0, 15.0, 6.0), (0, 0.0, 0.2), -12),
    "LineupC": ("TigerStripe", (18.0, 15.0, 6.0), (0, 0.0, 0.2), -12),
    "Callsign": ("TigerStripe", (21.0, 9.0, 3.5), (0, 1.0, 0.2), -8),  # side-on, room above for the name
}


def setup(scene):
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 96
    scene.render.film_transparent = True
    scene.render.resolution_x = scene.render.resolution_y = SIZE * 2  # cropped down afterwards
    world = scene.world or bpy.data.worlds.new("World")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    bg.inputs["Color"].default_value = (0.55, 0.62, 0.8, 1)
    bg.inputs["Strength"].default_value = 0.8
    key = bpy.data.objects.new("Key", bpy.data.lights.new("Key", "SUN"))
    key.data.energy = 5.0
    key.rotation_euler = (math.radians(40), math.radians(15), math.radians(130))
    scene.collection.objects.link(key)
    rim = bpy.data.objects.new("Rim", bpy.data.lights.new("Rim", "SUN"))
    rim.data.energy = 2.5
    rim.data.color = (1.0, 0.85, 0.6)
    rim.rotation_euler = (math.radians(110), 0, math.radians(-40))  # from behind and below: a warm edge
    scene.collection.objects.link(rim)
    for o in bpy.data.objects:
        if o.type == "MESH" and o.get("afterburner_kind") in ("Gear", "GearWheel", "GearDoor"):
            o.hide_render = True  # gear up, as in flight
    cam = bpy.data.objects.new("PassCam", bpy.data.cameras.new("PassCam"))
    cam.data.lens = 50
    scene.collection.objects.link(cam)
    scene.camera = cam
    return cam


def aim(cam, eye, target, roll):
    cam.location = Vector(eye)
    q = (Vector(target) - Vector(eye)).to_track_quat("-Z", "Y")
    cam.rotation_euler = q.to_euler()
    cam.rotation_euler.rotate_axis("Z", math.radians(roll))


def crop(path):
    """Crops a render to the jet (its alpha) and fits it in SIZE x SIZE, keeping its shape."""
    img = bpy.data.images.load(path)
    w, h = img.size
    px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
    ys, xs = np.nonzero(px[..., 3] > 0.02)
    jet = px[ys.min() : ys.max() + 1, xs.min() : xs.max() + 1]
    jh, jw = jet.shape[:2]
    scale = min(SIZE / jw, SIZE / jh, 1.0)
    nw, nh = max(int(jw * scale), 1), max(int(jh * scale), 1)
    yi = (np.arange(nh) / scale).astype(np.int64).clip(0, jh - 1)
    xi = (np.arange(nw) / scale).astype(np.int64).clip(0, jw - 1)
    small = jet[yi][:, xi]
    res = bpy.data.images.new("pass", nw, nh, alpha=True)
    res.pixels = small.ravel()
    res.filepath_raw = path
    res.file_format = "PNG"
    res.save()


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--textures", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--shots", default=",".join(SHOTS), help="comma list (default: all)")
    args = parser.parse_args(argv)
    os.makedirs(args.out, exist_ok=True)
    scene = bpy.context.scene
    cam = setup(scene)
    for name in args.shots.split(","):
        camo, eye, target, roll = SHOTS[name]
        for set_name in SETS:
            paths = {m: os.path.join(args.textures, f"F16A_{camo}_{set_name}_{m}.png") for m in ("Color", "Roughness", "Metalness", "Normal")}
            paint.apply_preview_material(set_name, paths)
        aim(cam, eye, target, roll)
        path = os.path.join(args.out, f"PassJet_{name}.png")
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        crop(path)
        print("pass jet", path)


main()
