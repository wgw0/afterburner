"""
Afterburner: the jet renders for the game pass icons (tools/passes/pass_icons.py lays them out): the F-16A in a
camo from a chosen angle, on a transparent background, cropped to the jet.

  blender -b tools/blender/out/F16A_base.blend --python tools/blender/pass_icons.py -- \
      --textures <dir with F16A_<Camo>_<Set>_<Map>.png> --out <dir>

Writes PassJet_<Shot>.png, 1024 x 1024 at most, one per SHOTS entry. The look is dramatic on purpose (Will:
cool over realistic): a glossy clear coat that catches the sky, a strong rim light in the icon's own colour,
and lit afterburners.
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
# name: (camo, camera position, look-at point, roll in degrees about the view, rim light colour)
GOLD, ICE, MINT = (1.0, 0.72, 0.25), (0.35, 0.65, 1.0), (0.35, 1.0, 0.6)
SHOTS = {
    "VIP": ("VIPGold", (15.0, 13.0, -5.5), (0, 0.8, 0.4), -32, GOLD),  # from below the nose, banking hard
    "LineupA": ("VIPGold", (18.0, 15.0, 6.0), (0, 0.0, 0.2), -14, ICE),
    "LineupB": ("ArcticSplinter", (18.0, 15.0, 6.0), (0, 0.0, 0.2), -14, ICE),
    "LineupC": ("TigerStripe", (18.0, 15.0, 6.0), (0, 0.0, 0.2), -14, ICE),
    "Callsign": ("TigerStripe", (20.0, 9.5, 2.5), (0, 1.0, 0.2), -10, MINT),  # side-on, room above for the name
}
AFTERBURNER_GLOW = (1.0, 0.55, 0.15)


def setup(scene):
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 96
    scene.render.film_transparent = True
    scene.render.resolution_x = scene.render.resolution_y = SIZE * 2  # cropped down afterwards
    world = scene.world or bpy.data.worlds.new("World")
    scene.world = world
    world.use_nodes = True
    # A real sky to reflect in the clear coat (the background itself stays transparent)
    nodes, links = world.node_tree.nodes, world.node_tree.links
    bg = nodes.get("Background")
    try:
        sky = nodes.new("ShaderNodeTexSky")
        sky.sky_type = "NISHITA"
        sky.sun_elevation = math.radians(25)
        links.new(sky.outputs["Color"], bg.inputs["Color"])
        bg.inputs["Strength"].default_value = 0.35
    except Exception:
        bg.inputs["Color"].default_value = (0.55, 0.62, 0.8, 1)
        bg.inputs["Strength"].default_value = 0.8
    try:
        scene.view_settings.look = "AgX - High Contrast"  # punchier than the default
    except Exception:
        pass
    key = bpy.data.objects.new("Key", bpy.data.lights.new("Key", "SUN"))
    key.data.energy = 4.5
    key.data.color = (1.0, 0.95, 0.88)
    key.data.angle = math.radians(2)
    key.rotation_euler = (math.radians(40), math.radians(15), math.radians(130))
    scene.collection.objects.link(key)
    fill = bpy.data.objects.new("Fill", bpy.data.lights.new("Fill", "SUN"))
    fill.data.energy = 0.8
    fill.data.color = (0.6, 0.7, 1.0)
    fill.rotation_euler = (math.radians(60), 0, math.radians(-60))
    scene.collection.objects.link(fill)
    rim = bpy.data.objects.new("Rim", bpy.data.lights.new("Rim", "SUN"))
    rim.data.energy = 9.0
    rim.data.angle = math.radians(1)
    rim.rotation_euler = (math.radians(118), 0, math.radians(-25))  # from behind: a hard coloured edge
    scene.collection.objects.link(rim)
    scene["rim"] = rim.name
    # Glossy clear coat on the paint, and lit afterburners
    for mat in bpy.data.materials:
        bsdf = mat.node_tree and mat.node_tree.nodes.get("Principled BSDF")
        if bsdf and "Coat Weight" in bsdf.inputs:
            bsdf.inputs["Coat Weight"].default_value = 0.55
            bsdf.inputs["Coat Roughness"].default_value = 0.06
    glow = bpy.data.materials.new("PassAfterburner")
    glow.use_nodes = True
    gb = glow.node_tree.nodes.get("Principled BSDF")
    gb.inputs["Base Color"].default_value = (*AFTERBURNER_GLOW, 1)
    gb.inputs["Emission Color"].default_value = (*AFTERBURNER_GLOW, 1)
    gb.inputs["Emission Strength"].default_value = 60
    for o in bpy.data.objects:
        if o.type == "MESH" and o.get("afterburner_kind") == "Afterburner":
            o.data.materials.clear()
            o.data.materials.append(glow)
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
        camo, eye, target, roll, rim_colour = SHOTS[name]
        bpy.data.objects[scene["rim"]].data.color = rim_colour
        for set_name in SETS:
            paths = {m: os.path.join(args.textures, f"F16A_{camo}_{set_name}_{m}.png") for m in ("Color", "Roughness", "Metalness", "Normal")}
            paint.apply_preview_material(set_name, paths)
            bsdf = bpy.data.materials[f"F16A_{set_name}"].node_tree.nodes.get("Principled BSDF")
            if bsdf and "Coat Weight" in bsdf.inputs:
                bsdf.inputs["Coat Weight"].default_value = 0.55
                bsdf.inputs["Coat Roughness"].default_value = 0.06
        aim(cam, eye, target, roll)
        path = os.path.join(args.out, f"PassJet_{name}.png")
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        crop(path)
        print("pass jet", path)


main()
