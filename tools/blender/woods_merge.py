"""Bakes the Strait's woods into a few dozen meshes (MAP-03 map cleanup).

15,000 trees as two MeshParts each (30,000 parts) loaded and drew slowly. This takes every tree's
placement (scripts/woods-export.luau reads them from the place file) and the tree meshes from the
scenery kit, and joins nearby trees into meshes of at most MAX_TRIS triangles, in map coordinates.
Colour comes from a small palette texture: each tree's faces are mapped onto the swatch for its trunk
or its foliage colour, so one texture serves every wood.

Each object is named "Woods_<n>@x,y,z", where x,y,z is the centre of its bounding box in studs (map
coordinates); SceneryBuilder.installMergedWoods puts each MeshPart there.

    "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b tools/blender/out/Scenery_kit.blend \\
        --python tools/blender/woods_merge.py -- --trees tools/blender/out/trees.txt --out tools/blender/out
"""

import argparse
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

STUDS = 1 / 0.28  # studs per metre
MAX_TRIS = 10000
TRUNK = (88, 64, 44)  # SceneryBuilder's trunk colour
KINDS = {"C": "TreeConifer", "B": "TreeBroadleaf", "P": "TreePoplar"}
SWATCH = 16  # pixels per palette swatch


def read_trees(path):
    trees = []
    with open(path) as f:
        for line in f:
            parts = line.split()
            if len(parts) != 7:
                continue
            kind, x, y, z, yaw, scale, colour = parts
            trees.append({
                "kind": KINDS[kind],
                "pos": (float(x), float(y), float(z)),
                "yaw": math.radians(float(yaw)),
                "scale": int(scale) / 100,
                "colour": tuple(int(colour[i:i + 2], 16) for i in (0, 2, 4)),
            })
    return trees


def kit_tree(kind):
    """The kit's trunk and foliage meshes for a kind, moved so the tree's base is at the origin."""
    trunk = bpy.data.objects[f"{kind}__Trunk"]
    foliage = bpy.data.objects[f"{kind}__Foliage"]
    corners = [trunk.matrix_world @ Vector(c) for c in trunk.bound_box]
    base = Vector((sum(c.x for c in corners) / 8, sum(c.y for c in corners) / 8, 0))
    out = {}
    for piece, obj in (("Trunk", trunk), ("Foliage", foliage)):
        bm = bmesh.new()
        bm.from_mesh(obj.data)
        bm.transform(Matrix.Translation(-base) @ obj.matrix_world)
        bmesh.ops.triangulate(bm, faces=bm.faces[:])
        out[piece] = bm
    return out


def build_palette(colours, out_dir):
    """A row of swatches; returns {colour: (u, v)} at each swatch's centre."""
    count = len(colours)
    width, height = SWATCH * count, SWATCH
    image = bpy.data.images.new("Woods_Palette", width=width, height=height)
    pixels = [0.0] * (width * height * 4)
    uv = {}
    for i, colour in enumerate(colours):
        for y in range(height):
            for x in range(i * SWATCH, (i + 1) * SWATCH):
                k = (y * width + x) * 4
                pixels[k:k + 4] = [colour[0] / 255, colour[1] / 255, colour[2] / 255, 1.0]
        uv[colour] = ((i + 0.5) / count, 0.5)
    image.pixels = pixels
    image.filepath_raw = os.path.join(out_dir, "Woods_Palette.png")
    image.file_format = "PNG"
    image.save()
    return uv


def groups(trees, tris_of):
    """Splits trees into spatially compact groups of at most MAX_TRIS triangles (a quadtree)."""
    out = []

    def split(items, x0, z0, size):
        total = sum(tris_of[t["kind"]] for t in items)
        if total <= MAX_TRIS or size < 64:
            if items:
                out.append(items)
            return
        half = size / 2
        quads = [[], [], [], []]
        for t in items:
            x, _, z = t["pos"]
            quads[(x >= x0 + half) + 2 * (z >= z0 + half)].append(t)
        for i, q in enumerate(quads):
            split(q, x0 + half * (i % 2), z0 + half * (i // 2), half)

    split(trees, -20480, -20480, 40960)
    return out


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--trees", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args(argv)

    trees = read_trees(args.trees)
    kit = {kind: kit_tree(kind) for kind in KINDS.values()}
    tris_of = {kind: len(m["Trunk"].faces) + len(m["Foliage"].faces) for kind, m in kit.items()}
    colours = [TRUNK] + sorted({t["colour"] for t in trees})
    uv_of = build_palette(colours, args.out)

    # Start from an empty scene: only the merged woods get exported
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)

    total_tris = 0
    parts = groups(trees, tris_of)
    for n, items in enumerate(parts, start=1):
        bm = bmesh.new()
        uv_layer = bm.loops.layers.uv.new("UVMap")
        for t in items:
            x, y, z = t["pos"]
            place = (
                Matrix.Translation(Vector((x / STUDS, -z / STUDS, y / STUDS)))
                @ Matrix.Rotation(t["yaw"], 4, "Z")
                @ Matrix.Scale(t["scale"], 4)
            )
            for piece, colour in (("Trunk", TRUNK), ("Foliage", t["colour"])):
                src = kit[t["kind"]][piece]
                verts = [bm.verts.new(place @ v.co) for v in src.verts]
                u, v = uv_of[colour]
                for face in src.faces:
                    new = bm.faces.new([verts[vert.index] for vert in face.verts])
                    for loop in new.loops:
                        loop[uv_layer].uv = (u, v)
        bm.normal_update()
        # Origin at the bounding box centre, which is what Roblox's MeshPart.Position will be
        lo = Vector((min(v.co.x for v in bm.verts), min(v.co.y for v in bm.verts), min(v.co.z for v in bm.verts)))
        hi = Vector((max(v.co.x for v in bm.verts), max(v.co.y for v in bm.verts), max(v.co.z for v in bm.verts)))
        centre = (lo + hi) / 2
        bm.transform(Matrix.Translation(-centre))
        mesh = bpy.data.meshes.new(f"Woods_{n}")
        bm.to_mesh(mesh)
        bm.free()
        rx, ry, rz = centre.x * STUDS, centre.z * STUDS, -centre.y * STUDS  # Roblox map coordinates
        obj = bpy.data.objects.new(f"Woods_{n}@{rx:.1f},{ry:.1f},{rz:.1f}", mesh)
        obj.location = centre
        bpy.context.collection.objects.link(obj)
        total_tris += len(mesh.polygons)

    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.fbx(
        filepath=os.path.join(args.out, "Woods_merged.fbx"),
        use_selection=True, object_types={"MESH"}, apply_unit_scale=True, apply_scale_options="FBX_SCALE_ALL",
        axis_forward="-Z", axis_up="Y", bake_space_transform=True, mesh_smooth_type="FACE",
        add_leaf_bones=False,
    )
    print(f"WOODS {len(trees)} trees -> {len(parts)} meshes, {total_tris} triangles, palette {len(colours)} colours")


if __name__ == "__main__":
    main()
