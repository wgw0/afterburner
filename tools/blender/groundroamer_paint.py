"""
Afterburner: paints the Ground Roamer (groundroamer_generate.py): its Body, Canvas and Details texture sets,
with the jets' baking (f5e_paint.py: world position, normal, part and AO baked per texel, then painted here).

  Body     paint with door shut lines, the waist crease, rivet rows along the cappings and wing tops,
           galvanised top cappings, hinges, dust on the flat tops and mud thrown up low down
  Canvas   the tilt: woven canvas, stitched seams, stains and dust
  Details  chassis and bumper (black, rust at the edges), tyres (rubber with a tread in the normal map),
           steel rims and hubs, lamps (lenses, chrome rims, indicators), the grille's slats, the cab

The badge and number plates (the Decals set) are drawn by groundroamer_decals.py.

  blender -b tools/blender/out/GroundRoamer.blend --python tools/blender/groundroamer_paint.py -- \
      --out <absolute dir> [--skin BronzeGreen] [--preview]
"""

import argparse
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import groundroamer_generate as gr  # noqa: E402  (sets the shared generator module to the Ground Roamer)
import f5e_paint as paint  # noqa: E402  (baking, noise and output helpers)

srgb = paint.srgb
fbm = paint.fbm
smooth = paint.smooth
groove = paint.groove

SETS = {"Body": 1024, "Canvas": 512, "Details": 1024}

SKINS = {
    # Bronze green with an olive canvas tilt (the army's colours)
    "BronzeGreen": {"paint": srgb(70, 80, 62), "canvas": srgb(96, 98, 76), "rim": srgb(70, 80, 62)},
    # Desert sand
    "Sand": {"paint": srgb(184, 164, 124), "canvas": srgb(170, 152, 114), "rim": srgb(184, 164, 124)},
    # Pastel green with a black hood and pale rims
    "PastelGreen": {"paint": srgb(148, 166, 136), "canvas": srgb(38, 38, 38), "rim": srgb(222, 222, 208)},
    # Red with a black hood and pale rims
    "Red": {"paint": srgb(146, 38, 32), "canvas": srgb(38, 38, 38), "rim": srgb(222, 222, 208)},
}

MUD = srgb(96, 78, 56)
DUST = srgb(150, 136, 110)
BLACK = srgb(26, 26, 26)
RUBBER = srgb(30, 30, 30)
GALV = srgb(150, 152, 150)
RUST = srgb(110, 64, 38)


def lines(values, centres, width):
    out = np.zeros_like(values)
    for c in centres:
        out = np.maximum(out, groove(values - c, width))
    return out


def grime(P, N, z):
    """Mud low down (thrown up by the wheels), dust on the flat tops: (mud, dust) amounts 0..1."""
    splash = fbm(P, 6.0, 4, seed=5)
    mud = smooth(0.95, 0.35, z) * np.clip(0.4 + 0.9 * (splash - 0.45), 0, 1)
    dust = np.clip(N[..., 2], 0, 1) ** 2 * np.clip(0.25 + 0.5 * fbm(P, 2.0, 3, seed=9), 0, 1)
    return np.clip(mud, 0, 1), np.clip(dust, 0, 0.6)


def paint_body(P, N, part, ids, ao, s):
    x, y, z = P[..., 0], P[..., 1], P[..., 2]
    ax = np.abs(x)
    side = np.abs(N[..., 0]) > 0.6
    up = N[..., 2] > 0.6
    colour = np.broadcast_to(s["paint"], P.shape).copy()
    colour *= (0.95 + 0.08 * fbm(P, 3.0, 4, seed=1))[..., None]
    # Panel lines: door shut lines, the wing joint and the waist
    seam = np.zeros_like(x)
    seam = np.maximum(seam, side * lines(y, [gr.BULKHEAD - 0.06, gr.DOOR_REAR + 0.01], 0.006) * (z < gr.CAPPING) * (z > 0.5))
    seam = np.maximum(seam, side * groove(z - (gr.CAPPING - 0.01), 0.008))
    seam = np.maximum(seam, up * lines(ax, [gr.WING_IN], 0.008) * (y > gr.BULKHEAD))  # bonnet edges
    # Rivets along the tub cappings and the wing tops
    riv = paint.rivets(z - (gr.CAPPING - 0.03), y, 0.07, 0.006) * side * (y < -0.1)
    riv = np.maximum(riv, paint.rivets(ax - (gr.HALF_W - 0.03), y, 0.07, 0.006) * up * (y > gr.BULKHEAD))
    # Galvanised top cappings of the tub
    capping = (z > gr.CAPPING - 0.045) & (y < gr.DOOR_REAR) & ((ax > gr.HALF_W - 0.075) | (y < gr.REAR + 0.065))
    colour = np.where(capping[..., None], GALV * (0.9 + 0.15 * fbm(P, 8.0, 2, seed=3))[..., None], colour)
    # Hinges on the front of the doors
    mud, dust = grime(P, N, z)
    colour = colour * (1 - mud[..., None]) + MUD * mud[..., None]
    colour = colour * (1 - dust[..., None]) + DUST * dust[..., None]
    colour *= (1 - 0.5 * seam)[..., None]
    colour *= (0.75 + 0.25 * ao)[..., None]
    rough = 0.55 + 0.25 * mud + 0.2 * dust - 0.2 * capping
    metal = 0.6 * capping
    height = -0.4 * seam + 0.6 * riv
    return colour, rough, metal, height


def paint_canvas(P, N, part, ids, ao, s):
    x, y, z = P[..., 0], P[..., 1], P[..., 2]
    weave = 0.5 + 0.5 * np.sin(x * 900) * np.sin(y * 900 + z * 900)
    colour = np.broadcast_to(s["canvas"], P.shape).copy()
    colour *= (0.9 + 0.12 * fbm(P, 2.5, 4, seed=21) + 0.03 * weave)[..., None]
    # Stitched seams: the cab and rear sections, the roof edges, the rolled-up rear flap
    seam = lines(y, [-0.10, gr.REAR + 0.15], 0.02) + lines(z, [gr.ROOF - 0.08, gr.CAPPING + 0.06], 0.02)
    stitch = np.clip(seam, 0, 1) * (np.sin(np.maximum(np.abs(y), np.abs(x)) * 400) > 0.3)
    stains = np.clip((fbm(P, 1.5, 3, seed=23) - 0.55) * 2.0, 0, 1) * 0.4
    mud, dust = grime(P, N, z)
    colour *= (1 - 0.25 * np.clip(seam, 0, 1) - stains)[..., None]
    colour = colour * (1 - dust[..., None]) + DUST * dust[..., None]
    colour *= (0.8 + 0.2 * ao)[..., None]
    rough = np.full_like(x, 0.92)
    metal = np.zeros_like(x)
    height = 0.15 * weave - 0.5 * np.clip(seam, 0, 1) + 0.3 * stitch
    return colour, rough, metal, height


def paint_details(P, N, part, ids, ao, s):
    x, y, z = P[..., 0], P[..., 1], P[..., 2]
    colour = np.broadcast_to(BLACK, P.shape).copy()
    rough = np.full_like(x, 0.6)
    metal = np.zeros_like(x)
    height = np.zeros_like(x)

    def on(*names):
        m = np.zeros_like(x, dtype=bool)
        for n in names:
            if n in ids:
                m |= part == ids[n]
        return m

    # Chassis and bumper: black, with rust at the edges and mud
    ch = on("Chassis")
    rust = np.clip((fbm(P, 12.0, 3, seed=31) - 0.72) * 3, 0, 0.35)
    mud, _ = grime(P, N, z)
    mud = mud * 0.35
    c = BLACK * (1 + 0.4 * fbm(P, 5.0, 3, seed=33))[..., None]
    c = c * (1 - rust[..., None]) + RUST * rust[..., None]
    c = c * (1 - mud[..., None]) + MUD * mud[..., None]
    colour = np.where(ch[..., None], c, colour)
    rough = np.where(ch, 0.55 + 0.3 * rust, rough)

    # Wheels and the spare: rubber tyre with a tread, painted steel rim, hub nuts
    for name, (wx, wy) in list(gr.WHEELS.items()) + [("Spare", gr.SPARE[:2])]:
        m = on(f"Wheel{name}" if name != "Spare" else "SpareWheel")
        if name == "Spare":
            cz = gr.SPARE[2]
            r = np.hypot(x - wx, y - wy)
            ang = np.arctan2(y - wy, x - wx)
            across = z - cz
        else:
            r = np.hypot(y - wy, z - gr.TYRE_R)
            ang = np.arctan2(z - gr.TYRE_R, y - wy)
            across = x - wx
        tyre = m & (r > 0.229)
        tread_face = tyre & (r > gr.TYRE_R - 0.03)
        lugs = (np.sin(ang * 22 + np.sign(across) * 2.0) > 0.1) & (np.abs(across) < gr.TYRE_W * 0.47)
        colour = np.where(tyre[..., None], RUBBER * (0.9 + 0.2 * fbm(P, 20.0, 2, seed=41))[..., None], colour)
        colour = np.where((tyre & (r < gr.TYRE_R - 0.03))[..., None], colour * 1.15, colour)  # sidewall
        height = np.where(tread_face, np.where(lugs, 1.0, -1.0), height)
        rough = np.where(tyre, 0.9, rough)
        rim = m & (r <= 0.229)
        nuts = rim & (np.abs(r - 0.10) < 0.012) & (np.sin(ang * 5) > 0.92)
        colour = np.where(rim[..., None], s["rim"] * (0.9 + 0.1 * fbm(P, 10.0, 2, seed=43))[..., None], colour)
        colour = np.where(nuts[..., None], GALV, colour)
        height = np.where(rim, 0.4 * nuts - 0.3 * (np.abs(r - 0.17) < 0.006), height)
        rough = np.where(rim, 0.5, rough)

    # Lamps, grille, mirrors, wipers
    lamps = on("Lamps")
    dl = np.hypot(np.abs(x) - gr.LAMP_X, z - gr.LAMP_Z)
    at_lamp = lamps & (y > gr.WING_FRONT - 0.08) & (dl < gr.LAMP_R + 0.012)
    lens = at_lamp & (dl < gr.LAMP_R - 0.018) & (N[..., 1] > 0.3)
    chrome = at_lamp & ~lens & (dl > gr.LAMP_R - 0.03)
    indicator = lamps & (np.hypot(np.abs(x) - 0.775, z - 0.70) < 0.036) & (y > gr.WING_FRONT - 0.01)
    sidelamp = lamps & (np.hypot(np.abs(x) - 0.775, z - 0.98) < 0.034) & (y > gr.WING_FRONT - 0.01)
    rear = lamps & (y < gr.REAR + 0.01) & (z > 0.76) & (z < 1.0)
    rear_amber = rear & (z > 0.92)
    grille = lamps & (np.abs(x) < 0.32) & (y > gr.WING_FRONT - 0.045) & (z > 0.61) & (z < 0.99)
    colour = np.where(chrome[..., None], srgb(200, 200, 196), colour)
    colour = np.where(lens[..., None], srgb(232, 232, 220), colour)
    colour = np.where(indicator[..., None], srgb(236, 120, 30), colour)
    colour = np.where(sidelamp[..., None], srgb(236, 236, 228), colour)
    colour = np.where(rear[..., None], srgb(170, 24, 20), colour)
    colour = np.where(rear_amber[..., None], srgb(236, 120, 30), colour)
    slats = grille & (y > gr.WING_FRONT - 0.021)
    colour = np.where(grille[..., None], np.where(slats[..., None], srgb(178, 178, 172), srgb(40, 40, 40)), colour)
    height = np.where(grille, np.where(slats, 1.0, -1.0), height)
    height = np.where(lens, 0.5 * np.sin(dl * 260), height)  # the reflector's rings behind the glass
    rough = np.where(chrome | lens, 0.15, rough)
    metal = np.where(chrome, 0.9, metal)

    # Cab: dark grey dashboard, black seats and wheel
    cab = on("Cab")
    colour = np.where(cab[..., None], srgb(46, 46, 46) * (0.9 + 0.2 * fbm(P, 6.0, 3, seed=51))[..., None], colour)
    rough = np.where(cab, 0.7, rough)

    colour *= (0.7 + 0.3 * ao)[..., None]
    return colour, rough, metal, height


PAINTERS = {"Body": paint_body, "Canvas": paint_canvas, "Details": paint_details}


def render_preview(out_dir, prefix):
    import bpy
    from mathutils import Vector

    scene = bpy.context.scene
    scene.cycles.samples = 64
    scene.render.resolution_x, scene.render.resolution_y = 1600, 1000
    world = scene.world
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    bg.inputs["Color"].default_value = (0.55, 0.68, 0.85, 1)
    bg.inputs["Strength"].default_value = 0.8
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
    sun.data.energy = 4.0
    sun.rotation_euler = (math.radians(50), math.radians(10), math.radians(140))
    scene.collection.objects.link(sun)
    me = bpy.data.meshes.new("Ground")
    me.from_pydata([(-20, -20, 0), (20, -20, 0), (20, 20, 0), (-20, 20, 0)], [], [(0, 1, 2, 3)])
    ground = bpy.data.objects.new("Ground", me)
    scene.collection.objects.link(ground)
    gm = bpy.data.materials.new("Ground")
    gm.use_nodes = True
    gm.node_tree.nodes.get("Principled BSDF").inputs["Base Color"].default_value = (0.18, 0.2, 0.12, 1)
    me.materials.append(gm)
    cam = bpy.data.objects.new("PaintCam", bpy.data.cameras.new("PaintCam"))
    scene.collection.objects.link(cam)
    scene.camera = cam
    cam.data.lens = 50
    for name, eye, target in (
        ("front", Vector((5.0, 7.0, 2.4)), Vector((0, 0.3, 0.9))),
        ("rear", Vector((-4.5, -6.5, 2.8)), Vector((0, -0.3, 0.9))),
        ("side", Vector((8.5, 0.2, 1.4)), Vector((0, 0.1, 0.9))),
        ("close", Vector((2.2, 3.4, 1.4)), Vector((0.2, 1.4, 0.9))),
    ):
        cam.location = eye
        cam.rotation_euler = (target - eye).to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = os.path.join(out_dir, f"{prefix}_paint_{name}.png")
        bpy.ops.render.render(write_still=True)
        print("rendered", scene.render.filepath)


def main():
    import bpy

    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", required=True)
    parser.add_argument("--skin", default="BronzeGreen")
    parser.add_argument("--preview", action="store_true")
    parser.add_argument("--decals", default=None, help="folder with GroundRoamer_Decals_Color.png, for the preview")
    args = parser.parse_args(argv)
    os.makedirs(args.out, exist_ok=True)
    s = SKINS[args.skin]

    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.render.bake.margin_type = "EXTEND"
    world = scene.world or bpy.data.worlds.new("World")
    scene.world = world
    world.light_settings.distance = 0.2

    written = {}
    for set_name, size in SETS.items():
        maps, ids, objs = paint.bake_maps(set_name, size * paint.SUPERSAMPLE)
        P, N, part, ao, valid = maps["P"], maps["N"], maps["ID"], maps["AO"], maps["valid"]
        colour, rough, metal, height = PAINTERS[set_name](P, N, part, ids, ao, s)
        fill = s["canvas"] if set_name == "Canvas" else (s["paint"] if set_name == "Body" else BLACK)
        colour = np.where(valid[..., None], colour, fill)
        rough, metal, height = np.where(valid, rough, 0.6), np.where(valid, metal, 0), np.where(valid, height, 0)
        base = os.path.join(args.out, f"GroundRoamer_{args.skin}_{set_name}")
        paths = {m: f"{base}_{m}.png" for m in ("Color", "Roughness", "Metalness", "Normal")}
        paint.save_png(paths["Color"], paint.to_srgb(paint.downsample(colour)), "sRGB")
        paint.save_png(paths["Roughness"], paint.downsample(rough), "Non-Color")
        paint.save_png(paths["Metalness"], paint.downsample(metal), "Non-Color")
        paint.bake_normal(set_name, objs, height.astype(np.float32), size, paths["Normal"])
        written[set_name] = paths
        print(f"painted {set_name}: {size}px, {len(objs)} parts")

    if args.preview:
        for set_name, paths in written.items():
            paint.apply_preview_material(set_name, paths)
        if args.decals:
            decal = os.path.join(args.decals, "GroundRoamer_Decals_Color.png")
            if os.path.exists(decal):
                mat = bpy.data.materials.get("GroundRoamer_Decals")
                nodes, links = mat.node_tree.nodes, mat.node_tree.links
                tex = nodes.new("ShaderNodeTexImage")
                tex.image = bpy.data.images.load(decal)
                links.new(tex.outputs["Color"], nodes.get("Principled BSDF").inputs["Base Color"])
        render_preview(args.out, f"GroundRoamer_{args.skin}")


if __name__ == "__main__":
    main()
