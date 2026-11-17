"""
Afterburner: the shop cards' pictures for the cosmetics that aren't camos (Config/Cosmetics "Card"), in the camo
cards' style (tools/blender/camo_cards.py): the F-16A in its default Three-Tone Grey, on a transparent background
so it sits on the card's own colour, cropped and fitted to 1024 x 512.
  Trail: the jet on afterburner streaming display smoke in that colour from both wingtips (several colours
    follow one another along the trail, as in the game).
  WingArt: the jet from above, the decal on top of each wing, mid-span, pointing outboard (as Shared/WingArt).
  Marker: a close-up of the cockpit's side with a row of that kill marker under the canopy (as
    Shared/KillMarkers), five of them.
The game itself draws these cards live (src/client/UI/ShopPreview.luau: trails and wing art in a ViewportFrame,
markers in 2D), so nothing needs uploading; this is the offline, higher-quality option if Will wants baked
pictures instead (upload them and point the cards at them, as the camos' Images do).

  blender -b tools/blender/out/F16A_base.blend --python tools/blender/cosmetic_cards.py -- \
      --textures tools/blender/out/textures --decals tools/cosmetics/out --out <dir> [--only TrailRed,WingAce]

The wing-art decals come from tools/cosmetics/wing_art.py (--decals). Writes <Id>.png for each cosmetic.
"""

import argparse
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import camo_cards  # noqa: E402  (the camo cards' lighting, camera and crop)
import f16a_paint  # noqa: E402,F401  (sets the shared generator module to the F-16A)
import f5e_paint as paint  # noqa: E402

SKIN = "Falcon"
SYMBOLS = r"C:\Windows\Fonts\seguisym.ttf"


def rgb(r, g, b):
    return (r / 255, g / 255, b / 255)


GOLD = rgb(255, 201, 60)
# Config/Cosmetics: the trails' colours (along the trail) and the markers' glyphs and colours
TRAILS = {
    "TrailRed": [rgb(235, 60, 50)],
    "TrailBlue": [rgb(60, 120, 240)],
    "TrailGreen": [rgb(70, 200, 90)],
    "TrailOrange": [rgb(255, 138, 61)],
    "TrailTricolour": [rgb(235, 60, 50), rgb(245, 245, 245), rgb(60, 120, 240)],
    "TrailVIP": [GOLD],
    "TrailAurora": [rgb(80, 255, 170), rgb(110, 150, 255), rgb(200, 90, 255)],
}
MARKERS = {
    "MarkerBars": ("▮", rgb(235, 235, 225)),
    "MarkerRoundels": ("◉", rgb(235, 80, 70)),
    "MarkerJets": ("✈", rgb(235, 235, 225)),
    "MarkerGold": ("★", GOLD),
    "MarkerDiamonds": ("◆", rgb(90, 220, 255)),
    "MarkerSun": ("☀", rgb(255, 170, 50)),
}
WING_ART = ("WingShark", "WingAce", "WingBolt", "WingEight", "WingComet", "WingSunburst")
MARKS = 5  # kill markers in a row: a five-star mastery


def linear(c):
    return tuple(v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in c)


def attachment(name):
    return bpy.data.objects[f"ATT_{name}"].matrix_world.translation.copy()


def ray(origin, direction):
    """The first hit on the jet's skin: (location, normal, object) or None."""
    hit, loc, normal, _, obj, _ = bpy.context.scene.ray_cast(bpy.context.view_layer.depsgraph, origin, direction)
    return (loc, normal, obj) if hit else None


def camera(eye, target, lens=50):
    cam = bpy.context.scene.camera
    cam.data.lens = lens
    cam.location = Vector(eye)
    cam.rotation_euler = (Vector(target) - Vector(eye)).to_track_quat("-Z", "Y").to_euler()


def hide(names, hidden=True):
    for n in names:
        o = bpy.data.objects.get(n)
        if o:
            o.hide_render = hidden


# --- Trails ---------------------------------------------------------------------------------------------------

def smoke_material(name):
    """Display smoke: the colour from the trail's 'Col' attribute, thinning out (its alpha) along the trail."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    for n in list(nodes):
        nodes.remove(n)
    out = nodes.new("ShaderNodeOutputMaterial")
    col = nodes.new("ShaderNodeAttribute")
    col.attribute_name = "Col"
    lit = nodes.new("ShaderNodeBsdfDiffuse")
    glow = nodes.new("ShaderNodeEmission")
    glow.inputs["Strength"].default_value = 0.9  # glowing, so the colour reads bold
    links.new(col.outputs["Color"], lit.inputs["Color"])
    links.new(col.outputs["Color"], glow.inputs["Color"])
    both = nodes.new("ShaderNodeAddShader")
    links.new(lit.outputs[0], both.inputs[0])
    links.new(glow.outputs[0], both.inputs[1])
    # Puffs: noise through the smoke, so it reads as smoke rather than a tube
    geo = nodes.new("ShaderNodeNewGeometry")
    puffs = nodes.new("ShaderNodeTexNoise")
    puffs.inputs["Scale"].default_value = 0.9
    puffs.inputs["Detail"].default_value = 5
    links.new(geo.outputs["Position"], puffs.inputs["Vector"])
    soft = nodes.new("ShaderNodeMapRange")
    soft.inputs["From Min"].default_value = 0.3
    soft.inputs["From Max"].default_value = 0.6
    soft.inputs["To Min"].default_value = 0.35
    links.new(puffs.outputs["Fac"], soft.inputs["Value"])
    alpha = nodes.new("ShaderNodeMath")
    alpha.operation = "MULTIPLY"
    links.new(col.outputs["Alpha"], alpha.inputs[0])
    links.new(soft.outputs[0], alpha.inputs[1])
    clear = nodes.new("ShaderNodeBsdfTransparent")
    mix = nodes.new("ShaderNodeMixShader")
    links.new(alpha.outputs[0], mix.inputs["Fac"])
    links.new(clear.outputs[0], mix.inputs[1])
    links.new(both.outputs[0], mix.inputs[2])
    links.new(mix.outputs[0], out.inputs["Surface"])
    return mat


def trail(name, start, colours, mat, length=20.0, sides=14, segments=90):
    """A tube from a wingtip back along a gentle climbing turn, thickening and fading, colours in turn along it."""
    verts, faces, cols = [], [], []
    for i in range(segments + 1):
        t = i / segments
        centre = start + Vector((start.x * 0.15 * t, -length * t, -1.6 * t * t))
        ahead = start + Vector((start.x * 0.15 * (t + 0.01), -length * (t + 0.01), -1.6 * (t + 0.01) ** 2))
        d = (centre - ahead).normalized()
        side = d.cross(Vector((0, 0, 1))).normalized()
        up = side.cross(d).normalized()
        r = 0.15 + 0.9 * t ** 0.8
        band = min(int(t * len(colours) * 1.0), len(colours) - 1)  # equal stretches of each colour
        colour = linear(colours[band])
        alpha = min(1.0, t * 12) * (1 - t) ** 0.6 * 0.95
        for k in range(sides):
            a = k / sides * math.tau
            verts.append(centre + (side * math.cos(a) + up * math.sin(a)) * r)
            cols.append((*colour, alpha))
    for i in range(segments):
        for k in range(sides):
            a, b = i * sides + k, i * sides + (k + 1) % sides
            faces.append((a, b, b + sides, a + sides))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata([tuple(v) for v in verts], [], faces)
    attr = mesh.color_attributes.new("Col", "FLOAT_COLOR", "POINT")
    for i, c in enumerate(cols):
        attr.data[i].color = c
    mesh.polygons.foreach_set("use_smooth", [True] * len(mesh.polygons))
    mesh.materials.append(mat)
    obj = bpy.data.objects.new(name, mesh)
    obj.visible_shadow = False
    bpy.context.scene.collection.objects.link(obj)
    return obj


def flame():
    """The afterburner: an orange cone out of the nozzle (display smoke only flows on afterburner)."""
    nozzle = attachment("Nozzle1")
    made = []
    for name, colour, strength, alpha, radius, depth in (("Plume", (1, 0.3, 0.04, 1), 3, 0.55, 0.46, 3.6),
                                                         ("Core", (1, 0.62, 0.25, 1), 6, 0.9, 0.24, 2.2)):
        mat = bpy.data.materials.new(name)
        mat.use_nodes = True
        b = mat.node_tree.nodes.get("Principled BSDF")
        b.inputs["Base Color"].default_value = (0, 0, 0, 1)
        b.inputs["Emission Color"].default_value = colour
        b.inputs["Emission Strength"].default_value = strength
        b.inputs["Alpha"].default_value = alpha
        bpy.ops.mesh.primitive_cone_add(radius1=radius, radius2=0.03, depth=depth, vertices=24,
                                        location=nozzle + Vector((0, -depth / 2, 0)),
                                        rotation=(math.radians(90), 0, 0))
        cone = bpy.context.active_object
        cone.data.materials.append(mat)
        cone.visible_shadow = False
        made.append(cone)
    return made


def trail_cards(ids, out):
    mat = smoke_material("Smoke")
    tips = [attachment("WingtipR"), attachment("WingtipL")]
    extras = flame()
    camera((19.0, 17.0, 7.5), (0.0, -4.0, -0.3), lens=40)
    for cid in ids:
        made = [trail(f"{cid}_{i}", tip, TRAILS[cid], mat) for i, tip in enumerate(tips)]
        render(out, cid)
        for o in made:
            bpy.data.objects.remove(o)
    for o in extras:
        bpy.data.objects.remove(o)


# --- Decals (wing art, kill markers) ---------------------------------------------------------------------------

def decal_material(name, image_path):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = nodes.get("Principled BSDF")
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(image_path)
    tex.extension = "CLIP"
    links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    links.new(tex.outputs["Alpha"], bsdf.inputs["Alpha"])
    bsdf.inputs["Roughness"].default_value = 0.5
    return mat


def plate(name, centre, normal, along, size, mat):
    """A flat decal: width along `along`, height across it on the skin, lifted just off the skin."""
    x = along.normalized()
    z = normal.normalized()
    y = z.cross(x).normalized()
    x = y.cross(z).normalized()
    bpy.ops.mesh.primitive_plane_add(size=1)
    obj = bpy.context.active_object
    obj.name = name
    obj.matrix_world = Matrix.Translation(centre + z * 0.02) @ Matrix((x, y, z)).transposed().to_4x4() @ \
        Matrix.Diagonal((size[0], size[1], 1, 1))
    obj.data.materials.append(mat)
    obj.visible_shadow = False
    return obj


def wing_spot(tip):
    """Mid-span, mid-chord on the wing's top: (point, normal), searching along the chord for the top skin."""
    x = tip.x * 0.55
    hits = []
    y = tip.y + 4.0
    while y > tip.y - 4.0:
        h = ray(Vector((x, y, 5.0)), Vector((0, 0, -1)))
        if h and h[2].name.startswith(("Wing", "LEFlap", "Flap", "Aileron")) and h[1].z > 0.7:
            hits.append(h)
        y -= 0.05
    front, back = hits[0][0], hits[-1][0]
    mid = (front + back) / 2
    h = ray(Vector((mid.x, mid.y, 5.0)), Vector((0, 0, -1)))
    return h[0], h[1], (front - back).length


def wing_cards(ids, decals, out):
    camera((14.0, 9.0, 17.0), (0.0, -0.8, 0.0), lens=55)
    tipR, tipL = attachment("WingtipR"), attachment("WingtipL")
    semi = (abs(tipR.x) + abs(tipL.x)) / 2
    for cid in ids:
        made = []
        for side, tip in (("R", tipR), ("L", tipL)):
            point, normal, chord = wing_spot(tip)
            h = min(semi * 0.3, chord * 0.85)  # as big as fits: it has to read on a small card
            mat = decal_material(f"{cid}_{side}", os.path.join(decals, f"{cid}_{side}.png"))
            made.append(plate(f"{cid}_{side}", point, normal, Vector((1, 0, 0)), (h * 2, h), mat))
        render(out, cid)
        for o in made:
            bpy.data.objects.remove(o)


def marker_strip(cid, glyph, colour, centre, normal):
    """A row of glyphs laid on the fuselage's side, read nose-wards, wrapped on to the skin."""
    curve = bpy.data.curves.new(cid, "FONT")
    curve.body = glyph * MARKS
    curve.font = bpy.data.fonts.load(SYMBOLS)
    curve.size = 0.6
    curve.align_x = "CENTER"
    curve.align_y = "CENTER"
    obj = bpy.data.objects.new(cid, curve)
    bpy.context.scene.collection.objects.link(obj)
    z = normal.normalized()
    x = Vector((0, 1 if z.x > 0 else -1, 0))  # reads towards the nose, seen from that side
    y = z.cross(x).normalized()
    obj.matrix_world = Matrix.Translation(centre + z * 0.03) @ Matrix((x, y, z)).transposed().to_4x4()
    mat = bpy.data.materials.new(cid)
    mat.use_nodes = True
    b = mat.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (*linear(colour), 1)
    b.inputs["Roughness"].default_value = 0.45
    curve.materials.append(mat)
    obj.visible_shadow = False
    wrap = obj.modifiers.new("Wrap", "SHRINKWRAP")
    wrap.target = bpy.data.objects["Fuselage"]
    wrap.wrap_method = "PROJECT"
    wrap.use_negative_direction = True
    wrap.use_project_z = True
    wrap.offset = 0.015
    return obj


def marker_cards(ids, out):
    eye = attachment("CockpitEye")
    spot = eye + Vector((0, -0.9, -0.85))  # Shared/KillMarkers: under the eye and a little behind it
    hit = ray(spot + Vector((4, 0, 0)), Vector((-1, 0, 0)))
    centre, normal = hit[0], hit[1]
    camera((5.0, 4.2, 1.0), (centre.x - 0.4, centre.y + 0.3, centre.z + 0.1), lens=42)
    for cid in ids:
        glyph, colour = MARKERS[cid]
        strip = marker_strip(cid, glyph, colour, centre, normal)
        render(out, cid, crop=False)
        bpy.data.objects.remove(strip)


# --- Render ------------------------------------------------------------------------------------------------------

def gpu(scene):
    """Cycles on the GPU when there is one (much quicker), else the CPU."""
    prefs = bpy.context.preferences.addons["cycles"].preferences
    for backend in ("HIP", "OPTIX", "CUDA", "METAL", "ONEAPI"):
        try:
            prefs.compute_device_type = backend
            prefs.get_devices()
        except Exception:
            continue
        if any(d.type == backend for d in prefs.devices):
            for d in prefs.devices:
                d.use = d.type == backend
            scene.cycles.device = "GPU"
            return


def render(out, name, crop=True):
    scene = bpy.context.scene
    path = os.path.join(out, f"{name}.png")
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    if crop:
        camo_cards.crop(path)
    else:  # a close-up fills the frame: just halve it
        img = bpy.data.images.load(path)
        img.scale(camo_cards.WIDTH, camo_cards.HEIGHT)
        img.filepath_raw = path
        img.save()
    print("card", path)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--textures", required=True)
    parser.add_argument("--decals", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--only", default="", help="comma list of cosmetic ids; default: all")
    args = parser.parse_args(argv)
    os.makedirs(args.out, exist_ok=True)
    only = set(filter(None, args.only.split(",")))

    def wanted(ids):
        return [i for i in ids if not only or i in only]

    scene = bpy.context.scene
    camo_cards.setup(scene)
    scene.cycles.samples = 96
    gpu(scene)
    try:
        scene.view_settings.look = "AgX - Punchy"  # bold colours (Will: cool over realistic)
    except TypeError:
        pass
    for set_name in camo_cards.SETS:
        paint.apply_preview_material(set_name, {m: os.path.join(args.textures, f"F16A_{SKIN}_{set_name}_{m}.png")
                                                for m in ("Color", "Roughness", "Metalness", "Normal")})
    trail_cards(wanted(TRAILS), args.out)
    wing_cards(wanted(WING_ART), args.decals, args.out)
    marker_cards(wanted(MARKERS), args.out)


main()
