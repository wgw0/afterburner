"""
Afterburner: F-5E Tiger II base mesh generator (Blender 4.x / 5.x).

Builds a mid-poly, modular F-5E at real-world size, measured from reference drawings:
  * a lofted fuselage (shark nose, flat-topped cockpit section, dorsal spine, area-ruled waist),
    D-section intakes, LERX, canopy and frame
  * wings, leading-edge flaps, trailing-edge flaps and ailerons cut from real airfoil sections
  * all-moving stabilators, fin with dorsal fillet, rudder
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
(1 m = 3.5714 studs in the game). The origin sits at the centre of gravity (25% of the mean
aerodynamic chord), the point the flight model rotates the jet about.

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
# Reference. Shapes are measured from the Wikimedia Commons three-view "Northrop F-5E Tiger II
# 3-view.svg" (side view nose left, top view below it), cross-checked against the USAF flight manual
# T.O. 1F-5E-1 figure 2-8 and walkaround photos (see docs/art/reference/F5E/SOURCES.md, kept out of
# git). Measurements are in the drawing's pixels on a 2000 px wide copy:
#   xd   distance along the side and top views (pitot tip at 22.9, nozzle exit at 1545.8)
#   row  height in the side view (row 290 is z = 0; smaller rows are higher)
# The scale comes from the published length, 14.45 m pitot to nozzle; it also reproduces the
# published height (4.08 m) and span (8.13 m over the rails).
# ---------------------------------------------------------------------------------------------------

REF_PX_PER_M = (1545.8 - 22.9) / 14.45
REF_PITOT_XD = 22.9
REF_Z0_ROW = 290.0
CG_FROM_PITOT = 8.825  # metres from the pitot tip back to 25% MAC, which becomes the origin


def Y(xd):
    """Blender Y (forward) at a drawing station."""
    return CG_FROM_PITOT - (xd - REF_PITOT_XD) / REF_PX_PER_M


def Z(row):
    """Blender Z (up) at a side-view row."""
    return (REF_Z0_ROW - row) / REF_PX_PER_M


# Fuselage stations: (xd, half width, bottom z, shoulder z, top z, spine half width, exponent).
# The section is a superellipse body (half width x bottom..shoulder) blended with a narrower dorsal
# spine rising to the top z behind the canopy. Under the canopy the top is the cockpit sill.
FUSELAGE = [
    (95, 0.012, -0.34, -0.32, -0.32, 0.0, 2.0),  # radome tip
    (110, 0.073, -0.39, -0.27, -0.27, 0.0, 2.0),
    (150, 0.181, -0.45, -0.19, -0.19, 0.0, 2.1),
    (190, 0.266, -0.49, -0.11, -0.11, 0.0, 2.2),  # shark nose: wider than deep
    (230, 0.335, -0.51, -0.03, -0.03, 0.0, 2.3),
    (290, 0.406, -0.525, 0.083, 0.083, 0.0, 2.5),
    (350, 0.456, -0.53, 0.207, 0.207, 0.0, 2.7),
    (410, 0.478, -0.53, 0.323, 0.323, 0.0, 3.0),
    (465, 0.48, -0.53, 0.44, 0.44, 0.0, 3.3),  # windscreen base
    (560, 0.48, -0.53, 0.47, 0.47, 0.0, 3.5),
    (650, 0.49, -0.53, 0.49, 0.49, 0.0, 3.5),  # intake lips start
    (690, 0.52, -0.53, 0.49, 0.62, 0.40, 3.5),  # spine rises inside the canopy's rear
    (720, 0.54, -0.53, 0.49, 0.88, 0.43, 3.5),
    (750, 0.56, -0.53, 0.49, 0.93, 0.44, 3.5),
    (850, 0.66, -0.52, 0.47, 0.86, 0.42, 3.4),
    (965, 0.757, -0.50, 0.43, 0.79, 0.38, 3.3),  # intakes merged
    (1060, 0.74, -0.48, 0.42, 0.72, 0.34, 3.2),  # area-rule waist at the wing
    (1150, 0.79, -0.44, 0.42, 0.66, 0.30, 3.1),
    (1230, 0.76, -0.40, 0.44, 0.53, 0.22, 3.0),
    (1300, 0.735, -0.36, 0.44, 0.50, 0.20, 2.9),
    (1390, 0.656, -0.29, 0.45, 0.47, 0.0, 2.8),
    (1470, 0.574, -0.17, 0.45, 0.45, 0.0, 2.6),
    (1500, 0.53, -0.12, 0.43, 0.43, 0.0, 2.5),  # nozzles start
]
FUSELAGE_RINGS = 60
FUSELAGE_SEGMENTS = 44

# Intakes: (xd, outer half width, top z, bottom z). The lip is swept back 0.34 m from inner to outer.
INTAKES = [
    (655, 0.90, 0.20, -0.43),
    (690, 0.95, 0.30, -0.46),
    (772, 1.00, 0.42, -0.48),
    (855, 0.88, 0.42, -0.46),
    (930, 0.80, 0.34, -0.40),
    (1000, 0.74, 0.22, -0.28),
]
INTAKE_LIP_SWEEP = 0.34

# LERX outer edge (half width, xd), from the intake to where it meets the wing leading edge
LERX_EDGE = [(0.92, 700), (1.09, 750), (1.28, 790), (1.34, 850), (1.37, 885)]
LERX_INNER = 0.80

# Canopy: (xd, half width at the sill, top z)
CANOPY = [
    (465, 0.10, 0.45),
    (490, 0.32, 0.55),
    (520, 0.41, 0.69),
    (553, 0.44, 0.86),  # windscreen bow
    (590, 0.445, 0.95),
    (650, 0.44, 0.983),
    (700, 0.41, 0.97),
    (735, 0.32, 0.95),
    (755, 0.18, 0.935),  # fairs into the spine
]
CANOPY_FRAMES = (553, 668)  # windscreen bow and the canopy's rear frame


def _on(line, x):
    (x0, y0), (x1, y1) = line
    return y0 + (y1 - y0) * (x - x0) / (x1 - x0)


# Wing planform (one side, x outboard). Measured leading and trailing edges (half width, Y).
_WING_LE = ((0.83, Y(851)), (3.87, Y(1030)))
_WING_TE = ((0.83, Y(1147)), (3.87, Y(1117)))
WING_ROOT_X, WING_TIP_X = 0.72, 3.87
WING_ROOT_LE, WING_ROOT_TE = _on(_WING_LE, WING_ROOT_X), _on(_WING_TE, WING_ROOT_X)
WING_SWEEP_LE = math.atan((WING_ROOT_LE - _WING_LE[1][1]) / (WING_TIP_X - WING_ROOT_X))
WING_TIP_CHORD = _WING_LE[1][1] - _WING_TE[1][1]
WING_Z = Z(312)
WING_THICKNESS = 0.048
# Chord fractions and spans of the moving surfaces
LE_FLAP_CHORD = 0.13
TE_HINGE = 0.75
TE_FLAP_SPAN = (0.85, 2.17)
AILERON_SPAN = (2.21, 3.06)
RAIL_Y, RAIL_LENGTH = (Y(1010) + Y(1150)) / 2, Y(1010) - Y(1150)

# Stabilator (all-moving)
STAB_ROOT_X, STAB_TIP_X = 0.70, 2.10
STAB_ROOT_LE, STAB_ROOT_CHORD = Y(1293), (1450 - 1293) / REF_PX_PER_M
STAB_SWEEP_LE = math.atan((Y(1293) - Y(1388)) / (STAB_TIP_X - STAB_ROOT_X))
STAB_TIP_CHORD = 0.49
STAB_Z = Z(298)
STAB_THICKNESS = 0.05

# Fin and rudder (root embedded slightly in the spine)
FIN_ROOT_Z, FIN_TIP_Z = 0.46, Z(18.9)
FIN_ROOT_LE, FIN_ROOT_CHORD = Y(1183), (1476 - 1183) / REF_PX_PER_M
FIN_SWEEP_LE = math.atan((Y(1183) - Y(1336)) / (FIN_TIP_Z - Z(237)))
FIN_TIP_CHORD = 0.68
FIN_THICKNESS = 0.05
RUDDER_HINGE = 0.72
RUDDER_SPAN = (0.52, Z(137))

# Engines: twin J85 nozzles
NOZZLE_X, NOZZLE_Z, NOZZLE_R = 0.265, Z(274.6), 0.245
NOZZLE_Y0, NOZZLE_Y1 = Y(1500), Y(1545.8)

# Gear, measured from the side view (wheel circles) and the manual's top view (track 3.4 m)
NOSE_WHEEL = {"at": (0, Y(469), Z(428.5)), "radius": 0.233, "width": 0.14}
MAIN_WHEEL = {"at": (1.70, Y(1005), Z(420)), "radius": 0.266, "width": 0.18}

# Gameplay data in Roblox axes (metres), matched to this model. Roblox z = -Blender Y.
HULL = {"size": [1.5, 1.3, 13.4], "at": [0, 0, -1.25]}
HITBOXES = {
    "Cockpit": {"size": [1.0, 1.1, 2.6], "at": [0, 0.45, -3.6]},
    "Fuselage": {"size": [1.6, 1.3, 8.8], "at": [0, 0, -2.5]},
    "Engine": {"size": [1.6, 1.2, 3.7], "at": [0, 0.12, 3.75]},
    "WingL": {"size": [3.1, 0.4, 2.4], "at": [-2.35, round(WING_Z, 2), 0.6]},
    "WingR": {"size": [3.1, 0.4, 2.4], "at": [2.35, round(WING_Z, 2), 0.6]},
    "Tail": {"size": [4.2, 2.6, 2.6], "at": [0, 1.0, 3.7]},
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


def pchip(xs, ys, x):
    """Monotone cubic interpolation (Fritsch-Carlson) through (xs, ys); xs increasing. No overshoot."""
    n = len(xs)
    if x <= xs[0]:
        return ys[0]
    if x >= xs[-1]:
        return ys[-1]
    h = [xs[i + 1] - xs[i] for i in range(n - 1)]
    d = [(ys[i + 1] - ys[i]) / h[i] for i in range(n - 1)]
    m = [d[0]] + [0.0] * (n - 2) + [d[-1]]
    for i in range(1, n - 1):
        if d[i - 1] * d[i] > 0:
            w1, w2 = 2 * h[i] + h[i - 1], h[i] + 2 * h[i - 1]
            m[i] = (w1 + w2) / (w1 / d[i - 1] + w2 / d[i])
    i = max(k for k in range(n - 1) if xs[k] <= x)
    t = (x - xs[i]) / h[i]
    t2, t3 = t * t, t * t * t
    return ((2 * t3 - 3 * t2 + 1) * ys[i] + (t3 - 2 * t2 + t) * h[i] * m[i]
            + (-2 * t3 + 3 * t2) * ys[i + 1] + (t3 - t2) * h[i] * m[i + 1])


def table_at(table, xd):
    """Interpolates every column of a station table at xd (column 0 is xd)."""
    xs = [row[0] for row in table]
    return tuple(pchip(xs, [row[k] for row in table], xd) for k in range(1, len(table[0])))


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
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
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
# Fuselage sections
# ---------------------------------------------------------------------------------------------------


def _superellipse_hit(origin_z, dx, dz, a, cz, b, e):
    """Distance along the ray (0, origin_z) + t (dx, dz) to the superellipse |x/a|^e + |(z-cz)/b|^e = 1
    (the origin must be inside it)."""
    lo, hi = 0.0, 4.0
    for _ in range(40):
        t = (lo + hi) / 2
        f = abs(t * dx / a) ** e + abs((origin_z + t * dz - cz) / b) ** e
        lo, hi = (t, hi) if f < 1 else (lo, t)
    return (lo + hi) / 2


def fuselage_params(xd):
    hw, zb, zs, zt, wsp, e = table_at(FUSELAGE, xd)
    return max(hw, 0.004), zb, zs, max(zt, zs), max(wsp, 0.0), e


def fuselage_ring(xd, segments=FUSELAGE_SEGMENTS):
    """Section points (x, z) at a station, going round from the top centre. The body superellipse and
    the dorsal spine are blended with a smooth maximum so the spine rises out of the shoulders."""
    hw, zb, zs, zt, wsp, e = fuselage_params(xd)
    cz = (zs + zb) / 2
    hb = max((zs - zb) / 2, 0.004)
    spine = wsp > 0.02 and zt - zs > 0.01
    pts = []
    for i in range(segments):
        ang = math.pi / 2 - 2 * math.pi * i / segments
        dx, dz = math.cos(ang), math.sin(ang)
        r = _superellipse_hit(cz, dx, dz, hw, cz, hb, e)
        if spine:
            rs = _superellipse_hit(cz, dx, dz, wsp, cz, zt - cz, 2.6)
            k = 10.0
            r = (r**k + rs**k) ** (1 / k)
        pts.append((r * dx, cz + r * dz))
    return pts


def fuselage_surface_z(xd, x):
    """Height of the fuselage's upper surface at lateral offset x (for seating the canopy)."""
    ring = fuselage_ring(xd, 96)
    upper = [p for p in ring[: len(ring) // 4 + 1]]  # top centre round to the right side
    for (x0, z0), (x1, z1) in zip(upper, upper[1:]):
        if x0 <= x <= x1 or x1 <= x <= x0:
            t = 0 if x1 == x0 else (x - x0) / (x1 - x0)
            return lerp(z0, z1, t)
    return upper[-1][1]


def fuselage_stations():
    """Ring stations from the radome tip to the nozzles, closer together at the nose."""
    x0, x1 = FUSELAGE[0][0], FUSELAGE[-1][0]
    return [x0 + (x1 - x0) * (k / (FUSELAGE_RINGS - 1)) ** 1.25 for k in range(FUSELAGE_RINGS)]


# ---------------------------------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------------------------------


def build_fuselage(col):
    rings = []
    for xd in fuselage_stations():
        y = Y(xd)
        rings.append([(x, y, z) for x, z in fuselage_ring(xd)])
    verts, faces = lofted(rings, cap_start=True, cap_end=True)
    make_object("Fuselage", verts, faces, col, "Body")


def build_intakes(col):
    """Side intakes: D-section ducts against the fuselage (flat side on the skin), with a swept lip and
    a recessed mouth, fading into the fuselage over the wing root."""

    def ring(xd, outer, zt, zb, side, scale=1.0, dxd=0.0, sweep=True):
        hw = fuselage_params(xd)[0]
        inner = hw - 0.06
        zc = (zt + zb) / 2
        hz = (zt - zb) / 2 * scale
        b = (outer - inner) * scale
        y0 = Y(xd + dxd)
        pts = []
        for i in range(13):  # outer half, bottom -> top: a slightly squared D
            ang = -math.pi / 2 + math.pi * i / 12
            c, s_ = math.cos(ang), math.sin(ang)
            off = 0.02 + b * (abs(c) ** 0.6)
            x = inner + off
            z = zc + math.copysign(abs(s_) ** 0.8, s_) * hz
            y = y0 - (INTAKE_LIP_SWEEP * off / max(outer - inner, 0.01) if sweep else 0.0)
            pts.append((side * x, y, z))
        for i in range(1, 4):  # flat inner side, top -> bottom
            z = zc + hz - 2 * hz * i / 4
            pts.append((side * inner, y0, z))
        return pts

    parts = []
    for side in (1, -1):
        xd0, o0, t0, b0 = INTAKES[0]
        rings = [ring(xd0, o0, t0, b0, side, 0.78, 45), ring(xd0, o0, t0, b0, side, 0.86, -2)]
        rings += [ring(xd, o, t, b, side, sweep=(k == 0)) for k, (xd, o, t, b) in enumerate(INTAKES)]
        parts.append(lofted(rings, cap_start=True, cap_end=False))
    verts, faces = merge(*parts)
    make_object("Intakes", verts, faces, col, "Body")


def build_lerx(col):
    """Leading-edge root extensions: thin strakes with a sharp outer edge, from the intakes to the wing."""
    parts = []
    z, th = WING_Z + 0.01, 0.025
    for side in (1, -1):
        top, bottom, edge = [], [], []
        for hw, xd in LERX_EDGE:
            y = Y(xd)
            top.append((side * LERX_INNER, y, z + th))
            bottom.append((side * LERX_INNER, y, z - th))
            edge.append((side * hw, y, z))
        n = len(edge)
        verts = top + bottom + edge
        faces = []
        for i in range(n - 1):
            faces.append((i, i + 1, 2 * n + i + 1, 2 * n + i))  # upper surface
            faces.append((n + i, 2 * n + i, 2 * n + i + 1, n + i + 1))  # lower surface
            faces.append((i, n + i, n + i + 1, i + 1))  # inner face (inside the fuselage)
        faces.append((0, 2 * n, n))  # front
        faces.append((n - 1, 2 * n - 1, 3 * n - 1))  # back (inside the wing root)
        parts.append((verts, faces))
    verts, faces = merge(*parts)
    make_object("LERX", verts, faces, col, "Body")


def canopy_ring(xd, grow=0.0, steps=17):
    """Canopy section: a superellipse arch from the fuselage surface up to the canopy top."""
    w, top = table_at(CANOPY, xd)
    w += grow
    top += grow
    base = fuselage_surface_z(xd, min(w, fuselage_params(xd)[0] * 0.98)) - 0.03
    y = Y(xd)
    pts = []
    for i in range(steps):
        ang = math.pi * i / (steps - 1)
        c, s = math.cos(ang), math.sin(ang)
        x = w * math.copysign(abs(c) ** (2 / 2.4), c)
        pts.append((x, y, base + (top - base) * abs(s) ** (2 / 2.4)))
    return pts


def build_canopy(col_glass, col_body):
    first, last = CANOPY[0][0], CANOPY[-1][0]
    rings = [canopy_ring(first + (last - first) * k / 15) for k in range(16)]
    verts, faces = lofted(rings, cap_start=True, cap_end=True)
    make_object("Canopy", verts, faces, col_glass, "Glass")
    # Frame: the windscreen bow and the rear frame, slightly proud of the glass
    frame_parts = []
    for xd in CANOPY_FRAMES:
        outer = canopy_ring(xd, 0.02)
        inner = canopy_ring(xd, -0.015)
        d = 0.03
        verts = ([(p[0], p[1] + d, p[2]) for p in outer] + [(p[0], p[1] - d, p[2]) for p in outer]
                 + [(p[0], p[1] + d, p[2]) for p in inner] + [(p[0], p[1] - d, p[2]) for p in inner])
        n = len(outer)
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
            panel(root_le, root_te, tip_le, tip_te, up, WING_THICKNESS, 0.0, 1.0, frac(AILERON_SPAN[1]), 1.0, 2, 12),
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
        v, f = box((WING_TIP_X + 0.04, RAIL_Y, WING_Z), (0.08, RAIL_LENGTH, 0.10))
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

    # Dorsal fillet: a thin wedge from the spine curving up (concave) into the fin's leading edge
    fillet_z = 0.88
    le_y = FIN_ROOT_LE - (fillet_z - FIN_ROOT_Z) * math.tan(FIN_SWEEP_LE)
    outline = [(Y(1140), 0.60)]  # front, low on the spine
    for t in (0.35, 0.65):  # concave top edge: close to the spine first, then rising steeply
        outline.append((lerp(Y(1140), le_y, t), lerp(0.62, fillet_z, t**2.2)))
    outline += [(le_y, fillet_z), (FIN_ROOT_LE - 0.3, FIN_ROOT_Z)]
    half = [0.05, 0.04, 0.03, 0.02, 0.05]
    n = len(outline)
    fv = [(-h, y, z) for (y, z), h in zip(outline, half)] + [(h, y, z) for (y, z), h in zip(outline, half)]
    ff = [tuple(range(n)), tuple(reversed(range(n, 2 * n)))]
    ff += [(i, n + i, n + (i + 1) % n, (i + 1) % n) for i in range(n)]

    fin_parts = [
        panel(fin_root_le, fin_root_te, fin_tip_le, fin_tip_te, side_n, FIN_THICKNESS, 0.0, RUDDER_HINGE, 0, 1, 8, 10),
        panel(fin_root_le, fin_root_te, fin_tip_le, fin_tip_te, side_n, FIN_THICKNESS, RUDDER_HINGE, 1.0, 0, frac(RUDDER_SPAN[0]), 1, 4),
        panel(fin_root_le, fin_root_te, fin_tip_le, fin_tip_te, side_n, FIN_THICKNESS, RUDDER_HINGE, 1.0, frac(RUDDER_SPAN[1]), 1, 3, 4),
        (fv, ff),
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
        x = side * NOZZLE_X
        p0, p1 = (x, NOZZLE_Y0 + 0.05, NOZZLE_Z), (x, NOZZLE_Y1, NOZZLE_Z)
        nv, nf = cylinder(p0, p1, NOZZLE_R + 0.015, 20, radius1=NOZZLE_R, caps=False)
        iv, i_f = cylinder(p0, p1, NOZZLE_R - 0.025, 20, radius1=NOZZLE_R - 0.03, caps=False)
        # Close the lip between the outer and inner walls at the exit
        n = 20
        lip = [(n + i, n + (i + 1) % n, len(nv) + n + (i + 1) % n, len(nv) + n + i) for i in range(n)]
        verts, faces = merge((nv, nf), (iv, flip_faces(i_f)))
        faces += lip
        make_object(f"Nozzle{name}", verts, faces, col, "Details", "Nozzle", extra={"engine": name})
        cv, cf = cylinder((x, NOZZLE_Y1 + 0.12, NOZZLE_Z), (x, NOZZLE_Y0 + 0.05, NOZZLE_Z), NOZZLE_R - 0.04, 16,
                          radius1=0.04, caps=True)
        make_object(f"Afterburner{name}", cv, cf, col, "Details", "Afterburner", extra={"engine": name})


def build_seat(col):
    parts = [
        box((0, 3.10, 0.02), (0.48, 0.50, 0.10)),  # pan
        box((0, 2.82, 0.36), (0.48, 0.12, 0.66)),  # back
        box((0, 2.86, 0.80), (0.36, 0.20, 0.26)),  # headbox
    ]
    verts, faces = merge(*parts)
    make_object("EjectionSeat", verts, faces, col, "Details")


def build_pitot(col):
    v, f = cylinder((0, Y(95) + 0.02, Z(324.8)), (0, Y(REF_PITOT_XD), Z(324.8)), 0.022, 8)
    make_object("Pitot", v, f, col, "Details")


def wheel(centre, radius, width, axis_x=True, segments=18):
    cx, cy, cz = centre
    p0 = (cx - width / 2, cy, cz) if axis_x else (cx, cy - width / 2, cz)
    p1 = (cx + width / 2, cy, cz) if axis_x else (cx, cy + width / 2, cz)
    return cylinder(p0, p1, radius, segments)


def build_gear(col):
    """Gear modelled down; pivots at the retraction hinges (the game keeps it retracted in flight)."""
    nx, ny, nz = NOSE_WHEEL["at"]
    nose_top = (0, ny + 0.16, -0.50)
    v, f = cylinder(nose_top, (0, ny, nz + 0.08), 0.05, 10)
    make_object("NoseGearStrut", v, f, col, "Details", "Gear", origin=nose_top,
                hinge={"axis": (1, 0, 0), "min": 0, "max": 95, "control": "Gear"})
    v, f = wheel(NOSE_WHEEL["at"], NOSE_WHEEL["radius"], NOSE_WHEEL["width"])
    make_object("NoseGearWheel", v, f, col, "Details", "GearWheel", origin=NOSE_WHEEL["at"],
                hinge={"axis": (1, 0, 0), "min": -720, "max": 720, "control": "Wheel"})
    mx, my, mz = MAIN_WHEEL["at"]
    for side, name in ((1, "R"), (-1, "L")):
        top = (side * 1.45, my + 0.04, WING_Z - 0.09)  # nearly vertical leg (walkaround photos)
        v, f = cylinder(top, (side * (mx - 0.12), my, mz + 0.08), 0.07, 10)
        make_object(f"MainGearStrut{name}", v, f, col, "Details", "Gear", origin=top,
                    hinge={"axis": (0, 1, 0), "min": 0, "max": 90, "control": "Gear"})
        centre = (side * mx, my, mz)
        v, f = wheel(centre, MAIN_WHEEL["radius"], MAIN_WHEEL["width"])
        make_object(f"MainGearWheel{name}", v, f, col, "Details", "GearWheel", origin=centre,
                    hinge={"axis": (1, 0, 0), "min": -720, "max": 720, "control": "Wheel"})
        # Main door (hinged along the wing root's underside)
        v, f = box((side * 1.30, my, WING_Z - 0.38), (0.04, 1.0, 0.55))
        make_object(f"MainGearDoor{name}", v, f, col, "Details", "GearDoor", origin=(side * 1.28, my, WING_Z - 0.10),
                    hinge={"axis": (0, 1, 0), "min": 0, "max": 85, "control": "GearDoor"})
        # Nose doors
        v, f = box((side * 0.16, ny + 0.10, -0.645), (0.03, 0.70, 0.25))
        make_object(f"NoseGearDoor{name}", v, f, col, "Details", "GearDoor", origin=(side * 0.14, ny + 0.10, -0.52),
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
    "CockpitEye": (0, 3.15, 0.80),
    "GunMuzzle": (0, Y(290), Z(278)),  # the two nose guns sit either side of this point
    "Nozzle1": (-NOZZLE_X, NOZZLE_Y1, NOZZLE_Z),
    "Nozzle2": (NOZZLE_X, NOZZLE_Y1, NOZZLE_Z),
    "WingtipL": (-(WING_TIP_X + 0.08), RAIL_Y, WING_Z),
    "WingtipR": (WING_TIP_X + 0.08, RAIL_Y, WING_Z),
    "FlareDispenser": (0, -3.40, -0.33),
    "ChaffDispenser": (0, -3.00, -0.37),
    "ChaseCam": (0, -20.5, 3.5),
    "Hardpoint1": (-(WING_TIP_X + 0.08), RAIL_Y, WING_Z - 0.12),
    "Hardpoint2": (WING_TIP_X + 0.08, RAIL_Y, WING_Z - 0.12),
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
