"""
Afterburner: paints the F-5E. Procedural PBR textures for the generated, already-unwrapped model.

  blender -b tools/blender/out/F5E_base.blend --python tools/blender/f5e_paint.py -- \
      --out <absolute dir> [--skin Ghost] [--preview]

Use the .blend whose FBX was imported into Studio: the textures follow its UV layout.

How it works, per texture set (Body, Wings, Details; the canopy stays plain glass):
  1. Cycles bakes, for every texel, where it sits on the jet (world position), which way it faces
     (normal), which part it belongs to (object index) and how occluded it is (ambient occlusion).
  2. numpy turns those into Color, Roughness, Metalness and a Height map from the F-5E's panel layout
     (frames, longerons, spars, ribs, access panels, rivet rows) and the paint scheme (camouflage,
     anti-glare panel, radome, insignia, walkways, gun and exhaust soot, grime, worn leading edges).
     Everything is computed from 3D position, so it lines up across UV seams.
  3. Cycles bakes the tangent-space Normal map (OpenGL, as Roblox expects) from the height map.
Texels are computed at twice the output size and averaged down, for clean panel lines.

Outputs <Airframe>_<Skin>_<Set>_<Map>.png (Map: Color, Normal, Roughness, Metalness) at 1024 px
(Body, Wings) and 512 px (Details), the largest Roblox accepts. --preview also renders the painted jet
and saves F5E_painted.blend; the source .blend is never overwritten.
"""

import argparse
import math
import os
import sys

import bpy
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import f5e_generate as gen  # noqa: E402  (shapes, stations and the drawing-to-metres helpers)

Y, Z = gen.Y, gen.Z
SETS = {"Body": 1024, "Wings": 1024, "Details": 512}
SUPERSAMPLE = 2
SENTINEL = 10.0  # untouched texels keep this (baked values are 0..1)
BUMP_DISTANCE = 0.0012  # metres of relief for a height of 1


def srgb(r, g, b):
    """sRGB 0-255 -> linear 0-1 (paint colours are given as they look)."""
    c = np.array([r, g, b], dtype=np.float32) / 255.0
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def to_srgb(c):
    c = np.clip(c, 0, 1)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * np.power(c, 1 / 2.4) - 0.055)


# ---------------------------------------------------------------------------------------------------
# Paint schemes (more skins are more entries here)
# ---------------------------------------------------------------------------------------------------

SCHEMES = {
    # USAF two-tone "Ghost" greys (FS 36320 over FS 36375), low-visibility insignia
    "Ghost": {
        "upper": srgb(98, 108, 117),
        "lower": srgb(140, 150, 158),
        "antiglare": srgb(62, 66, 72),
        "radome": srgb(84, 90, 96),
        "insignia": srgb(70, 76, 82),
        "walkway": srgb(74, 78, 83),
        "demarcation": -0.10,  # z (m) of the soft upper/lower line on the fuselage sides
    },
    # Aggressor schemes: camouflage bands wrapped over the whole jet, in the style of the US adversary
    # squadrons' F-5Es (see the skins reference photos). "camo" colours are listed lightest first.
    "Desert": {
        "camo": [srgb(206, 186, 146), srgb(176, 132, 92), srgb(150, 156, 112)],
        "camo_scale": 2.6,
        "radome": srgb(28, 28, 30),
        "antiglare": srgb(54, 50, 46),
        "insignia": srgb(52, 48, 44),
        "walkway": srgb(96, 86, 72),
    },
    "Pacific": {
        "camo": [srgb(186, 202, 210), srgb(132, 168, 186), srgb(84, 112, 134)],
        "camo_scale": 3.0,
        "radome": srgb(28, 30, 34),
        "antiglare": srgb(50, 56, 64),
        "insignia": srgb(46, 54, 62),
        "walkway": srgb(70, 84, 96),
    },
    "Lizard": {
        "camo": [srgb(160, 160, 118), srgb(118, 128, 82), srgb(78, 90, 60)],
        "camo_scale": 2.2,
        "radome": srgb(30, 32, 28),
        "antiglare": srgb(46, 50, 40),
        "insignia": srgb(40, 44, 34),
        "walkway": srgb(66, 72, 52),
    },
}

for _scheme in SCHEMES.values():  # fills used by the Details set and outside the UV islands
    if "camo" in _scheme:
        _scheme.setdefault("upper", _scheme["camo"][1])
        _scheme.setdefault("lower", _scheme["camo"][0])

METAL = srgb(176, 178, 182)
SOOT = srgb(30, 28, 27)
DUCT = srgb(22, 23, 25)

# ---------------------------------------------------------------------------------------------------
# Noise (vectorised value noise on 3D positions, in metres)
# ---------------------------------------------------------------------------------------------------


def _hash(ix, iy, iz, seed):
    h = (ix * 374761393 + iy * 668265263 + iz * 1274126177 + seed * 1442695041) & 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
    return ((h ^ (h >> 16)) & 0xFFFFFF).astype(np.float32) / float(0xFFFFFF)


def vnoise(p, freq, seed=0, stretch=(1.0, 1.0, 1.0)):
    q = p * np.array(stretch, dtype=np.float32) * freq
    i = np.floor(q).astype(np.int64)
    f = q - i
    u = f * f * (3 - 2 * f)
    out = 0.0
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                w = ((u[..., 0] if dx else 1 - u[..., 0]) * (u[..., 1] if dy else 1 - u[..., 1])
                     * (u[..., 2] if dz else 1 - u[..., 2]))
                out = out + w * _hash(i[..., 0] + dx, i[..., 1] + dy, i[..., 2] + dz, seed)
    return out


def fbm(p, freq, octaves=4, seed=0, stretch=(1.0, 1.0, 1.0)):
    total, amp, norm = 0.0, 1.0, 0.0
    for o in range(octaves):
        total = total + amp * vnoise(p, freq * (2**o), seed + o * 17, stretch)
        norm += amp
        amp *= 0.5
    return total / norm


def smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def groove(d, width):
    """Panel-line profile: 1 on the line, 0 at `width` away."""
    return 1 - smooth(0, width, np.abs(d))


def rivets(d_perp, s, spacing, radius, offset=0.0):
    """Rivet heads in a row along a line: d_perp across it, s along it (metres)."""
    ds = np.mod(s, spacing) - spacing / 2
    r = np.sqrt((np.abs(d_perp) - offset) ** 2 + ds**2)
    return 1 - smooth(radius * 0.5, radius, r)


def cell_tone(index, seed, amount):
    """A small random brightness offset per panel (index array of integers)."""
    h = _hash(index.astype(np.int64), np.zeros_like(index, dtype=np.int64), np.zeros_like(index, dtype=np.int64), seed)
    return 1 + (h - 0.5) * 2 * amount


# ---------------------------------------------------------------------------------------------------
# Shapes: insignia (signed distance, 2D)
# ---------------------------------------------------------------------------------------------------


def sd_polygon(u, v, poly):
    d = np.full(u.shape, np.inf, dtype=np.float32)
    inside = np.zeros(u.shape, dtype=bool)
    n = len(poly)
    for i in range(n):
        (ax, ay), (bx, by) = poly[i], poly[(i + 1) % n]
        ex, ey = bx - ax, by - ay
        wx, wy = u - ax, v - ay
        t = np.clip((wx * ex + wy * ey) / (ex * ex + ey * ey), 0, 1)
        d = np.minimum(d, np.hypot(wx - ex * t, wy - ey * t))
        cond = ((ay > v) != (by > v)) & (u < (bx - ax) * (v - ay) / (by - ay + 1e-12) + ax)
        inside ^= cond
    return np.where(inside, -d, d)


def star_and_bar(u, v, r):
    """USAF national insignia, star pointing +v, as a low-visibility outline mask (0..1)."""
    star = []
    for k in range(10):
        ang = math.pi / 2 + k * math.pi / 5
        rad = r if k % 2 == 0 else r * 0.382
        star.append((rad * math.cos(ang), rad * math.sin(ang)))
    d_star = sd_polygon(u, v, star)
    d_circle = np.hypot(u, v) - r
    top, bottom = r * 0.309, r * 0.309 - r * 0.5
    bars = [(-2.0 * r, bottom), (2.0 * r, bottom), (2.0 * r, top), (-2.0 * r, top)]
    d_bars = sd_polygon(u, v, bars)
    d_outer = np.minimum(d_circle, d_bars)
    w = r * 0.05
    return np.maximum(groove(d_outer, w), groove(d_star, w))


# ---------------------------------------------------------------------------------------------------
# Baking helpers
# ---------------------------------------------------------------------------------------------------


def set_objects(set_name):
    return [o for o in bpy.data.objects if o.type == "MESH" and o.get("afterburner_set") == set_name]


def new_image(name, size, float_buffer, colorspace, fill=None):
    img = bpy.data.images.new(name, size, size, alpha=True, float_buffer=float_buffer)
    img.colorspace_settings.name = colorspace
    if fill is not None:
        img.pixels.foreach_set(np.full(size * size * 4, fill, dtype=np.float32))
    return img


def pixels(img):
    a = np.empty(img.size[0] * img.size[1] * 4, dtype=np.float32)
    img.pixels.foreach_get(a)
    return a.reshape(img.size[1], img.size[0], 4)


def bake_material(build):
    """A temporary material: build(nodes, links) wires the shader; returns (material, image node)."""
    mat = bpy.data.materials.new("BAKE_TEMP")
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    nodes.clear()
    out = nodes.new("ShaderNodeOutputMaterial")
    shader = build(nodes, links)
    links.new(shader.outputs[0], out.inputs["Surface"])
    target = nodes.new("ShaderNodeTexImage")
    nodes.active = target
    return mat, target


def with_material(objs, mat, fn):
    saved = {o.name: [s.material for s in o.material_slots] for o in objs}
    for o in objs:
        for s in o.material_slots:
            s.material = mat
    try:
        fn()
    finally:
        for o in objs:
            for s, m in zip(o.material_slots, saved[o.name]):
                s.material = m


def bake(objs, mat, target_img, kind, margin):
    mat.node_tree.nodes.active.image = target_img
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]

    def run():
        kwargs = {"type": kind, "margin": margin, "use_clear": False}
        if kind == "NORMAL":
            kwargs.update(normal_space="TANGENT")
        bpy.ops.object.bake(**kwargs)

    with_material(objs, mat, run)


POS_RANGE = 20.0  # positions are baked as (p + R) / 2R, so every value is 0..1


def emission_of(socket_getter, offset, scale):
    """Emits a vector socket, remapped as (v + offset) * scale so it bakes as a plain 0..1 colour."""

    def build(nodes, links):
        add = nodes.new("ShaderNodeVectorMath")
        add.operation = "ADD"
        add.inputs[1].default_value = (offset, offset, offset)
        links.new(socket_getter(nodes), add.inputs[0])
        mul = nodes.new("ShaderNodeVectorMath")
        mul.operation = "SCALE"
        mul.inputs["Scale"].default_value = scale
        links.new(add.outputs["Vector"], mul.inputs[0])
        em = nodes.new("ShaderNodeEmission")
        links.new(mul.outputs["Vector"], em.inputs["Color"])
        return em

    return build


def bake_maps(set_name, size):
    """World position, world normal, object index (all float) and AO for a set, at `size`."""
    objs = set_objects(set_name)
    for i, o in enumerate(objs):
        o.pass_index = i + 1
    scene = bpy.context.scene
    scene.cycles.samples = 1
    maps = {}
    for key, getter, offset, scale in (
        ("P", lambda n: n.new("ShaderNodeNewGeometry").outputs["Position"], POS_RANGE, 0.5 / POS_RANGE),
        ("N", lambda n: n.new("ShaderNodeNewGeometry").outputs["Normal"], 1.0, 0.5),
        ("ID", lambda n: n.new("ShaderNodeObjectInfo").outputs["Object Index"], 0.0, 1.0 / 64),
    ):
        img = new_image(f"{set_name}_{key}", size, True, "Non-Color", SENTINEL)
        mat, _ = bake_material(emission_of(getter, offset, scale))
        bake(objs, mat, img, "EMIT", 8 * SUPERSAMPLE)
        raw = pixels(img)[..., :3]
        if key == "ID":
            maps["valid"] = raw[..., 0] < 2  # untouched texels keep the sentinel
            maps[key] = np.where(maps["valid"], np.round(raw[..., 0] * 64), 0).astype(np.int32)
        else:
            maps[key] = np.where(raw < 2, raw / scale - offset, 0).astype(np.float32)
        bpy.data.materials.remove(mat)
    ao_size = size // SUPERSAMPLE
    scene.cycles.samples = 48
    img = new_image(f"{set_name}_AO", ao_size, True, "Non-Color", 1.0)
    mat, _ = bake_material(lambda nodes, links: nodes.new("ShaderNodeBsdfDiffuse"))
    bake(objs, mat, img, "AO", 8)
    bpy.data.materials.remove(mat)
    ao = pixels(img)[..., 0]
    maps["AO"] = np.repeat(np.repeat(ao, SUPERSAMPLE, axis=0), SUPERSAMPLE, axis=1)
    ids = {o.name: i + 1 for i, o in enumerate(objs)}
    return maps, ids, objs


# ---------------------------------------------------------------------------------------------------
# Layout: the F-5E's panels (drawing stations via Y(), heights in metres)
# ---------------------------------------------------------------------------------------------------

FRAMES = [232, 335, 440, 560, 650, 735, 855, 960, 1040, 1100, 1185, 1260, 1330, 1410, 1470]
SIDE_LINES = [(0.07, 232, 650), (-0.42, 232, 735), (0.30, 735, 1470), (-0.25, 855, 1470)]  # (z, from, to)
TOP_LINES = [(0.235, 750, 1150), (0.13, 250, 455)]  # (|x|, from, to) on upward faces
BOTTOM_LINES = [(0.25, 1040, 1410), (0.0, 232, 1470)]
SIDE_PANELS = [(245, 330, -0.33, -0.02), (345, 430, -0.35, 0.05), (1110, 1180, -0.15, 0.20), (1340, 1400, -0.05, 0.25)]
GUN_MUZZLES = [(-0.13, 290), (0.13, 290)]
INSIGNIA_FUSELAGE = (1255, 0.10, 0.27)  # station, z, radius
INSIGNIA_WING = (2.55, 0.30)  # |x|, radius: upper left wing, lower right wing


def wing_le(xabs):
    return gen.WING_ROOT_LE - (xabs - gen.WING_ROOT_X) * math.tan(gen.WING_SWEEP_LE)


def wing_te(xabs):
    tip_te = wing_le(gen.WING_TIP_X) - gen.WING_TIP_CHORD
    t = (xabs - gen.WING_ROOT_X) / (gen.WING_TIP_X - gen.WING_ROOT_X)
    return gen.WING_ROOT_TE + (tip_te - gen.WING_ROOT_TE) * t


def wing_fraction(x, y):
    xa = np.abs(x)
    le, te = wing_le(xa), wing_te(xa)
    return (le - y) / np.maximum(le - te, 1e-3)


def stab_fraction(x, y):
    xa = np.abs(x)
    le = gen.STAB_ROOT_LE - (xa - gen.STAB_ROOT_X) * math.tan(gen.STAB_SWEEP_LE)
    t = (xa - gen.STAB_ROOT_X) / (gen.STAB_TIP_X - gen.STAB_ROOT_X)
    chord = gen.STAB_ROOT_CHORD + (gen.STAB_TIP_CHORD - gen.STAB_ROOT_CHORD) * t
    return (le - y) / np.maximum(chord, 1e-3)


def fin_fraction(y, z):
    le = gen.FIN_ROOT_LE - (z - gen.FIN_ROOT_Z) * math.tan(gen.FIN_SWEEP_LE)
    t = (z - gen.FIN_ROOT_Z) / (gen.FIN_TIP_Z - gen.FIN_ROOT_Z)
    chord = gen.FIN_ROOT_CHORD + (gen.FIN_TIP_CHORD - gen.FIN_ROOT_CHORD) * t
    return (le - y) / np.maximum(chord, 1e-3)


def xd_of(y):
    return gen.REF_PITOT_XD + (gen.CG_FROM_PITOT - y) * gen.REF_PX_PER_M


# ---------------------------------------------------------------------------------------------------
# Painting
# ---------------------------------------------------------------------------------------------------


def make_on(part, ids):
    def on(*names):
        wanted = [ids[n] for n in names if n in ids]
        return np.isin(part, wanted) if wanted else np.zeros(part.shape, bool)

    return on


def camouflage(P, scheme):
    """Hard-edged, wavy camouflage bands from 3D noise, so they wrap continuously over the airframe.
    The two thresholds split the noise into three roughly equal areas."""
    scale = scheme["camo_scale"]
    n = fbm(P, 1.0 / scale, 3, seed=61) + 0.12 * (fbm(P, 5.0 / scale, 2, seed=67) - 0.5)
    c0, c1, c2 = scheme["camo"]
    edge = 0.006
    a = smooth(0.452 - edge, 0.452 + edge, n)[..., None]
    b = smooth(0.548 - edge, 0.548 + edge, n)[..., None]
    return c0 * (1 - a) + c1 * (a - b) + c2 * b


def paint_airframe(P, N, part, ids, ao, scheme):
    """Body and Wings sets. part: object index per texel (ids: name -> index). Returns colour, rough,
    metal, height."""
    x, y, z = P[..., 0], P[..., 1], P[..., 2]
    nz = N[..., 2]
    side = np.abs(nz) < 0.6
    up, down = nz >= 0.6, nz <= -0.6
    shape = x.shape
    line = np.zeros(shape, np.float32)  # panel-line grooves
    rivet = np.zeros(shape, np.float32)
    w = 0.0045  # groove half-width (m): about a texel at 1024 px

    on = make_on(part, ids)
    fus = on("Fuselage")
    intake = on("Intakes")
    wing = on("WingL", "WingR")
    surf = on("LEFlapL", "LEFlapR", "FlapL", "FlapR", "AileronL", "AileronR")
    stab = on("StabilatorL", "StabilatorR")
    fin = on("Fin")
    rudder = on("Rudder")
    lerx = on("LERX")
    frame = on("CanopyFrame")
    xd = xd_of(y)

    # Fuselage frames, longerons, panels
    body = fus | intake
    for f in FRAMES:
        d = y - Y(f)
        line = np.maximum(line, np.where(body, groove(d, w), 0))
        s = np.where(side, z, x)
        rivet = np.maximum(rivet, np.where(fus, rivets(d, s, 0.05, 0.004, offset=0.018), 0))
    for zz, a, b in SIDE_LINES:
        m = fus & side & (xd >= a) & (xd <= b)
        line = np.maximum(line, np.where(m, groove(z - zz, w), 0))
        rivet = np.maximum(rivet, np.where(m, rivets(z - zz, y, 0.05, 0.004, offset=0.016), 0))
    for xx, a, b in TOP_LINES:
        m = fus & up & (xd >= a) & (xd <= b)
        line = np.maximum(line, np.where(m, groove(np.abs(x) - xx, w), 0))
    for xx, a, b in BOTTOM_LINES:
        m = fus & down & (xd >= a) & (xd <= b)
        line = np.maximum(line, np.where(m, groove(np.abs(x) - xx, w), 0))
    for a, b, z0, z1 in SIDE_PANELS:
        inside = fus & side & (xd >= a) & (xd <= b) & (z >= z0) & (z <= z1)
        edge = np.minimum(np.minimum(np.abs(xd - a), np.abs(xd - b)) / gen.REF_PX_PER_M,
                          np.minimum(np.abs(z - z0), np.abs(z - z1)))
        line = np.maximum(line, np.where(inside, groove(edge, w), 0))
        # fasteners just inside the edge
        rivet = np.maximum(rivet, np.where(inside & (edge > 0.012) & (edge < 0.03),
                                           rivets(edge - 0.02, y + z, 0.07, 0.006), 0))
    for f in (700, 772, 855):
        line = np.maximum(line, np.where(intake, groove(y - Y(f), w), 0))
    line = np.maximum(line, np.where(lerx, groove(np.abs(x) - 0.86, w), 0))

    # Wings: spars and ribs on the wing box; ribs on the moving surfaces
    fw = wing_fraction(x, y)
    for sf in (0.20, 0.68):
        m = wing & (np.abs(x) < gen.WING_TIP_X - 0.05)
        chord = wing_le(np.abs(x)) - wing_te(np.abs(x))
        d = (fw - sf) * chord
        line = np.maximum(line, np.where(m, groove(d, w), 0))
        rivet = np.maximum(rivet, np.where(m, rivets(d, x, 0.05, 0.004, offset=0.016), 0))
    for rx in (1.25, 1.85, 2.45, 3.05, 3.55):
        m = wing & (fw > 0.2) & (fw < 0.68)
        d = np.abs(x) - rx
        line = np.maximum(line, np.where(m, groove(d, w), 0))
        rivet = np.maximum(rivet, np.where(m, rivets(d, y, 0.05, 0.004, offset=0.016), 0))
    for x0, x1, f0, f1 in ((1.5, 1.95, 0.30, 0.50), (2.5, 2.85, 0.33, 0.50)):  # fuel / access panels
        xa = np.abs(x)
        inside = wing & (xa >= x0) & (xa <= x1) & (fw >= f0) & (fw <= f1)
        chord = wing_le(xa) - wing_te(xa)
        edge = np.minimum(np.minimum(xa - x0, x1 - xa), np.minimum(fw - f0, f1 - fw) * chord)
        line = np.maximum(line, np.where(inside, groove(edge, w), 0))
        rivet = np.maximum(rivet, np.where(inside & (edge > 0.01) & (edge < 0.03), rivets(edge - 0.018, x + y, 0.06, 0.005), 0))
    for k in range(1, 14):
        line = np.maximum(line, np.where(surf, groove(np.abs(x) - (gen.WING_ROOT_X + 0.3 * k), w * 0.8), 0))
    fs = stab_fraction(x, y)
    for sf in (0.25, 0.70):
        line = np.maximum(line, np.where(stab, groove((fs - sf) * gen.STAB_ROOT_CHORD * 0.8, w), 0))
    for rx in (1.2, 1.7):
        line = np.maximum(line, np.where(stab & (fs > 0.25) & (fs < 0.7), groove(np.abs(x) - rx, w), 0))
    ff = fin_fraction(y, z)
    for sf in (0.20, 0.55):
        line = np.maximum(line, np.where(fin & (ff < 0.72), groove((ff - sf) * 1.8, w), 0))
    for rz in (1.0, 1.5, 2.0):
        line = np.maximum(line, np.where(fin & (ff < 0.72), groove(z - rz, w), 0))
    for k in range(1, 5):
        line = np.maximum(line, np.where(rudder, groove(z - (gen.RUDDER_SPAN[0] + 0.2 * k), w * 0.8), 0))

    # ---- Colour ---------------------------------------------------------------------------------
    upper_c, lower_c = scheme["upper"], scheme["lower"]
    wave = scheme.get("demarcation", -0.10) + 0.05 * np.sin(y * 1.3) + 0.06 * (fbm(P, 1.2, 3, seed=5) - 0.5)
    t_upper = smooth(wave - 0.04, wave + 0.04, z)
    horizontal = wing | surf | stab | lerx
    t_upper = np.where(horizontal, (nz > 0).astype(np.float32), t_upper)
    t_upper = np.where(fin | rudder | frame, 1.0, t_upper)
    t_upper = np.where(up & (body | frame), np.maximum(t_upper, 1.0), t_upper)
    colour = lower_c * (1 - t_upper[..., None]) + upper_c * t_upper[..., None]
    if "camo" in scheme:
        colour = camouflage(P, scheme)

    # Panel-to-panel tone variation
    fidx = np.searchsorted(-np.array([Y(f) for f in FRAMES]), -y)
    region = (np.where(side, 0, np.where(up, 1, 2)) * 4 + (x > 0)).astype(np.int64)
    cell = np.where(body, fidx * 16 + region, (np.floor(np.abs(x) / 0.6) * 8 + np.floor(fw * 3) + (x > 0) * 97).astype(np.int64))
    colour *= cell_tone(cell, 3, 0.025)[..., None]

    # Radome and anti-glare panel
    radome = fus & (xd < 232)
    colour = np.where(radome[..., None], scheme["radome"], colour)
    colour = np.where((fus & (xd < 95 + 18))[..., None], srgb(40, 42, 45), colour)
    ag_half = np.clip((xd - 300) / (465 - 300), 0, 1) * 0.30 + 0.06
    antiglare = fus & (xd >= 300) & (xd <= 470) & (nz > 0.35) & (np.abs(x) < ag_half)
    colour = np.where(antiglare[..., None], scheme["antiglare"], colour)

    # Walkways on the wing roots (non-slip, darker)
    walk = wing & up & (np.abs(x) < 1.15) & (fw > 0.22) & (fw < 0.62)
    colour = np.where(walk[..., None], scheme["walkway"], colour)

    # Insignia: fuselage sides, upper left wing, lower right wing
    st, iz, ir = INSIGNIA_FUSELAGE
    ins = np.where(fus & side & (np.abs(N[..., 0]) > 0.5), star_and_bar(y - Y(st), z - iz, ir), 0)
    ix, wr = INSIGNIA_WING
    for sign, face in ((-1, up), (1, down)):
        x0 = sign * ix
        y0 = wing_le(ix) - 0.48 * (wing_le(ix) - wing_te(ix))
        m = wing & face & (np.sign(x) == sign)
        ins = np.maximum(ins, np.where(m, star_and_bar(x - x0, y - y0, wr), 0))
    if scheme.get("markings") != "none":
        colour = colour * (1 - ins[..., None]) + scheme["insignia"] * ins[..., None]

    # Intake lips (bare metal) and the duct (dark)
    lip_inner = gen.fuselage_params(655)[0] - 0.06
    off = np.clip((np.abs(x) - lip_inner) / (0.90 - lip_inner), 0, 1)
    lip_y = Y(655) - gen.INTAKE_LIP_SWEEP * off
    lip = intake & (y > lip_y - 0.07)
    duct = intake & (N[..., 1] > 0.6) & (y < lip_y - 0.03)
    colour = np.where(lip[..., None], METAL * 0.82, colour)
    colour = np.where(duct[..., None], DUCT, colour)

    # Gun ports and gun soot
    soot = np.zeros(shape, np.float32)
    for gx, gxd in GUN_MUZZLES:
        dx = x - gx
        along = Y(gxd) - y  # positive aft of the muzzle
        streak = smooth(0.06, 0.02, np.abs(dx)) * smooth(-0.02, 0.05, along) * smooth(1.0, 0.1, along)
        soot = np.maximum(soot, np.where(fus & (nz > 0), streak * 0.85, 0))
        port = np.hypot(dx, (y - Y(gxd)) * 0.6) < 0.025
        colour = np.where((fus & port)[..., None], srgb(12, 12, 12), colour)
    # Exhaust soot: rear fuselage, stabilator undersides, rudder base
    aft = smooth(Y(1360), Y(1500), y)
    streaks = fbm(P, 3.0, 3, seed=11, stretch=(4.0, 0.25, 4.0))
    lower_bias = np.clip(0.6 - z * 1.2, 0.2, 1.0)
    soot = np.maximum(soot, np.where(fus | rudder | (stab & down), aft * (0.35 + 0.5 * streaks) * lower_bias, 0))
    colour = colour * (1 - soot[..., None]) + SOOT * soot[..., None]

    # Grime: streaks with the airflow, dirt in the panel lines, darker underneath
    frame_ys = np.array([Y(f) for f in FRAMES], dtype=np.float32)
    aft_of = np.full(shape, 9.0, np.float32)  # metres aft of the nearest seam ahead
    for fy in frame_ys:
        d = fy - y
        aft_of = np.where((d >= 0) & (d < aft_of), d, aft_of)
    seam_wake = np.where(body, np.exp(-aft_of / 0.35), 0.5)
    grime = fbm(P, 2.2, 4, seed=21, stretch=(3.0, 0.3, 3.0))
    grime = np.clip((grime - 0.52) * 2.0, 0, 1) * (0.05 + 0.05 * down) * (0.4 + 0.9 * seam_wake)
    colour *= (1 - grime - 0.3 * line)[..., None]
    import cockpit_kit  # the cockpit well, seen through the canopy: cockpit-dark
    import livery_paint

    colour = livery_paint.lines(scheme, colour, line)

    well = fus & cockpit_kit.well_mask(P)
    colour = np.where(well[..., None], srgb(46, 48, 50), colour)
    colour *= (0.55 + 0.45 * np.power(np.clip(ao, 0, 1), 0.8))[..., None]

    # Worn leading edges: chips of bare metal
    le_zone = (surf & on("LEFlapL", "LEFlapR") & (fw < 0.03)) | ((stab) & (fs < 0.04)) | (fin & (ff < 0.03))
    le_zone = le_zone & (np.where(stab, fs, np.where(fin, ff, fw)) < 0.015)
    chips = le_zone & (fbm(P, 30.0, 3, seed=31) > 0.68)
    colour = np.where(chips[..., None], METAL * 0.75, colour)

    # ---- Roughness, metalness, height ---------------------------------------------------------------
    rough0, metal0 = livery_paint.base(scheme, False)
    rough = rough0 + 0.08 * (fbm(P, 4.0, 3, seed=41) - 0.5) + 0.12 * grime + 0.12 * line
    rough = np.where(antiglare, 0.78, rough)
    rough = np.where(walk, 0.88, rough)
    rough = np.where(radome, 0.45, rough)
    rough = np.maximum(rough, soot * 0.85)
    metal = np.where(radome | antiglare | walk | well, 0.0, np.full(shape, metal0, np.float32))
    metal = np.where(lip, 0.35, metal)
    rough = np.where(lip, 0.48, rough)
    metal = np.where(chips, 0.7, metal)
    rough = np.where(chips, 0.45, rough)
    keep = radome | antiglare | lip | duct | well | (fus & (xd < 95 + 18))
    colour, rough, metal = livery_paint.trim(scheme, P, N, ao, line, colour, rough, metal, fus, wing | surf,
                                             wing_le(np.abs(x)) - y, [on("StabilatorL"), on("StabilatorR")],
                                             fin | rudder, keep, Y(232) - 0.3, Y(1360) + 0.2)
    height = -line - 0.35 * rivet
    return colour, np.clip(rough, 0.05, 1), metal, height


def paint_details(P, N, part, ids, ao, scheme):
    x, y, z = P[..., 0], P[..., 1], P[..., 2]
    shape = x.shape
    colour = np.broadcast_to(scheme["lower"], shape + (3,)).copy()
    rough = np.full(shape, 0.55, np.float32)
    metal = np.zeros(shape, np.float32)
    height = np.zeros(shape, np.float32)

    on = make_on(part, ids)

    # Nozzles: titanium with a heat tint toward the exit, sooty inside, petal seams
    noz = on("NozzleL", "NozzleR")
    cx = np.where(x > 0, gen.NOZZLE_X, -gen.NOZZLE_X)
    radial = np.stack([x - cx, np.zeros_like(x), z - gen.NOZZLE_Z], axis=-1)
    inner = (radial * N).sum(-1) < 0
    t = np.clip((gen.NOZZLE_Y0 - y) / (gen.NOZZLE_Y0 - gen.NOZZLE_Y1), 0, 1)
    keys = [(0.0, srgb(160, 162, 166)), (0.45, srgb(178, 156, 108)), (0.7, srgb(130, 95, 70)),
            (0.88, srgb(84, 78, 118)), (1.0, srgb(70, 70, 80))]
    tint = np.zeros(shape + (3,), np.float32)
    for (t0, c0), (t1, c1) in zip(keys, keys[1:]):
        k = np.clip((t - t0) / (t1 - t0), 0, 1)[..., None]
        seg = (t >= t0) & (t <= t1)
        tint = np.where(seg[..., None], c0 * (1 - k) + c1 * k, tint)
    tint *= (0.85 + 0.3 * fbm(P, 9.0, 3, seed=51))[..., None]
    colour = np.where((noz & ~inner)[..., None], tint, colour)
    colour = np.where((noz & inner)[..., None], SOOT, colour)
    metal = np.where(noz, np.where(inner, 0.3, 0.92), metal)
    rough = np.where(noz, np.where(inner, 0.85, 0.32 + 0.15 * fbm(P, 12.0, 2, seed=53)), rough)
    petal = np.mod(np.arctan2(z - gen.NOZZLE_Z, x - cx) * 16 / (2 * math.pi), 1.0)
    height = np.where(noz & ~inner, -groove(np.minimum(petal, 1 - petal), 0.06), height)

    ab = on("AfterburnerL", "AfterburnerR")
    colour = np.where(ab[..., None], srgb(46, 40, 36), colour)
    metal = np.where(ab, 0.7, metal)
    rough = np.where(ab, 0.62, rough)

    seat = on("EjectionSeat")
    cushion = seat & ((N[..., 1] > 0.6) | (N[..., 2] > 0.6))
    colour = np.where(seat[..., None], srgb(24, 25, 27), colour)
    colour = np.where(cushion[..., None], srgb(68, 72, 50), colour)
    rough = np.where(seat, 0.8, rough)

    pitot = on("Pitot")
    colour = np.where(pitot[..., None], METAL, colour)
    metal = np.where(pitot, 0.9, metal)
    rough = np.where(pitot, 0.3, rough)

    rails = on("WingtipRailL", "WingtipRailR")
    colour = np.where(rails[..., None], scheme["lower"] * 0.9, colour)
    slot = rails & (N[..., 2] < -0.6)
    colour = np.where(slot[..., None], srgb(40, 42, 44), colour)

    struts = on("NoseGearStrut", "MainGearStrutL", "MainGearStrutR")
    colour = np.where(struts[..., None], srgb(200, 202, 205), colour)
    metal = np.where(struts, 0.6, metal)
    rough = np.where(struts, 0.35, rough)
    wheels = on("NoseGearWheel", "MainGearWheelL", "MainGearWheelR")
    colour = np.where(wheels[..., None], srgb(28, 28, 28), colour)
    rough = np.where(wheels, 0.9, rough)

    colour *= (0.6 + 0.4 * np.power(np.clip(ao, 0, 1), 0.8))[..., None]
    return colour, np.clip(rough, 0.05, 1), metal, height


# ---------------------------------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------------------------------


def downsample(a):
    h, w = a.shape[0] // SUPERSAMPLE, a.shape[1] // SUPERSAMPLE
    return a.reshape(h, SUPERSAMPLE, w, SUPERSAMPLE, *a.shape[2:]).mean(axis=(1, 3))


def save_png(path, rgb, colorspace):
    h, w = rgb.shape[:2]
    img = bpy.data.images.new(os.path.basename(path), w, h, alpha=False, float_buffer=False)
    img.colorspace_settings.name = colorspace
    rgba = np.concatenate([rgb.reshape(h, w, -1)[..., :3] if rgb.ndim == 3 else np.repeat(rgb[..., None], 3, -1),
                           np.ones((h, w, 1), np.float32)], axis=-1)
    img.pixels.foreach_set(np.clip(rgba, 0, 1).astype(np.float32).ravel())
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    return img


def bake_normal(set_name, objs, height_full, size, path):
    hh, hw = height_full.shape
    himg = new_image(f"{set_name}_Height", hh, True, "Non-Color")
    himg.pixels.foreach_set(np.repeat(height_full[..., None], 4, axis=-1).astype(np.float32).ravel())
    target = new_image(f"{set_name}_NormalBake", size, False, "Non-Color", 0.5)

    def build(nodes, links):
        uv = nodes.new("ShaderNodeTexImage")
        uv.image = himg
        uv.interpolation = "Linear"
        bump = nodes.new("ShaderNodeBump")
        bump.inputs["Distance"].default_value = BUMP_DISTANCE
        links.new(uv.outputs["Color"], bump.inputs["Height"])
        bsdf = nodes.new("ShaderNodeBsdfPrincipled")
        links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
        return bsdf

    mat, _ = bake_material(build)
    bpy.context.scene.cycles.samples = 4
    bake(objs, mat, target, "NORMAL", 8)
    bpy.data.materials.remove(mat)
    target.filepath_raw = path
    target.file_format = "PNG"
    target.save()


def apply_preview_material(set_name, paths):
    mat = bpy.data.materials.get(f"{gen.AIRFRAME}_{set_name}")
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


def render_preview(out_dir, prefix):
    scene = bpy.context.scene
    scene.cycles.samples = 64
    try:
        scene.cycles.use_denoising = True
    except Exception:
        pass
    scene.render.resolution_x, scene.render.resolution_y = 1600, 1000
    world = scene.world or bpy.data.worlds.new("World")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    bg.inputs["Color"].default_value = (0.55, 0.68, 0.85, 1)
    bg.inputs["Strength"].default_value = 0.8
    sun_data = bpy.data.lights.new("Sun", "SUN")
    sun_data.energy = 4.0
    sun = bpy.data.objects.new("Sun", sun_data)
    sun.rotation_euler = (math.radians(50), math.radians(10), math.radians(140))
    scene.collection.objects.link(sun)
    for o in bpy.data.objects:
        if o.type == "MESH" and o.get("afterburner_kind") in ("Gear", "GearWheel", "GearDoor"):
            o.hide_render = True  # as in the game: gear up
    cam = bpy.data.objects.new("PaintCam", bpy.data.cameras.new("PaintCam"))
    scene.collection.objects.link(cam)
    scene.camera = cam
    cam.data.lens = 50
    from mathutils import Vector

    for name, eye, target in (
        ("front", Vector((9.5, 12.0, 4.0)), Vector((0, 1.2, 0.2))),
        ("rear", Vector((-8.5, -11.0, 5.5)), Vector((0, 0.0, 0.3))),
        ("top", Vector((0.5, 1.0, 16.0)), Vector((0, 1.0, 0))),
        ("close", Vector((3.2, 3.6, 1.6)), Vector((0.2, 1.2, 0.1))),
    ):
        cam.location = eye
        cam.rotation_euler = (target - eye).to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = os.path.join(out_dir, f"{prefix}_paint_{name}.png")
        bpy.ops.render.render(write_still=True)
        print("rendered", scene.render.filepath)


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", required=True)
    parser.add_argument("--skin", default="Ghost")
    parser.add_argument("--preview", action="store_true")
    args = parser.parse_args(argv)
    os.makedirs(args.out, exist_ok=True)
    import livery_paint

    scheme = livery_paint.with_liveries(SCHEMES)[args.skin]

    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.render.bake.margin_type = "EXTEND"
    world = scene.world or bpy.data.worlds.new("World")
    scene.world = world
    world.light_settings.distance = 0.35  # AO reach (m)

    written = {}
    for set_name, size in SETS.items():
        full = size * SUPERSAMPLE
        maps, ids, objs = bake_maps(set_name, full)
        P, N, part, ao, valid = maps["P"], maps["N"], maps["ID"], maps["AO"], maps["valid"]
        if set_name == "Details":
            colour, rough, metal, height = paint_details(P, N, part, ids, ao, scheme)
        else:
            colour, rough, metal, height = paint_airframe(P, N, part, ids, ao, scheme)
        # Outside every UV island: a neutral fill so mipmaps don't bleed dark edges
        colour = np.where(valid[..., None], colour, scheme["upper"] if set_name != "Details" else scheme["lower"])
        rough = np.where(valid, rough, 0.6)
        metal = np.where(valid, metal, 0)
        height = np.where(valid, height, 0)

        base = os.path.join(args.out, f"{gen.AIRFRAME}_{args.skin}_{set_name}")
        paths = {
            "Color": base + "_Color.png",
            "Roughness": base + "_Roughness.png",
            "Metalness": base + "_Metalness.png",
            "Normal": base + "_Normal.png",
        }
        save_png(paths["Color"], to_srgb(downsample(colour)), "sRGB")
        save_png(paths["Roughness"], downsample(rough), "Non-Color")
        save_png(paths["Metalness"], downsample(metal), "Non-Color")
        bake_normal(set_name, objs, height.astype(np.float32), size, paths["Normal"])
        written[set_name] = paths
        print(f"painted {set_name}: {size}px, {len(objs)} parts")

    if args.preview:
        for set_name, paths in written.items():
            apply_preview_material(set_name, paths)
        render_preview(args.out, f"{gen.AIRFRAME}_{args.skin}")
        bpy.ops.wm.save_as_mainfile(filepath=os.path.join(args.out, f"{gen.AIRFRAME}_painted.blend"))


if __name__ == "__main__":
    main()
