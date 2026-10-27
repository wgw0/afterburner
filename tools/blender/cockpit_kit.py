"""
Afterburner: cockpit interiors (art pipeline §7). Shared by every jet, like the airframe kit in
f5e_generate.py, whose module settings (drawing scale, fuselage, canopy, attachments) say which jet it is.

A jet's cockpit is a separate, low-poly model in the jet's own axes (origin at the centre of gravity),
built from that jet's COCKPIT spec (in its generator script) and the shapes already measured for its
exterior, so it fits inside the real canopy:
  * Tub: the lining of the cockpit well (walls, floor, a flange over the sill), with front and rear walls
  * ConsoleL / ConsoleR: side consoles, the throttle on the left one
  * Panel: the instrument panel, tilted back, with bezels and scope hoods as geometry
  * Coaming: the glareshield hood over the panel, tucked under the windscreen
  * Gunsight (body) and HUDGlass (the combiner)
  * Stick: centre stick or side stick
  * CanopyFrameInner: the inside of the windscreen bow and the canopy's rear frame, the sill rails, mirrors
The instruments that show live values (airspeed, altimeter, G, RPM, radar) are faces: the manifest gives
each one's centre, normal, up and size, and the game draws its gauge there (CockpitController). The rest
are painted into the cockpit texture (cockpit_paint.py).

The exterior fuselage is closed across the top under the canopy, so the generator opens a well for the
cockpit to sit in (open_well), after unwrapping: the UVs stay exactly as they were, so the jet's skins
still fit. The tub lines the well, so its stretched paint never shows.
"""

import json
import math
import os
import sys

from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import f5e_generate as kit  # noqa: E402  (the airframe kit; the jet's script has already configured it)

STUDS_PER_METRE = kit.STUDS_PER_METRE
PANEL_THICKNESS = 0.03
BEZEL_DEPTH = 0.012
LINING = 0.012  # metres between the well and the tub lining
SHELL = 0.01  # thickness of the lining
LIP = 0.035  # depth of the glareshield's lip over the panel
MIRROR_AFT = 0.07  # mirrors hang this far behind the windscreen bow


def spec():
    return kit.COCKPIT


def eye():
    return Vector(kit.ATTACHMENTS["CockpitEye"])


def xd_of(y):
    return kit.REF_PITOT_XD + (kit.CG_FROM_PITOT - y) * kit.REF_PX_PER_M


def canopy_half_width(y, z):
    """Half width of the canopy glass at height z and station y (0 above it, or ahead of / behind it)."""
    xd = xd_of(y)
    if xd < kit.CANOPY[0][0] or xd > kit.CANOPY[-1][0]:
        return 0.0
    right = kit.canopy_ring(xd, 0.0, 33)[:17]  # from +w at the base up to the top centre
    if z <= right[0][2]:
        return right[0][0]
    for (x0, _, z0), (x1, _, z1) in zip(right, right[1:]):
        if z0 <= z <= z1:
            return x0 + (x1 - x0) * (z - z0) / max(z1 - z0, 1e-6)
    return 0.0


# ---------------------------------------------------------------------------------------------------
# The panel's frame: T is the centre of its top edge (on the face toward the pilot), X right, D down the
# panel's face, N toward the pilot. Instruments are placed at (u, v): u metres right, v metres down.
# ---------------------------------------------------------------------------------------------------


def panel_frame():
    p, e = spec()["panel"], eye()
    t = math.radians(p["tilt"])
    top = Vector((0, e.y + p["distance"], e.z + p["top"]))
    down = Vector((0, -math.sin(t), -math.cos(t)))
    normal = Vector((0, -math.cos(t), math.sin(t)))
    height = (p["top"] - p["bottom"]) / math.cos(t)
    return top, down, normal, height


def panel_point(u, v):
    top, down, _, _ = panel_frame()
    return top + Vector((u, 0, 0)) + down * v


# ---------------------------------------------------------------------------------------------------
# The cockpit well in the exterior fuselage
# ---------------------------------------------------------------------------------------------------


def well_stations():
    """Fuselage ring stations (xd) the well opens: from behind the seat to just ahead of the panel."""
    w = spec()["well"]
    return [xd for xd in kit.fuselage_stations() if w["back"] <= kit.Y(xd) <= w["front"]]


def open_well():
    """Pushes the top of the fuselage rings in the well down to the cockpit floor. Run after the UVs are
    made: vertices move, UVs don't. The outermost pushed vertex each side is set to the well's half
    width, so the sloped faces up to the sill stay outside the tub lining."""
    import bpy

    obj = bpy.data.objects["Fuselage"]
    w = spec()["well"]
    hw, floor = w["half_width"], w["floor"]
    rings = {kit.Y(xd): xd for xd in well_stations()}
    moved = 0
    for ry, xd in rings.items():
        _, zb, zs, _, _, _ = kit.fuselage_params(xd)
        mid = (zb + zs) / 2
        top = [v for v in obj.data.vertices if abs(v.co.y - ry) < 1e-4 and v.co.z > mid and abs(v.co.x) < hw]
        for sign in (1, -1):
            side = [v for v in top if v.co.x * sign > 1e-6]
            if side:
                outer = max(side, key=lambda v: abs(v.co.x))
                outer.co.x = sign * hw
        for v in top:
            v.co.z = floor
        moved += len(top)
    obj.data.update()
    print(f"cockpit well: {len(rings)} rings, {moved} vertices lowered to z={floor}")


def well_mask(P):
    """Texels of the exterior fuselage inside the cockpit well (for the skin painters: other players see
    into it through the canopy, so it is painted cockpit-dark)."""
    import numpy as np

    w = spec()["well"]
    stations = well_stations()
    ys = [kit.Y(xd) for xd in stations]
    sill = min(kit.fuselage_surface_z(xd, w["half_width"]) for xd in stations)
    x, y, z = P[..., 0], P[..., 1], P[..., 2]
    return (np.abs(x) < w["half_width"] + 0.005) & (y > min(ys) - 0.005) & (y < max(ys) + 0.005) & (z < sill - 0.015)


# ---------------------------------------------------------------------------------------------------
# Geometry helpers (all closed solids, so the kit's normal recalculation points every face outward)
# ---------------------------------------------------------------------------------------------------


def strip_solid(inner_rings, outer_rings):
    """A thick open surface: inner_rings and outer_rings are lists of open polylines (one per station,
    same length), the visible face and its back. Returns a closed solid."""
    n = len(inner_rings[0])
    verts = []
    for a, b in zip(inner_rings, outer_rings):
        verts.extend(a)
        verts.extend(b)
    faces = []
    stride = 2 * n
    for r in range(len(inner_rings) - 1):
        a, b = r * stride, (r + 1) * stride
        for i in range(n - 1):
            faces.append((a + i, a + i + 1, b + i + 1, b + i))  # inner
            faces.append((a + n + i, b + n + i, b + n + i + 1, a + n + i + 1))  # outer
        for i in (0, n - 1):  # the profile's two edges
            faces.append((a + i, b + i, b + n + i, a + n + i))
    last = (len(inner_rings) - 1) * stride
    for i in range(n - 1):  # end caps, one quad per profile segment
        faces.append((i, n + i, n + i + 1, i + 1))
        faces.append((last + i, last + i + 1, last + n + i + 1, last + n + i))
    return verts, faces


def oriented_box(centre, x, y, z, size):
    """A box with its own axes (x, y, z unit vectors) and size along them."""
    c = Vector(centre)
    hx, hy, hz = (Vector(a) * (s / 2) for a, s in zip((x, y, z), size))
    verts = [tuple(c + sx * hx + sy * hy + sz * hz) for sz in (-1, 1) for sy in (-1, 1) for sx in (-1, 1)]
    # order: (sx, sy, sz) = (-,-,-) (+,-,-) (-,+,-) (+,+,-) then the same at +z
    faces = [(0, 2, 3, 1), (4, 5, 7, 6), (0, 1, 5, 4), (1, 3, 7, 5), (3, 2, 6, 7), (2, 0, 4, 6)]
    return verts, faces


def ring_tube(centre, normal, up, r_in, r_out, depth, segments=16, phase=0.0):
    """A bezel: a short tube around an instrument, standing `depth` out of the panel along `normal`.
    segments=4 with phase=45 makes a square frame (r is then the half diagonal)."""
    c, n, u = Vector(centre), Vector(normal).normalized(), Vector(up).normalized()
    r = n.cross(u).normalized()

    def ring(radius, offset):
        pts = []
        for i in range(segments):
            ang = math.radians(phase) + 2 * math.pi * i / segments
            pts.append(tuple(c + n * offset + (r * math.cos(ang) + u * math.sin(ang)) * radius))
        return pts

    rings = [ring(r_out, -0.004), ring(r_out, depth), ring(r_in, depth), ring(r_in, -0.004)]
    verts = [p for ring_ in rings for p in ring_]
    faces = []
    for k in range(4):
        a, b = k * segments, ((k + 1) % 4) * segments
        for i in range(segments):
            j = (i + 1) % segments
            faces.append((a + i, a + j, b + j, b + i))
    return verts, faces


# ---------------------------------------------------------------------------------------------------
# Parts
# ---------------------------------------------------------------------------------------------------


def surface_z(y, x):
    return kit.fuselage_surface_z(xd_of(y), x)


def build_tub(col):
    """Lining of the well: a U section (sill flange, wall, floor) along the well's rings, plus front and
    rear walls."""
    w = spec()["well"]
    a = w["half_width"] - LINING
    floor = w["floor"] + LINING
    ys = sorted(kit.Y(xd) for xd in well_stations())
    inner, outer = [], []
    for y in ys:
        zs = surface_z(y, w["half_width"]) + 0.006
        f = w["half_width"] + w.get("flange", 0.08)
        glass = canopy_half_width(y, zs)
        if glass > 0:
            f = min(f, glass - 0.012)  # under the canopy, the flange stops short of the glass
        f = max(f, a + 0.02)
        inner.append([(-f, y, zs), (-a, y, zs), (-a, y, floor), (a, y, floor), (a, y, zs), (f, y, zs)])
        t = SHELL
        outer.append([(-f, y, zs - t), (-a - t, y, zs - t), (-a - t, y, floor - t), (a + t, y, floor - t),
                      (a + t, y, zs - t), (f, y, zs - t)])
    parts = [strip_solid(inner, outer)]
    # Front wall (behind the panel) and rear wall (behind the seat), up to the sill
    for y, sign in ((ys[0], 1), (ys[-1], -1)):
        top = surface_z(y, 0) + 0.01
        parts.append(kit.box((0, y + sign * 0.006, (floor + top) / 2), (2 * a + 0.02, 0.012, top - floor + 0.02)))
    v, f = kit.merge(*parts)
    kit.make_object("Tub", v, f, col, "Cockpit")


def build_consoles(col):
    c, e, w = spec()["consoles"], eye(), spec()["well"]
    floor = w["floor"] + LINING
    top = e.z + c["top"]
    y0, y1 = e.y + c["aft"], e.y + c["fore"]
    outer = w["half_width"] - LINING
    for side, name in ((-1, "L"), (1, "R")):
        x = side * (outer - c["width"] / 2)
        parts = [kit.box((x, (y0 + y1) / 2, (floor + top) / 2), (c["width"], y1 - y0, top - floor))]
        if side < 0:  # throttle: a quadrant on the console and the grip
            ty = e.y + c.get("throttle", 0.05)
            parts.append(kit.box((x, ty, top + 0.02), (0.05, 0.16, 0.04)))
            parts.append(kit.box((x + 0.01, ty + 0.03, top + 0.09), (0.045, 0.06, 0.08)))
        if side > 0 and spec().get("stick") == "side":  # the side stick's base
            parts.append(kit.box((x, e.y + 0.20, top + 0.025), (0.08, 0.14, 0.05)))
        v, f = kit.merge(*parts)
        kit.make_object(f"Console{name}", v, f, col, "Cockpit")


def build_stick(col):
    e, w = eye(), spec()["well"]
    if spec().get("stick") == "side":
        c = spec()["consoles"]
        x = w["half_width"] - LINING - c["width"] / 2
        base = (x, e.y + 0.20, e.z + c["top"] + 0.05)
        grip = (x, e.y + 0.21, e.z + c["top"] + 0.17)
        parts = [kit.cylinder(base, grip, 0.02, 10), kit.box((x, e.y + 0.215, e.z + c["top"] + 0.16), (0.045, 0.06, 0.10))]
    else:
        y = e.y + spec().get("stick_fore", 0.42)
        base = (0, y - 0.03, w["floor"] + LINING)
        top = (0, y, e.z - 0.40)
        parts = [
            kit.cylinder(base, top, 0.018, 10),
            kit.cylinder(base, (base[0], base[1], base[2] + 0.08), 0.06, 12, radius1=0.025),  # boot
            kit.box((0, y + 0.005, e.z - 0.35), (0.045, 0.055, 0.11)),  # grip
        ]
    v, f = kit.merge(*parts)
    kit.make_object("Stick", v, f, col, "Cockpit")


def panel_half_width():
    """The panel's half width: the spec's, narrowed to fit under the canopy at its top and in the well."""
    p = spec()["panel"]
    top, _, _, _ = panel_frame()
    fit = min(canopy_half_width(top.y, top.z + 0.02) - 0.03, spec()["well"]["half_width"] - LINING - 0.004)
    if fit < p["half_width"]:
        print(f"panel narrowed to {fit:.3f} m to fit the canopy and well (spec {p['half_width']})")
    return min(p["half_width"], fit)


def build_panel(col, faces):
    top, down, normal, height = panel_frame()
    hw = panel_half_width()
    right = Vector((1, 0, 0))
    centre = top + down * (height / 2) - normal * (PANEL_THICKNESS / 2)
    parts = [oriented_box(centre, right, -down, -normal, (2 * hw, height, PANEL_THICKNESS))]
    up = -down
    for inst in spec()["instruments"]:
        c = panel_point(inst["u"], inst["v"])
        kind, size = inst["kind"], inst["size"]
        if kind == "Dial":
            r = size / 2
            parts.append(ring_tube(c, normal, up, r, r + 0.008, BEZEL_DEPTH, 16))
        elif kind in ("Scope", "MFD"):
            half = size / 2
            parts.append(ring_tube(c, normal, up, half * math.sqrt(2), (half + 0.012) * math.sqrt(2), BEZEL_DEPTH, 4, 45))
            if inst.get("hood"):  # rubber hood round a radar scope, deeper at the top
                hood = inst["hood"]
                parts.append(ring_tube(c + normal * BEZEL_DEPTH, normal, up, (half + 0.006) * math.sqrt(2),
                                       (half + 0.016) * math.sqrt(2), hood, 4, 45))
        if inst.get("live"):
            w, h = (size, size)
            faces.append({
                "name": inst["name"],
                "gauge": inst["live"],
                "style": inst.get("style", spec().get("style", "Dial")),
                "centre": kit.to_roblox(tuple(c + normal * 0.002)),
                "normal": kit.to_roblox(tuple(normal)),
                "up": kit.to_roblox(tuple(up)),
                "size": [round(w, 4), round(h, 4)],
            })
    v, f = kit.merge(*parts)
    kit.make_object("Panel", v, f, col, "Cockpit")
    return hw


def build_coaming(col, hw):
    """The glareshield: a flat-topped hood from a lip over the panel forward under the windscreen. It
    narrows and drops forward so it stays inside the glass."""
    c = spec()["coaming"]
    top, _, normal, _ = panel_frame()
    lip = c.get("overhang", 0.05)
    y_aft, y_fore = top.y - lip, top.y + c["length"]
    z_aft = top.z + 0.025
    rings = []
    steps = 8
    for k in range(steps + 1):
        t = k / steps
        y = kit.lerp(y_aft, y_fore, t)
        z_top = kit.lerp(z_aft, z_aft - c.get("drop", 0.06), t)
        width = min(hw + 0.015, canopy_half_width(y, z_top + 0.015) - 0.02)
        width = max(width, 0.06)
        z_bot = z_top - LIP if y < top.y + PANEL_THICKNESS else min(surface_z(y, 0) - 0.02, z_top - 0.05)
        r = 0.02
        rings.append([(-width, y, z_bot), (-width, y, z_top - r), (-width + r, y, z_top), (width - r, y, z_top),
                      (width, y, z_top - r), (width, y, z_bot)])
    v, f = kit.lofted(rings, True, True)
    kit.make_object("Coaming", v, f, col, "Cockpit")
    return z_aft, y_aft


def build_sight(cols, z_coaming, y_aft):
    s = spec().get("sight", "Gunsight")
    big = s == "HUD"
    wide = s == "WideHUD"
    bw, bd, bh = spec().get("sight_body", (0.16 if big or wide else 0.12, 0.14, 0.06))
    y = y_aft + 0.07
    body = kit.box((0, y + 0.02, z_coaming + bh / 2), (bw, bd, bh))
    kit.make_object("Gunsight", *body, cols["Cockpit"], "Cockpit")
    # Combiner: a plate leaning back toward the pilot
    lean = math.radians(28 if not wide else 35)
    gw, h = spec().get("sight_glass", (0.11 if not (big or wide) else (0.15 if big else 0.24), 0.09 if not (big or wide) else 0.12))
    base = Vector((0, y - 0.02, z_coaming + bh))
    upv = Vector((0, -math.sin(lean), math.cos(lean)))
    centre = base + upv * (h / 2)
    glass = oriented_box(tuple(centre), (1, 0, 0), tuple(upv), tuple(Vector((1, 0, 0)).cross(upv)), (gw, h, 0.006))
    kit.make_object("HUDGlass", *glass, cols["Glass"], "Glass")


def build_canopy_frame_inner(col):
    """The inside of the canopy frames (windscreen bow, rear frame) just inside the exterior ones, sill
    rails along the canopy's base, and mirrors on the bow."""
    parts = []
    # The windscreen bow and the first frame behind the pilot (tandem canopies have more frames aft). A
    # frameless bubble canopy has only the frame behind the pilot: its sill rails start at the canopy's
    # front instead.
    frames = list(kit.CANOPY_FRAMES)
    if len(frames) == 1:
        xd0, xd1 = kit.CANOPY[1][0], frames[0]
        drawn = [xd1]
    else:
        xd0 = frames[0]
        xd1 = next((xd for xd in frames[1:] if kit.Y(xd) < eye().y), frames[-1])
        drawn = [xd0, xd1]
    for xd in drawn:
        outer = kit.canopy_ring(xd, -0.012)
        inner = kit.canopy_ring(xd, -0.045)
        d = 0.035
        ring_in = [[(p[0], p[1] + d, p[2]) for p in inner], [(p[0], p[1] - d, p[2]) for p in inner]]
        ring_out = [[(p[0], p[1] + d, p[2]) for p in outer], [(p[0], p[1] - d, p[2]) for p in outer]]
        parts.append(strip_solid(ring_in, ring_out))
    # Sill rails between the frames, on the canopy's base each side
    for side in (-1, 1):
        rings = []
        for k in range(7):
            xd = kit.lerp(xd0, xd1, k / 6)
            base = kit.canopy_ring(xd, 0.0, 17)[0 if side > 0 else -1]
            x, y, z = abs(base[0]) - 0.03, base[1], base[2] + 0.03
            rings.append([(side * (x - 0.03), y, z - 0.03), (side * (x + 0.02), y, z - 0.03),
                          (side * (x + 0.02), y, z + 0.03), (side * (x - 0.03), y, z + 0.03)])
        parts.append(kit.lofted(rings, True, True))
    ring = kit.canopy_ring(xd0, -0.05, 65)
    for x, width in spec().get("mirrors", []):  # (x, width) hanging just behind the bow
        z = min(p[2] for p in ring if abs(p[0] - x) <= width / 2 + 0.02) - 0.045
        parts.append(kit.box((x, ring[0][1] - MIRROR_AFT, z), (width, 0.012, 0.05)))
    v, f = kit.merge(*parts)
    kit.make_object("CanopyFrameInner", v, f, col, "Cockpit")


# ---------------------------------------------------------------------------------------------------
# Build, manifest, export
# ---------------------------------------------------------------------------------------------------


def build(out_dir, manifest_luau=None):
    import bpy

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.unit_settings.system = "METRIC"
    kit.PARTS.clear()
    kit.MATERIALS.clear()
    kit.TEXTURE_SETS["Cockpit"] = (0.22, 0.24, 0.26, 0.0, 0.7)
    a = kit.AIRFRAME
    root = kit.collection(f"{a}_Cockpit")
    cols = {"Cockpit": kit.collection(f"{a}_CockpitParts", root), "Glass": kit.collection(f"{a}_CockpitGlass", root)}

    faces = []
    build_tub(cols["Cockpit"])
    build_consoles(cols["Cockpit"])
    build_stick(cols["Cockpit"])
    hw = build_panel(cols["Cockpit"], faces)
    z_coaming, y_aft = build_coaming(cols["Cockpit"], hw)
    build_sight(cols, z_coaming, y_aft)
    build_canopy_frame_inner(cols["Cockpit"])
    check_panel_clear()

    kit.smooth_all()
    kit.unwrap_sets()
    counts = kit.triangle_counts()
    for entry in kit.PARTS:
        entry["triangles"] = counts.get(entry["name"], 0)
    manifest = {
        "airframe": a,
        "units": "metres (Roblox axes: x right, y up, z aft), in the jet's Root space",
        "studsPerMetre": round(STUDS_PER_METRE, 4),
        "triangles": sum(counts.values()),
        "eye": kit.to_roblox(tuple(eye())),
        "fit": {"front": "Coaming", "back": "Tub", "left": "ConsoleL", "right": "ConsoleR"},
        "parts": kit.PARTS,
        "faces": faces,
    }
    with open(os.path.join(out_dir, f"{a}_cockpit_manifest.json"), "w", encoding="utf-8") as fh:
        json.dump(manifest, fh, indent=2)
    if manifest_luau:
        os.makedirs(os.path.dirname(manifest_luau), exist_ok=True)
        with open(manifest_luau, "w", encoding="utf-8", newline="\n") as fh:
            fh.write("--!strict\n")
            fh.write(f"-- Generated by tools/blender/cockpit_generate.py: the {a} cockpit manifest (parts, live instrument\n")
            fh.write("-- faces). Roblox axes, metres, in the jet's Root space. Do not edit by hand; re-run the generator.\n")
            fh.write("return " + kit.to_luau(manifest) + "\n")
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(out_dir, f"{a}_cockpit.blend"))
    kit.export(out_dir, f"{a}_cockpit.fbx")
    print("=" * 60)
    print(f"{a} cockpit: {len(kit.PARTS)} parts, {manifest['triangles']} triangles, {len(faces)} live faces")
    for name, tris in sorted(counts.items(), key=lambda kv: -kv[1]):
        print(f"  {name:22s} {tris:6d}")
    print("=" * 60)
    return manifest


def check_panel_clear():
    """Warns if a live instrument is hidden behind the coaming or the canopy bow from the eye."""
    e = eye()
    top, _, _, _ = panel_frame()
    lip_y = top.y - spec()["coaming"].get("overhang", 0.05)
    lip_z = top.z + 0.025 - LIP
    hw = panel_half_width()
    for inst in spec()["instruments"]:
        if abs(inst["u"]) + inst["size"] / 2 + 0.008 > hw:
            print(f"WARNING: {inst['name']} runs off the panel's edge (half width {hw:.3f})")
        c = panel_point(inst["u"], inst["v"] - inst["size"] / 2)  # the instrument's top edge
        t = (lip_y - e.y) / max(c.y - e.y, 1e-6)
        z_at_lip = e.z + (c.z - e.z) * t
        if z_at_lip > lip_z and t < 1:
            print(f"WARNING: {inst['name']} top edge is hidden behind the glareshield lip")
