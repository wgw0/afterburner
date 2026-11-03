"""
Afterburner: the sunset cover's picture (1920 x 1080 after sunset_cover_compose.py), the icon's scene opened out
to a wide frame. The F-22A in Air Dominance Grey, big in the frame, banked hard towards the camera at sunset with
a hot rim light, a glossy coat, layered afterburner flames and vapour off its wingtips, dumping flares; behind it
a Su-57 on its tail, silhouetted against the low sun, whose missile has gone for the flares and blown up in them.
Real-looking country below (Will: realistic, not the icon's low-poly): green hills, woods and lakes rising to
rocky, snow-capped ridges, hazing into a physical sunset sky. Made to sell the game in a thumbnail: one big subject,
a clear story (a dogfight, and you're winning it), hot colours on a cool ground.

Everything is placed relative to the camera, which sits at CAM looking along +Y (X to the right of the frame,
Z up). A jet's model faces +Y with +X to its right.

  blender -b --factory-startup --python tools/marketing/sunset_cover_render.py -- --out <png>
      [--size 1920x1080] [--samples 128] [--sky 0.17] [--sky-rot <degrees>] [--eevee]
"""

import argparse
import json
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402
from mathutils import Matrix, Vector, noise  # noqa: E402

import scene as sc  # noqa: E402

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
parser = argparse.ArgumentParser()
parser.add_argument("--out", required=True)
parser.add_argument("--size", default="1920x1080")
parser.add_argument("--samples", type=int, default=128)
parser.add_argument("--sky", type=float, default=0.17, help="sky brightness")
parser.add_argument("--sky-rot", type=float, default=None, help="the sky's sun rotation, degrees")
parser.add_argument("--eevee", action="store_true", help="a quick look instead of the final Cycles render")
args = parser.parse_args(argv)

scene = sc.reset()
hexcol = sc.hexcol
CAM = Vector((0.0, 0.0, 800.0))
LENS = 32
SUN_DIR = Vector((0.36, 1.0, 0.13)).normalized()  # towards the sun: ahead and right, low over the mountains


def at(x, y, z):
    """A point x right, y ahead and z up of the camera."""
    return CAM + Vector((x, y, z))


def frame(forward, up):
    """A jet's orientation from where its nose and its top point."""
    fwd = Vector(forward).normalized()
    up = Vector(up)
    up = (up - fwd * up.dot(fwd)).normalized()
    right = fwd.cross(up).normalized()
    return Matrix((right, fwd, up)).transposed()


def glow_material(name, colour, strength, alpha=1.0, lit=True):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    b = mat.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = colour if lit else (0, 0, 0, 1)
    b.inputs["Emission Color"].default_value = colour
    b.inputs["Emission Strength"].default_value = strength
    b.inputs["Alpha"].default_value = alpha
    return mat


def point_light(location, energy, colour):
    light = bpy.data.objects.new("Light", bpy.data.lights.new("Light", "POINT"))
    light.data.energy = energy
    light.data.color = colour
    light.data.use_shadow = False
    light.location = location
    scene.collection.objects.link(light)
    return light


def tube(name, material, points, r0, r1, power=1.6):
    """A trail through points (newest first), thickening from r0 to r1 and fading out along its length."""
    trail = sc.Trail(scene, name, material, r0, r1, life=1.0, power=power)
    n = len(points) - 1
    trail.build([(p, i / n * 0.999) for i, p in enumerate(points)])
    return trail.obj


def wispy(mat, scale=0.35):
    """Breaks a trail material up with noise, so it reads as smoke rather than a solid tube."""
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    opacity = next(n for n in nodes if n.type == "MATH")
    mix = next(n for n in nodes if n.type == "MIX_SHADER")
    geo = nodes.new("ShaderNodeNewGeometry")
    tex = nodes.new("ShaderNodeTexNoise")
    tex.inputs["Scale"].default_value = scale
    tex.inputs["Detail"].default_value = 6
    tex.inputs["Roughness"].default_value = 0.65
    links.new(geo.outputs["Position"], tex.inputs["Vector"])
    puffs = nodes.new("ShaderNodeMapRange")
    puffs.inputs["From Min"].default_value = 0.32
    puffs.inputs["From Max"].default_value = 0.62
    links.new(tex.outputs["Fac"], puffs.inputs["Value"])
    both = nodes.new("ShaderNodeMath")
    both.operation = "MULTIPLY"
    links.new(opacity.outputs[0], both.inputs[0])
    links.new(puffs.outputs[0], both.inputs[1])
    links.new(both.outputs[0], mix.inputs["Fac"])
    return mat


def bezier(p0, p1, p2, p3, steps=48):
    out = []
    for i in range(steps + 1):
        t = i / steps
        u = 1 - t
        out.append(p0 * u ** 3 + p1 * 3 * u * u * t + p2 * 3 * u * t * t + p3 * t ** 3)
    return out


# --- The hero: the F-22A, close and big, banked hard towards the camera -------------------------------------

HERO_AT = at(-1.5, 34.0, -1.8)
HERO_FWD = Vector((-1.0, -0.38, 0.3)).normalized()
HERO = frame(HERO_FWD, (-0.4, -0.75, 0.6))
f22 = sc.Jet(scene, "F22A", "AirDominance", canopy="#b08a3a", flames=False)
f22.place(Matrix.Translation(HERO_AT) @ HERO.to_4x4())
for set_name in ("Body", "Wings", "Details"):
    mat = bpy.data.materials.get(f"F22A_{set_name}")
    bsdf = mat and mat.node_tree.nodes.get("Principled BSDF")
    if bsdf and "Coat Weight" in bsdf.inputs:  # a glossy coat that catches the sunset
        bsdf.inputs["Coat Weight"].default_value = 0.6
        bsdf.inputs["Coat Roughness"].default_value = 0.05
HERO_M = f22.rig.matrix_world.copy()


def hero(p):
    return HERO_M @ Vector(p)


# Afterburners: an orange plume round a white-hot core, with shock diamonds down it (the icon's)
plume = glow_material("Plume", (1, 0.3, 0.04, 1), 4, 0.6)
core = glow_material("Core", (1, 0.7, 0.3, 1), 10, 0.95)
diamond = glow_material("Diamond", (1, 0.9, 0.65, 1), 22, 0.9)
along = HERO_M.to_3x3() @ Matrix.Rotation(math.radians(90), 3, "X")
for nozzle, width in f22.nozzles:
    x, y, z = nozzle
    for radius, depth, mat in ((0.48, 6.4, plume), (0.24, 4.2, core)):
        bpy.ops.mesh.primitive_cone_add(radius1=radius, radius2=0.03, depth=depth, vertices=28)
        cone = bpy.context.active_object
        cone.location = hero((x, y - depth / 2, z))
        cone.rotation_euler = along.to_euler()
        cone.data.materials.append(mat)
        cone.visible_shadow = False
    for k, d in enumerate((1.0, 2.0, 2.9, 3.7)):
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.2 - k * 0.035, segments=16, ring_count=8)
        dot = bpy.context.active_object
        dot.location = hero((x, y - d, z))
        dot.scale = (1, 1, 1.8)
        dot.rotation_euler = along.to_euler()
        dot.data.materials.append(diamond)
        dot.visible_shadow = False
    point_light(hero((x, y - 1.6, z)), 2500, (1, 0.5, 0.15))

# Vapour off the wingtips, following the arc of the turn back behind the jet
vapour = sc.trail_material("Vapour", "#fff1e0", lit=False, opacity=0.8)
for tip in f22.wingtips:
    tip_local = HERO_M.inverted() @ tip
    pts = []
    for i in range(61):
        th = i / 60 * 1.25
        pts.append(hero(tip_local + Vector((0, -70 * math.sin(th), 70 - 70 * math.cos(th)))))
    tube("Vapour", vapour, pts, 0.1, 1.8)

# Flares, dropping back and down from the tail in a fan, each trailing white smoke back to the jet
flare_mat = glow_material("Flare", (1, 0.8, 0.45, 1), 120)
smoke = wispy(sc.trail_material("FlareSmoke", "#f4ece4", lit=True, opacity=0.8), 0.8)
TAIL = hero((0, -6.0, 0.2))
BACK = -HERO_FWD
ACROSS = BACK.cross(Vector((0, 0, 1))).normalized()
FLARES = [TAIL + BACK * b + ACROSS * a + Vector((0, 0, -d)) for b, a, d in
          ((4, -1.0, 1.0), (5.5, 1.6, 1.8), (7.5, -2.0, 2.8), (9, 2.6, 3.6), (11.5, 0.2, 4.8), (13, -3.2, 5.8))]
for i, f in enumerate(FLARES):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.42 - i * 0.02, segments=16, ring_count=8, location=f)
    ball = bpy.context.active_object
    ball.data.materials.append(flare_mat)
    ball.visible_shadow = False
    point_light(f, 1500, (1, 0.7, 0.35))
    sag = (TAIL + f) / 2 + Vector((0, 0, 1.6))
    tube("FlareSmoke", smoke, bezier(f, f.lerp(sag, 0.6), TAIL.lerp(sag, 0.6), TAIL, 24), 0.15, 0.7, power=1.0)

# --- The enemy: a Su-57 on the F-22A's tail, against the sun, its missile blown up in the flares --------------

ENEMY_AT = at(25.0, 95.0, 13.0)
BLAST = TAIL + BACK * 10 + Vector((0, 1.5, -1.0))
su57 = sc.Jet(scene, "Su57", "Dark", flames=True)
su57.place(Matrix.Translation(ENEMY_AT) @ frame(HERO_AT - ENEMY_AT + Vector((0, 0, 10)), (0.45, 0.0, 1.0)).to_4x4())

# The missile's smoke: from under the Su-57, a long curling arc that bent round to chase the flares
missile_smoke = wispy(sc.trail_material("MissileSmoke", "#ece6e0", lit=True, opacity=0.9))
launch = su57.rig.matrix_world @ Vector((0, 3.0, -1.4))
path = bezier(BLAST, BLAST + Vector((10, 14, 9)), launch.lerp(BLAST, 0.45) + Vector((8, 0, 8)), launch, 64)
tube("MissileSmoke", missile_smoke, path, 0.6, 2.6, power=0.7)

# The blast: a ball of fire in billowing smoke, soft volumes with noise through them
rng = random.Random(4)


def nodes_of(mat):
    mat.use_nodes = True
    nt = mat.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    return nt.nodes, nt.links


def math_node(nodes, links, op, a, b=None):
    m = nodes.new("ShaderNodeMath")
    m.operation = op
    for i, v in enumerate((a, b)):
        if v is None:
            continue
        if isinstance(v, (int, float)):
            m.inputs[i].default_value = v
        else:
            links.new(v, m.inputs[i])
    return m.outputs[0]


def puff_material(name, smoke_colour, density, fire_colour=None, fire_strength=0.0, scale=2.2):
    """A soft ball of volume: densest in the middle, broken up by noise, glowing if it's fire."""
    mat = bpy.data.materials.new(name)
    nodes, links = nodes_of(mat)
    out = nodes.new("ShaderNodeOutputMaterial")
    coords = nodes.new("ShaderNodeTexCoord")
    centred = nodes.new("ShaderNodeVectorMath")
    centred.operation = "SUBTRACT"
    centred.inputs[1].default_value = (0.5, 0.5, 0.5)
    links.new(coords.outputs["Generated"], centred.inputs[0])
    length = nodes.new("ShaderNodeVectorMath")
    length.operation = "LENGTH"
    links.new(centred.outputs[0], length.inputs[0])
    falloff = nodes.new("ShaderNodeMapRange")
    falloff.inputs["From Min"].default_value = 0.5
    falloff.inputs["From Max"].default_value = 0.15
    links.new(length.outputs["Value"], falloff.inputs["Value"])
    tex = nodes.new("ShaderNodeTexNoise")
    tex.noise_dimensions = "4D"
    tex.inputs["Scale"].default_value = scale
    tex.inputs["Detail"].default_value = 6
    tex.inputs["Roughness"].default_value = 0.6
    tex.inputs["W"].default_value = rng.uniform(0, 10)
    links.new(coords.outputs["Object"], tex.inputs["Vector"])
    shaped = math_node(nodes, links, "SUBTRACT", math_node(nodes, links, "MULTIPLY", falloff.outputs[0], 1.6),
                       math_node(nodes, links, "MULTIPLY", tex.outputs["Fac"], 0.9))
    shaped = math_node(nodes, links, "MAXIMUM", shaped, 0.0)
    vol = nodes.new("ShaderNodeVolumePrincipled")
    vol.inputs["Color"].default_value = smoke_colour
    links.new(math_node(nodes, links, "MULTIPLY", shaped, density), vol.inputs["Density"])
    if fire_colour:
        vol.inputs["Emission Color"].default_value = fire_colour
        links.new(math_node(nodes, links, "MULTIPLY", shaped, fire_strength), vol.inputs["Emission Strength"])
    links.new(vol.outputs[0], out.inputs["Volume"])
    return mat


fire_core = puff_material("BlastCore", hexcol("#ffcf80"), 6, hexcol("#ff9530"), 12, scale=1.6)
fire = puff_material("BlastFire", hexcol("#ff7a20"), 5, hexcol("#ff4a06"), 12)
blast_smoke = puff_material("BlastSmoke", hexcol("#2a2624"), 3.5, hexcol("#ff4a08"), 1.5, scale=1.4)
for mat, count, spread, size in ((blast_smoke, 9, 3.2, (1.3, 2.1)), (fire, 12, 2.0, (1.0, 1.6)),
                                 (fire_core, 5, 0.8, (0.7, 1.1))):
    for _ in range(count):
        d = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1)))
        d = d.normalized() * spread * rng.uniform(0.4, 1.0) if d.length > 0 else d
        if mat is blast_smoke:
            d += Vector((0, 1.6, 1.8))  # smoke lags behind and above the fire
        bpy.ops.mesh.primitive_uv_sphere_add(segments=24, ring_count=12, radius=rng.uniform(*size), location=BLAST + d)
        puff = bpy.context.active_object
        puff.data.materials.append(mat)
        puff.visible_shadow = False
point_light(BLAST, 30000, (1, 0.5, 0.15))

# --- The world: real-looking country under a low sun. Rolling green hills and lakes rising to rocky, snow-capped
# ridges, the air going hazy and warm with distance, as at sunset ---------------------------------------------

WATER_Z = 55.0
VIEW = Vector((0.15, 1.0, 0)).normalized()


def smoothstep(a, b, x):
    t = min(max((x - a) / (b - a), 0.0), 1.0)
    return t * t * (3 - 2 * t)


def height(x, y):
    ahead = (x - CAM.x) * VIEW.x + (y - CAM.y) * VIEW.y
    h = 70 + noise.fractal(Vector((x / 1500, y / 1500, 0.3)), 0.55, 2.0, 7) * 120
    h += noise.fractal(Vector((x / 260, y / 260, 4.1)), 0.6, 2.0, 4) * 5
    m = smoothstep(3000, 7000, ahead)
    if m > 0:
        ridges = noise.ridged_multi_fractal(Vector((x / 2100, y / 2100, 2.1)), 0.95, 2.05, 7, 1.0, 2.1)
        h += m * (ridges * 480 + 120)
    return h


def terrain():
    """A heightfield, finer near the camera than far away, smooth-shaded."""
    nx, ny = 700, 520
    verts = []
    for j in range(ny + 1):
        v = j / ny
        y = CAM.y + 500 + v ** 1.8 * 15000
        for i in range(nx + 1):
            u = i / nx * 2 - 1
            x = CAM.x + math.copysign(abs(u) ** 1.6, u) * 11000
            verts.append((x, y, height(x, y)))
    faces = []
    for j in range(ny):
        for i in range(nx):
            a = j * (nx + 1) + i
            faces.append((a, a + 1, a + nx + 2, a + nx + 1))
    mesh = bpy.data.meshes.new("Terrain")
    mesh.from_pydata(verts, [], faces)
    mesh.polygons.foreach_set("use_smooth", [True] * len(mesh.polygons))
    obj = bpy.data.objects.new("Terrain", mesh)
    scene.collection.objects.link(obj)
    print("terrain heights", min(v[2] for v in verts), max(v[2] for v in verts))
    return obj


def haze(nodes, links, shader, out, density=1 / 12000):
    """Aerial perspective: the surface fades into warm haze towards the sun and cooler haze away from it."""
    cam_data = nodes.new("ShaderNodeCameraData")
    amount = math_node(nodes, links, "MULTIPLY", cam_data.outputs["View Distance"], -density)
    amount = math_node(nodes, links, "SUBTRACT", 1.0, math_node(nodes, links, "EXPONENT", amount))
    geo = nodes.new("ShaderNodeNewGeometry")
    facing = nodes.new("ShaderNodeVectorMath")
    facing.operation = "DOT_PRODUCT"
    facing.inputs[1].default_value = tuple(-SUN_DIR)
    links.new(geo.outputs["Incoming"], facing.inputs[0])
    towards = nodes.new("ShaderNodeMapRange")
    towards.inputs["From Min"].default_value = 0.85
    towards.inputs["From Max"].default_value = 1.0
    links.new(facing.outputs["Value"], towards.inputs["Value"])
    tint = nodes.new("ShaderNodeMix")
    tint.data_type = "RGBA"
    tint.inputs["A"].default_value = HAZE_AWAY
    tint.inputs["B"].default_value = HAZE_SUN
    links.new(towards.outputs[0], tint.inputs["Factor"])
    glow = nodes.new("ShaderNodeEmission")
    glow.inputs["Strength"].default_value = 0.8
    links.new(tint.outputs["Result"], glow.inputs["Color"])
    mix = nodes.new("ShaderNodeMixShader")
    links.new(amount, mix.inputs["Fac"])
    links.new(shader, mix.inputs[1])
    links.new(glow.outputs[0], mix.inputs[2])
    links.new(mix.outputs[0], out.inputs["Surface"])


HAZE_AWAY = hexcol("#8f94b8")  # cool, lilac haze away from the sun
HAZE_SUN = (1.5, 0.78, 0.4, 1)  # bright, golden haze towards it


def ramp_node(nodes, links, fac, stops):
    r = nodes.new("ShaderNodeValToRGB")
    els = r.color_ramp.elements
    els[0].position, els[0].color = stops[0]
    els[1].position, els[1].color = stops[-1]
    for pos, c in stops[1:-1]:
        els.new(pos).color = c
    links.new(fac, r.inputs["Fac"])
    return r.outputs["Color"]


def mix_colour(nodes, links, fac, a, b):
    m = nodes.new("ShaderNodeMix")
    m.data_type = "RGBA"
    links.new(fac, m.inputs["Factor"])
    for sock, v in (("A", a), ("B", b)):
        if isinstance(v, tuple):
            m.inputs[sock].default_value = v
        else:
            links.new(v, m.inputs[sock])
    return m.outputs["Result"]


def map_range(nodes, links, value, lo, hi):
    m = nodes.new("ShaderNodeMapRange")
    m.inputs["From Min"].default_value = lo
    m.inputs["From Max"].default_value = hi
    links.new(value, m.inputs["Value"])
    return m.outputs[0]


def terrain_material():
    mat = bpy.data.materials.new("Terrain")
    nodes, links = nodes_of(mat)
    out = nodes.new("ShaderNodeOutputMaterial")
    geo = nodes.new("ShaderNodeNewGeometry")
    normal = nodes.new("ShaderNodeSeparateXYZ")
    links.new(geo.outputs["Normal"], normal.inputs[0])
    pos = nodes.new("ShaderNodeSeparateXYZ")
    links.new(geo.outputs["Position"], pos.inputs[0])

    def noise_tex(scale, detail=8, rough=0.6):
        t = nodes.new("ShaderNodeTexNoise")
        t.inputs["Scale"].default_value = scale
        t.inputs["Detail"].default_value = detail
        t.inputs["Roughness"].default_value = rough
        links.new(geo.outputs["Position"], t.inputs["Vector"])
        return t.outputs["Fac"]

    broad, fine, patches = noise_tex(0.0025), noise_tex(0.06), noise_tex(0.0012, 4)
    # Meadows and woods: green grass broken by darker forest
    grass = ramp_node(nodes, links, broad, [(0.3, hexcol("#3f6b22")), (0.5, hexcol("#56842a")),
                                            (0.7, hexcol("#7a9436"))])
    woods = ramp_node(nodes, links, fine, [(0.3, hexcol("#1d3317")), (0.7, hexcol("#2f4a22"))])
    green = mix_colour(nodes, links, map_range(nodes, links, patches, 0.5, 0.56), grass, woods)
    # Rock on the steep and high ground, snow on the highest ground that isn't too steep
    rock = ramp_node(nodes, links, fine, [(0.3, hexcol("#4a4a4e")), (0.5, hexcol("#66666a")),
                                          (0.75, hexcol("#85837f"))])
    jitter = math_node(nodes, links, "ADD", normal.outputs["Z"],
                       math_node(nodes, links, "MULTIPLY", math_node(nodes, links, "SUBTRACT", fine, 0.5), 0.12))
    rocky = math_node(nodes, links, "MAXIMUM", map_range(nodes, links, jitter, 0.8, 0.65),
                      math_node(nodes, links, "MULTIPLY", map_range(nodes, links, pos.outputs["Z"], 480, 680), 0.85))
    ground = mix_colour(nodes, links, rocky, green, rock)
    snow_h = map_range(nodes, links, math_node(nodes, links, "ADD", pos.outputs["Z"],
                                               math_node(nodes, links, "MULTIPLY", broad, 160)), 820, 940)
    snow = math_node(nodes, links, "MULTIPLY", snow_h, map_range(nodes, links, jitter, 0.55, 0.72))
    colour = mix_colour(nodes, links, snow, ground, hexcol("#eef0f2"))
    # Sand and mud at the waterline
    colour = mix_colour(nodes, links, map_range(nodes, links, pos.outputs["Z"], WATER_Z + 6, WATER_Z + 1), colour,
                        hexcol("#8a7a5c"))
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    links.new(colour, bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.92
    bump = nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.5
    bump.inputs["Distance"].default_value = 2.0
    links.new(noise_tex(0.12, 10), bump.inputs["Height"])
    links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    haze(nodes, links, bsdf.outputs[0], out)
    return mat


land = terrain()
land.data.materials.append(terrain_material())

# Lakes in the low ground: dark, glassy water with a little chop to catch the sun
bpy.ops.mesh.primitive_plane_add(size=1, location=(CAM.x, CAM.y + 8000, WATER_Z))
lake = bpy.context.active_object
lake.scale = (24000, 17000, 1)
water = bpy.data.materials.new("Water")
nodes, links = nodes_of(water)
wout = nodes.new("ShaderNodeOutputMaterial")
wb = nodes.new("ShaderNodeBsdfPrincipled")
wb.inputs["Base Color"].default_value = hexcol("#0e2633")
wb.inputs["Roughness"].default_value = 0.03
wb.inputs["IOR"].default_value = 1.33
chop = nodes.new("ShaderNodeTexNoise")
chop.inputs["Scale"].default_value = 0.03
chop.inputs["Detail"].default_value = 6
wgeo = nodes.new("ShaderNodeNewGeometry")
links.new(wgeo.outputs["Position"], chop.inputs["Vector"])
wbump = nodes.new("ShaderNodeBump")
wbump.inputs["Strength"].default_value = 0.08
links.new(chop.outputs["Fac"], wbump.inputs["Height"])
links.new(wbump.outputs["Normal"], wb.inputs["Normal"])
haze(nodes, links, wb.outputs[0], wout)
lake.data.materials.append(water)

# --- Sky, light, camera, render -----------------------------------------------------------------------------

world_data = bpy.data.worlds.new("World")
scene.world = world_data
world_data.use_nodes = True
wn, wl = world_data.node_tree.nodes, world_data.node_tree.links
for n in list(wn):
    wn.remove(n)
sky = wn.new("ShaderNodeTexSky")
for kind in ("MULTIPLE_SCATTERING", "NISHITA", "SINGLE_SCATTERING"):
    try:
        sky.sky_type = kind
        break
    except TypeError:
        continue
sky.sun_disc = False
sky.sun_elevation = math.radians(1.5)  # lower than the lamp, for a redder sky
sky.sun_rotation = math.radians(args.sky_rot) if args.sky_rot is not None else math.atan2(SUN_DIR.x, SUN_DIR.y)
for attr, value in (("altitude", 400.0), ("air_density", 1.3), ("dust_density", 1.0), ("aerosol_density", 1.0),
                    ("ozone_density", 3.0)):
    if hasattr(sky, attr):
        setattr(sky, attr, value)
bg = wn.new("ShaderNodeBackground")
bg.inputs["Strength"].default_value = args.sky
wo = wn.new("ShaderNodeOutputWorld")
wl.new(sky.outputs["Color"], bg.inputs["Color"])
wl.new(bg.outputs[0], wo.inputs["Surface"])
print("sky", sky.sky_type)

sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
sun.data.energy = 4.2
sun.data.color = (1.0, 0.68, 0.4)
sun.data.angle = math.radians(1.5)
sun.rotation_euler = SUN_DIR.to_track_quat("Z", "Y").to_euler()  # shining back along -SUN_DIR
scene.collection.objects.link(sun)

# A soft, cool fill from over the camera, so the F-22A's top isn't lost in shadow
fill = bpy.data.objects.new("Fill", bpy.data.lights.new("Fill", "AREA"))
fill.data.energy = 22000
fill.data.size = 20
fill.data.color = (0.7, 0.78, 1.0)
fill.location = HERO_AT + Vector((-4, -18, 10))
fill.rotation_euler = (HERO_AT - fill.location).to_track_quat("-Z", "Y").to_euler()
scene.collection.objects.link(fill)

# A warm key from behind the camera's left shoulder: not where the sun is, but it shows the jet and the ground
key = bpy.data.objects.new("Key", bpy.data.lights.new("Key", "SUN"))
key.data.energy = 1.0
key.data.color = (1.0, 0.72, 0.6)
key.data.angle = math.radians(3)
key.rotation_euler = Vector((-0.6, -1.0, 0.55)).to_track_quat("Z", "Y").to_euler()
scene.collection.objects.link(key)

cam = sc.camera(scene, LENS)
sc.aim(cam, CAM, CAM + Vector((0, 1, -0.045)))
cam.data.shift_y = 0.0

try:
    scene.view_settings.view_transform = "AgX"
    scene.view_settings.look = "AgX - High Contrast"
except Exception:
    pass
(sc.use_eevee if args.eevee else sc.use_cycles)(scene, 64 if args.eevee else args.samples)
w, h = (int(v) for v in args.size.split("x"))
scene.render.resolution_x, scene.render.resolution_y = w, h
scene.render.filepath = args.out


def screen(p):
    """Where a world point lands in the frame, as fractions from the top left (for the compose step)."""
    from bpy_extras.object_utils import world_to_camera_view
    v = world_to_camera_view(scene, cam, p)
    return round(v.x, 4), round(1 - v.y, 4)


# The compose step needs these to put its glows in the right places: written beside the render
marks = {
    "sun": screen(CAM + SUN_DIR * 10000),
    "nozzles": [screen(hero(n)) for n, _ in f22.nozzles],
    "flares": [screen(f) for f in FLARES],
    "blast": screen(BLAST),
    "enemy_nozzles": [screen(su57.rig.matrix_world @ n) for n, _ in su57.nozzles],
}
with open(os.path.splitext(args.out)[0] + ".json", "w") as f:
    json.dump(marks, f, indent=1)
print("SCREEN", marks)
bpy.ops.render.render(write_still=True)
print("rendered", args.out)
