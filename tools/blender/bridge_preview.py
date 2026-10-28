"""
Afterburner: renders previews of the strait bridge with a skin's tiling textures, over water.

  blender -b tools/blender/out/SevernBridge.blend --python tools/blender/bridge_preview.py -- \
      --out <absolute dir> --textures <dir with the skin PNGs> [--skin Severn]

Writes SevernBridge_<Skin>_{wide,quarter,tower,deck,anchorage}.png.
"""

import argparse
import math
import os
import sys

import bpy
from mathutils import Vector

NAME = "SevernBridge"
SETS = ("Steel", "Concrete", "Road", "Cable")


def set_material(set_name, folder, skin):
    mat = bpy.data.materials.get(f"{NAME}_{set_name}")
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    nodes.clear()
    out = nodes.new("ShaderNodeOutputMaterial")
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    links.new(bsdf.outputs[0], out.inputs["Surface"])

    def tex(kind, colorspace):
        n = nodes.new("ShaderNodeTexImage")
        n.image = bpy.data.images.load(os.path.join(folder, f"{NAME}_{skin}_{set_name}_{kind}.png"))
        n.image.colorspace_settings.name = colorspace
        n.extension = "REPEAT"
        return n

    links.new(tex("Color", "sRGB").outputs["Color"], bsdf.inputs["Base Color"])
    links.new(tex("Roughness", "Non-Color").outputs["Color"], bsdf.inputs["Roughness"])
    links.new(tex("Metalness", "Non-Color").outputs["Color"], bsdf.inputs["Metallic"])
    nmap = nodes.new("ShaderNodeNormalMap")
    links.new(tex("Normal", "Non-Color").outputs["Color"], nmap.inputs["Color"])
    links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])


def light_material():
    mat = bpy.data.materials.new("AviationLight")
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    bsdf = nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (0.9, 0.05, 0.03, 1)
    bsdf.inputs["Emission Color"].default_value = (1.0, 0.05, 0.02, 1)
    bsdf.inputs["Emission Strength"].default_value = 20.0
    return mat


def water():
    me = bpy.data.meshes.new("Water")
    s = 6000
    me.from_pydata([(-s, -s, 0), (s, -s, 0), (s, s, 0), (-s, s, 0)], [], [(0, 1, 2, 3)])
    obj = bpy.data.objects.new("Water", me)
    bpy.context.scene.collection.objects.link(obj)
    mat = bpy.data.materials.new("Water")
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (0.09, 0.11, 0.10, 1)
    bsdf.inputs["Roughness"].default_value = 0.12
    me.materials.append(mat)


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", required=True)
    parser.add_argument("--textures", required=True)
    parser.add_argument("--skin", default="Severn")
    args = parser.parse_args(argv)

    for s in SETS:
        set_material(s, args.textures, args.skin)
    lights = light_material()
    for o in bpy.data.objects:
        if o.get("afterburner_kind") == "Light":
            o.data.materials.clear()
            o.data.materials.append(lights)
    water()

    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 48
    scene.cycles.use_denoising = True
    scene.render.resolution_x, scene.render.resolution_y = 1600, 900
    world = scene.world or bpy.data.worlds.new("World")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    bg.inputs["Color"].default_value = (0.62, 0.72, 0.85, 1)
    bg.inputs["Strength"].default_value = 0.9
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
    sun.data.energy = 3.5
    sun.rotation_euler = (math.radians(55), math.radians(15), math.radians(35))
    scene.collection.objects.link(sun)
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    cam.data.clip_end = 20000
    scene.collection.objects.link(cam)
    scene.camera = cam

    for label, eye, target, lens in (
        ("wide", Vector((1500, -900, 160)), Vector((0, 0, 60)), 35),
        ("quarter", Vector((420, -760, 70)), Vector((0, -494, 70)), 35),
        ("tower", Vector((80, -560, 58)), Vector((0, -494, 80)), 28),
        ("deck", Vector((-4.5, -680, 55)), Vector((0, -300, 70)), 24),
        ("anchorage", Vector((150, -1010, 22)), Vector((0, -820, 22)), 30),
    ):
        cam.data.lens = lens
        cam.location = eye
        cam.rotation_euler = (target - eye).to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = os.path.join(args.out, f"{NAME}_{args.skin}_{label}.png")
        bpy.ops.render.render(write_still=True)
        print("rendered", scene.render.filepath)


if __name__ == "__main__":
    main()
