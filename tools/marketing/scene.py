"""
Afterburner marketing: the world shared by the cover (cover_render.py) and the trailer (trailer_render.py), run
inside Blender. The game's own jets (their models and skins from tools/blender/out) flown along scripted paths
over a low-poly, flat-shaded valley ringed by mountains, the icon's look: realistic jets, Roblox-style world.

Everything here is in metres, Z up; a jet's model faces +Y with +X to its right.
"""

import math
import os
import random

import bpy
from mathutils import Matrix, Vector, noise

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(ROOT, "tools", "blender", "out")
TEXTURES = os.path.join(OUT, "textures")
G = 9.81
MISSILE_SCALE = 3  # drawn at 3x, as in the game, so they read on screen


def hexcol(h, a=1.0):
    h = h.lstrip("#")
    srgb = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    lin = [c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in srgb]
    return (*lin, a)


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    random.seed(7)
    return bpy.context.scene


# --- Flight paths -----------------------------------------------------------------------------------------

def frame_of(path, t, h=1 / 120):
    """Position and orientation (a 3x3 matrix: right, forward, up as columns) of a path at time t. The jet
    banks so its lift (up) points along its acceleration plus gravity, as in a coordinated turn."""
    p0, p1, p2 = path(t - h), path(t), path(t + h)
    vel = (p2 - p0) / (2 * h)
    acc = (p2 - 2 * p1 + p0) / (h * h)
    fwd = vel.normalized()
    lift = acc + Vector((0, 0, G))
    up = (lift - fwd * lift.dot(fwd)).normalized()
    right = fwd.cross(up).normalized()
    m = Matrix((right, fwd, up)).transposed()
    return p1, m, vel


def world_matrix(path, t):
    p, m, _ = frame_of(path, t)
    return Matrix.Translation(p) @ m.to_4x4()


# --- Jets -------------------------------------------------------------------------------------------------

def _texture(nodes, name, colorspace):
    n = nodes.new("ShaderNodeTexImage")
    n.image = bpy.data.images.load(os.path.join(TEXTURES, name), check_existing=True)
    n.image.colorspace_settings.name = colorspace
    return n


class Jet:
    """One of the game's jets in a skin, all its parts under one empty (self.rig)."""

    def __init__(self, scene, airframe, skin, canopy="#3a4a5a", flames=True):
        self.airframe = airframe
        with bpy.data.libraries.load(os.path.join(OUT, f"{airframe}_base.blend"), link=False) as (src, dst):
            dst.objects = [n for n in src.objects]
        self.rig = bpy.data.objects.new(f"{airframe}_Rig", None)
        scene.collection.objects.link(self.rig)
        parts = []
        for o in dst.objects:
            if o is None or o.type != "MESH":
                continue
            scene.collection.objects.link(o)
            if o.get("afterburner_kind") in ("Gear", "GearWheel", "GearDoor"):
                o.hide_render = o.hide_viewport = True
                continue
            for p in o.data.polygons:
                p.use_smooth = True
            parts.append(o)
        bpy.context.view_layer.update()
        # Wingtips (the outermost points) and nozzles (the rear of the afterburner cans), in the jet's frame
        tip = max((o.matrix_world @ v.co for o in parts for v in o.data.vertices), key=lambda c: c.x)
        self.wingtips = [Vector((tip.x, tip.y, tip.z)), Vector((-tip.x, tip.y, tip.z))]
        self.nozzles = []
        for o in parts:
            if o.get("afterburner_kind") == "Afterburner":
                corners = [o.matrix_world @ Vector(c) for c in o.bound_box]
                mid = sum(corners, Vector()) / 8
                self.nozzles.append((Vector((mid.x, min(c.y for c in corners), mid.z)),
                                     max(c.x for c in corners) - min(c.x for c in corners)))
        if not self.nozzles:  # single-engine fallback: the rear of the fuselage
            back = min((o.matrix_world @ v.co for o in parts for v in o.data.vertices), key=lambda c: c.y)
            self.nozzles = [(Vector((0, back.y, back.z)), 0.9)]
        for o in parts:
            if o.parent is None:
                o.parent = self.rig
        self._paint(skin, canopy)
        if flames:
            self._flames(scene)

    def _paint(self, skin, canopy):
        for set_name in ("Body", "Wings", "Details"):
            mat = bpy.data.materials.get(f"{self.airframe}_{set_name}")
            if not mat:
                continue
            mat.use_nodes = True
            nodes, links = mat.node_tree.nodes, mat.node_tree.links
            bsdf = nodes.get("Principled BSDF")
            base = f"{self.airframe}_{skin}_{set_name}"
            links.new(_texture(nodes, f"{base}_Color.png", "sRGB").outputs["Color"], bsdf.inputs["Base Color"])
            links.new(_texture(nodes, f"{base}_Roughness.png", "Non-Color").outputs["Color"],
                      bsdf.inputs["Roughness"])
            links.new(_texture(nodes, f"{base}_Metalness.png", "Non-Color").outputs["Color"],
                      bsdf.inputs["Metallic"])
            nmap = nodes.new("ShaderNodeNormalMap")
            links.new(_texture(nodes, f"{base}_Normal.png", "Non-Color").outputs["Color"], nmap.inputs["Color"])
            links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])
        glass = bpy.data.materials.get(f"{self.airframe}_Glass")
        if glass:
            glass.use_nodes = True
            b = glass.node_tree.nodes.get("Principled BSDF")
            b.inputs["Base Color"].default_value = hexcol(canopy)
            b.inputs["Metallic"].default_value = 0.9
            b.inputs["Roughness"].default_value = 0.08

    def _flames(self, scene):
        flame = bpy.data.materials.get("Flame") or _flame_material()
        for nozzle, width in self.nozzles:
            r = width * 0.42
            depth = 3.4 * r / 0.36
            bpy.ops.mesh.primitive_cone_add(radius1=r, radius2=r * 0.1, depth=depth, vertices=24)
            cone = bpy.context.active_object
            cone.name = f"{self.airframe}_Flame"
            cone.parent = self.rig
            cone.location = nozzle + Vector((0, -depth / 2, 0))
            cone.rotation_euler = (math.radians(90), 0, 0)
            cone.data.materials.append(flame)
            cone.visible_shadow = False
            light = bpy.data.objects.new("FlameLight", bpy.data.lights.new("FlameLight", "POINT"))
            light.data.energy = 900
            light.data.use_shadow = False
            light.data.color = (1, 0.55, 0.2)
            light.parent = self.rig
            light.location = nozzle + Vector((0, -0.9, 0))
            scene.collection.objects.link(light)

    def place(self, matrix):
        self.rig.matrix_world = matrix

    def wingtips_world(self):
        return [self.rig.matrix_world @ w for w in self.wingtips]


def _flame_material():
    flame = bpy.data.materials.new("Flame")
    flame.use_nodes = True
    fb = flame.node_tree.nodes.get("Principled BSDF")
    fb.inputs["Base Color"].default_value = (1, 0.45, 0.1, 1)
    fb.inputs["Emission Color"].default_value = (1, 0.32, 0.04, 1)
    fb.inputs["Emission Strength"].default_value = 7
    fb.inputs["Alpha"].default_value = 0.85
    return flame


def missile(scene, kind="Sidewinder"):
    """A missile model (3x scale, as in the game) under its own empty, pointing +Y."""
    with bpy.data.libraries.load(os.path.join(OUT, "Missiles.blend"), link=False) as (src, dst):
        dst.objects = [n for n in src.objects if n.startswith(kind + "_")]
    rig = bpy.data.objects.new(f"{kind}_Rig", None)
    scene.collection.objects.link(rig)
    body = bpy.data.materials.new("MissileBody")
    body.use_nodes = True
    bb = body.node_tree.nodes.get("Principled BSDF")
    bb.inputs["Base Color"].default_value = hexcol("#e8e8e4")
    bb.inputs["Roughness"].default_value = 0.4
    trim = bpy.data.materials.new("MissileTrim")
    trim.use_nodes = True
    tb = trim.node_tree.nodes.get("Principled BSDF")
    tb.inputs["Base Color"].default_value = hexcol("#4a4f55")
    tb.inputs["Roughness"].default_value = 0.5
    for o in dst.objects:
        scene.collection.objects.link(o)
        o.data.materials.clear()
        o.data.materials.append(trim if o.name.endswith("Trim") else body)
        o.parent = rig
        o.location = (0, 0, 0)
    rig.scale = (MISSILE_SCALE,) * 3
    # The motor's glow
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.22, location=(0, -1.55, 0))
    glow = bpy.context.active_object
    glow.parent = rig
    glow.data.materials.append(_flame_material() if not bpy.data.materials.get("Flame") else
                               bpy.data.materials["Flame"])
    glow.scale = (1, 2.2, 1)
    glow.visible_shadow = False
    return rig


# --- Trails: tubes through a history of points, thickening and fading with age ----------------------------

def trail_material(name, colour, lit, opacity):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    if hasattr(mat, "surface_render_method"):
        mat.surface_render_method = "BLENDED"
    elif hasattr(mat, "blend_method"):
        mat.blend_method = "BLEND"
    vn, vl = mat.node_tree.nodes, mat.node_tree.links
    for n in list(vn):
        vn.remove(n)
    out = vn.new("ShaderNodeOutputMaterial")
    mix = vn.new("ShaderNodeMixShader")
    transparent = vn.new("ShaderNodeBsdfTransparent")
    if lit:
        shade = vn.new("ShaderNodeBsdfDiffuse")
        shade.inputs["Color"].default_value = hexcol(colour)
    else:
        shade = vn.new("ShaderNodeEmission")
        shade.inputs["Color"].default_value = hexcol(colour)
        shade.inputs["Strength"].default_value = 1.3
    fade = vn.new("ShaderNodeAttribute")
    fade.attribute_name = "Fade"
    scale = vn.new("ShaderNodeMath")
    scale.operation = "MULTIPLY"
    scale.inputs[1].default_value = opacity
    vl.new(fade.outputs["Fac"], scale.inputs[0])
    vl.new(scale.outputs[0], mix.inputs["Fac"])
    vl.new(transparent.outputs[0], mix.inputs[1])
    vl.new(shade.outputs[0], mix.inputs[2])
    vl.new(mix.outputs[0], out.inputs["Surface"])
    return mat


class Trail:
    """A tube object whose mesh is rebuilt from (point, age) samples, newest first."""

    def __init__(self, scene, name, material, r0, r1, life, sides=10, power=1.6):
        self.obj = bpy.data.objects.new(name, bpy.data.meshes.new(name))
        self.obj.data.materials.append(material)
        self.obj.visible_shadow = False
        scene.collection.objects.link(self.obj)
        self.r0, self.r1, self.life, self.sides, self.power = r0, r1, life, sides, power

    def build(self, samples):
        samples = [(p, a) for p, a in samples if a <= self.life]
        verts, faces, fades = [], [], []
        if len(samples) >= 2:
            for i, (p, age) in enumerate(samples):
                j = min(i + 1, len(samples) - 1)
                k = max(i - 1, 0)
                d = (samples[k][0] - samples[j][0])
                d = d.normalized() if d.length > 1e-6 else Vector((0, 1, 0))
                side = d.cross(Vector((0, 0, 1)))
                side = side.normalized() if side.length > 1e-6 else Vector((1, 0, 0))
                upv = side.cross(d).normalized()
                t = age / self.life
                r = self.r0 + (self.r1 - self.r0) * t
                for s in range(self.sides):
                    a = s / self.sides * math.tau
                    verts.append(tuple(p + (side * math.cos(a) + upv * math.sin(a)) * r))
                    fades.append((1 - t) ** self.power * min(1.0, i / 3))
            n = self.sides
            for i in range(len(samples) - 1):
                for s in range(n):
                    a, b = i * n + s, i * n + (s + 1) % n
                    faces.append((a, b, b + n, a + n))
        mesh = bpy.data.meshes.new(self.obj.name)
        mesh.from_pydata(verts, [], faces)
        attr = mesh.color_attributes.new("Fade", "FLOAT_COLOR", "POINT")
        for i, f in enumerate(fades):
            attr.data[i].color = (f, f, f, 1)
        for p in mesh.polygons:
            p.use_smooth = True
        mesh.materials.append(self.obj.data.materials[0])
        old = self.obj.data
        self.obj.data = mesh
        bpy.data.meshes.remove(old)


# --- The world --------------------------------------------------------------------------------------------

MOUNTAINS_FROM = 2600  # metres from the middle of the valley


def ground_height(x, y):
    dist = math.hypot(x, y)
    h = noise.fractal(Vector((x / 900, y / 900, 0.3)), 0.6, 2.1, 4) * 90 + 30
    ridge = max(0.0, (dist - MOUNTAINS_FROM) / 1700)
    h += min(ridge, 1.7) ** 1.4 * (260 + noise.fractal(Vector((x / 700, y / 700, 1.7)), 0.6, 2.1, 4) * 300)
    return h


def build_world(scene, size=14000, n=230):
    verts, faces = [], []
    for j in range(n + 1):
        for i in range(n + 1):
            x = (i / n - 0.5) * size
            y = (j / n - 0.5) * size
            verts.append((x + random.uniform(-8, 8), y + random.uniform(-8, 8), ground_height(x, y)))
    for j in range(n):
        for i in range(n):
            a = j * (n + 1) + i
            faces.append((a, a + 1, a + n + 2, a + n + 1))
    mesh = bpy.data.meshes.new("Terrain")
    mesh.from_pydata(verts, [], faces)
    colour = mesh.color_attributes.new("Col", "FLOAT_COLOR", "CORNER")
    greens = ["#5f9e3c", "#6aa843", "#57923a", "#76b04a", "#4f8a35"]
    for poly in mesh.polygons:
        z = sum(mesh.vertices[v].co.z for v in poly.vertices) / len(poly.vertices)
        slope = 1 - poly.normal.z
        if z < 10:
            c = "#d9c88f"  # beach sand
        elif z > 720:
            c = "#f2f4f6"  # snow
        elif z > 380 or slope > 0.4:
            c = random.choice(["#8a8a86", "#7d7c78", "#94928c"])  # rock
        else:
            c = random.choice(greens)
        for li in poly.loop_indices:
            colour.data[li].color = hexcol(c)
    terrain = bpy.data.objects.new("Terrain", mesh)
    scene.collection.objects.link(terrain)
    mat = bpy.data.materials.new("Terrain")
    mat.use_nodes = True
    tb = mat.node_tree.nodes.get("Principled BSDF")
    attr = mat.node_tree.nodes.new("ShaderNodeVertexColor")
    attr.layer_name = "Col"
    mat.node_tree.links.new(attr.outputs["Color"], tb.inputs["Base Color"])
    tb.inputs["Roughness"].default_value = 0.95
    mesh.materials.append(mat)

    # Water in the low ground, Roblox-blue
    bpy.ops.mesh.primitive_plane_add(size=size, location=(0, 0, 4))
    sea = bpy.context.active_object
    sea_mat = bpy.data.materials.new("Sea")
    sea_mat.use_nodes = True
    sb = sea_mat.node_tree.nodes.get("Principled BSDF")
    sb.inputs["Base Color"].default_value = hexcol("#2f86c8")
    sb.inputs["Roughness"].default_value = 0.12
    sea.data.materials.append(sea_mat)

    # Puffy low-poly clouds scattered through the valley at about the height the jets fly, for a sense of speed
    cloud_mat = bpy.data.materials.new("Cloud")
    cloud_mat.use_nodes = True
    cb = cloud_mat.node_tree.nodes.get("Principled BSDF")
    cb.inputs["Base Color"].default_value = (0.96, 0.97, 1.0, 1)
    cb.inputs["Roughness"].default_value = 1.0
    rng = random.Random(11)
    for _ in range(26):
        ang = rng.uniform(0, math.tau)
        dist = rng.uniform(600, 3600)
        if 850 < dist < 1350:  # keep the jets' circle clear, so no cloud swallows them
            dist += 600
        cx, cy = math.cos(ang) * dist, math.sin(ang) * dist
        cz = rng.uniform(560, 900)
        s = rng.uniform(0.7, 1.5)
        for _k in range(7):
            bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=rng.uniform(40, 75) * s,
                                                  location=(cx + rng.uniform(-110, 110) * s,
                                                            cy + rng.uniform(-40, 40) * s,
                                                            cz + rng.uniform(-20, 25) * s))
            blob = bpy.context.active_object
            blob.scale.z = 0.62
            blob.data.materials.append(cloud_mat)

    # Sky and sun
    world_data = scene.world or bpy.data.worlds.new("World")
    scene.world = world_data
    world_data.use_nodes = True
    wn, wl = world_data.node_tree.nodes, world_data.node_tree.links
    for node in list(wn):
        wn.remove(node)
    coords = wn.new("ShaderNodeTexCoord")
    split = wn.new("ShaderNodeSeparateXYZ")
    ramp = wn.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.0
    ramp.color_ramp.elements[0].color = hexcol("#bfe0f7")
    ramp.color_ramp.elements[1].position = 0.45
    ramp.color_ramp.elements[1].color = hexcol("#1f63c9")
    ramp.color_ramp.elements.new(0.12).color = hexcol("#7fbcef")
    bg = wn.new("ShaderNodeBackground")
    bg.inputs["Strength"].default_value = 1.0
    wo = wn.new("ShaderNodeOutputWorld")
    wl.new(coords.outputs["Generated"], split.inputs[0])
    wl.new(split.outputs["Z"], ramp.inputs["Fac"])
    wl.new(ramp.outputs["Color"], bg.inputs["Color"])
    wl.new(bg.outputs[0], wo.inputs["Surface"])

    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
    sun.data.energy = 3.6
    sun.data.angle = math.radians(2)
    sun.rotation_euler = (math.radians(45), 0, math.radians(130))
    scene.collection.objects.link(sun)


def camera(scene, lens=50):
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    cam.data.lens = lens
    cam.data.clip_start = 0.5
    cam.data.clip_end = 20000
    scene.collection.objects.link(cam)
    scene.camera = cam
    return cam


def aim(cam, location, target, up=Vector((0, 0, 1))):
    """Points the camera from location at target, with `up` as the top of the frame."""
    fwd = (target - location).normalized()
    right = fwd.cross(up).normalized()
    top = right.cross(fwd).normalized()
    m = Matrix((right, top, -fwd)).transposed()
    cam.matrix_world = Matrix.Translation(location) @ m.to_4x4()


def look(scene):
    try:
        scene.view_settings.view_transform = "AgX"
        scene.view_settings.look = "AgX - Punchy"
    except Exception:
        pass
    scene.view_settings.exposure = -0.15


def use_cycles(scene, samples):
    scene.render.engine = "CYCLES"
    prefs = bpy.context.preferences.addons["cycles"].preferences
    for backend in ("HIP", "OPTIX", "CUDA", "METAL", "ONEAPI"):
        try:
            prefs.compute_device_type = backend
            prefs.get_devices()
            if any(d.type == backend for d in prefs.devices):
                for d in prefs.devices:
                    d.use = d.type == backend
                scene.cycles.device = "GPU"
                print("cycles on", backend)
                break
        except Exception:
            continue
    scene.cycles.samples = samples
    scene.cycles.use_denoising = True


def use_eevee(scene, samples):
    for engine in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT"):
        try:
            scene.render.engine = engine
            break
        except TypeError:
            continue
    scene.eevee.taa_render_samples = samples
    for attr, value in (("use_shadows", True), ("use_raytracing", True)):
        if hasattr(scene.eevee, attr):
            setattr(scene.eevee, attr, value)
