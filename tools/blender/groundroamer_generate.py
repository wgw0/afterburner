"""
Afterburner: the Ground Roamer (Blender 4.x / 5.x), a drivable 4x4 for exploring the map from the ground. It is
modelled on a classic British short-wheelbase (88 in) soft-top utility vehicle of the 1970s, with no maker's names
or badges: its own badge reads GROUND ROAMER.

Built at real size with the jets' kit (f5e_generate.py) for its outputs (texture sets, manifest, FBX), but its
shapes are made the way a car body is: panels are bevelled boxes with the round wheel arches and lamp bowls cut
by booleans, the tilt is lofted over its hoops and sags between them, and the tyres are revolved from a real
tyre section. Each part is assembled from temporary objects with Bevel and Boolean modifiers, then evaluated.

  Body     front wings (headlamp bowls, round arches), bonnet, grille panel, bulkhead with its vent flaps, doors
           and their window frames, the rear tub with its arches, galvanised cappings, tailgate, floor, wheel boxes
  Frame    the windscreen frame, raked back 6 degrees
  Tilt     the canvas hood over the cab and the back
  Glass    windscreen and door glass
  Chassis  ladder frame, bumper, crossmember, axles and differentials, leaf springs, dampers, propshafts,
           track rod, exhaust and silencer, fuel tank, mudflaps
  Lamps    headlamps, side lamps, indicators, rear lamps, the grille and its slats, mirrors, wipers, hinges,
           handles
  Cab      dashboard with the centre instrument binnacle, steering wheel and column, seats, levers
  Wheels   WheelFL, WheelFR, WheelRL, WheelRR (origin on the hub) and the SpareWheel lying on the bonnet
  Decals   badge and number plates (a hand-laid UV strip for groundroamer_decals.py)

Axes: Blender X right, Y forward, Z up; the origin is on the ground midway between the axles. Units are metres
(1 stud = 1 m). Dimensions are the published ones (2,235 mm wheelbase, 1,310 mm track, 3,620 mm long,
1,680 mm wide, 1,970 mm high with the tilt, 7.50-16 tyres); shapes are from the photos in
docs/art/reference/GroundRoamer (kept out of git).

  blender -b --python tools/blender/groundroamer_generate.py -- --out <dir> --manifest-luau tools/Manifests/Vehicles/GroundRoamer.luau
"""

import argparse
import math
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import f5e_generate as kit  # noqa: E402  (shared helpers; its module settings are switched below)

kit.AIRFRAME = "GroundRoamer"
kit.LENGTH = 3.62
kit.TEXTURE_SETS = {
    "Body": (0.24, 0.28, 0.20, 0.0, 0.55),
    "Canvas": (0.30, 0.31, 0.24, 0.0, 0.9),
    "Details": (0.06, 0.06, 0.06, 0.2, 0.6),
    "Glass": (0.08, 0.12, 0.15, 0.0, 0.02),
    "Decals": (0.9, 0.9, 0.9, 0.0, 0.5),
}
kit.PARTS.clear()

# Layout (metres)
WHEELBASE = 2.235
TRACK = 1.31
TYRE_R = 0.40
TYRE_W = 0.205
AXLE_F, AXLE_R = WHEELBASE / 2, -WHEELBASE / 2
FRONT, REAR = 1.84, -1.78  # bumper face, tailgate
HALF_W = 0.84  # body half width (1.68 m)
WING_IN = 0.48  # inner edge of the front wings
WING_TOP = 1.05
WING_FRONT = 1.62
BONNET = 1.09
CAPPING = 1.07  # top of the tub cappings
BULKHEAD = 0.66  # front face of the bulkhead
DOOR_REAR = -0.05
SCREEN_BOT, SCREEN_TOP = 1.12, 1.72
RAKE = math.radians(6)
ROOF = 1.95
SILL = 0.52
ARCH_R = 0.50
DRIVER_X = 0.38  # right-hand drive
LAMP_X, LAMP_Z, LAMP_R = 0.645, 0.84, 0.105

WHEELS = {"FL": (-TRACK / 2, AXLE_F), "FR": (TRACK / 2, AXLE_F), "RL": (-TRACK / 2, AXLE_R), "RR": (TRACK / 2, AXLE_R)}
SPARE = (0.0, 1.17, BONNET + 0.11)

EYE = (DRIVER_X, -0.12, 1.52)
kit.HULL = {"size": [1.68, 1.97, 3.62], "at": [0, 0.985, -0.03]}
kit.HITBOXES = {"Body": {"size": [1.68, 1.45, 3.62], "at": [0, 1.0, -0.03]}}
kit.ATTACHMENTS = {
    "DriverEye": EYE,
    "ChaseCam": (0, -7.5, 3.0),
    "Exhaust": (0.62, REAR + 0.05, 0.36),
    "HeadlampL": (-LAMP_X, WING_FRONT, LAMP_Z),
    "HeadlampR": (LAMP_X, WING_FRONT, LAMP_Z),
    **{f"Wheel{k}": (x, y, TYRE_R) for k, (x, y) in WHEELS.items()},
}

SCRATCH = []  # temporary objects, deleted after evaluation


# ---------------------------------------------------------------------------------------------------
# Temporary objects, modifiers and evaluation
# ---------------------------------------------------------------------------------------------------


def temp(verts, faces, name="tmp"):
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    me.update()
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    SCRATCH.append(obj)
    return obj


def rbox(x0, x1, y0, y1, z0, z1, bevel=0.02, segments=2):
    """A box from its extents, with its edges rounded."""
    x0, x1 = sorted((x0, x1))
    v, f = kit.box(((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), (x1 - x0, y1 - y0, z1 - z0))
    obj = temp(v, f)
    if bevel > 0:
        width = min(bevel, (x1 - x0) * 0.45, (y1 - y0) * 0.45, (z1 - z0) * 0.45)
        m = obj.modifiers.new("bevel", "BEVEL")
        m.width = width
        m.segments = segments
        m.limit_method = "NONE"
    return obj


def cyl(p0, p1, radius, segments=16, radius1=None, caps=True):
    v, f = kit.cylinder(p0, p1, radius, segments, radius1=radius1, caps=caps)
    return temp(v, f)


def cut(obj, cutter):
    m = obj.modifiers.new("cut", "BOOLEAN")
    m.operation = "DIFFERENCE"
    m.object = cutter
    m.solver = "EXACT"
    cutter.hide_render = True
    return obj


def arch_cutter(y, side_x0, side_x1, radius=ARCH_R):
    """A cylinder along x through the panel, centred on an axle."""
    return cyl((side_x0, y, TYRE_R), (side_x1, y, TYRE_R), radius, 28)


def collect(objs, transform=None):
    """Evaluated world-space verts and faces of the objects (after their modifiers), merged."""
    dg = bpy.context.evaluated_depsgraph_get()
    verts, faces = [], []
    for obj in objs:
        ev = obj.evaluated_get(dg)
        me = ev.to_mesh()
        mw = obj.matrix_world
        base = len(verts)
        for v in me.vertices:
            p = mw @ v.co
            verts.append(transform(tuple(p)) if transform else tuple(p))
        for poly in me.polygons:
            faces.append(tuple(base + i for i in poly.vertices))
        ev.to_mesh_clear()
    return verts, faces


def part(name, objs, col, set_name, kind="Static", origin=(0, 0, 0), extra=None, transform=None):
    v, f = collect(objs, transform)
    return kit.make_object(name, v, f, col, set_name, kind=kind, origin=origin, extra=extra)


def clear_scratch():
    for obj in SCRATCH:
        me = obj.data
        bpy.data.objects.remove(obj)
        bpy.data.meshes.remove(me)
    SCRATCH.clear()


def rake(p):
    """Leans a point of the windscreen back about the bottom of the screen."""
    x, y, z = p
    return (x, y - (z - SCREEN_BOT) * math.tan(RAKE), z)


def revolve(profile, centre, axis_sign=1, segments=28, axis="x"):
    """A closed (r, a) section revolved round an axis through centre (a along the axis, outwards for +sign)."""
    cx, cy, cz = centre
    rings = []
    for k in range(segments):
        ang = 2 * math.pi * k / segments
        c, s = math.cos(ang), math.sin(ang)
        ring = []
        for r, a in profile:
            if axis == "x":
                ring.append((cx + axis_sign * a, cy + r * c, cz + r * s))
            else:
                ring.append((cx + r * c, cy + r * s, cz + axis_sign * a))
        rings.append(ring)
    n = len(profile)
    verts = [p for ring in rings for p in ring]
    faces = []
    for k in range(segments):
        k1 = (k + 1) % segments
        for i in range(n):
            i1 = (i + 1) % n
            faces.append((k * n + i, k * n + i1, k1 * n + i1, k1 * n + i))
    return verts, faces


# ---------------------------------------------------------------------------------------------------
# Body
# ---------------------------------------------------------------------------------------------------


def build_body(col):
    objs = []
    for s in (1, -1):
        # Front wing: flat top, rounded edges, round arch over the wheel, headlamp bowl in its face
        wing = rbox(s * WING_IN, s * HALF_W, BULKHEAD + 0.02, WING_FRONT, 0.60, WING_TOP, 0.035, 3)
        cut(wing, arch_cutter(AXLE_F, s * (WING_IN - 0.05), s * (HALF_W + 0.05)))
        cut(wing, cyl((s * LAMP_X, WING_FRONT - 0.07, LAMP_Z), (s * LAMP_X, WING_FRONT + 0.05, LAMP_Z), LAMP_R, 20))
        objs.append(wing)
        # Door: lower panel, then its window frame (front post, top rail, rear post)
        objs.append(rbox(s * (HALF_W - 0.04), s * HALF_W, DOOR_REAR + 0.01, BULKHEAD - 0.06, SILL + 0.03, CAPPING - 0.01, 0.012))
        objs.append(rbox(s * (HALF_W - 0.045), s * (HALF_W - 0.005), BULKHEAD - 0.11, BULKHEAD - 0.06, CAPPING - 0.01, SCREEN_TOP - 0.03, 0.012))
        objs.append(rbox(s * (HALF_W - 0.045), s * (HALF_W - 0.005), DOOR_REAR + 0.01, BULKHEAD - 0.06, SCREEN_TOP - 0.07, SCREEN_TOP - 0.03, 0.012))
        objs.append(rbox(s * (HALF_W - 0.045), s * (HALF_W - 0.005), DOOR_REAR + 0.01, DOOR_REAR + 0.05, CAPPING - 0.01, SCREEN_TOP - 0.03, 0.012))
        # Sill under the door
        objs.append(rbox(s * (HALF_W - 0.06), s * (HALF_W - 0.01), DOOR_REAR, BULKHEAD, SILL - 0.02, SILL + 0.03, 0.01))
        # Rear tub side with its round arch
        tub = rbox(s * (HALF_W - 0.035), s * HALF_W, REAR, DOOR_REAR, SILL - 0.02, CAPPING - 0.02, 0.012)
        cut(tub, arch_cutter(AXLE_R, s * (HALF_W - 0.1), s * (HALF_W + 0.05)))
        objs.append(tub)
        # Galvanised capping along the tub top (painted as galvanised by groundroamer_paint.py)
        objs.append(rbox(s * (HALF_W - 0.07), s * (HALF_W + 0.012), REAR, DOOR_REAR, CAPPING - 0.04, CAPPING, 0.015))
        # Inner wheel box in the tub
        wb = rbox(s * (WING_IN + 0.02), s * (HALF_W - 0.035), AXLE_R - ARCH_R - 0.02, AXLE_R + ARCH_R + 0.02, SILL, 0.90, 0.02)
        cut(wb, arch_cutter(AXLE_R, s * (WING_IN - 0.05), s * (HALF_W + 0.05), ARCH_R - 0.02))
        objs.append(wb)
        # Rear corner post and capping across the back
        objs.append(rbox(s * (HALF_W - 0.10), s * HALF_W, REAR, REAR + 0.05, SILL - 0.02, CAPPING, 0.012))
    objs.append(rbox(-(HALF_W - 0.10), HALF_W - 0.10, REAR, REAR + 0.06, CAPPING - 0.04, CAPPING, 0.015))
    # Tailgate
    objs.append(rbox(-(HALF_W - 0.10), HALF_W - 0.10, REAR - 0.005, REAR + 0.035, SILL + 0.02, CAPPING - 0.05, 0.012))
    # Bonnet with a rolled front edge, the grille panel set back between the wings
    objs.append(rbox(-WING_IN + 0.005, WING_IN - 0.005, BULKHEAD + 0.03, WING_FRONT - 0.03, WING_TOP - 0.06, BONNET, 0.035, 3))
    objs.append(rbox(-WING_IN, WING_IN, WING_FRONT - 0.07, WING_FRONT - 0.03, 0.56, WING_TOP - 0.03, 0.012))
    # Bulkhead, with the two vent flaps under the windscreen
    objs.append(rbox(-HALF_W, HALF_W, BULKHEAD - 0.08, BULKHEAD, SILL - 0.02, SCREEN_BOT, 0.02))
    for s in (1, -1):
        objs.append(rbox(s * 0.10, s * 0.62, BULKHEAD, BULKHEAD + 0.025, SCREEN_BOT - 0.12, SCREEN_BOT - 0.03, 0.01))
    # Floor, cut round the rear wheels
    floor = rbox(-(HALF_W - 0.04), HALF_W - 0.04, REAR + 0.04, BULKHEAD - 0.08, SILL - 0.03, SILL + 0.01, 0.0)
    for s in (1, -1):
        cut(floor, arch_cutter(AXLE_R, s * (WING_IN + 0.02), s * HALF_W, ARCH_R - 0.02))
    objs.append(floor)
    part("Body", objs, col, "Body")

    # Windscreen frame: posts, rails, centre post, raked back about its bottom
    f = []
    for x in (-0.80, 0.75):
        f.append(rbox(x, x + 0.05, BULKHEAD - 0.06, BULKHEAD - 0.01, SCREEN_BOT, SCREEN_TOP, 0.012))
    f.append(rbox(-0.80, 0.80, BULKHEAD - 0.06, BULKHEAD - 0.01, SCREEN_BOT, SCREEN_BOT + 0.05, 0.012))
    f.append(rbox(-0.80, 0.80, BULKHEAD - 0.06, BULKHEAD - 0.01, SCREEN_TOP - 0.05, SCREEN_TOP, 0.012))
    f.append(rbox(-0.02, 0.02, BULKHEAD - 0.055, BULKHEAD - 0.015, SCREEN_BOT, SCREEN_TOP, 0.008))
    part("Frame", f, col, "Body", transform=rake)


def build_tilt(col):
    """The canvas hood: lofted over the hoops, sagging between them; over the doors it sits on the door frames,
    over the back it comes down to the cappings."""
    hoops = [BULKHEAD - 0.06, 0.22, DOOR_REAR - 0.03, -0.95, REAR + 0.02]
    hw, r = HALF_W + 0.012, 0.16

    def top_at(y):
        for a, b in zip(hoops, hoops[1:]):
            lo, hi = min(a, b), max(a, b)
            if lo <= y <= hi:
                t = (y - lo) / (hi - lo)
                return ROOF - 0.03 * math.sin(math.pi * t)
        return ROOF

    def section(y, bottom, top):
        pts = [(hw, y, bottom)]
        for k in range(7):
            a = (math.pi / 2) * k / 6
            pts.append((hw - r + r * math.cos(a), y, top - r + r * math.sin(a)))
        for k in range(7):
            a = math.pi / 2 + (math.pi / 2) * k / 6
            pts.append((-hw + r + r * math.cos(a), y, top - r + r * math.sin(a)))
        pts.append((-hw, y, bottom))
        return pts

    stations = []
    y = BULKHEAD - 0.06
    while y > REAR + 0.02:
        stations.append(y)
        y -= 0.08
    stations.append(REAR + 0.02)
    rings = []
    for y in stations:
        cab = y > DOOR_REAR - 0.03
        bottom = SCREEN_TOP - 0.03 if cab else CAPPING - 0.02
        top = top_at(y)
        if y > BULKHEAD - 0.20:  # the front edge comes down onto the windscreen top
            t = (y - (BULKHEAD - 0.20)) / 0.14
            top = top - (top - (SCREEN_TOP + 0.02)) * t
        rings.append(section(y, bottom, max(top, bottom + 0.03)))
    # Open loft (the profile has no bottom), with end caps
    n = len(rings[0])
    verts = [p for ring in rings for p in ring]
    faces = []
    for i in range(len(rings) - 1):
        for k in range(n - 1):
            faces.append((i * n + k, i * n + k + 1, (i + 1) * n + k + 1, (i + 1) * n + k))
    faces.append(tuple(range(n)))
    last = (len(rings) - 1) * n
    faces.append(tuple(last + k for k in reversed(range(n))))
    obj = temp(verts, faces)
    sol = obj.modifiers.new("thick", "SOLIDIFY")
    sol.thickness = 0.008
    part("Tilt", [obj], col, "Canvas")


def build_glass(col):
    g = [rbox(-0.75, -0.02, BULKHEAD - 0.04, BULKHEAD - 0.035, SCREEN_BOT + 0.05, SCREEN_TOP - 0.05, 0.0),
         rbox(0.02, 0.75, BULKHEAD - 0.04, BULKHEAD - 0.035, SCREEN_BOT + 0.05, SCREEN_TOP - 0.05, 0.0)]
    part("Glass", g, col, "Glass", transform=rake)
    d = []
    for s in (1, -1):
        d.append(rbox(s * (HALF_W - 0.03), s * (HALF_W - 0.025), DOOR_REAR + 0.05, BULKHEAD - 0.11, CAPPING - 0.01, SCREEN_TOP - 0.07, 0.0))
    part("DoorGlass", d, col, "Glass")


# ---------------------------------------------------------------------------------------------------
# Chassis and running gear
# ---------------------------------------------------------------------------------------------------


def leaf_spring(x, y, length=1.2, sag=0.05):
    pts = []
    for k in range(9):
        t = k / 8
        pts.append((x, y - length / 2 + length * t, TYRE_R + 0.11 + sag * (2 * t - 1) ** 2))
    out = []
    for leaf in range(3):
        shorten = leaf * 0.12
        seg = [p for p in pts if abs(p[1] - y) <= length / 2 - shorten + 1e-6]
        seg = [(p[0], p[1], p[2] - 0.018 * leaf) for p in seg]
        for a, b in zip(seg, seg[1:]):
            out.append(rbox(x - 0.03, x + 0.03, min(a[1], b[1]), max(a[1], b[1]), min(a[2], b[2]) - 0.006, max(a[2], b[2]) + 0.006, 0.0))
    return out


def build_chassis(col):
    o = []
    for x in (-0.43, 0.43):  # box-section rails, with the dumb irons at the front
        o.append(rbox(x - 0.035, x + 0.035, REAR + 0.04, FRONT - 0.08, 0.44, 0.60, 0.01))
    o.append(rbox(-0.86, 0.86, FRONT - 0.10, FRONT, 0.40, 0.58, 0.012))  # bumper
    o.append(rbox(-0.80, 0.80, REAR - 0.01, REAR + 0.07, 0.40, 0.56, 0.01))  # rear crossmember
    o.append(rbox(-0.06, 0.06, REAR - 0.07, REAR - 0.01, 0.42, 0.50, 0.01))  # towing jaw
    for y, dx in ((AXLE_F, -0.14), (AXLE_R, 0.14)):  # axle casings and differentials
        o.append(cyl((-TRACK / 2 + 0.10, y, TYRE_R), (TRACK / 2 - 0.10, y, TYRE_R), 0.05, 10))
        o.append(cyl((dx, y - 0.14, TYRE_R), (dx, y + 0.10, TYRE_R), 0.15, 14, radius1=0.12))
        for s in (1, -1):
            o += leaf_spring(s * 0.43, y)
            o.append(cyl((s * 0.50, y + 0.12, TYRE_R + 0.02), (s * 0.47, y + 0.20, 0.72), 0.03, 8))  # damper
    o.append(cyl((-0.14, AXLE_F - 0.15, TYRE_R), (0.0, 0.20, 0.48), 0.035, 8))  # front propshaft
    o.append(cyl((0.0, -0.30, 0.48), (0.14, AXLE_R + 0.15, TYRE_R), 0.035, 8))  # rear propshaft
    o.append(rbox(-0.18, 0.18, -0.30, 0.45, 0.40, 0.62, 0.04))  # gearbox and transfer box
    o.append(cyl((-0.55, AXLE_F - 0.12, TYRE_R + 0.01), (0.55, AXLE_F - 0.12, TYRE_R + 0.01), 0.018, 6))  # track rod
    o.append(cyl((0.20, 0.30, 0.42), (0.60, -0.50, 0.40), 0.03, 8))  # exhaust
    o.append(cyl((0.60, -0.50, 0.40), (0.60, -1.05, 0.40), 0.08, 12))  # silencer
    o.append(cyl((0.60, -1.05, 0.40), (0.62, REAR + 0.05, 0.36), 0.03, 8))
    o.append(rbox(0.50, 0.78, -0.45, 0.05, 0.36, SILL - 0.03, 0.03))  # fuel tank under the driver's seat
    for s in (1, -1):  # mudflaps behind the rear wheels
        o.append(rbox(s * (TRACK / 2 - 0.13), s * (TRACK / 2 + 0.13), AXLE_R - 0.50, AXLE_R - 0.49, 0.16, SILL, 0.005))
    part("Chassis", o, col, "Details")


def build_lamps(col):
    o = []
    for s in (1, -1):
        x = s * LAMP_X
        o.append(cyl((x, WING_FRONT - 0.07, LAMP_Z), (x, WING_FRONT - 0.03, LAMP_Z), LAMP_R - 0.005, 20))  # bowl
        o.append(cyl((x, WING_FRONT - 0.035, LAMP_Z), (x, WING_FRONT + 0.005, LAMP_Z), LAMP_R + 0.01, 20, radius1=LAMP_R - 0.01))  # chrome ring
        o.append(cyl((x, WING_FRONT - 0.04, LAMP_Z), (x, WING_FRONT - 0.01, LAMP_Z), LAMP_R - 0.015, 20, radius1=LAMP_R - 0.035))  # lens
        o.append(cyl((s * 0.775, WING_FRONT, 0.98), (s * 0.775, WING_FRONT + 0.03, 0.98), 0.032, 12))  # side lamp
        o.append(cyl((s * 0.775, WING_FRONT, 0.70), (s * 0.775, WING_FRONT + 0.03, 0.70), 0.034, 12))  # indicator
        o.append(rbox(s * 0.70, s * 0.79, REAR - 0.03, REAR, 0.78, 0.98, 0.01))  # rear lamp cluster
        # Door mirror on its arm from the windscreen post, door handle and hinges
        o.append(cyl((s * 0.80, BULKHEAD - 0.03, 1.20), (s * 0.95, BULKHEAD - 0.02, 1.40), 0.012, 6))
        o.append(rbox(s * 0.90, s * 1.02, BULKHEAD - 0.05, BULKHEAD - 0.01, 1.36, 1.50, 0.015))
        o.append(rbox(s * HALF_W, s * (HALF_W + 0.015), DOOR_REAR + 0.10, DOOR_REAR + 0.18, 0.95, 0.97, 0.004))
        for z in (0.68, 0.98):
            o.append(rbox(s * HALF_W, s * (HALF_W + 0.02), BULKHEAD - 0.10, BULKHEAD - 0.05, z, z + 0.06, 0.005))
        # Wiper on the bottom of the screen
        o.append(rbox(s * 0.10, s * 0.55, BULKHEAD - 0.07, BULKHEAD - 0.065, SCREEN_BOT + 0.07, SCREEN_BOT + 0.085, 0.0))
    # The grille: a frame with vertical slats, set in the grille panel
    o.append(rbox(-0.31, 0.31, WING_FRONT - 0.04, WING_FRONT - 0.02, 0.62, 0.98, 0.012))
    for k in range(15):
        x = -0.28 + 0.56 * k / 14
        o.append(rbox(x - 0.008, x + 0.008, WING_FRONT - 0.02, WING_FRONT - 0.005, 0.64, 0.96, 0.0))
    part("Lamps", o, col, "Details", kind="Lights")


def build_cab(col):
    o = [rbox(-0.80, 0.80, BULKHEAD - 0.26, BULKHEAD - 0.08, 0.98, 1.10, 0.03, 2)]  # padded dash rail
    o.append(rbox(-0.16, 0.16, BULKHEAD - 0.20, BULKHEAD - 0.08, 1.00, 1.15, 0.025, 2))  # centre instrument binnacle
    for x in (DRIVER_X, -DRIVER_X):  # seat cushions and backs
        o.append(rbox(x - 0.23, x + 0.23, -0.32, 0.14, 0.60, 0.74, 0.04, 2))
        o.append(rbox(x - 0.23, x + 0.23, -0.40, -0.28, 0.74, 1.24, 0.04, 2))
    o.append(rbox(-0.12, 0.12, -0.32, 0.14, 0.60, 0.72, 0.03, 2))  # middle seat
    # Steering column and the large two-spoke wheel, tilted back
    col_top = (DRIVER_X, 0.24, 1.17)
    o.append(cyl((DRIVER_X, BULKHEAD - 0.12, 1.00), col_top, 0.028, 8))
    tilt = math.radians(50)
    rim = []
    for k in range(25):
        a = 2 * math.pi * k / 24
        rr = 0.215 * math.sin(a)
        rim.append((col_top[0] + 0.215 * math.cos(a), col_top[1] - rr * math.cos(tilt) - 0.02, col_top[2] + rr * math.sin(tilt)))
    for a, b in zip(rim, rim[1:]):
        o.append(cyl(a, b, 0.016, 6))
    for k in (0, 12):
        o.append(cyl((col_top[0], col_top[1] - 0.02, col_top[2]), rim[k], 0.012, 6))
    # Gear lever, transfer levers, handbrake
    for x, h in ((0.02, 0.48), (-0.10, 0.40), (-0.16, 0.36)):
        base = (x, 0.25, 0.60)
        top = (x, 0.20, 0.60 + h)
        o.append(cyl(base, top, 0.012, 6))
        o.append(cyl((top[0], top[1], top[2] - 0.02), (top[0], top[1], top[2] + 0.02), 0.03, 8))
    part("Cab", o, col, "Details")


# ---------------------------------------------------------------------------------------------------
# Wheels: a revolved 7.50-16 tyre section and a dished steel rim
# ---------------------------------------------------------------------------------------------------

TYRE_SECTION = [(0.215, -0.085), (0.30, -0.104), (0.365, -0.100), (0.392, -0.084), (0.402, -0.04), (0.404, 0.0),
                (0.402, 0.04), (0.392, 0.084), (0.365, 0.100), (0.30, 0.104), (0.215, 0.085)]
RIM_SECTION = [(0.216, -0.080), (0.228, -0.088), (0.228, -0.060), (0.205, -0.02), (0.150, 0.015), (0.075, 0.02),
               (0.065, 0.065), (0.0, 0.065), (0.0, -0.03), (0.200, -0.03), (0.216, 0.080), (0.228, 0.088), (0.205, 0.07)]


def wheel_objects(centre, axis="x", sign=1):
    tv, tf = revolve(TYRE_SECTION, centre, sign, 28, axis)
    rv, rf = revolve(RIM_SECTION, centre, sign, 20, axis)
    objs = [temp(tv, tf), temp(rv, rf)]
    cx, cy, cz = centre
    for k in range(5):  # wheel nuts
        a = 2 * math.pi * k / 5
        if axis == "x":
            p = (cx + sign * 0.02, cy + 0.10 * math.cos(a), cz + 0.10 * math.sin(a))
            objs.append(cyl(p, (p[0] + sign * 0.025, p[1], p[2]), 0.014, 6))
        else:
            p = (cx + 0.10 * math.cos(a), cy + 0.10 * math.sin(a), cz + sign * 0.02)
            objs.append(cyl(p, (p[0], p[1], p[2] + sign * 0.025), 0.014, 6))
    return objs


def build_wheels(col):
    for name, (x, y) in WHEELS.items():
        centre = (x, y, TYRE_R)
        part(f"Wheel{name}", wheel_objects(centre, "x", 1 if x > 0 else -1), col, "Details", kind="Wheel", origin=centre,
             extra={"steers": name.startswith("F"), "radius": TYRE_R})
    spare = wheel_objects(SPARE, "z", 1)
    spare.append(rbox(-0.03, 0.03, SPARE[1] - 0.30, SPARE[1] + 0.30, BONNET, BONNET + 0.02, 0.005))  # clamp bar
    part("SpareWheel", spare, col, "Details")


def build_decals(col):
    """The badge on the grille panel and the two number plates, with a hand-laid UV strip:
    u 0..0.4 front plate, 0.4..0.8 rear plate, 0.8..1 badge (see groundroamer_decals.py)."""
    pieces = [
        ((-0.26, 0.26, FRONT + 0.004, 0.44, 0.55), (0.0, 0.4)),
        ((-0.26, 0.26, REAR - 0.009, 0.62, 0.73), (0.4, 0.8)),
        ((-0.12, 0.12, WING_FRONT - 0.018, 0.985, 1.02), (0.8, 1.0)),
    ]
    verts, faces = [], []
    for (x0, x1, y, z0, z1), _ in pieces:
        base = len(verts)
        verts += [(x0, y, z0), (x1, y, z0), (x1, y, z1), (x0, y, z1)]
        faces.append((base, base + 1, base + 2, base + 3))
    kit.make_object("Decals", verts, faces, col, "Decals")
    me = bpy.data.objects["Decals"].data
    layer = me.uv_layers.new(name="UVMap")
    for poly in me.polygons:
        for li in poly.loop_indices:
            p = me.vertices[me.loops[li].vertex_index].co
            (x0, x1, y, z0, z1), (u0, u1) = min(pieces, key=lambda pc: abs(p.y - pc[0][2]))
            t = (p.x - x0) / (x1 - x0)
            if y > 0:  # seen from the front, +x (the vehicle's right) is on the viewer's left
                t = 1 - t
            layer.data[li].uv = (u0 + (u1 - u0) * t, (p.z - z0) / (z1 - z0))


def unwrap_except_decals():
    by_set = {}
    for obj in bpy.data.objects:
        if obj.type == "MESH" and obj.name != "Decals":
            by_set.setdefault(obj["afterburner_set"], []).append(obj)
    for objs in by_set.values():
        bpy.ops.object.select_all(action="DESELECT")
        for obj in objs:
            obj.select_set(True)
        bpy.context.view_layer.objects.active = objs[0]
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.uv.smart_project(angle_limit=math.radians(55), island_margin=0.01)
        bpy.ops.uv.pack_islands(margin=0.004)
        bpy.ops.object.mode_set(mode="OBJECT")
    bpy.ops.object.select_all(action="DESELECT")


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", default=os.path.join(os.path.dirname(__file__), "out"))
    parser.add_argument("--manifest-luau", default=None)
    args = parser.parse_args(argv)
    os.makedirs(args.out, exist_ok=True)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    a = kit.AIRFRAME
    root = kit.collection(a)
    cols = {name: kit.collection(f"{a}_{name}", root) for name in ("Body", "Details", "Glass", "Attachments")}

    build_body(cols["Body"])
    build_tilt(cols["Body"])
    build_glass(cols["Glass"])
    build_chassis(cols["Details"])
    build_lamps(cols["Details"])
    build_cab(cols["Details"])
    build_wheels(cols["Details"])
    clear_scratch()
    build_decals(cols["Details"])
    kit.add_attachment_empties(cols["Attachments"])

    kit.smooth_all()
    unwrap_except_decals()
    counts = kit.triangle_counts()
    manifest = kit.write_manifest(os.path.join(args.out, f"{a}_manifest.json"), args.manifest_luau, counts)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(args.out, f"{a}.blend"))
    kit.export(args.out, f"{a}.fbx")

    print("=" * 60)
    print(f"{a}: {len(kit.PARTS)} parts, {manifest['triangles']} triangles")
    for name, tris in sorted(counts.items(), key=lambda kv: -kv[1]):
        print(f"  {name:14s} {tris:6d}")
    print("=" * 60)


if __name__ == "__main__":
    main()
