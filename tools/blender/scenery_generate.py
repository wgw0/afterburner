"""
Afterburner: scenery kit generator (Blender 4.x / 5.x). Low-poly props for the Strait map, at real size,
for one FBX import into Studio:

  trees      TreeConifer, TreeBroadleaf, TreePoplar
  buildings  House, Barn, Apartment, Shop, Warehouse, Church
  airbase    Hangar, Shelter (hardened aircraft shelter), Tower, OpsBuilding, FuelTank

Every prop is made of a few objects named "<Prop>__<Piece>" (Walls, Roof, Windows, Doors, Glass, Trunk,
Foliage...). Pieces are flat-shaded and untextured: Studio colours them by piece name
(tools/SceneryBuilder.luau), so the whole kit costs no texture memory. Each prop stands on z = 0 at its own
spot along X, and doors face -Y (Blender), which the builder reads back to orient hangars and shelters.

  blender -b --python tools/blender/scenery_generate.py -- --out tools/blender/out
"""

import argparse
import math
import os
import sys

import bpy
import bmesh

OBJECTS = []


def mesh_object(name, bm, location):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = False
    obj = bpy.data.objects.new(name, me)
    obj.location = location
    bpy.context.scene.collection.objects.link(obj)
    OBJECTS.append(obj)
    return obj


def add_box(bm, centre, size):
    m = bmesh.ops.create_cube(bm, size=1.0)
    for v in m["verts"]:
        v.co.x = v.co.x * size[0] + centre[0]
        v.co.y = v.co.y * size[1] + centre[1]
        v.co.z = v.co.z * size[2] + centre[2]


def add_cone(bm, base_z, top_z, r0, r1, segments, x=0.0, y=0.0, cap_top=True):
    m = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segments, radius1=r0, radius2=r1,
                              depth=top_z - base_z)
    for v in m["verts"]:
        v.co.z += (base_z + top_z) / 2
        v.co.x += x
        v.co.y += y


def add_blob(bm, centre, scale, subdiv=1):
    m = bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=1.0)
    for v in m["verts"]:
        v.co.x = v.co.x * scale[0] + centre[0]
        v.co.y = v.co.y * scale[1] + centre[1]
        v.co.z = v.co.z * scale[2] + centre[2]


def add_prism_roof(bm, length, width, eave_z, ridge_z, overhang=0.4):
    """Gable roof along X: two sloping quads and two gable triangles, as a closed solid."""
    hl, hw = length / 2 + overhang, width / 2 + overhang
    v = [bm.verts.new(c) for c in (
        (-hl, -hw, eave_z), (hl, -hw, eave_z), (hl, hw, eave_z), (-hl, hw, eave_z),
        (-hl, 0, ridge_z), (hl, 0, ridge_z),
    )]
    for f in ((0, 1, 5, 4), (2, 3, 4, 5), (0, 4, 3), (1, 2, 5), (0, 3, 2, 1)):
        bm.faces.new([v[i] for i in f])


def add_arch(bm, width, length, height, wall, segments=10, y0=0.0):
    """Barrel arch along Y (a hangar roof or a shelter), closed at both ends, sitting on z = wall."""
    hw = width / 2
    rings = []
    for y in (y0 - length / 2, y0 + length / 2):
        ring = []
        for i in range(segments + 1):
            a = math.pi * i / segments
            ring.append(bm.verts.new((-hw * math.cos(a), y, wall + height * math.sin(a))))
        rings.append(ring)
    for i in range(segments):
        bm.faces.new((rings[0][i], rings[0][i + 1], rings[1][i + 1], rings[1][i]))
    bm.faces.new(rings[0][::-1])
    bm.faces.new(rings[1])
    bm.faces.new((rings[0][0], rings[1][0], rings[1][-1], rings[0][-1]))


def window_strip(bm, x0, x1, y, z0, z1, depth=0.06, facing=1):
    add_box(bm, ((x0 + x1) / 2, y + facing * depth / 2, (z0 + z1) / 2), (x1 - x0, depth, z1 - z0))


def window_strip_x(bm, y0, y1, x, z0, z1, depth=0.06, facing=1):
    add_box(bm, (x + facing * depth / 2, (y0 + y1) / 2, (z0 + z1) / 2), (depth, y1 - y0, z1 - z0))


# ---------------------------------------------------------------------------------------------------
# Props (metres). Each returns {piece: bmesh}
# ---------------------------------------------------------------------------------------------------


def tree_conifer():
    trunk, foliage = bmesh.new(), bmesh.new()
    add_cone(trunk, 0, 3.0, 0.35, 0.25, 6)
    for z0, z1, r in ((2.0, 8.5, 3.2), (5.0, 11.5, 2.5), (8.0, 15.0, 1.7)):
        add_cone(foliage, z0, z1, r, 0.0, 8)
    return {"Trunk": trunk, "Foliage": foliage}


def tree_broadleaf():
    trunk, foliage = bmesh.new(), bmesh.new()
    add_cone(trunk, 0, 5.0, 0.45, 0.3, 6)
    add_blob(foliage, (0, 0, 7.5), (3.8, 3.6, 3.2))
    add_blob(foliage, (1.4, 0.8, 9.2), (2.4, 2.3, 2.1))
    return {"Trunk": trunk, "Foliage": foliage}


def tree_poplar():
    trunk, foliage = bmesh.new(), bmesh.new()
    add_cone(trunk, 0, 2.5, 0.3, 0.22, 6)
    add_blob(foliage, (0, 0, 9.0), (1.9, 1.9, 7.2))
    return {"Trunk": trunk, "Foliage": foliage}


def house():
    walls, roof, windows = bmesh.new(), bmesh.new(), bmesh.new()
    L, W, H = 10.0, 8.0, 5.5
    add_box(walls, (0, 0, H / 2), (L, W, H))
    add_box(walls, (2.5, 1.5, H + 2.4), (0.8, 0.8, 2.0))  # chimney
    add_prism_roof(roof, L, W, H, H + 3.2)
    for x in (-3.0, 3.0):
        for side in (-1, 1):
            window_strip(windows, x - 0.7, x + 0.7, side * W / 2, 1.2, 2.4, facing=side)
            window_strip(windows, x - 0.7, x + 0.7, side * W / 2, 3.7, 4.8, facing=side)
    window_strip(windows, -0.6, 0.6, -W / 2, 0.0, 2.2, facing=-1)  # door
    return {"Walls": walls, "Roof": roof, "Windows": windows}


def barn():
    walls, roof, doors = bmesh.new(), bmesh.new(), bmesh.new()
    L, W, H = 16.0, 10.0, 4.5
    add_box(walls, (0, 0, H / 2), (L, W, H))
    add_prism_roof(roof, L, W, H, H + 5.0, overhang=0.6)
    window_strip(doors, -2.2, 2.2, -W / 2, 0.0, 4.0, facing=-1)
    return {"Walls": walls, "Roof": roof, "Doors": doors}


def apartment():
    walls, roof, windows = bmesh.new(), bmesh.new(), bmesh.new()
    L, W, F = 28.0, 12.0, 5
    H = F * 3.1
    add_box(walls, (0, 0, H / 2), (L, W, H))
    add_box(roof, (0, 0, H + 0.4), (L + 0.3, W + 0.3, 0.8))  # parapet cap
    for f in range(F):
        z0, z1 = 0.9 + f * 3.1, 2.3 + f * 3.1
        for side in (-1, 1):
            window_strip(windows, -L / 2 + 1, L / 2 - 1, side * W / 2, z0, z1, facing=side)
            window_strip_x(windows, -W / 2 + 1, W / 2 - 1, side * L / 2, z0, z1, facing=side)
    return {"Walls": walls, "Roof": roof, "Windows": windows}


def shop():
    walls, roof, windows, awning = bmesh.new(), bmesh.new(), bmesh.new(), bmesh.new()
    L, W, H = 12.0, 10.0, 7.0
    add_box(walls, (0, 0, H / 2), (L, W, H))
    add_box(roof, (0, 0, H + 0.3), (L + 0.2, W + 0.2, 0.6))
    window_strip(windows, -5.0, 5.0, -W / 2, 0.3, 2.8, facing=-1)  # shopfront
    for x in (-3.5, 0, 3.5):
        window_strip(windows, x - 0.8, x + 0.8, -W / 2, 4.0, 5.6, facing=-1)
        window_strip(windows, x - 0.8, x + 0.8, W / 2, 4.0, 5.6, facing=1)
    add_box(awning, (0, -W / 2 - 0.9, 3.2), (L - 1.0, 1.8, 0.15))
    return {"Walls": walls, "Roof": roof, "Windows": windows, "Awning": awning}


def warehouse():
    walls, roof, doors = bmesh.new(), bmesh.new(), bmesh.new()
    L, W, H = 40.0, 24.0, 8.0
    add_box(walls, (0, 0, H / 2), (L, W, H))
    add_prism_roof(roof, L, W, H, H + 2.0, overhang=0.3)
    for x in (-12.0, 0.0, 12.0):
        window_strip(doors, x - 2.5, x + 2.5, -W / 2, 0.0, 5.0, facing=-1)
    return {"Walls": walls, "Roof": roof, "Doors": doors}


def church():
    walls, roof, windows = bmesh.new(), bmesh.new(), bmesh.new()
    add_box(walls, (0, 0, 4.5), (18.0, 10.0, 9.0))  # nave
    add_prism_roof(roof, 18.0, 10.0, 9.0, 14.0, overhang=0.3)
    add_box(walls, (-11.5, 0, 9.0), (5.0, 5.0, 18.0))  # tower
    add_cone(roof, 18.0, 27.0, 3.6, 0.0, 4, x=-11.5)  # spire
    for x in (-5.0, 0.0, 5.0):
        for side in (-1, 1):
            window_strip(windows, x - 0.6, x + 0.6, side * 5.0, 3.0, 7.0, facing=side)
    return {"Walls": walls, "Roof": roof, "Windows": windows}


def hangar():
    walls, roof, doors = bmesh.new(), bmesh.new(), bmesh.new()
    W, D, wall, rise = 62.0, 50.0, 10.0, 14.0
    add_box(walls, (0, 0, wall / 2), (W, D, wall))
    add_arch(roof, W + 1.0, D + 1.0, rise, wall, segments=12)  # its end caps close the front and back
    for i in range(6):  # sliding door panels on the front (-Y), just proud of the arch's end cap
        x0 = -W / 2 + 2 + i * (W - 4) / 6
        add_box(doors, (x0 + (W - 4) / 12, -(D + 1.0) / 2 - 0.3, 8.0), ((W - 4) / 6 - 0.3, 0.4, 16.0))
    return {"Walls": walls, "Roof": roof, "Doors": doors}


def shelter():
    shell, doors = bmesh.new(), bmesh.new()
    W, D, H = 24.0, 34.0, 9.5
    add_arch(shell, W, D, H, 0.0, segments=12)
    add_box(shell, (0, -D / 2 - 1.0, H / 2), (W + 3.0, 2.0, H))  # blast face
    add_box(doors, (0, -D / 2 - 2.1, 3.6), (W - 4.0, 0.4, 7.2))
    return {"Shell": shell, "Doors": doors}


def tower():
    walls, glass, roof = bmesh.new(), bmesh.new(), bmesh.new()
    add_box(walls, (4.0, 0, 3.5), (18.0, 12.0, 7.0))  # ops block at the foot
    add_box(walls, (-4.0, 0, 18.0), (6.0, 6.0, 36.0))  # shaft
    add_cone(roof, 35.6, 36.4, 6.0, 6.0, 8, x=-4.0)  # cab floor slab
    add_cone(glass, 36.4, 40.4, 5.2, 5.8, 8, x=-4.0)  # glass cab, flaring outwards
    add_cone(roof, 40.4, 41.2, 6.6, 6.0, 8, x=-4.0)  # cab roof
    add_box(roof, (-4.0, 0, 42.6), (0.3, 0.3, 2.8))  # mast
    add_box(roof, (4.0, 0, 7.3), (18.4, 12.4, 0.6))
    return {"Walls": walls, "Glass": glass, "Roof": roof}


def ops_building():
    walls, roof, windows = bmesh.new(), bmesh.new(), bmesh.new()
    L, W, H = 30.0, 15.0, 7.0
    add_box(walls, (0, 0, H / 2), (L, W, H))
    add_box(roof, (0, 0, H + 0.3), (L + 0.3, W + 0.3, 0.6))
    for side in (-1, 1):
        window_strip(windows, -L / 2 + 1.5, L / 2 - 1.5, side * W / 2, 1.0, 2.6, facing=side)
        window_strip(windows, -L / 2 + 1.5, L / 2 - 1.5, side * W / 2, 4.3, 5.9, facing=side)
    return {"Walls": walls, "Roof": roof, "Windows": windows}


def fuel_tank():
    tank = bmesh.new()
    add_cone(tank, 0, 9.0, 7.0, 7.0, 16)
    add_cone(tank, 9.0, 10.5, 7.0, 1.0, 16)
    return {"Tank": tank}


PROPS = [
    ("TreeConifer", tree_conifer), ("TreeBroadleaf", tree_broadleaf), ("TreePoplar", tree_poplar),
    ("House", house), ("Barn", barn), ("Apartment", apartment), ("Shop", shop), ("Warehouse", warehouse),
    ("Church", church), ("Hangar", hangar), ("Shelter", shelter), ("Tower", tower),
    ("OpsBuilding", ops_building), ("FuelTank", fuel_tank),
]


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", default=os.path.join(os.path.dirname(__file__), "out"))
    args = parser.parse_args(argv)
    os.makedirs(args.out, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)

    x = 0.0
    tris = {}
    for name, build in PROPS:
        pieces = build()
        for piece, bm in pieces.items():
            bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
            obj = mesh_object(f"{name}__{piece}", bm, (x, 0, 0))
            tris[name] = tris.get(name, 0) + sum(len(p.vertices) - 2 for p in obj.data.polygons)
        x += 90.0

    bpy.ops.object.select_all(action="DESELECT")
    for obj in OBJECTS:
        obj.select_set(True)
    bpy.ops.export_scene.fbx(
        filepath=os.path.join(args.out, "Scenery_kit.fbx"),
        use_selection=True, object_types={"MESH"}, apply_unit_scale=True, apply_scale_options="FBX_SCALE_ALL",
        axis_forward="-Z", axis_up="Y", bake_space_transform=True, mesh_smooth_type="FACE",
        add_leaf_bones=False,
    )
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(args.out, "Scenery_kit.blend"))
    print("SCENERY", len(OBJECTS), "objects")
    for name, t in tris.items():
        print(f"  {name:14s} {t:5d} triangles")


if __name__ == "__main__":
    main()
