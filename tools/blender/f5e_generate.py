"""
Afterburner: F-5E Tiger II base mesh generator (Blender 4.x / 5.x).

Builds a mid-poly, modular F-5E at real-world size from published dimensions:
  * a lofted fuselage (area-ruled, superellipse sections), intakes, LERX, canopy and frame
  * wings, leading-edge flaps, trailing-edge flaps and ailerons cut from real airfoil sections
  * all-moving stabilators, fin and rudder
  * twin nozzles with afterburner cones, ejection seat, wingtip rails, pitot
  * landing gear (struts, wheels, doors) as separate parts
Every moving part is its own object with its origin on its hinge line (rotation left at identity,
aligned to the world axes). Objects are grouped by texture set (Body, Wings, Details, Glass) with one
material per set and UVs packed per set, ready for PBR painting.

Outputs (in --out):
  F5E_base.blend      the generated scene, for further modelling and texturing
  F5E_base.fbx        for Roblox Studio's 3D importer
  F5E_manifest.json   part list, hinges, attachments, hull and hitboxes (Roblox axes, metres)
and, with --manifest-luau, the same manifest as a Luau module for the Studio assembler.

Axes. Blender: X right, Y forward (the nose points +Y), Z up. With the FBX exporter's default
Forward -Z / Up Y, Blender +Y becomes -Z, which is the nose direction the game's model contract uses.
The manifest is written in Roblox axes: x right, y up, z aft (nose toward -z). Units: metres
(1 m = 3.5714 studs in the game).

Run headless:
  blender -b --python tools/blender/f5e_generate.py -- --out tools/blender/out \
      --manifest-luau tools/Manifests/F5E.luau
"""

import argparse
import json
import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector

AIRFRAME = "F5E"
STUDS_PER_METRE = 1 / 0.28

# ---------------------------------------------------------------------------------------------------
# Published dimensions (F-5E): length 14.45 m, span 8.13 m over the wingtip rails, height 4.08 m,
# wing area 17.3 m², leading-edge sweep ~32°, thin wing (~4.8%), all-moving stabilators.
# Stations are along Y (nose tip at +7.2, tail at -7.25).
# ---------------------------------------------------------------------------------------------------

# Fuselage key sections: (y, half width, top z, bottom z, superellipse exponent)
FUSELAGE = [
    (7.20, 0.015, 0.02, -0.02, 2.0),
    (6.90, 0.10, 0.11, -0.09, 2.0),
    (6.40, 0.22, 0.24, -0.19, 2.1),
    (5.60, 0.36, 0.40, -0.31, 2.2),
    (4.70, 0.48, 0.54, -0.41, 2.4),
    (3.80, 0.54, 0.63, -0.48, 2.6),
    (2.70, 0.60, 0.70, -0.55, 2.8),
    (1.70, 0.66, 0.68, -0.58, 3.0),
    (0.60, 0.70, 0.64, -0.60, 3.2),
    (-0.80, 0.66, 0.62, -0.61, 3.2),  # area-rule waist at the wing
    (-2.40, 0.70, 0.60, -0.60, 3.0),
    (-4.20, 0.70, 0.57, -0.56, 2.8),
    (-5.80, 0.66, 0.52, -0.50, 2.6),
    (-6.80, 0.62, 0.48, -0.44, 2.5),
    (-7.25, 0.60, 0.46, -0.42, 2.5),
]
FUSELAGE_STATIONS = 44
FUSELAGE_SEGMENTS = 40

# Wing planform (one side, x outboard): root at the fuselage side, tip before the rail.
WING_ROOT_X, WING_TIP_X = 0.68, 3.85
WING_ROOT_LE, WING_ROOT_TE = 0.95, -2.45
WING_SWEEP_LE = math.radians(32)
WING_TIP_CHORD = 0.70
WING_Z = -0.10
WING_THICKNESS = 0.048
# Chord fractions and spans of the moving surfaces
LE_FLAP_CHORD = 0.13
TE_HINGE = 0.75
TE_FLAP_SPAN = (0.72, 2.35)
AILERON_SPAN = (2.40, 3.62)

# Stabilator (all-moving), fin and rudder
STAB_ROOT_X, STAB_TIP_X = 0.50, 2.15
STAB_ROOT_LE, STAB_ROOT_CHORD = -5.55, 1.55
STAB_SWEEP_LE = math.radians(35)
STAB_TIP_CHORD = 0.55
STAB_Z = -0.02
STAB_THICKNESS = 0.05
FIN_ROOT_Z, FIN_TIP_Z = 0.50, 2.60
FIN_ROOT_LE, FIN_ROOT_CHORD = -3.95, 3.00
FIN_SWEEP_LE = math.radians(43)
FIN_TIP_CHORD = 0.85
FIN_THICKNESS = 0.05
RUDDER_HINGE = 0.72
RUDDER_SPAN = (0.80, 2.35)

# Gameplay data carried over from the greybox F-5E (Roblox axes, metres), so the jet plays the same.
HULL = {"size": [1.4, 1.4, 13.0], "at": [0, 0, -0.3]}
HITBOXES = {
    "Cockpit": {"size": [1.2, 1.2, 2.0], "at": [0, 0.4, -2.6]},
    "Fuselage": {"size": [1.5, 1.4, 6.0], "at": [0, 0, -0.5]},
    "Engine": {"size": [1.5, 1.3, 3.5], "at": [0, 0, 4.5]},
    "WingL": {"size": [3.3, 0.5, 2.4], "at": [-2.4, 0, 1.0]},
    "WingR": {"size": [3.3, 0.5, 2.4], "at": [2.4, 0, 1.0]},
    "Tail": {"size": [3.4, 2.4, 2.0], "at": [0, 0.8, 5.5]},
}

# ---------------------------------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------------------------------

PARTS = []  # manifest entries
TEXTURE_SETS = {
    "Body": (0.42, 0.45, 0.47, 0.0, 0.55),  # rgb, metallic, roughness: matte grey paint
    "Wings": (0.40, 0.43, 0.45, 0.0, 0.55),
    "Details": (0.20, 0.20, 0.22, 0.6, 0.45),  # gear, nozzles, seat
    "Glass": (0.08, 0.12, 0.15, 0.0, 0.02),
}


def to_roblox(v):
    """Blender (x right, y forward, z up) -> Roblox metres (x right, y up, z aft)."""
    return [round(v[0], 4), round(v[2], 4), round(-v[1], 4)]


def lerp(a, b, t):
    return a + (b - a) * t


def catmull(p0, p1, p2, p3, t):
    t2, t3 = t * t, t * t * t
    return 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3)


def naca_half_thickness(x, ratio):
    """Half thickness of a symmetric NACA 4-digit section at chord fraction x (0..1)."""
    x = min(max(x, 0.0), 1.0)
    return 5 * ratio * (0.2969 * math.sqrt(x) - 0.1260 * x - 0.3516 * x**2 + 0.2843 * x**3 - 0.1036 * x**4)


def cosine_spacing(f0, f1, n):
    """n points from f0 to f1, denser near the leading edge."""
    pts = []
    for i in range(n):
        s = i / (n - 1)
        u = (1 - math.cos(s * math.pi)) / 2
        pts.append(lerp(f0, f1, u))
    return pts


def collection(name, parent=None):
    col = bpy.data.collections.get(name) or bpy.data.collections.new(name)
    if col.name not in [c.name for c in (parent.children if parent else bpy.context.scene.collection.children)]:
        (parent.children if parent else bpy.context.scene.collection.children).link(col)
    return col


MATERIALS = {}


def material(set_name):
    if set_name in MATERIALS:
        return MATERIALS[set_name]
    r, g, b, metallic, roughness = TEXTURE_SETS[set_name]
    mat = bpy.data.materials.new(f"{AIRFRAME}_{set_name}")
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = (r, g, b, 1)
        bsdf.inputs["Metallic"].default_value = metallic
        bsdf.inputs["Roughness"].default_value = roughness
        if set_name == "Glass":
            bsdf.inputs["Alpha"].default_value = 0.35
    if set_name == "Glass":
        mat.blend_method = "BLEND" if hasattr(mat, "blend_method") else mat.blend_method
    MATERIALS[set_name] = mat
    return mat


def make_object(name, verts, faces, col, set_name, kind="Static", origin=(0, 0, 0), hinge=None, extra=None):
    """Creates a mesh object. origin: where its pivot sits (world, Blender axes). hinge: dict with the
    hinge axis (Blender axes), deflection limits in degrees."""
    mesh = bpy.data.meshes.new(name)
    ox, oy, oz = origin
    mesh.from_pydata([(v[0] - ox, v[1] - oy, v[2] - oz) for v in verts], [], faces)
    mesh.validate(clean_customdata=False)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    obj.location = origin
    col.objects.link(obj)
    obj.data.materials.append(material(set_name))
    obj["afterburner_set"] = set_name
    obj["afterburner_kind"] = kind
    entry = {"name": name, "set": set_name, "kind": kind, "pivot": to_roblox(origin)}
    if hinge:
        axis = Vector(hinge["axis"]).normalized()
        entry["hinge"] = {
            "axis": to_roblox(axis),
            "min": hinge.get("min", -20),
            "max": hinge.get("max", 20),
            "control": hinge.get("control", ""),
        }
        obj["afterburner_hinge_axis"] = list(axis)
    if extra:
        entry.update(extra)
    PARTS.append(entry)
    return obj


def mirror_x(verts):
    return [(-v[0], v[1], v[2]) for v in verts]


def flip_faces(faces):
    return [tuple(reversed(f)) for f in faces]


def lofted(rings, cap_start=True, cap_end=True):
    """Faces for a list of equal-length vertex rings (closed loops). Returns verts, faces."""
    verts, faces = [], []
    n = len(rings[0])
    for ring in rings:
        verts.extend(ring)
    for r in range(len(rings) - 1):
        a, b = r * n, (r + 1) * n
        for i in range(n):
            j = (i + 1) % n
            faces.append((a + i, a + j, b + j, b + i))
    if cap_start:
        c = len(verts)
        verts.append(tuple(sum(v[k] for v in rings[0]) / n for k in range(3)))
        for i in range(n):
            faces.append((c, (i + 1) % n, i))
    if cap_end:
        c = len(verts)
        base = (len(rings) - 1) * n
        verts.append(tuple(sum(v[k] for v in rings[-1]) / n for k in range(3)))
        for i in range(n):
            faces.append((c, base + i, base + (i + 1) % n))
    return verts, faces


def cylinder(p0, p1, radius, segments=16, radius1=None, caps=True):
    """A cylinder (or cone with radius1) between two points along any axis."""
    a, b = Vector(p0), Vector(p1)
    axis = (b - a).normalized()
    helper = Vector((0, 0, 1)) if abs(axis.z) < 0.9 else Vector((1, 0, 0))
    u = axis.cross(helper).normalized()
    v = axis.cross(u).normalized()
    r1 = radius if radius1 is None else radius1
    rings = []
    for centre, r in ((a, radius), (b, r1)):
        ring = []
        for i in range(segments):
            ang = 2 * math.pi * i / segments
            p = centre + (u * math.cos(ang) + v * math.sin(ang)) * r
            ring.append(tuple(p))
        rings.append(ring)
    return lofted(rings, caps, caps)


def box(centre, size):
    cx, cy, cz = centre
    sx, sy, sz = (s / 2 for s in size)
    verts = [
        (cx - sx, cy - sy, cz - sz), (cx + sx, cy - sy, cz - sz), (cx + sx, cy + sy, cz - sz), (cx - sx, cy + sy, cz - sz),
        (cx - sx, cy - sy, cz + sz), (cx + sx, cy - sy, cz + sz), (cx + sx, cy + sy, cz + sz), (cx - sx, cy + sy, cz + sz),
    ]
    faces = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
    return verts, faces


def merge(*parts):
    verts, faces = [], []
    for pv, pf in parts:
        off = len(verts)
        verts.extend(pv)
        faces.extend(tuple(i + off for i in f) for f in pf)
    return verts, faces


# ---------------------------------------------------------------------------------------------------
# Surfaces (wings, stabilators, fin) from airfoil sections
# ---------------------------------------------------------------------------------------------------


def panel(root_le, root_te, tip_le, tip_te, normal, ratio, f0, f1, s0=0.0, s1=1.0, span_steps=8, chord_steps=10):
    """A tapered, airfoil-section panel between two spanwise fractions (s0..s1) and chord fractions
    (f0..f1). Points are 3D (Blender axes); normal is the thickness direction."""
    rl, rt, tl, tt = (Vector(p) for p in (root_le, root_te, tip_le, tip_te))
    n = Vector(normal).normalized()
    chord_u = cosine_spacing(f0, f1, chord_steps)
    rings = []
    for k in range(span_steps + 1):
        s = lerp(s0, s1, k / span_steps)
        le = rl.lerp(tl, s)
        te = rt.lerp(tt, s)
        chord = (te - le).length
        upper = [le.lerp(te, u) + n * max(naca_half_thickness(u, ratio) * chord, 0.002) for u in chord_u]
        lower = [le.lerp(te, u) - n * max(naca_half_thickness(u, ratio) * chord, 0.002) for u in reversed(chord_u)]
        rings.append([tuple(p) for p in upper + lower])
    return lofted(rings, True, True)


def hinge_line(root_le, root_te, tip_le, tip_te, fraction, s0, s1):
    """Hinge points (inboard, outboard) at a chord fraction between spanwise fractions."""
    rl, rt, tl, tt = (Vector(p) for p in (root_le, root_te, tip_le, tip_te))
    a = rl.lerp(tl, s0).lerp(rt.lerp(tt, s0), fraction)
    b = rl.lerp(tl, s1).lerp(rt.lerp(tt, s1), fraction)
    return a, b


# ---------------------------------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------------------------------


def fuselage_section(t):
    """Interpolated fuselage section at parameter t (0 = nose, 1 = tail) with Catmull-Rom."""
    keys = FUSELAGE
    seg = t * (len(keys) - 1)
    i = min(int(seg), len(keys) - 2)
    local = seg - i
    p = [keys[max(i - 1, 0)], keys[i], keys[i + 1], keys[min(i + 2, len(keys) - 1)]]
    return tuple(catmull(p[0][k], p[1][k], p[2][k], p[3][k], local) for k in range(5))


def fuselage_top(y):
    """Top of the fuselage (z) at station y, for seating the canopy, LERX and fin."""
    best = None
    for k in range(400):
        sec = fuselage_section(k / 399)
        if best is None or abs(sec[0] - y) < abs(best[0] - y):
            best = sec
    return best


def build_fuselage(col):
    rings = []
    for k in range(FUSELAGE_STATIONS):
        y, hw, zt, zb, e = fuselage_section(k / (FUSELAGE_STATIONS - 1))
        ring = []
        for i in range(FUSELAGE_SEGMENTS):
            ang = 2 * math.pi * i / FUSELAGE_SEGMENTS
            c, s = math.cos(ang), math.sin(ang)
            x = hw * math.copysign(abs(c) ** (2 / e), c)
            z = math.copysign(abs(s) ** (2 / e), s) * (zt if s >= 0 else -zb)
            ring.append((x, y, z))
        rings.append(ring)
    verts, faces = lofted(rings, cap_start=True, cap_end=True)
    make_object("Fuselage", verts, flip_faces(faces), col, "Body")


def build_intakes(col):
    """Side intakes: D-section ducts hugging the fuselage (flat side against the skin), with a lip and a
    recessed mouth, blending back into the fuselage behind the wing root."""
    parts = []
    stations = [  # (y, bulge out from the skin, top z, bottom z, inset of the mouth)
        (1.95, 0.30, 0.26, -0.34),
        (1.40, 0.30, 0.27, -0.35),
        (0.40, 0.26, 0.26, -0.33),
        (-0.60, 0.16, 0.22, -0.28),
        (-1.40, 0.04, 0.16, -0.20),
    ]

    def ring(y, bulge, zt, zb, side, scale=1.0, dy=0.0):
        _, hw, _, _, _ = fuselage_section(min(max((7.2 - y) / 14.45, 0), 1))
        inner = hw - 0.05
        zc = (zt + zb) / 2
        hz = (zt - zb) / 2 * scale
        b = bulge * scale
        pts = []
        # Outer half (bottom -> top), superellipse for a slightly squared D
        for i in range(13):
            ang = -math.pi / 2 + math.pi * i / 12
            c, s_ = math.cos(ang), math.sin(ang)
            x = inner + (0.02 + b * (abs(c) ** 0.6))
            z = zc + math.copysign(abs(s_) ** 0.8, s_) * hz
            pts.append((side * x, y + dy, z))
        # Flat inner side (top -> bottom)
        for i in range(1, 4):
            z = zc + hz - 2 * hz * i / 4
            pts.append((side * inner, y + dy, z))
        return pts

    for side in (1, -1):
        y0, b0, t0, z0 = stations[0]
        rings = [ring(y0 - 0.45, b0, t0, z0, side, 0.78), ring(y0, b0, t0, z0, side, 0.84, 0.02)]
        rings += [ring(y, b, t, z, side) for (y, b, t, z) in stations]
        verts, faces = lofted(rings, cap_start=True, cap_end=False)
        parts.append((verts, faces if side < 0 else flip_faces(faces)))
    verts, faces = merge(*parts)
    make_object("Intakes", verts, faces, col, "Body")


def build_lerx(col):
    parts = []
    for side in (1, -1):
        y0, y1 = 2.3, WING_ROOT_LE
        pts = [(0.60, y0), (0.86, y1 + 0.15), (0.86, y1 - 0.05), (0.60, y1 - 0.05)]
        v_top = [(side * x, y, 0.08) for x, y in pts]
        v_bot = [(side * x, y, 0.03) for x, y in pts]
        verts = v_top + v_bot
        faces = [(0, 1, 2, 3), (7, 6, 5, 4), (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)]
        parts.append((verts, faces if side > 0 else flip_faces(faces)))
    verts, faces = merge(*parts)
    make_object("LERX", verts, faces, col, "Body")


def build_canopy(col_glass, col_body):
    rings = []
    stations = [3.95, 3.6, 3.2, 2.8, 2.4, 2.0, 1.75]
    widths = [0.20, 0.36, 0.44, 0.46, 0.45, 0.40, 0.30]
    heights = [0.05, 0.38, 0.60, 0.70, 0.68, 0.55, 0.30]
    for y, w, h in zip(stations, widths, heights):
        base = fuselage_top(y)[2] - 0.04
        ring = []
        for i in range(17):
            ang = math.pi * i / 16
            ring.append((math.cos(ang) * w, y, base + math.sin(ang) * h))
        rings.append(ring)
    verts, faces = lofted(rings, cap_start=True, cap_end=True)
    make_object("Canopy", verts, faces, col_glass, "Glass")
    # Frame: windscreen arch and rear arch, slightly proud of the glass
    frame_parts = []
    for y, w, h in ((3.32, 0.47, 0.66), (1.78, 0.33, 0.33)):
        base = fuselage_top(y)[2] - 0.04
        outer = [(math.cos(math.pi * i / 16) * (w + 0.02), y, base + math.sin(math.pi * i / 16) * (h + 0.02)) for i in range(17)]
        inner = [(math.cos(math.pi * i / 16) * (w - 0.02), y, base + math.sin(math.pi * i / 16) * (h - 0.01)) for i in range(17)]
        front = [(p[0], p[1] + 0.03, p[2]) for p in outer]
        back = [(p[0], p[1] - 0.03, p[2]) for p in outer]
        verts = front + back + [(p[0], p[1] + 0.03, p[2]) for p in inner] + [(p[0], p[1] - 0.03, p[2]) for p in inner]
        n = 17
        faces = []
        for i in range(n - 1):
            faces.append((i, i + 1, n + i + 1, n + i))  # outer skin
            faces.append((2 * n + i + 1, 2 * n + i, 3 * n + i, 3 * n + i + 1))  # inner skin
            faces.append((2 * n + i, 2 * n + i + 1, i + 1, i))  # front face
            faces.append((n + i, n + i + 1, 3 * n + i + 1, 3 * n + i))  # back face
        frame_parts.append((verts, faces))
    verts, faces = merge(*frame_parts)
    make_object("CanopyFrame", verts, faces, col_body, "Body")


def build_wings(col):
    root_le = (WING_ROOT_X, WING_ROOT_LE, WING_Z)
    root_te = (WING_ROOT_X, WING_ROOT_TE, WING_Z)
    tip_le_y = WING_ROOT_LE - (WING_TIP_X - WING_ROOT_X) * math.tan(WING_SWEEP_LE)
    tip_le = (WING_TIP_X, tip_le_y, WING_Z)
    tip_te = (WING_TIP_X, tip_le_y - WING_TIP_CHORD, WING_Z)
    span = WING_TIP_X - WING_ROOT_X
    up = (0, 0, 1)

    def frac(x):
        return (x - WING_ROOT_X) / span

    for side, name in ((1, "R"), (-1, "L")):
        def m(v):
            return v if side > 0 else mirror_x(v)

        def mf(f):
            return f if side > 0 else flip_faces(f)

        # Main wing box: behind the LE flap, ahead of the trailing-edge surfaces (full chord at the tip)
        box_parts = [
            panel(root_le, root_te, tip_le, tip_te, up, WING_THICKNESS, LE_FLAP_CHORD, TE_HINGE, 0, frac(AILERON_SPAN[1]), 8, 10),
            panel(root_le, root_te, tip_le, tip_te, up, WING_THICKNESS, 0.0, 1.0, frac(AILERON_SPAN[1]), 1.0, 1, 12),
            # Inboard of the flap: a small fixed trailing edge strip
            panel(root_le, root_te, tip_le, tip_te, up, WING_THICKNESS, TE_HINGE, 1.0, 0, frac(TE_FLAP_SPAN[0]), 1, 4),
            # Between flap and aileron
            panel(root_le, root_te, tip_le, tip_te, up, WING_THICKNESS, TE_HINGE, 1.0, frac(TE_FLAP_SPAN[1]), frac(AILERON_SPAN[0]), 1, 4),
        ]
        v, f = merge(*box_parts)
        make_object(f"Wing{name}", m(v), mf(f), col, "Wings")

        # Leading-edge flap (hinged at its trailing edge, droops down)
        v, f = panel(root_le, root_te, tip_le, tip_te, up, WING_THICKNESS, 0.0, LE_FLAP_CHORD, 0, frac(AILERON_SPAN[1]), 8, 6)
        a, b = hinge_line(root_le, root_te, tip_le, tip_te, LE_FLAP_CHORD, 0, frac(AILERON_SPAN[1]))
        make_object(f"LEFlap{name}", m(v), mf(f), col, "Wings", "ControlSurface",
                    origin=tuple(m([tuple(a.lerp(b, 0.5))])[0]),
                    hinge={"axis": tuple(m([tuple((b - a))])[0]), "min": 0, "max": 24, "control": "LEFlap"})

        # Trailing-edge flap and aileron (hinged at TE_HINGE)
        for surface, (x0, x1), lims, control in (
            ("Flap", TE_FLAP_SPAN, (0, 30), "Flap"),
            ("Aileron", AILERON_SPAN, (-20, 20), "Aileron" + name),
        ):
            v, f = panel(root_le, root_te, tip_le, tip_te, up, WING_THICKNESS, TE_HINGE, 1.0, frac(x0), frac(x1), 4, 6)
            a, b = hinge_line(root_le, root_te, tip_le, tip_te, TE_HINGE, frac(x0), frac(x1))
            make_object(f"{surface}{name}", m(v), mf(f), col, "Wings", "ControlSurface",
                        origin=tuple(m([tuple(a.lerp(b, 0.5))])[0]),
                        hinge={"axis": tuple(m([tuple((b - a))])[0]), "min": lims[0], "max": lims[1], "control": control})

        # Wingtip launch rail
        rail_y = tip_le_y - WING_TIP_CHORD * 0.5
        v, f = box((WING_TIP_X + 0.08, rail_y, WING_Z), (0.08, 2.4, 0.10))
        make_object(f"WingtipRail{name}", m(v), mf(f), col, "Details")


def build_tail(col):
    up = (0, 0, 1)
    tip_le_y = STAB_ROOT_LE - (STAB_TIP_X - STAB_ROOT_X) * math.tan(STAB_SWEEP_LE)
    root_le = (STAB_ROOT_X, STAB_ROOT_LE, STAB_Z)
    root_te = (STAB_ROOT_X, STAB_ROOT_LE - STAB_ROOT_CHORD, STAB_Z)
    tip_le = (STAB_TIP_X, tip_le_y, STAB_Z)
    tip_te = (STAB_TIP_X, tip_le_y - STAB_TIP_CHORD, STAB_Z)
    pivot = (0.0, STAB_ROOT_LE - STAB_ROOT_CHORD * 0.35, STAB_Z)  # spigot at ~35% root chord
    for side, name in ((1, "R"), (-1, "L")):
        v, f = panel(root_le, root_te, tip_le, tip_te, up, STAB_THICKNESS, 0.0, 1.0, 0, 1, 6, 10)
        if side < 0:
            v, f = mirror_x(v), flip_faces(f)
        origin = (side * STAB_ROOT_X, pivot[1], pivot[2])
        make_object(f"Stabilator{name}", v, f, col, "Wings", "ControlSurface", origin=origin,
                    hinge={"axis": (1, 0, 0), "min": -20, "max": 15, "control": "Stabilator"})

    # Fin and rudder: span along +Z, thickness along X
    side_n = (1, 0, 0)
    fin_root_le = (0, FIN_ROOT_LE, FIN_ROOT_Z)
    fin_root_te = (0, FIN_ROOT_LE - FIN_ROOT_CHORD, FIN_ROOT_Z)
    fin_tip_le_y = FIN_ROOT_LE - (FIN_TIP_Z - FIN_ROOT_Z) * math.tan(FIN_SWEEP_LE)
    fin_tip_le = (0, fin_tip_le_y, FIN_TIP_Z)
    fin_tip_te = (0, fin_tip_le_y - FIN_TIP_CHORD, FIN_TIP_Z)
    h = FIN_TIP_Z - FIN_ROOT_Z

    def frac(z):
        return (z - FIN_ROOT_Z) / h

    fin_parts = [
        panel(fin_root_le, fin_root_te, fin_tip_le, fin_tip_te, side_n, FIN_THICKNESS, 0.0, RUDDER_HINGE, 0, 1, 8, 10),
        panel(fin_root_le, fin_root_te, fin_tip_le, fin_tip_te, side_n, FIN_THICKNESS, RUDDER_HINGE, 1.0, 0, frac(RUDDER_SPAN[0]), 1, 4),
        panel(fin_root_le, fin_root_te, fin_tip_le, fin_tip_te, side_n, FIN_THICKNESS, RUDDER_HINGE, 1.0, frac(RUDDER_SPAN[1]), 1, 1, 4),
    ]
    v, f = merge(*fin_parts)
    make_object("Fin", v, f, col, "Body")
    v, f = panel(fin_root_le, fin_root_te, fin_tip_le, fin_tip_te, side_n, FIN_THICKNESS, RUDDER_HINGE, 1.0,
                 frac(RUDDER_SPAN[0]), frac(RUDDER_SPAN[1]), 6, 6)
    a, b = hinge_line(fin_root_le, fin_root_te, fin_tip_le, fin_tip_te, RUDDER_HINGE, frac(RUDDER_SPAN[0]), frac(RUDDER_SPAN[1]))
    make_object("Rudder", v, f, col, "Body", "ControlSurface", origin=tuple(a.lerp(b, 0.5)),
                hinge={"axis": tuple(b - a), "min": -30, "max": 30, "control": "Rudder"})


def build_engines(col):
    for side, name in ((1, "R"), (-1, "L")):
        x = side * 0.28
        nv, nf = cylinder((x, -6.85, -0.02), (x, -7.45, -0.02), 0.30, 20, radius1=0.28, caps=False)
        iv, i_f = cylinder((x, -6.85, -0.02), (x, -7.45, -0.02), 0.26, 20, radius1=0.25, caps=False)
        verts, faces = merge((nv, nf), (iv, flip_faces(i_f)))
        make_object(f"Nozzle{name}", verts, faces, col, "Details", "Nozzle", extra={"engine": name})
        cv, cf = cylinder((x, -7.30, -0.02), (x, -6.95, -0.02), 0.24, 16, radius1=0.04, caps=True)
        make_object(f"Afterburner{name}", cv, cf, col, "Details", "Afterburner", extra={"engine": name})


def build_seat(col):
    parts = [
        box((0, 2.62, 0.10), (0.48, 0.50, 0.10)),  # pan
        box((0, 2.36, 0.48), (0.48, 0.12, 0.78)),  # back
        box((0, 2.40, 0.98), (0.36, 0.20, 0.26)),  # headbox
    ]
    verts, faces = merge(*parts)
    make_object("EjectionSeat", verts, faces, col, "Details")


def build_pitot(col):
    v, f = cylinder((0, 7.15, 0.0), (0, 7.75, 0.0), 0.018, 8)
    make_object("Pitot", v, f, col, "Details")


def wheel(centre, radius, width, axis_x=True, segments=18):
    cx, cy, cz = centre
    p0 = (cx - width / 2, cy, cz) if axis_x else (cx, cy - width / 2, cz)
    p1 = (cx + width / 2, cy, cz) if axis_x else (cx, cy + width / 2, cz)
    return cylinder(p0, p1, radius, segments)


def build_gear(col):
    """Gear modelled down; pivots at the retraction hinges (the game keeps it retracted in flight)."""
    nose_top = (0, 4.55, -0.42)
    v, f = cylinder(nose_top, (0, 4.55, -1.20), 0.05, 10)
    make_object("NoseGearStrut", v, f, col, "Details", "Gear", origin=nose_top,
                hinge={"axis": (1, 0, 0), "min": 0, "max": 95, "control": "Gear"})
    v, f = wheel((0, 4.55, -1.30), 0.22, 0.15)
    make_object("NoseGearWheel", v, f, col, "Details", "GearWheel", origin=(0, 4.55, -1.30),
                hinge={"axis": (1, 0, 0), "min": -720, "max": 720, "control": "Wheel"})
    for side, name in ((1, "R"), (-1, "L")):
        top = (side * 0.62, -1.55, -0.50)
        v, f = cylinder(top, (side * 0.98, -1.55, -1.30), 0.07, 10)
        make_object(f"MainGearStrut{name}", v, f, col, "Details", "Gear", origin=top,
                    hinge={"axis": (0, 1, 0), "min": 0, "max": 90, "control": "Gear"})
        v, f = wheel((side * 1.06, -1.55, -1.42), 0.32, 0.18)
        make_object(f"MainGearWheel{name}", v, f, col, "Details", "GearWheel", origin=(side * 1.06, -1.55, -1.42),
                    hinge={"axis": (1, 0, 0), "min": -720, "max": 720, "control": "Wheel"})
        # Main door (hinged along the fuselage bottom)
        v, f = box((side * 0.70, -1.55, -0.85), (0.04, 1.05, 0.62))
        make_object(f"MainGearDoor{name}", v, f, col, "Details", "GearDoor", origin=(side * 0.55, -1.55, -0.56),
                    hinge={"axis": (0, 1, 0), "min": 0, "max": 85, "control": "GearDoor"})
        # Nose doors
        v, f = box((side * 0.16, 4.55, -0.62), (0.03, 0.80, 0.36))
        make_object(f"NoseGearDoor{name}", v, f, col, "Details", "GearDoor", origin=(side * 0.14, 4.55, -0.44),
                    hinge={"axis": (0, 1, 0), "min": 0, "max": 85, "control": "GearDoor"})


# ---------------------------------------------------------------------------------------------------
# Finishing: smoothing, UVs, attachments, manifest, export
# ---------------------------------------------------------------------------------------------------


def smooth_all():
    for obj in bpy.data.objects:
        if obj.type != "MESH":
            continue
        for poly in obj.data.polygons:
            poly.use_smooth = True
        sharp_angle = math.radians(35)
        try:  # Blender 4.1+
            bpy.context.view_layer.objects.active = obj
            obj.select_set(True)
            bpy.ops.object.shade_smooth_by_angle(angle=sharp_angle)
            obj.select_set(False)
        except Exception:
            if hasattr(obj.data, "use_auto_smooth"):
                obj.data.use_auto_smooth = True
                obj.data.auto_smooth_angle = sharp_angle


def unwrap_sets():
    """One UV layout per texture set: smart project, then pack every object of the set together."""
    by_set = {}
    for obj in bpy.data.objects:
        if obj.type == "MESH":
            by_set.setdefault(obj.get("afterburner_set", "Body"), []).append(obj)
    for set_name, objs in by_set.items():
        bpy.ops.object.select_all(action="DESELECT")
        for obj in objs:
            obj.select_set(True)
        bpy.context.view_layer.objects.active = objs[0]
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.uv.smart_project(angle_limit=math.radians(55), island_margin=0.01)
        try:
            bpy.ops.uv.pack_islands(margin=0.004)
        except Exception as err:  # older versions
            print(f"pack_islands failed for {set_name}: {err}")
        bpy.ops.object.mode_set(mode="OBJECT")
    bpy.ops.object.select_all(action="DESELECT")


ATTACHMENTS = {
    # Blender axes; converted to Roblox axes in the manifest
    "CockpitEye": (0, 2.75, 1.18),
    "GunMuzzle": (0, 6.20, 0.25),
    "Nozzle1": (-0.28, -7.45, -0.02),
    "Nozzle2": (0.28, -7.45, -0.02),
    "WingtipL": (-(WING_TIP_X + 0.08), -1.30, WING_Z),
    "WingtipR": (WING_TIP_X + 0.08, -1.30, WING_Z),
    "FlareDispenser": (0, -5.00, -0.55),
    "ChaffDispenser": (0, -4.60, -0.55),
    "ChaseCam": (0, -22.0, 3.5),
    "Hardpoint1": (-(WING_TIP_X + 0.08), -1.30, WING_Z - 0.12),
    "Hardpoint2": (WING_TIP_X + 0.08, -1.30, WING_Z - 0.12),
    "Hardpoint3": (0, 0.0, -0.80),
}


def add_attachment_empties(col):
    for name, pos in ATTACHMENTS.items():
        empty = bpy.data.objects.new(f"ATT_{name}", None)
        empty.empty_display_type = "PLAIN_AXES"
        empty.empty_display_size = 0.25
        empty.location = pos
        col.objects.link(empty)


def triangle_counts():
    counts = {}
    for obj in bpy.data.objects:
        if obj.type == "MESH":
            counts[obj.name] = sum(len(p.vertices) - 2 for p in obj.data.polygons)
    return counts


def write_manifest(path_json, path_luau, counts):
    for entry in PARTS:
        entry["triangles"] = counts.get(entry["name"], 0)
    manifest = {
        "airframe": AIRFRAME,
        "units": "metres (Roblox axes: x right, y up, z aft)",
        "studsPerMetre": round(STUDS_PER_METRE, 4),
        "length": 14.45,
        "triangles": sum(counts.values()),
        "parts": PARTS,
        "attachments": {name: to_roblox(pos) for name, pos in ATTACHMENTS.items()},
        "hull": HULL,
        "hitboxes": HITBOXES,
    }
    with open(path_json, "w", encoding="utf-8") as fh:
        json.dump(manifest, fh, indent=2)
    if path_luau:
        os.makedirs(os.path.dirname(path_luau), exist_ok=True)
        with open(path_luau, "w", encoding="utf-8", newline="\n") as fh:
            fh.write("--!strict\n")
            fh.write(f"-- Generated by tools/blender/f5e_generate.py: the {AIRFRAME} model manifest (parts, hinges,\n")
            fh.write("-- attachments, hull, hitboxes). Roblox axes, metres. Do not edit by hand; re-run the generator.\n")
            fh.write("return " + to_luau(manifest) + "\n")
    return manifest


def to_luau(value, indent=0):
    pad = "\t" * (indent + 1)
    if isinstance(value, dict):
        items = [f"{pad}{key_luau(k)} = {to_luau(v, indent + 1)}," for k, v in value.items()]
        return "{\n" + "\n".join(items) + "\n" + "\t" * indent + "}"
    if isinstance(value, list):
        if all(isinstance(v, (int, float)) for v in value):
            return "{ " + ", ".join(num(v) for v in value) + " }"
        items = [f"{pad}{to_luau(v, indent + 1)}," for v in value]
        return "{\n" + "\n".join(items) + "\n" + "\t" * indent + "}"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return num(value)
    return json.dumps(value)


def key_luau(k):
    return k if k.isidentifier() else f'["{k}"]'


def num(v):
    if isinstance(v, float):
        s = f"{v:.4f}".rstrip("0").rstrip(".")
        return s if s not in ("-0", "") else "0"
    return str(v)


def export(out_dir):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in bpy.data.objects:
        if obj.type == "MESH":
            obj.select_set(True)
    bpy.ops.export_scene.fbx(
        filepath=os.path.join(out_dir, f"{AIRFRAME}_base.fbx"),
        use_selection=True,
        object_types={"MESH"},
        apply_unit_scale=True,
        apply_scale_options="FBX_SCALE_ALL",
        axis_forward="-Z",
        axis_up="Y",
        bake_space_transform=True,
        mesh_smooth_type="FACE",
        use_mesh_modifiers=True,
        add_leaf_bones=False,
        path_mode="COPY",
    )


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", default=os.path.join(os.path.dirname(__file__), "out"))
    parser.add_argument("--manifest-luau", default=None)
    args = parser.parse_args(argv)
    os.makedirs(args.out, exist_ok=True)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0

    root = collection(AIRFRAME)
    cols = {name: collection(f"{AIRFRAME}_{name}", root) for name in ("Body", "Wings", "Details", "Glass", "Gear", "Attachments")}

    build_fuselage(cols["Body"])
    build_intakes(cols["Body"])
    build_lerx(cols["Body"])
    build_canopy(cols["Glass"], cols["Body"])
    build_wings(cols["Wings"])
    build_tail(cols["Wings"])
    build_engines(cols["Details"])
    build_seat(cols["Details"])
    build_pitot(cols["Details"])
    build_gear(cols["Gear"])
    add_attachment_empties(cols["Attachments"])

    smooth_all()
    unwrap_sets()
    counts = triangle_counts()
    manifest = write_manifest(os.path.join(args.out, f"{AIRFRAME}_manifest.json"), args.manifest_luau, counts)

    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(args.out, f"{AIRFRAME}_base.blend"))
    export(args.out)

    print("=" * 60)
    print(f"{AIRFRAME}: {len(PARTS)} parts, {manifest['triangles']} triangles")
    for name, tris in sorted(counts.items(), key=lambda kv: -kv[1]):
        print(f"  {name:22s} {tris:6d}")
    print("=" * 60)


if __name__ == "__main__":
    main()
