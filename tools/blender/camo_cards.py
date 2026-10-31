"""
Afterburner: the shop cards' pictures of the camos (Config/Cosmetics "Camo" Images): the F-16A in each camo, from
the front three-quarters, on a transparent background so it sits on the card's own colour, cropped to the jet.

  blender -b tools/blender/out/F16A_base.blend --python tools/blender/camo_cards.py -- \
      --textures <dir with F16A_<Camo>_<Set>_<Map>.png> --out <dir>

Paint the camos first (rafalec_paint.py and the rest, or f16a_paint.py --skin <Camo>): the textures are read from
--textures. Writes CamoCard_<Camo>.png, 1024 x 512.
"""

import argparse
import math
import os
import sys

import bpy
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import f16a_paint  # noqa: E402,F401  (sets the shared generator module to the F-16A)
import f5e_paint as paint  # noqa: E402

CAMOS = ("VIPGold", "ArcticSplinter", "TigerStripe")
SETS = ("Body", "Wings", "Details")
WIDTH, HEIGHT = 1024, 512
MARGIN = 0.06  # of the picture, round the jet


def setup(scene):
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 64
    scene.render.film_transparent = True
    scene.render.resolution_x, scene.render.resolution_y = WIDTH * 2, HEIGHT * 2  # cropped down afterwards
    world = scene.world or bpy.data.worlds.new("World")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    bg.inputs["Color"].default_value = (0.55, 0.68, 0.85, 1)
    bg.inputs["Strength"].default_value = 0.9
    sun_data = bpy.data.lights.new("Sun", "SUN")
    sun_data.energy = 4.5
    sun = bpy.data.objects.new("Sun", sun_data)
    sun.rotation_euler = (math.radians(50), math.radians(10), math.radians(140))
    scene.collection.objects.link(sun)
    for o in bpy.data.objects:
        if o.type == "MESH" and o.get("afterburner_kind") in ("Gear", "GearWheel", "GearDoor"):
            o.hide_render = True  # gear up, as in flight
    cam = bpy.data.objects.new("CardCam", bpy.data.cameras.new("CardCam"))
    scene.collection.objects.link(cam)
    scene.camera = cam
    cam.data.lens = 50
    from mathutils import Vector

    eye, target = Vector((19.0, 16.0, 7.0)), Vector((0, 0.0, 0.2))
    cam.location = eye
    cam.rotation_euler = (target - eye).to_track_quat("-Z", "Y").to_euler()


def crop(path):
    """Crops a render to the jet (its alpha), with a margin, and fits it in WIDTH x HEIGHT."""
    img = bpy.data.images.load(path)
    w, h = img.size
    px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
    ys, xs = np.nonzero(px[..., 3] > 0.02)
    x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
    jet = px[y0:y1, x0:x1]
    jh, jw = jet.shape[:2]
    scale = min(WIDTH * (1 - 2 * MARGIN) / jw, HEIGHT * (1 - 2 * MARGIN) / jh)
    nw, nh = max(int(jw * scale), 1), max(int(jh * scale), 1)
    # Nearest-texel resample is enough here: the source is twice the size
    yi = (np.arange(nh) / scale).astype(np.int64).clip(0, jh - 1)
    xi = (np.arange(nw) / scale).astype(np.int64).clip(0, jw - 1)
    small = jet[yi][:, xi]
    out = np.zeros((HEIGHT, WIDTH, 4), np.float32)
    oy, ox = (HEIGHT - nh) // 2, (WIDTH - nw) // 2
    out[oy : oy + nh, ox : ox + nw] = small
    res = bpy.data.images.new("card", WIDTH, HEIGHT, alpha=True)
    res.pixels = out.ravel()
    res.filepath_raw = path
    res.file_format = "PNG"
    res.save()


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--textures", required=True)
    parser.add_argument("--out", required=True)
    args = parser.parse_args(argv)
    os.makedirs(args.out, exist_ok=True)
    scene = bpy.context.scene
    setup(scene)
    for camo in CAMOS:
        for set_name in SETS:
            paths = {m: os.path.join(args.textures, f"F16A_{camo}_{set_name}_{m}.png") for m in ("Color", "Roughness", "Metalness", "Normal")}
            paint.apply_preview_material(set_name, paths)
        path = os.path.join(args.out, f"CamoCard_{camo}.png")
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        crop(path)
        print("card", path)


main()
