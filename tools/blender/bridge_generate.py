"""
Afterburner: the strait bridge (Blender 4.x / 5.x), after the Severn Bridge (1966), at real size. One model
serves both crossings: the west and east channels between the landmasses and the central island.

  * the suspension bridge: a 988 m main span and two 305 m side spans, two 136 m steel towers on concrete
    piers, two main cables and the inclined, zig-zag hangers that are the Severn Bridge's signature
  * the slender aerofoil box-girder deck with a dual two-lane carriageway, the cantilevered walkways,
    barriers, parapets and lamp posts
  * concrete anchorages at the ends of the side spans, and a short approach viaduct and abutment beyond each,
    so the deck runs 1,890 m from end to end and lands on the shore of either channel

Blender X is across the bridge, Y along it, Z up; the origin is the middle of the main span at the water line.
Units are metres (1 stud = 1 m in the game). Parts are split so each stays under Roblox's limits and so
collision can be set per part (the towers and piers are what a jet flying under the bridge can hit).

Surfaces use four tiling texture sets (bridge_textures.py), not one atlas: the bridge is too long for a unique
texture to stay sharp. UVs are in tile units (they run past 0..1 and the textures repeat):

  Steel     towers, deck box, barriers, parapets, lamp posts     box-projected, 6 m tiles
  Concrete  piers, anchorages, approach viaduct, walkways          box-projected, 8 m tiles
  Road      the carriageway                                       u across the 22.86 m road, v every 24 m
  Cable     main cables and hangers                               u round the cable, v every 1.5 m along it

  blender -b --python tools/blender/bridge_generate.py -- --out <dir> [--manifest-luau tools/Manifests/Scenery/SevernBridge.luau]

References: published dimensions of the Severn Bridge, and Commons photos (docs/art/reference/SevernBridge,
kept out of git).
"""

import argparse
import json
import math
import os
import sys

import bpy

NAME = "SevernBridge"

# Spans and stations along the bridge (|y|, metres from midspan)
MAIN_SPAN = 988.0
SIDE_SPAN = 305.0
TOWER_Y = MAIN_SPAN / 2  # 494
ANCHOR_Y = TOWER_Y + SIDE_SPAN  # 799
END_Y = 945.0  # end of the deck, on the abutment
APPROACH_PIERS = (860.0, 900.0)

# Heights (z, metres above the water)
ROAD_MID = 50.0  # road surface at midspan (47 m clearance under the deck)
ROAD_END = 18.0  # road surface at the ends of the deck
TOWER_TOP = 136.0
PIER_TOP = 6.0
FOOTING = -6.0  # foundations go below the shallow sea floor

# Across the bridge (x, metres from the centre line)
ROAD_HALF = 11.43  # the box girder's top: the carriageway
WALK_OUT = 15.9  # walkways cantilevered outside it
CABLE_X = 13.0  # plane of the main cables and hangers
LEG_X = 13.9  # tower legs (inner face clears the deck)

TILE = {"Steel": 6.0, "Concrete": 8.0}
ROAD_TILE = 24.0
CABLE_TILE = 1.5

OBJECTS = []


def road_z(y):
    """Road surface height along the bridge: a parabolic vertical curve, highest at midspan."""
    return ROAD_MID - (ROAD_MID - ROAD_END) * (y / END_Y) ** 2


CABLE_LOW = ROAD_MID + 3.0  # the cables' lowest point, over midspan
ANCHOR_Z = road_z(ANCHOR_Y) + 2.0  # where the cables enter the anchorages
SIDE_SAG = 12.0


def cable_z(y):
    a = abs(y)
    if a <= TOWER_Y:
        return CABLE_LOW + (TOWER_TOP - CABLE_LOW) * (a / TOWER_Y) ** 2
    t = (a - TOWER_Y) / SIDE_SPAN
    return TOWER_TOP + (ANCHOR_Z - TOWER_TOP) * t - 4 * SIDE_SAG * t * (1 - t)


def stations(y0, y1, step):
    n = max(1, round(abs(y1 - y0) / step))
    return [y0 + (y1 - y0) * i / n for i in range(n + 1)]


# ---------------------------------------------------------------------------------------------------
# Mesh building: each piece is (verts, faces, uvs-per-face or None)
# ---------------------------------------------------------------------------------------------------


def merge(*parts):
    verts, faces, uvs = [], [], []
    for v, f, u in parts:
        base = len(verts)
        verts += v
        faces += [tuple(i + base for i in face) for face in f]
        uvs += u if u is not None else [None] * len(f)
    return verts, faces, uvs


def loft(rings, closed=True, cap=True):
    """Faces between rings of equal length (each a list of (x, y, z))."""
    n = len(rings[0])
    verts = [p for ring in rings for p in ring]
    faces = []
    for r in range(len(rings) - 1):
        for i in range(n if closed else n - 1):
            j = (i + 1) % n
            faces.append((r * n + i, r * n + j, (r + 1) * n + j, (r + 1) * n + i))
    if cap:
        faces.append(tuple(reversed(range(n))))
        last = (len(rings) - 1) * n
        faces.append(tuple(last + i for i in range(n)))
    return verts, faces, None


def box(centre, size):
    cx, cy, cz = centre
    hx, hy, hz = size[0] / 2, size[1] / 2, size[2] / 2
    v = [(cx + sx * hx, cy + sy * hy, cz + sz * hz) for sz in (-1, 1) for sy in (-1, 1) for sx in (-1, 1)]
    f = [(0, 2, 3, 1), (4, 5, 7, 6), (0, 1, 5, 4), (2, 6, 7, 3), (0, 4, 6, 2), (1, 3, 7, 5)]
    return v, f, None


def tapered_box(x, y, z0, z1, w0, d0, w1, d1):
    """A vertical leg: w across (x), d along (y), tapering from (w0, d0) at z0 to (w1, d1) at z1."""
    rings = []
    for z, w, d in ((z0, w0, d0), (z1, w1, d1)):
        rings.append([(x - w / 2, y - d / 2, z), (x + w / 2, y - d / 2, z), (x + w / 2, y + d / 2, z), (x - w / 2, y + d / 2, z)])
    return loft(rings)


def stadium(y, length, width, z0, z1, segments=8):
    """A pier with rounded ends: length across the bridge (x), width along it (y)."""
    r = width / 2
    half = length / 2 - r
    ring = []
    for sign in (1, -1):  # the +x end, then the -x end, going round anticlockwise seen from above
        for k in range(segments + 1):
            a = -math.pi / 2 + math.pi * k / segments
            ring.append((sign * (half + r * math.cos(a)), y + sign * r * math.sin(a)))
    rings = [[(px, py, z) for px, py in ring] for z in (z0, z1)]
    return loft(rings)


def tube(points, radius, segments=8, cap=False):
    """A tube along a polyline, with UVs: u round it, v along it in CABLE_TILE units."""
    verts, faces, uvs = [], [], []
    length = 0.0
    frames = []
    for i, p in enumerate(points):
        a = points[max(i - 1, 0)]
        b = points[min(i + 1, len(points) - 1)]
        t = [b[k] - a[k] for k in range(3)]
        tl = math.sqrt(sum(c * c for c in t)) or 1.0
        t = [c / tl for c in t]
        helper = (1.0, 0.0, 0.0) if abs(t[0]) < 0.9 else (0.0, 0.0, 1.0)
        u = [t[1] * helper[2] - t[2] * helper[1], t[2] * helper[0] - t[0] * helper[2], t[0] * helper[1] - t[1] * helper[0]]
        ul = math.sqrt(sum(c * c for c in u))
        u = [c / ul for c in u]
        w = [t[1] * u[2] - t[2] * u[1], t[2] * u[0] - t[0] * u[2], t[0] * u[1] - t[1] * u[0]]
        if i > 0:
            length += math.dist(points[i - 1], p)
        frames.append((p, u, w, length))
    for p, u, w, _ in frames:
        for k in range(segments):
            ang = 2 * math.pi * k / segments
            verts.append(tuple(p[c] + radius * (math.cos(ang) * u[c] + math.sin(ang) * w[c]) for c in range(3)))
    n = segments
    for r in range(len(frames) - 1):
        v0, v1 = frames[r][3] / CABLE_TILE, frames[r + 1][3] / CABLE_TILE
        for k in range(n):
            j = (k + 1) % n
            faces.append((r * n + k, r * n + j, (r + 1) * n + j, (r + 1) * n + k))
            uvs.append([(k / n, v0), ((k + 1) / n, v0), ((k + 1) / n, v1), (k / n, v1)])
    return verts, faces, uvs


def ribbon_box(ys, section, z_of=road_z):
    """A solid following the road's vertical curve: section is a list of (x, dz) round its outline."""
    rings = [[(x, y, z_of(y) + dz) for x, dz in section] for y in ys]
    return loft(rings)


# ---------------------------------------------------------------------------------------------------
# Objects
# ---------------------------------------------------------------------------------------------------


def material(set_name):
    name = f"{NAME}_{set_name}"
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True
    return mat


def make_object(name, piece, set_name, kind="Static"):
    verts, faces, uvs = piece
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    me.update()
    me.validate()
    layer = me.uv_layers.new(name="UVMap")
    tile = TILE.get(set_name)
    if uvs is None or len(uvs) != len(me.polygons):
        uvs = [None] * len(me.polygons)
    for poly, uv in zip(me.polygons, uvs):
        n = poly.normal
        for corner, li in enumerate(poly.loop_indices):
            p = me.vertices[me.loops[li].vertex_index].co
            if uv is not None:
                layer.data[li].uv = uv[corner]
            elif set_name == "Road":
                layer.data[li].uv = ((p.x + ROAD_HALF) / (2 * ROAD_HALF), p.y / ROAD_TILE)
            elif abs(n.z) >= max(abs(n.x), abs(n.y)):
                layer.data[li].uv = (p.x / tile, p.y / tile)
            elif abs(n.x) >= abs(n.y):
                layer.data[li].uv = (p.y / tile, p.z / tile)
            else:
                layer.data[li].uv = (p.x / tile, p.z / tile)
    for poly in me.polygons:
        poly.use_smooth = set_name == "Cable"
    me.materials.append(material(set_name))
    obj = bpy.data.objects.new(name, me)
    obj["afterburner_set"] = set_name
    obj["afterburner_kind"] = kind
    bpy.context.scene.collection.objects.link(obj)
    OBJECTS.append(obj)
    return obj


def build_deck():
    ys = stations(-END_Y, END_Y, 15.0)
    # The aerofoil box girder under the road: flat top, pointed edges, narrower flat bottom
    girder = [(-ROAD_HALF, 0.0), (ROAD_HALF, 0.0), (ROAD_HALF + 1.6, -0.9), (10.5, -3.05), (-10.5, -3.05), (-ROAD_HALF - 1.6, -0.9)]
    make_object("Deck", ribbon_box(ys, girder), "Steel")
    road = [(-ROAD_HALF, 0.0), (ROAD_HALF, 0.0), (ROAD_HALF, 0.06), (-ROAD_HALF, 0.06)]
    rings = [[(x, y, road_z(y) + dz + 0.02) for x, dz in road] for y in ys]
    v, f, _ = loft(rings)
    # only the top faces matter; keep the strip closed so it reads as a surface course from the side
    make_object("Road", (v, f, None), "Road")
    walks = []
    for s in (1, -1):
        section = [(s * ROAD_HALF, -0.10), (s * WALK_OUT, -0.10), (s * WALK_OUT, -0.40), (s * ROAD_HALF, -0.40)]
        if s < 0:
            section.reverse()
        walks.append(ribbon_box(ys, section))
    make_object("Walkways", merge(*walks), "Concrete")

    ys_b = stations(-END_Y, END_Y, 20.0)
    barriers = []
    for x, w, h in ((0.0, 0.6, 0.85), (ROAD_HALF - 0.25, 0.3, 0.9), (-ROAD_HALF + 0.25, 0.3, 0.9),
                    (WALK_OUT - 0.1, 0.18, 1.3), (-WALK_OUT + 0.1, 0.18, 1.3)):
        section = [(x - w / 2, 0.0), (x + w / 2, 0.0), (x + w / 2, h), (x - w / 2, h)]
        barriers.append(ribbon_box(ys_b, section, lambda y, base=0.0 if abs(x) < WALK_OUT - 1 else -0.10: road_z(y) + base))
    make_object("Barriers", merge(*barriers), "Steel")

    lamps = []
    for s in (1, -1):
        y = -END_Y + 30 + (27 if s < 0 else 0)
        while y < END_Y - 20:
            if abs(abs(y) - TOWER_Y) > 15:
                base = road_z(y)
                x = s * (ROAD_HALF - 0.25)
                lamps.append(box((x, y, base + 6.0), (0.22, 0.22, 12.0)))
                lamps.append(box((x - s * 1.0, y, base + 11.9), (2.0, 0.18, 0.16)))
                lamps.append(box((x - s * 1.9, y, base + 11.75), (0.5, 0.3, 0.14)))
            y += 54.0
    make_object("LampPosts", merge(*lamps), "Steel")


def build_towers():
    for label, ty in (("A", -TOWER_Y), ("B", TOWER_Y)):
        parts = []
        for s in (1, -1):
            parts.append(tapered_box(s * LEG_X, ty, PIER_TOP, TOWER_TOP, 4.4, 5.6, 3.4, 4.2))
            parts.append(box((s * LEG_X, ty, TOWER_TOP + 1.5), (4.6, 6.2, 3.0)))  # cable saddle housing
        for z0, z1 in ((TOWER_TOP - 9.0, TOWER_TOP - 1.0), (84.0, 92.0), (30.0, 36.0)):
            parts.append(box((0, ty, (z0 + z1) / 2), (2 * LEG_X - 2.0, 3.6, z1 - z0)))  # cross beams (portals)
        make_object(f"Tower{label}", merge(*parts), "Steel")
        # Aviation warning lights on the saddle housings
        lights = [box((s * LEG_X, ty, TOWER_TOP + 3.3), (0.6, 0.6, 0.6)) for s in (1, -1)]
        make_object(f"TowerLights{label}", merge(*lights), "Steel", kind="Light")


def build_substructure():
    piers = [stadium(ty, 2 * LEG_X + 10.0, 12.0, FOOTING, PIER_TOP) for ty in (-TOWER_Y, TOWER_Y)]
    make_object("TowerPiers", merge(*piers), "Concrete")

    anchorages = []
    for s in (1, -1):
        y0, y1 = s * (ANCHOR_Y - 12), s * (ANCHOR_Y + 30)
        top = road_z(ANCHOR_Y) - 3.3
        anchorages.append(box((0, (y0 + y1) / 2, (FOOTING + top) / 2), (36.0, abs(y1 - y0), top - FOOTING)))
        # the sloping front face the cables run into
        anchorages.append(box((0, s * (ANCHOR_Y - 16), (FOOTING + top - 8) / 2), (36.0, 8.0, top - 8 - FOOTING)))
    make_object("Anchorages", merge(*anchorages), "Concrete")

    approach = []
    for s in (1, -1):
        for py in APPROACH_PIERS:
            y = s * py
            top = road_z(py) - 3.3
            for x in (-9.0, 9.0):
                approach.append(box((x, y, (FOOTING + top) / 2), (3.0, 3.0, top - FOOTING)))
            approach.append(box((0, y, top - 1.2), (24.0, 3.6, 2.4)))  # cross head
        top = road_z(END_Y) - 3.3
        approach.append(box((0, s * (END_Y - 8), (FOOTING - 6 + top) / 2), (34.0, 22.0, top - FOOTING + 6)))  # abutment
    make_object("Approaches", merge(*approach), "Concrete")


def build_cables():
    cables = []
    for x in (CABLE_X, -CABLE_X):
        pts = [(x, y, cable_z(y)) for y in stations(-ANCHOR_Y + 8, ANCHOR_Y - 8, 10.0)]
        # land the ends inside the anchorages, past the side-span parabola
        pts = [(x, -(ANCHOR_Y - 2), ANCHOR_Z - 2.0)] + pts + [(x, ANCHOR_Y - 2, ANCHOR_Z - 2.0)]
        cables.append(tube(pts, 0.26, 10))
    make_object("MainCables", merge(*cables), "Cable")

    hangers = []
    spacing = 18.0
    for lo, hi in ((-ANCHOR_Y + 14, -TOWER_Y - 10), (-TOWER_Y + 10, TOWER_Y - 10), (TOWER_Y + 10, ANCHOR_Y - 14)):
        k = 0
        y = lo + 9
        while y <= hi - 9:
            yd = y + (9 if k % 2 == 0 else -9)  # alternate leans: V-shapes meeting at the deck
            for x in (CABLE_X, -CABLE_X):
                top = (x, y, cable_z(y) - 0.3)
                foot = (x, yd, road_z(yd) - 0.1)
                hangers.append(tube([foot, top], 0.045, 4))
            y += spacing
            k += 1
    make_object("Hangers", merge(*hangers), "Cable")


# ---------------------------------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------------------------------


def triangles(obj):
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def to_luau(value, indent=0):
    pad = "\t" * indent
    if isinstance(value, dict):
        inner = "".join(f"{pad}\t{k} = {to_luau(v, indent + 1)},\n" for k, v in value.items())
        return "{\n" + inner + pad + "}"
    if isinstance(value, (list, tuple)):
        if all(isinstance(v, (int, float)) for v in value):
            return "{ " + ", ".join(to_luau(v) for v in value) + " }"
        inner = "".join(f"{pad}\t{to_luau(v, indent + 1)},\n" for v in value)
        return "{\n" + inner + pad + "}"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        r = round(value, 3)
        return str(int(r)) if r == int(r) else str(r)
    return '"' + str(value) + '"'


def write_manifest(out_dir, luau_path):
    parts = []
    for o in OBJECTS:
        xs = [v.co.x for v in o.data.vertices]
        ys = [v.co.y for v in o.data.vertices]
        zs = [v.co.z for v in o.data.vertices]
        # Roblox axes: x right, y up, z = -Blender y
        parts.append({
            "name": o.name,
            "set": o["afterburner_set"],
            "kind": o["afterburner_kind"],
            "triangles": triangles(o),
            "centre": [round((min(xs) + max(xs)) / 2, 2), round((min(zs) + max(zs)) / 2, 2), round(-(min(ys) + max(ys)) / 2, 2)],
            "size": [round(max(xs) - min(xs), 2), round(max(zs) - min(zs), 2), round(max(ys) - min(ys), 2)],
        })
    manifest = {
        "name": NAME,
        "units": "metres (1 stud = 1 m)",
        "length": 2 * END_Y,
        "clearance": round(road_z(0) - 3.05, 2),
        "towerHeight": TOWER_TOP,
        # The deck's vertical curve and the stations the placement tool (tools/BridgeBuilder.luau) checks
        "profile": {
            "roadMid": ROAD_MID,
            "roadEnd": ROAD_END,
            "endY": END_Y,
            "towerY": TOWER_Y,
            "anchorY": ANCHOR_Y,
            "deckDepth": 3.05,
            "roadHalf": ROAD_HALF,
            "walkOut": WALK_OUT,
        },
        "triangles": sum(p["triangles"] for p in parts),
        "sets": {
            "Steel": {"tile": TILE["Steel"]},
            "Concrete": {"tile": TILE["Concrete"]},
            "Road": {"tile": ROAD_TILE, "width": 2 * ROAD_HALF},
            "Cable": {"tile": CABLE_TILE},
        },
        "parts": parts,
    }
    with open(os.path.join(out_dir, f"{NAME}_manifest.json"), "w") as fh:
        json.dump(manifest, fh, indent=1)
    if luau_path:
        os.makedirs(os.path.dirname(luau_path), exist_ok=True)
        header = ("--!strict\n"
                  "-- Generated by tools/blender/bridge_generate.py: the strait bridge, after the Severn Bridge.\n"
                  "-- Metres, Roblox axes (x across the bridge, y up, z along it); origin at midspan, on the water line.\n")
        with open(luau_path, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(header + "return " + to_luau(manifest) + "\n")
    return manifest


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", default=os.path.join(os.path.dirname(__file__), "out"))
    parser.add_argument("--manifest-luau", default=None)
    args = parser.parse_args(argv)
    os.makedirs(args.out, exist_ok=True)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    build_deck()
    build_towers()
    build_substructure()
    build_cables()

    manifest = write_manifest(args.out, args.manifest_luau)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(args.out, f"{NAME}.blend"))
    bpy.ops.object.select_all(action="DESELECT")
    for o in OBJECTS:
        o.select_set(True)
    bpy.ops.export_scene.fbx(
        filepath=os.path.join(args.out, f"{NAME}.fbx"), use_selection=True, apply_unit_scale=True,
        axis_forward="-Z", axis_up="Y", bake_space_transform=True, mesh_smooth_type="FACE", add_leaf_bones=False,
    )
    print("=" * 60)
    print(f"{NAME}: {len(OBJECTS)} parts, {manifest['triangles']} triangles, {manifest['length']:.0f} m long")
    for p in sorted(manifest["parts"], key=lambda p: -p["triangles"]):
        print(f"  {p['name']:16s} {p['set']:9s} {p['triangles']:6d}  {p['size']}")
    print("=" * 60)


if __name__ == "__main__":
    main()
