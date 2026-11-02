"""
Afterburner: paints the B-1B Lancer with the shared painter (jet_paint.py): its panel layout, markings and
skins.

  blender -b tools/blender/out/B1B_base.blend --python tools/blender/b1b_paint.py -- \
      --out <absolute dir> [--skin Strategic] [--preview]

Use the .blend whose FBX was imported into Studio: the textures follow its UV layout.

What differs from the fighters' painters, all from this script (the shared modules are unchanged):
  * the bake's position range is widened to +-50 m (the default +-20 m is a fighter's size)
  * there is no cockpit well: the fuselage under the windscreen glass is painted dark instead, so the
    windows read as windows from outside
  * a scheme can carry an `accent` (colour): a band along each side of the fuselage, a band across the fin
    and the wing and taileron tips in that colour (the Ember skin)
  * the previews are framed for a 44.5 m bomber
"""

import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import b1b_generate as b1  # noqa: E402  (sets the shared generator module to the B-1B)
import cockpit_kit  # noqa: E402
import jet_paint  # noqa: E402

paint = jet_paint.paint
kit = b1.kit
srgb, smooth = jet_paint.srgb, jet_paint.smooth
paint.POS_RANGE = 50.0


def edge(root_y, tip_y):
    """A wing edge as set (turned to the model's sweep), as a function of |x| for arrays."""
    x0, y0, _ = b1.turned((b1.WING_ROOT_X, root_y, b1.WING_Z))
    x1, y1, _ = b1.turned((b1.WING_TIP_X, tip_y, b1.WING_Z))

    def fn(xa):
        return y0 + (np.asarray(xa) - x0) * (y1 - y0) / (x1 - x0)

    return fn


LAYOUT = {
    "body": ["Fuselage", "Glove", "Nacelles", "Vanes"],
    "frames": [300, 585, 735, 900, 1100, 1350, 1600, 1850, 2100, 2350, 2600, 2850, 3100, 3350, 3600, 3850, 4100, 4300],
    "side_lines": [(0.45, 300, 4200), (-1.10, 600, 3500)],
    "side_panels": [(880, 1020, -1.30, -0.30), (1500, 1650, -1.50, -0.60)],  # crew entry, avionics bay
    "wing": (edge(b1.WING_ROOT_LE, b1.WING_TIP_LE), edge(b1.WING_ROOT_LE - b1.WING_ROOT_CHORD, b1.WING_TIP_LE - b1.WING_TIP_CHORD)),
    "wings": ["WingL", "WingR"],
    "surfaces": ["LEFlapL", "LEFlapR", "SpoilerL", "SpoilerR", "FlapL", "FlapR"],
    "tail": ["StabilatorL", "StabilatorR"],
    "spars": (0.12, 0.40, 0.62, 0.75),
    "ribs": (6.5, 18.0, 1.4),
    "fin": ["Fin"],
    "rudder": ["Rudder"],
    "fin_lines": [2.7, 4.0, 5.3, 6.5],
    "upper_only": ["CanopyFrame"],
    "under_z": (-0.70, -1.20),
    "radome": 300,
    "ducts": ["IntakeDucts"],
    "antiglare": (420, 585, 0.30, 0.80),
    "lip": (["Nacelles"], 2185),
    "hot": (4700, 4800),  # the tail is cold: the engines are under the wings
    "gun": None,
    "insignia": "star_us",
    "roundel_fuselage": (1300, 1.30, 0.62, ["Fuselage"]),
    "roundel_wing": (14.0, 0.85, 0.45),
    "fin_flash": None,
    "nozzles": [(-b1.ENGINE_X[0], b1.NOZZLE_Z), (b1.ENGINE_X[0], b1.NOZZLE_Z), (-b1.ENGINE_X[1], b1.NOZZLE_Z),
                (b1.ENGINE_X[1], b1.NOZZLE_Z)],
    "nozzle_y": (b1.NOZZLE_Y0, b1.NOZZLE_Y1),
    "petals": 20,
    "pitot": "metal",
}

SCHEMES = {
    # Gunship grey all over (FS 36118), low-visibility markings: the B-1B as it flies
    "Strategic": {
        "base": srgb(84, 89, 94),
        "radome": srgb(78, 82, 87),
        "antiglare": srgb(74, 78, 83),
        "lower": srgb(90, 95, 100),
        "upper": srgb(84, 89, 94),
        "markings": "lowvis",
    },
    # Ember (cool over real): dark charcoal with red-orange bands down the fuselage, across the fin and on the
    # wing and taileron tips; a black radome; no national markings
    "Ember": {
        "base": srgb(38, 40, 44),
        "radome": srgb(18, 18, 20),
        "antiglare": srgb(26, 27, 30),
        "lower": srgb(44, 46, 50),
        "upper": srgb(38, 40, 44),
        "markings": "none",
        "rough": 0.42,
        "line_colour": srgb(62, 64, 70),
        "accent": srgb(255, 84, 28),
    },
}


# ---------------------------------------------------------------------------------------------------
# B-1B specifics
# ---------------------------------------------------------------------------------------------------


def window_mask(P):
    """Fuselage texels under the windscreen glass: painted dark, so the panes read as windows."""
    x, y, z = P[..., 0], P[..., 1], P[..., 2]
    x0, x1 = b1.WINDOW_XD
    xd = kit.REF_PITOT_XD + (kit.CG_FROM_PITOT - y) * kit.REF_PX_PER_M
    stations = np.linspace(x0, x1, 16)
    cz = np.array([(kit.fuselage_params(s)[1] + kit.fuselage_params(s)[2]) / 2 for s in stations])
    phi = np.arctan2(x, z - np.interp(xd, stations, cz))
    return (xd > x0 + 2) & (xd < x1 - 2) & (np.abs(phi) < b1.WINDOW_PHI - 0.02)


cockpit_kit.well_mask = window_mask  # jet_paint paints this mask (on the fuselage) cockpit-dark

_paint_airframe = jet_paint.paint_airframe


def paint_airframe(L, P, N, part, ids, ao, scheme):
    colour, rough, metal, height = _paint_airframe(L, P, N, part, ids, ao, scheme)
    accent = scheme.get("accent")
    if accent is None:
        return colour, rough, metal, height
    x, y, z = P[..., 0], P[..., 1], P[..., 2]
    on = paint.make_on(part, ids)
    xd = kit.REF_PITOT_XD + (kit.CG_FROM_PITOT - y) * kit.REF_PX_PER_M
    mask = np.zeros(x.shape, np.float32)

    # A band down each side of the fuselage, rising from the nose to run above the glove, pointed at both ends
    fus = on("Fuselage")
    side = np.abs(N[..., 2]) < 0.75
    zc = 0.15 + 1.05 * smooth(450, 1150, xd)
    half = 0.16 * smooth(380, 900, xd) * (1 - smooth(3900, 4250, xd))
    band = 1 - smooth(half - 0.012, half + 0.012, np.abs(z - zc))
    mask = np.maximum(mask, np.where(fus & side & (xd > 380), band, 0))
    # and a thin pinstripe under it
    pin = 1 - smooth(0.018, 0.03, np.abs(z - (zc - half - 0.09)))
    mask = np.maximum(mask, np.where(fus & side & (xd > 900) & (xd < 3900), pin, 0))

    # Across the fin, a chevron band near the top; the rudder carries it too
    fin = on("Fin", "Rudder")
    fz = 6.0 - (xd - 3900) * 0.0012
    mask = np.maximum(mask, np.where(fin, 1 - smooth(0.32, 0.36, np.abs(z - fz)), 0))

    # Wing and taileron tips
    wings = on("WingL", "WingR", "LEFlapL", "LEFlapR", "FlapL", "FlapR")
    mask = np.maximum(mask, np.where(wings, smooth(16.6, 16.7, np.abs(x)), 0))
    tails = on("StabilatorL", "StabilatorR")
    mask = np.maximum(mask, np.where(tails, smooth(5.7, 5.8, np.abs(x)), 0))

    shade = (0.55 + 0.45 * np.power(np.clip(ao, 0, 1), 0.8))
    colour = colour * (1 - mask[..., None]) + (accent * shade[..., None]) * mask[..., None]
    rough = rough * (1 - mask) + 0.35 * mask
    metal = metal * (1 - mask)
    return colour, rough, metal, height


jet_paint.paint_airframe = paint_airframe


def render_preview(out_dir, prefix):
    """paint.render_preview, framed for the bomber."""
    import bpy
    from mathutils import Vector

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
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
    sun.data.energy = 4.0
    sun.rotation_euler = (math.radians(50), math.radians(10), math.radians(140))
    scene.collection.objects.link(sun)
    cam = bpy.data.objects.new("PaintCam", bpy.data.cameras.new("PaintCam"))
    scene.collection.objects.link(cam)
    scene.camera = cam
    cam.data.lens = 50
    cam.data.clip_end = 500
    for name, eye, target in (
        ("front", Vector((34.0, 42.0, 15.0)), Vector((0, -1.5, 0.5))),
        ("rear", Vector((-30.0, -40.0, 20.0)), Vector((0, -2.0, 1.0))),
        ("top", Vector((0.5, -1.0, 62.0)), Vector((0, -1.0, 0))),
        ("close", Vector((9.0, 24.0, 4.0)), Vector((0, 12.0, 0.6))),
    ):
        cam.location = eye
        cam.rotation_euler = (target - eye).to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = os.path.join(out_dir, f"{prefix}_paint_{name}.png")
        bpy.ops.render.render(write_still=True)
        print("rendered", scene.render.filepath)


paint.render_preview = render_preview

if __name__ == "__main__":
    jet_paint.main(LAYOUT, SCHEMES, "Strategic")
