"""
Afterburner: the experience icon's picture (512 x 512 after compose). The F-22A from the game (its model and
Air Dominance Grey textures, with a glossy clear coat) banked hard in a climbing turn at sunset: the sun low
behind it lighting a hot rim round the airframe, long layered afterburner flames with shock diamonds, vapour
off the wingtips and a spray of flares with smoke trails, over low-poly, flat-shaded hills, mountains and water
with puffy clouds: realistic jet, Roblox-style world, made to look cool (Will). tools/marketing/icon_compose.py
adds the lens flare, glow and wordmark.

  blender -b tools/blender/out/F22A_base.blend --python tools/marketing/icon_render.py -- --out <png> [--size 1024]
      [--samples 96]
"""

import argparse
import math
import os
import random
import sys

import bpy
from mathutils import Euler, Matrix, Vector, noise

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
TEXTURES = os.path.join(ROOT, "tools", "blender", "out", "textures")
SKIN = "AirDominance"

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
parser = argparse.ArgumentParser()
parser.add_argument("--out", required=True)
parser.add_argument("--size", type=int, default=1024)
parser.add_argument("--samples", type=int, default=96)
args = parser.parse_args(argv)

scene = bpy.context.scene
random.seed(7)


def hexcol(h, a=1.0):
    h = h.lstrip("#")
    srgb = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    lin = [c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in srgb]
    return (*lin, a)


# --- The jet: textures, gear up, one transform for the whole aircraft -------------------------------------

def texture(nodes, name, colorspace):
    n = nodes.new("ShaderNodeTexImage")
    n.image = bpy.data.images.load(os.path.join(TEXTURES, name))
    n.image.colorspace_settings.name = colorspace
    return n


for set_name in ("Body", "Wings", "Details"):
    mat = bpy.data.materials.get(f"F22A_{set_name}")
    if not mat:
        continue
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = nodes.get("Principled BSDF")
    base = f"F22A_{SKIN}_{set_name}"
    links.new(texture(nodes, f"{base}_Color.png", "sRGB").outputs["Color"], bsdf.inputs["Base Color"])
    links.new(texture(nodes, f"{base}_Roughness.png", "Non-Color").outputs["Color"], bsdf.inputs["Roughness"])
    links.new(texture(nodes, f"{base}_Metalness.png", "Non-Color").outputs["Color"], bsdf.inputs["Metallic"])
    nmap = nodes.new("ShaderNodeNormalMap")
    links.new(texture(nodes, f"{base}_Normal.png", "Non-Color").outputs["Color"], nmap.inputs["Color"])
    links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])
    if "Coat Weight" in bsdf.inputs:  # a glossy coat that catches the sunset
        bsdf.inputs["Coat Weight"].default_value = 0.6
        bsdf.inputs["Coat Roughness"].default_value = 0.05

glass = bpy.data.materials.get("F22A_Glass")
if glass:
    glass.use_nodes = True
    b = glass.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = hexcol("#b08a3a")  # the Raptor's gold-tinted canopy
    b.inputs["Metallic"].default_value = 0.9
    b.inputs["Roughness"].default_value = 0.08

jet_objects = [o for o in scene.objects if o.type == "MESH"]
for o in jet_objects:
    if o.get("afterburner_kind") in ("Gear", "GearWheel", "GearDoor"):
        o.hide_render = True
    elif o.type == "MESH":
        for p in o.data.polygons:
            p.use_smooth = True

rig = bpy.data.objects.new("JetRig", None)
scene.collection.objects.link(rig)
for o in jet_objects:
    if o.parent is None:
        o.parent = rig
# Hard left bank, nose up, coming towards the camera and off to the left of the frame
rig.rotation_euler = Euler((math.radians(20), math.radians(-60), math.radians(-108)), "XYZ")
bpy.context.view_layer.update()
JET = rig.matrix_world.copy()


def world(p):
    return JET @ Vector(p)


# --- Vapour: tubes that follow the arc of the turn behind each wingtip, fading out ----------------------

def trail_mesh(name, start_local, radius0, radius1, length_angle, turn_radius, segments=60, sides=10):
    """A tube from a point on the jet back along the turn (the jet turns about its own up axis)."""
    verts, faces, alphas = [], [], []
    for i in range(segments + 1):
        t = i / segments
        th = t * length_angle
        # the flight path, in the jet's frame: a circle in the forward/up plane
        offset = Vector((0, -turn_radius * math.sin(th), turn_radius - turn_radius * math.cos(th)))
        centre = world(Vector(start_local) + offset)
        ahead = world(Vector(start_local) + Vector((0, -turn_radius * math.sin(th + 0.01),
                                                       turn_radius - turn_radius * math.cos(th + 0.01))))
        d = (ahead - centre).normalized()
        side = d.cross(Vector((0, 0, 1))).normalized()
        upv = side.cross(d).normalized()
        r = radius0 + (radius1 - radius0) * t
        for k in range(sides):
            a = k / sides * math.tau
            verts.append(centre + (side * math.cos(a) + upv * math.sin(a)) * r)
            alphas.append((1 - t) ** 1.6)
    for i in range(segments):
        for k in range(sides):
            a, b = i * sides + k, i * sides + (k + 1) % sides
            faces.append((a, b, b + sides, a + sides))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata([tuple(v) for v in verts], [], faces)
    attr = mesh.color_attributes.new("Fade", "FLOAT_COLOR", "POINT")
    for i, al in enumerate(alphas):
        attr.data[i].color = (al, al, al, 1)
    obj = bpy.data.objects.new(name, mesh)
    scene.collection.objects.link(obj)
    for p in mesh.polygons:
        p.use_smooth = True
    return obj


vapour = bpy.data.materials.new("Vapour")
vapour.use_nodes = True
vapour.blend_method = "BLEND" if hasattr(vapour, "blend_method") else None
vn, vl = vapour.node_tree.nodes, vapour.node_tree.links
for n in list(vn):
    vn.remove(n)
out = vn.new("ShaderNodeOutputMaterial")
mix = vn.new("ShaderNodeMixShader")
transparent = vn.new("ShaderNodeBsdfTransparent")
glow = vn.new("ShaderNodeEmission")
glow.inputs["Color"].default_value = (1, 0.9, 0.8, 1)
glow.inputs["Strength"].default_value = 2.2
fade = vn.new("ShaderNodeAttribute")
fade.attribute_name = "Fade"
scale = vn.new("ShaderNodeMath")
scale.operation = "MULTIPLY"
scale.inputs[1].default_value = 0.85
vl.new(fade.outputs["Fac"], scale.inputs[0])
vl.new(scale.outputs[0], mix.inputs["Fac"])
vl.new(transparent.outputs[0], mix.inputs[1])
vl.new(glow.outputs[0], mix.inputs[2])
vl.new(mix.outputs[0], out.inputs["Surface"])

for x in (-6.72, 6.72):
    t = trail_mesh("Vapour", (x, -2.3, 0.18), 0.12, 1.6, 1.3, 70)
    t.data.materials.append(vapour)
    t.visible_shadow = False

# Afterburner flames: an orange plume round a white-hot core, with shock diamonds down it
def glow_material(name, colour, strength, alpha):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    b = mat.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = colour
    b.inputs["Emission Color"].default_value = colour
    b.inputs["Emission Strength"].default_value = strength
    b.inputs["Alpha"].default_value = alpha
    return mat


plume = glow_material("Plume", (1, 0.3, 0.04, 1), 4, 0.6)
core = glow_material("Core", (1, 0.7, 0.3, 1), 10, 0.95)
diamond = glow_material("Diamond", (1, 0.9, 0.65, 1), 22, 0.9)
along = JET.to_3x3() @ Euler((math.radians(90), 0, 0)).to_matrix()
for x in (-0.73, 0.73):
    for radius, depth, mat in ((0.48, 5.6, plume), (0.24, 3.8, core)):
        bpy.ops.mesh.primitive_cone_add(radius1=radius, radius2=0.03, depth=depth, vertices=28)
        cone = bpy.context.active_object
        cone.name = "Flame"
        cone.location = world((x, -5.8 - depth / 2, 0.0))
        cone.rotation_euler = along.to_euler()
        cone.data.materials.append(mat)
        cone.visible_shadow = False
    for k, d in enumerate((1.0, 2.0, 2.9)):
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.2 - k * 0.04, segments=16, ring_count=8)
        dot = bpy.context.active_object
        dot.location = world((x, -5.8 - d, 0.0))
        dot.scale = (1, 1, 1.8)
        dot.rotation_euler = along.to_euler()
        dot.data.materials.append(diamond)
        dot.visible_shadow = False
    p = bpy.data.lights.new("FlameLight", "POINT")
    p.energy = 2500
    p.color = (1, 0.5, 0.15)
    pl = bpy.data.objects.new("FlameLight", p)
    pl.location = world((x, -7.0, 0))
    scene.collection.objects.link(pl)

# Flares: bright balls dropping away behind and below the tail (their smoke is added in compose)
flare_mat = glow_material("Flare", (1, 0.8, 0.45, 1), 120, 1.0)
for x, y, z, r in ((-1.8, -10.5, -2.2, 0.42), (1.6, -12.5, -3.4, 0.38), (-3.4, -15.0, -5.2, 0.34),
                   (3.0, -17.0, -6.6, 0.3), (0.2, -19.5, -8.4, 0.28)):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r, segments=16, ring_count=8, location=world((x, y, z)))
    ball = bpy.context.active_object
    ball.data.materials.append(flare_mat)
    ball.visible_shadow = False
    fl = bpy.data.lights.new("FlareLight", "POINT")
    fl.energy = 1200
    fl.color = (1, 0.7, 0.35)
    flo = bpy.data.objects.new("FlareLight", fl)
    flo.location = world((x, y, z))
    scene.collection.objects.link(flo)

# --- The world: low-poly, flat-shaded terrain like the game's ---------------------------------------------

GROUND_Z = -260
CAMERA = Vector((23.0, 20.0, 3.9))
TARGET = Vector((0.0, 1.0, 0.4))
VIEW = Vector((TARGET.x - CAMERA.x, TARGET.y - CAMERA.y, 0)).normalized()  # on the ground, away from the camera


def terrain():
    n, size = 200, 12000
    verts, faces, cols = [], [], []
    for j in range(n + 1):
        for i in range(n + 1):
            x = (i / n - 0.5) * size + CAMERA.x
            y = (j / n - 0.5) * size + CAMERA.y
            ahead = (x - CAMERA.x) * VIEW.x + (y - CAMERA.y) * VIEW.y  # distance out along the view
            h = noise.fractal(Vector((x / 900, y / 900, 0.3)), 0.6, 2.1, 4) * 90
            ridge = max(0.0, (ahead - 2200) / 1800)
            h += min(ridge, 1.6) ** 1.4 * (220 + noise.fractal(Vector((x / 420, y / 420, 1.7)), 0.7, 2.2, 5) * 300)
            verts.append((x + random.uniform(-8, 8), y + random.uniform(-8, 8), GROUND_Z + h))
    for j in range(n):
        for i in range(n):
            a = j * (n + 1) + i
            faces.append((a, a + 1, a + n + 2, a + n + 1))
    mesh = bpy.data.meshes.new("Terrain")
    mesh.from_pydata(verts, [], faces)
    colour = mesh.color_attributes.new("Col", "FLOAT_COLOR", "CORNER")
    greens = ["#5f9e3c", "#6aa843", "#57923a", "#76b04a", "#4f8a35"]
    for poly in mesh.polygons:
        z = sum(mesh.vertices[v].co.z for v in poly.vertices) / len(poly.vertices) - GROUND_Z
        slope = 1 - poly.normal.z
        if z < 8:
            c = "#d9c88f"  # beach sand
        elif z > 640:
            c = "#f2f4f6"  # snow
        elif z > 330 or slope > 0.4:
            c = random.choice(["#8a8a86", "#7d7c78", "#94928c"])  # rock
        else:
            c = random.choice(greens)
        for li in poly.loop_indices:
            colour.data[li].color = hexcol(c)
    obj = bpy.data.objects.new("Terrain", mesh)
    scene.collection.objects.link(obj)
    mat = bpy.data.materials.new("Terrain")
    mat.use_nodes = True
    tb = mat.node_tree.nodes.get("Principled BSDF")
    attr = mat.node_tree.nodes.new("ShaderNodeVertexColor")
    attr.layer_name = "Col"
    mat.node_tree.links.new(attr.outputs["Color"], tb.inputs["Base Color"])
    tb.inputs["Roughness"].default_value = 0.95
    mesh.materials.append(mat)
    return obj


terrain()

# Sea in the low ground, Roblox-blue
bpy.ops.mesh.primitive_plane_add(size=14000, location=(CAMERA.x, CAMERA.y, GROUND_Z + 6))
sea = bpy.context.active_object
sea_mat = bpy.data.materials.new("Sea")
sea_mat.use_nodes = True
sb = sea_mat.node_tree.nodes.get("Principled BSDF")
sb.inputs["Base Color"].default_value = hexcol("#2f86c8")
sb.inputs["Roughness"].default_value = 0.12
sea.data.materials.append(sea_mat)

# Puffy low-poly clouds, as in the game
cloud_mat = bpy.data.materials.new("Cloud")
cloud_mat.use_nodes = True
cb = cloud_mat.node_tree.nodes.get("Principled BSDF")
cb.inputs["Base Color"].default_value = (0.96, 0.97, 1.0, 1)
cb.inputs["Roughness"].default_value = 1.0
SIDE = Vector((-VIEW.y, VIEW.x, 0))
for along, across, cz, s in ((1300, -520, 120, 1.0), (1700, 640, 220, 1.3), (2300, -150, 300, 1.6),
                             (900, 980, 40, 0.8), (2000, -1100, 260, 1.4)):
    spot = CAMERA + VIEW * along + SIDE * across
    cx, cy = spot.x, spot.y
    for k in range(7):
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=random.uniform(40, 75) * s,
                                              location=(cx + random.uniform(-110, 110) * s,
                                                        cy + random.uniform(-40, 40) * s,
                                                        cz + random.uniform(-20, 25) * s))
        blob = bpy.context.active_object
        blob.scale.z = 0.62
        blob.data.materials.append(cloud_mat)

# --- Light, sky, camera, render ----------------------------------------------------------------------------

world_data = scene.world or bpy.data.worlds.new("World")
scene.world = world_data
world_data.use_nodes = True
wn, wl = world_data.node_tree.nodes, world_data.node_tree.links
for n in list(wn):
    wn.remove(n)
coords = wn.new("ShaderNodeTexCoord")
split = wn.new("ShaderNodeSeparateXYZ")
ramp = wn.new("ShaderNodeValToRGB")
ramp.color_ramp.elements[0].position = 0.0
ramp.color_ramp.elements[0].color = hexcol("#ffc27a")  # warm horizon
ramp.color_ramp.elements[1].position = 0.5
ramp.color_ramp.elements[1].color = hexcol("#1a2a6c")  # deep blue overhead
mid = ramp.color_ramp.elements.new(0.1)
mid.color = hexcol("#f07a5a")
high = ramp.color_ramp.elements.new(0.24)
high.color = hexcol("#7a5aa8")
bg = wn.new("ShaderNodeBackground")
bg.inputs["Strength"].default_value = 1.5
wo = wn.new("ShaderNodeOutputWorld")
wl.new(coords.outputs["Generated"], split.inputs[0])
wl.new(split.outputs["Z"], ramp.inputs["Fac"])
wl.new(ramp.outputs["Color"], bg.inputs["Color"])
wl.new(bg.outputs[0], wo.inputs["Surface"])

sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
sun.data.energy = 4.2
sun.data.color = (1.0, 0.72, 0.42)
sun.data.angle = math.radians(1.5)
# Low, from behind the jet towards the camera: a hot rim of light round the airframe
travel = Vector((CAMERA.x - TARGET.x, CAMERA.y - TARGET.y, -0.35)).normalized()
travel = Matrix.Rotation(math.radians(-75), 3, "Z") @ travel  # from the side and behind
sun.rotation_euler = travel.to_track_quat("-Z", "Y").to_euler()
scene.collection.objects.link(sun)

# A soft fill from the camera's side, so the jet's top isn't lost in shadow
fill = bpy.data.objects.new("Fill", bpy.data.lights.new("Fill", "AREA"))
fill.data.energy = 7000
fill.data.size = 30
fill.data.color = (0.65, 0.75, 1.0)  # cool, against the warm sun
fill.location = CAMERA + Vector((0, 0, 12))
fill.rotation_euler = (TARGET - fill.location).to_track_quat("-Z", "Y").to_euler()
scene.collection.objects.link(fill)

cam = bpy.data.objects.new("IconCam", bpy.data.cameras.new("IconCam"))
cam.data.lens = 50
cam.data.clip_end = 20000
scene.collection.objects.link(cam)
scene.camera = cam
cam.location = CAMERA
cam.rotation_euler = (TARGET - CAMERA).to_track_quat("-Z", "Y").to_euler()
# Shift the jet down in the frame, leaving sky at the top for the wordmark
cam.data.shift_y = 0.12

scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.cycles.samples = args.samples
try:
    scene.cycles.use_denoising = True
except Exception:
    pass
scene.view_settings.view_transform = "AgX" if "AgX" in [v for v in ("AgX",)] else scene.view_settings.view_transform
try:
    scene.view_settings.look = "AgX - High Contrast"
except Exception:
    pass
scene.view_settings.exposure = 0.0
scene.render.resolution_x = scene.render.resolution_y = args.size
scene.render.film_transparent = False
scene.render.filepath = args.out
bpy.ops.render.render(write_still=True)
print("rendered", args.out)
