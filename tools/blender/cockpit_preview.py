"""
Afterburner: renders a cockpit as the pilot sees it, inside the jet's exterior.

  blender -b <out>/<Id>_base.blend --python tools/blender/cockpit_preview.py -- --out <absolute dir> \
      [--skin Ghost --textures <dir with <Id>_<Skin>_<Set>_<Map>.png>]

Appends <Id>_cockpit.blend (painted with <Id>_Cockpit_<Map>.png if they are in --out), hides the canopy
glass as the game does from inside, and renders from the CockpitEye with the game's 70° field of view:
looking ahead, down at the panel, and from outside over the canopy. Writes <Id>_cockpit_<view>.png.
"""

import argparse
import math
import os
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))


def textured(mat, paths):
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = nodes.get("Principled BSDF")

    def tex(path, colorspace):
        n = nodes.new("ShaderNodeTexImage")
        n.image = bpy.data.images.load(path)
        n.image.colorspace_settings.name = colorspace
        return n

    links.new(tex(paths["Color"], "sRGB").outputs["Color"], bsdf.inputs["Base Color"])
    links.new(tex(paths["Roughness"], "Non-Color").outputs["Color"], bsdf.inputs["Roughness"])
    links.new(tex(paths["Metalness"], "Non-Color").outputs["Color"], bsdf.inputs["Metallic"])
    nmap = nodes.new("ShaderNodeNormalMap")
    links.new(tex(paths["Normal"], "Non-Color").outputs["Color"], nmap.inputs["Color"])
    links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])


def maps(prefix):
    paths = {m: f"{prefix}_{m}.png" for m in ("Color", "Roughness", "Metalness", "Normal")}
    return paths if all(os.path.exists(p) for p in paths.values()) else None


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", required=True)
    parser.add_argument("--skin", default=None)
    parser.add_argument("--textures", default=None)
    parser.add_argument("--samples", type=int, default=48)
    args = parser.parse_args(argv)

    base = os.path.basename(bpy.data.filepath)
    airframe = base.replace("_base.blend", "")
    cockpit_blend = os.path.join(os.path.dirname(bpy.data.filepath), f"{airframe}_cockpit.blend")
    with bpy.data.libraries.load(cockpit_blend) as (src, dst):
        dst.objects = [n for n in src.objects]
    col = bpy.data.collections.new("Cockpit")
    bpy.context.scene.collection.children.link(col)
    for o in dst.objects:
        if o is not None and o.type == "MESH":
            col.objects.link(o)

    cockpit_maps = maps(os.path.join(args.out, f"{airframe}_Cockpit"))
    for o in col.objects:
        mat = o.material_slots[0].material if o.material_slots else None
        if mat and mat.name.endswith("_Cockpit") and cockpit_maps:
            textured(mat, cockpit_maps)
        if o.name == "HUDGlass" and mat:
            bsdf = mat.node_tree.nodes.get("Principled BSDF")
            bsdf.inputs["Base Color"].default_value = (0.4, 0.8, 0.6, 1)
            bsdf.inputs["Alpha"].default_value = 0.15
    if args.skin and args.textures:
        for set_name in ("Body", "Wings", "Details"):
            mat = bpy.data.materials.get(f"{airframe}_{set_name}")
            m = maps(os.path.join(args.textures, f"{airframe}_{args.skin}_{set_name}"))
            if mat and m:
                textured(mat, m)

    canopy = bpy.data.objects.get("Canopy")
    for o in bpy.data.objects:
        if o.type == "MESH" and o.get("afterburner_kind") in ("Gear", "GearWheel", "GearDoor"):
            o.hide_render = True

    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = args.samples
    try:
        scene.cycles.use_denoising = True
    except Exception:
        pass
    scene.render.resolution_x, scene.render.resolution_y = 1280, 720
    world = scene.world or bpy.data.worlds.new("World")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    bg.inputs["Color"].default_value = (0.55, 0.68, 0.85, 1)
    bg.inputs["Strength"].default_value = 1.0
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
    sun.data.energy = 4.0
    sun.rotation_euler = (math.radians(35), math.radians(-20), math.radians(200))
    scene.collection.objects.link(sun)
    cam = bpy.data.objects.new("EyeCam", bpy.data.cameras.new("EyeCam"))
    scene.collection.objects.link(cam)
    scene.camera = cam
    cam.data.sensor_fit = "VERTICAL"
    cam.data.clip_start = 0.02

    eye_obj = bpy.data.objects.get("ATT_CockpitEye")
    eye = eye_obj.location.copy() if eye_obj else Vector((0, 3.0, 0.8))
    views = [
        ("ahead", eye, eye + Vector((0, 1, 0)), 70, True),
        ("panel", eye, eye + Vector((0, 1, -0.45)), 70, True),
        ("left", eye, eye + Vector((-1, 0.6, -0.5)), 70, True),
        ("outside", eye + Vector((1.6, 1.2, 1.3)), eye + Vector((0, 0.3, -0.2)), 50, False),
    ]
    for name, at, target, fov, inside in views:
        if canopy:
            canopy.hide_render = inside
        cam.location = at
        cam.rotation_euler = (target - at).to_track_quat("-Z", "Y").to_euler()
        cam.data.angle = math.radians(fov)
        scene.render.filepath = os.path.join(args.out, f"{airframe}_cockpit_{name}.png")
        bpy.ops.render.render(write_still=True)
        print("rendered", scene.render.filepath)


if __name__ == "__main__":
    main()
