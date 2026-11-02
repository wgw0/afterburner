"""
Afterburner: B-1B Lancer base mesh generator (Blender 4.x / 5.x). AI only: the B-1B is the strike bomber of
Strike Escort and the PvE modes (players escort it or shoot it down; nobody flies it), so it has no cockpit
interior and no landing gear.

Builds a mid-poly, modular B-1B at real-world size in the same form as the F-5E (f5e_generate.py, whose
helpers this uses): separate objects per part, moving parts with their origin on the hinge line, texture
sets, a manifest for the Studio assembler, and an FBX.

  * the long blended fuselage with the pointed radome, the raised cockpit with its windscreen panes
    (`Canopy` glass over a dark-painted patch, `CanopyFrame` posts) and the ride-control vanes on the nose
  * the fixed blended wing-body glove (`Glove`), running on aft as the overwing fairing
  * swing wings set at a 40-degree sweep (origin on the pivot, as the F-14A), with full-span slats
    (`LEFlap`), spoilers (`Spoiler`, on the aileron controls: the B-1 rolls with spoilers and tailerons)
    and flaps
  * four F101 engines in two underwing nacelle pairs (`Nacelles`, dark `IntakeDucts`); each side's two
    nozzles and afterburner cones are one part (`NozzleL`/`NozzleR`, `AfterburnerL`/`AfterburnerR`)
  * the tall single fin with its dorsal fillet, the rudder, and all-moving tailerons on the elevon controls
  * two nose pitot probes (`Pitot`: the assembler lines the model up on it)

Run headless:
  blender -b --python tools/blender/b1b_generate.py -- --out <dir> --manifest-luau tools/Manifests/B1B.luau

No reference drawing: the shapes are designed from the published figures (length 44.5 m; span 41.8 m at
15 degrees, 24.1 m at 67.5 degrees; height 10.4 m) and the B-1B's well-known proportions. Like the
Tempest, the tables are in centimetres from the nose tip (xd), so kit.Y(xd) works as for the measured
jets; heights and half widths are metres.
"""

import argparse
import math
import os
import sys

from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import f5e_generate as kit  # noqa: E402  (shared helpers; its module settings are switched below)

kit.AIRFRAME = "B1B"
kit.REF_PX_PER_M = 100.0  # stations are centimetres from the nose tip
kit.REF_PITOT_XD = 0.0
kit.REF_Z0_ROW = 0.0
kit.CG_FROM_PITOT = 20.5  # just behind the wing pivots
kit.LENGTH = 44.5
kit.SPINE_UPPER_ONLY = True
Y = kit.Y

# Fuselage: (xd, half width, bottom z, shoulder z, top z, spine half width, exponent). z = 0 is roughly the
# fuselage's axis. The spine is the raised cockpit roof and the flat top running back to the fin.
kit.FUSELAGE = [
    (0, 0.02, -0.34, -0.30, -0.30, 0.0, 2.0),  # radome tip
    (60, 0.22, -0.56, -0.14, -0.14, 0.0, 2.0),
    (180, 0.52, -0.92, 0.10, 0.10, 0.0, 2.1),
    (330, 0.82, -1.24, 0.36, 0.40, 0.0, 2.2),
    (470, 1.02, -1.50, 0.60, 0.72, 0.72, 2.3),
    (580, 1.17, -1.66, 0.74, 1.08, 0.90, 2.4),  # windscreen base
    (690, 1.28, -1.78, 0.84, 1.66, 0.98, 2.5),  # windscreen top
    (800, 1.36, -1.86, 0.90, 1.92, 1.04, 2.6),  # cockpit roof
    (980, 1.46, -1.94, 0.94, 2.00, 1.10, 2.7),
    (1250, 1.58, -2.00, 0.96, 2.02, 1.16, 2.8),
    (1650, 1.70, -2.05, 0.96, 2.02, 1.22, 3.0),
    (2050, 1.74, -2.06, 0.94, 2.02, 1.22, 3.0),
    (2600, 1.68, -2.00, 0.94, 2.00, 1.16, 3.0),
    (3150, 1.48, -1.72, 0.94, 1.96, 1.00, 2.8),
    (3650, 1.16, -1.14, 0.98, 1.88, 0.82, 2.6),
    (4050, 0.82, -0.46, 1.02, 1.74, 0.58, 2.4),
    (4350, 0.42, 0.20, 1.06, 1.42, 0.0, 2.2),
    (4450, 0.14, 0.56, 1.02, 1.02, 0.0, 2.0),  # tail cone
]
kit.FUSELAGE_RINGS = 68
kit.FUSELAGE_SEGMENTS = 40

# Cockpit windows: the glass covers the front of the cockpit hump between these stations, within WINDOW_PHI of
# the top centre. Posts split it into the four windscreen panes.
WINDOW_XD = (585, 735)
WINDOW_PHI = math.radians(64)
WINDOW_POSTS = [math.radians(a) for a in (-32, 0, 32)]

# Glove: (xd, outer half width). Its inner edge is just inside the fuselage side. Aft of the pivot it carries
# on as the overwing fairing, outboard of the swing wing's root edge as set at 40 degrees, then in to the
# fuselage over the nacelles' ends.
GLOVE = [(1000, 1.50), (1150, 1.75), (1300, 2.10), (1450, 2.75), (1600, 3.55), (1750, 4.45), (1880, 5.30),
         (1980, 5.95), (2060, 6.25), (2140, 6.30), (2220, 6.05), (2360, 5.45), (2520, 4.80), (2700, 4.55),
         (2950, 4.35), (3150, 3.95), (3350, 3.00), (3500, 1.80)]
GLOVE_Z = 0.05  # the edge, at the wing's mid plane
GLOVE_EDGE = 0.06  # thickness at the edge
GLOVE_LIFT = 0.30  # aft of the pivot the edge rides this far up, as a fairing over the wing's root


def glove_edge_z(xd):
    return GLOVE_Z + GLOVE_LIFT * min(max((xd - 2140) / 260, 0.0), 1.0)


def glove_depth(xd):
    """Half depths (top, bottom) of the glove where it meets the fuselage: it fades in from the forward strake
    and out over the nacelles' ends."""
    fwd = min(max((xd - 1000) / 800, 0.0), 1.0)
    aft = min(max((3500 - xd) / 1000, 0.0), 1.0)
    k = (fwd ** 0.8) * (0.35 + 0.65 * aft)
    return 0.05 + 0.80 * k, 0.05 + 0.85 * k


# Swing wing: drawn spread (15-degree leading edge) and turned aft about the pivot to the model's 40 degrees.
# The pivot is 0.6 m behind the root's leading edge (as on the F-14A); its half width puts the spread span at
# the published 41.8 m and the fully swept span at 24.4 m (published 24.1 m).
WING_Z = GLOVE_Z
PIVOT_XD = 2050
PIVOT = (5.80, Y(PIVOT_XD))
SPREAD_SWEEP, MODEL_SWEEP, FULL_SWEEP = 15.0, 40.0, 67.5
TURN = math.radians(MODEL_SWEEP - SPREAD_SWEEP)
WING_ROOT_X, WING_TIP_X = 5.40, 20.90
WING_ROOT_LE = PIVOT[1] + 0.60
WING_ROOT_CHORD, WING_TIP_CHORD = 6.00, 1.90
WING_TIP_LE = WING_ROOT_LE - (WING_TIP_X - WING_ROOT_X) * math.tan(math.radians(SPREAD_SWEEP))
WING_THICKNESS = 0.07
SLAT_CHORD, SLAT_SPAN = 0.12, (0.04, 1.0)
SPOILER_HINGE, FLAP_HINGE = 0.62, 0.75
SPOILER_SPAN = (0.12, 0.62)
FLAP_SPAN = (0.04, 0.92)


def turned(p, turn=TURN):
    """A point of the spread wing turned aft about the pivot (right wing; mirror for the left)."""
    x, y, z = p
    px, py = PIVOT
    c, s = math.cos(turn), math.sin(turn)
    return (px + (x - px) * c + (y - py) * s, py - (x - px) * s + (y - py) * c, z)


# Engines: two nacelle pairs under the glove. Nacelle sections (xd, half width, centre z, half height) round
# x = NACELLE_X; the intakes face forward at station 2150, the nozzles end at 3380.
NACELLE_X = 3.20
NACELLE = [(2150, 1.24, -1.18, 1.08), (2350, 1.32, -1.16, 1.18), (2900, 1.32, -1.14, 1.16), (3200, 1.30, -1.22, 0.86),
           (3310, 1.28, -1.25, 0.68)]
ENGINE_X = (2.55, 3.85)  # inner and outer engine centrelines
NOZZLE_Z, NOZZLE_R = -1.25, 0.56
NOZZLE_Y0, NOZZLE_Y1 = Y(3300), Y(3380)

# Tailerons (all-moving) on the fin base, above the fuselage
STAB_ROOT_X, STAB_TIP_X = 0.30, 6.85
STAB_ROOT_LE, STAB_ROOT_TE = Y(3780), Y(4400)
STAB_TIP_LE, STAB_TIP_TE = Y(4270), Y(4450)
STAB_Z = 2.25
STAB_THICKNESS = 0.05

# Fin and rudder; the fin top sets the published 10.4 m height over GROUND_Z
FIN_ROOT_Z, FIN_TIP_Z = 1.55, 7.20
FIN_ROOT_LE, FIN_ROOT_TE = Y(3350), Y(4440)
FIN_TIP_LE, FIN_TIP_TE = Y(3960), Y(4330)
FIN_THICKNESS = 0.055
RUDDER_HINGE = 0.72
RUDDER_SPAN = (2.70, 6.90)
GROUND_Z = FIN_TIP_Z - 10.4

# Ride-control vanes on the nose (static here), 30 degrees of anhedral
VANE = {"root_x": 0.80, "span": 0.95, "dihedral": math.radians(-30), "root": (410, 490), "tip": (455, 500), "z": -0.62}

TIP = turned((WING_TIP_X, WING_TIP_LE - WING_TIP_CHORD / 2, WING_Z))

kit.HULL = {"size": [3.6, 4.1, 43.0], "at": [0, 0, 1.75]}
kit.HITBOXES = {
    "Cockpit": {"size": [2.9, 3.2, 9.0], "at": [0, 0.4, -14.5]},
    "Fuselage": {"size": [3.6, 4.2, 22.0], "at": [0, 0.0, -0.5]},
    "Engine": {"size": [9.4, 2.4, 13.0], "at": [0, -1.25, 7.0]},
    "WingL": {"size": [13.0, 1.0, 10.0], "at": [-12.0, round(WING_Z, 2), 3.5]},
    "WingR": {"size": [13.0, 1.0, 10.0], "at": [12.0, round(WING_Z, 2), 3.5]},
    "Tail": {"size": [14.0, 6.2, 11.5], "at": [0, 4.0, 18.6]},
}
EYE = (-0.55, Y(700), 1.40)  # the pilot's (left) seat
kit.ATTACHMENTS = {
    "CockpitEye": EYE,
    "GunMuzzle": (0, Y(10), -0.31),  # no gun: the contract wants a muzzle ahead of the centre, so the nose tip
    "Nozzle1": (-ENGINE_X[0], NOZZLE_Y1, NOZZLE_Z),
    "Nozzle2": (ENGINE_X[0], NOZZLE_Y1, NOZZLE_Z),
    "Nozzle3": (-ENGINE_X[1], NOZZLE_Y1, NOZZLE_Z),
    "Nozzle4": (ENGINE_X[1], NOZZLE_Y1, NOZZLE_Z),
    "WingtipL": (-TIP[0], TIP[1], TIP[2]),
    "WingtipR": (TIP[0], TIP[1], TIP[2]),
    "FlareDispenser": (0, Y(2950), 1.98),  # on the spine behind the wings, firing up
    "ChaffDispenser": (0, Y(2850), 1.99),
    "ChaseCam": (0, -62.0, 11.0),
    "Hardpoint1": (0, Y(1350), -2.10),  # the three internal weapons bays
    "Hardpoint2": (0, Y(1750), -2.15),
    "Hardpoint3": (0, Y(2900), -1.90),
}


# ---------------------------------------------------------------------------------------------------
# Builders
# ---------------------------------------------------------------------------------------------------


def surface_point(xd, phi, off=0.0):
    """The fuselage surface at station xd, phi radians round from the top centre (positive to +x), pushed out
    `off` metres along the section's radius."""
    hw, zb, zs, zt, wsp, e = kit.fuselage_params(xd)
    cz = (zs + zb) / 2
    hb = max((zs - zb) / 2, 0.004)
    dx, dz = math.sin(phi), math.cos(phi)
    r = kit._superellipse_hit(cz, dx, dz, hw, cz, hb, e)
    if wsp > 0.02 and zt - zs > 0.01 and dz > 0:
        rs = kit._superellipse_hit(cz, dx, dz, wsp, cz, zt - cz, 2.6)
        r = (r**10 + rs**10) ** 0.1
    r += off
    return (r * dx, Y(xd), cz + r * dz)


def build_windows(col_glass, col_body):
    """The windscreen panes as a thin glass shell over the cockpit hump, with frame posts proud of it."""
    x0, x1 = WINDOW_XD
    rows, cols = 6, 16
    rings = []
    for i in range(rows):
        xd = x0 + (x1 - x0) * i / (rows - 1)
        phis = [-WINDOW_PHI + 2 * WINDOW_PHI * k / cols for k in range(cols + 1)]
        outer = [surface_point(xd, p, 0.035) for p in phis]
        inner = [surface_point(xd, p, 0.012) for p in reversed(phis)]
        rings.append(outer + inner)
    v, f = kit.lofted(rings, True, True)
    kit.make_object("Canopy", v, f, col_glass, "Glass")

    bars = []

    def bar(path, w=0.05):
        """A frame bar along (xd, phi) points: a small box section riding on the surface."""
        rings = []
        for k, (xd, phi) in enumerate(path):
            a = path[max(k - 1, 0)]
            b = path[min(k + 1, len(path) - 1)]
            p0, p1 = Vector(surface_point(a[0], a[1], 0.03)), Vector(surface_point(b[0], b[1], 0.03))
            c = Vector(surface_point(xd, phi, 0.03))
            n = (Vector(surface_point(xd, phi, 0.5)) - c).normalized()
            t = (p1 - p0).normalized()
            s = t.cross(n).normalized()
            rings.append([tuple(c + s * w / 2 + n * 0.0), tuple(c + s * w / 2 + n * 0.035),
                          tuple(c - s * w / 2 + n * 0.035), tuple(c - s * w / 2 + n * 0.0)])
        bars.append(kit.lofted(rings, True, True))

    steps = 5
    for phi in WINDOW_POSTS:
        bar([(x0 + (x1 - x0) * i / steps, phi) for i in range(steps + 1)])
    for xd in (x0, x1):
        bar([(xd, -WINDOW_PHI + 2 * WINDOW_PHI * k / 10) for k in range(11)], 0.07)
    for phi in (-WINDOW_PHI, WINDOW_PHI):
        bar([(x0 + (x1 - x0) * i / steps, phi) for i in range(steps + 1)], 0.07)
    v, f = kit.merge(*bars)
    kit.make_object("CanopyFrame", v, f, col_body, "Body")


def glove_ring(xd, x_out):
    """The glove's section at a station, round from its inner top: deep where it meets the fuselage, thin
    at its edge."""
    x_in = max(kit.fuselage_params(xd)[0] - 0.20, 0.3)
    x_out = max(x_out, x_in + 0.05)
    t_in, b_in = glove_depth(xd)
    ze = glove_edge_z(xd)
    zt, zb = GLOVE_Z + t_in, GLOVE_Z - b_in  # where it meets the fuselage
    ts = [0.0, 0.2, 0.45, 0.7, 0.88, 1.0]
    top, bottom = [], []
    for t in ts:
        x = x_in + (x_out - x_in) * t
        k = (1 - t) ** 1.6
        top.append((x, Y(xd), ze + GLOVE_EDGE / 2 + (zt - ze - GLOVE_EDGE / 2) * k))
        bottom.append((x, Y(xd), ze - GLOVE_EDGE / 2 - (ze - GLOVE_EDGE / 2 - zb) * k))
    return top + list(reversed(bottom))


def build_glove(col):
    parts = []
    stations = []
    for (xa, wa), (xb, wb) in zip(GLOVE, GLOVE[1:]):
        for k in range(1):
            t = 0.0
            stations.append((xa + (xb - xa) * t, wa + (wb - wa) * t))
    stations.append(GLOVE[-1])
    for side in (1, -1):
        rings = []
        for xd, w in stations:
            ring = glove_ring(xd, w)
            rings.append(ring if side > 0 else [(-x, y, z) for x, y, z in ring])
        v, f = kit.lofted(rings, True, True)
        parts.append((v, f if side > 0 else kit.flip_faces(f)))
    v, f = kit.merge(*parts)
    kit.make_object("Glove", v, f, col, "Body")


def nacelle_ring(side, xd, hw, zc, hh, scale=1.0, segments=28, centre=NACELLE_X):
    pts = []
    for k in range(segments):
        ang = 2 * math.pi * k / segments
        c, s = math.cos(ang), math.sin(ang)
        x = side * centre + hw * scale * math.copysign(abs(c) ** (2 / 4.0), c)
        z = zc + hh * scale * math.copysign(abs(s) ** (2 / 4.0), s)
        pts.append((x, Y(xd), z))
    return pts


def build_nacelles(col):
    parts, ducts = [], []
    for side in (1, -1):
        xd0, hw, zc, hh = NACELLE[0]
        rings = [nacelle_ring(side, xd0 + 25, hw, zc, hh, 0.86), nacelle_ring(side, xd0 + 1, hw, zc, hh, 0.93)]
        rings += [nacelle_ring(side, xd, w, z, h) for xd, w, z, h in NACELLE]
        parts.append(kit.lofted(rings, True, True))
        # Two intake mouths per pair, either side of the splitter
        for ex in ENGINE_X:
            mw, mh = 0.56, hh * 0.80
            mouth = [nacelle_ring(side, xd0 + d, mw, zc, mh, 1.0, 16, ex) for d in (24, 23)]
            ducts.append(kit.lofted(mouth, True, True))
    v, f = kit.merge(*parts)
    kit.make_object("Nacelles", v, f, col, "Body")
    v, f = kit.merge(*ducts)
    kit.make_object("IntakeDucts", v, f, col, "Body")


def build_wings(col):
    up = (0, 0, 1)
    rl = (WING_ROOT_X, WING_ROOT_LE, WING_Z)
    rt = (WING_ROOT_X, WING_ROOT_LE - WING_ROOT_CHORD, WING_Z)
    tl = (WING_TIP_X, WING_TIP_LE, WING_Z)
    tt = (WING_TIP_X, WING_TIP_LE - WING_TIP_CHORD, WING_Z)
    pivot = (PIVOT[0], PIVOT[1], WING_Z)

    def tv(v):
        return [turned(p) for p in v]

    for side, name in ((1, "R"), (-1, "L")):
        def m(v):
            return v if side > 0 else kit.mirror_x(v)

        def mf(f):
            return f if side > 0 else kit.flip_faces(f)

        geo = (rl, rt, tl, tt, up, WING_THICKNESS)
        box = [
            kit.panel(*geo, SLAT_CHORD, SPOILER_HINGE, 0, 1, 10, 10),
            kit.panel(*geo, 0.0, SLAT_CHORD, 0, SLAT_SPAN[0], 1, 4),
            # between the box and the flaps: fixed where there are no spoilers
            kit.panel(*geo, SPOILER_HINGE, FLAP_HINGE, 0, SPOILER_SPAN[0], 1, 3),
            kit.panel(*geo, SPOILER_HINGE, FLAP_HINGE, SPOILER_SPAN[1], 1, 4, 3),
            kit.panel(*geo, FLAP_HINGE, 1.0, 0, FLAP_SPAN[0], 1, 4),
            kit.panel(*geo, FLAP_HINGE, 1.0, FLAP_SPAN[1], 1, 1, 4),
        ]
        v, f = kit.merge(*box)
        kit.make_object(f"Wing{name}", m(tv(v)), mf(f), col, "Wings", origin=tuple(m([turned(pivot)])[0]))
        for part, (f0, f1), (s0, s1), lims, control, hinge_f in (
            ("LEFlap", (0.0, SLAT_CHORD), SLAT_SPAN, (0, 20), "LEFlap", SLAT_CHORD),
            ("Spoiler", (SPOILER_HINGE, FLAP_HINGE), SPOILER_SPAN, (-45, 0), "Aileron" + name, SPOILER_HINGE),
            ("Flap", (FLAP_HINGE, 1.0), FLAP_SPAN, (0, 40), "Flap", FLAP_HINGE),
        ):
            v, f = kit.panel(*geo, f0, f1, s0, s1, 8, 5)
            a, b = kit.hinge_line(rl, rt, tl, tt, hinge_f, s0, s1)
            a, b = Vector(turned(tuple(a))), Vector(turned(tuple(b)))
            kit.make_object(f"{part}{name}", m(tv(v)), mf(f), col, "Wings", "ControlSurface",
                            origin=tuple(m([tuple(a.lerp(b, 0.5))])[0]),
                            hinge={"axis": tuple(m([tuple(b - a)])[0]), "min": lims[0], "max": lims[1], "control": control})


def build_tail(col_wings, col_body):
    up = (0, 0, 1)
    root_le, root_te = (STAB_ROOT_X, STAB_ROOT_LE, STAB_Z), (STAB_ROOT_X, STAB_ROOT_TE, STAB_Z)
    tip_le, tip_te = (STAB_TIP_X, STAB_TIP_LE, STAB_Z), (STAB_TIP_X, STAB_TIP_TE, STAB_Z)
    pivot_y = STAB_ROOT_LE - (STAB_ROOT_LE - STAB_ROOT_TE) * 0.40
    for side, name in ((1, "R"), (-1, "L")):
        v, f = kit.panel(root_le, root_te, tip_le, tip_te, up, STAB_THICKNESS, 0.0, 1.0, 0, 1, 8, 10)
        if side < 0:
            v, f = kit.mirror_x(v), kit.flip_faces(f)
        kit.make_object(f"Stabilator{name}", v, f, col_wings, "Wings", "ControlSurface",
                        origin=(side * STAB_ROOT_X, pivot_y, STAB_Z),
                        hinge={"axis": (1, 0, 0), "min": -25, "max": 15, "control": "Elevon" + name})

    side_n = (1, 0, 0)
    g = ((0, FIN_ROOT_LE, FIN_ROOT_Z), (0, FIN_ROOT_TE, FIN_ROOT_Z), (0, FIN_TIP_LE, FIN_TIP_Z), (0, FIN_TIP_TE, FIN_TIP_Z),
         side_n, FIN_THICKNESS)
    h = FIN_TIP_Z - FIN_ROOT_Z

    def frac(z):
        return (z - FIN_ROOT_Z) / h

    # Dorsal fillet: from the spine behind the wings, curving up into the fin's leading edge
    fz = 2.90
    le_y = FIN_ROOT_LE + (FIN_TIP_LE - FIN_ROOT_LE) * frac(fz)
    outline = [(Y(2800), 1.85)]
    for t in (0.35, 0.65):
        outline.append((kit.lerp(Y(2800), le_y, t), kit.lerp(1.92, fz, t**2.2)))
    outline += [(le_y, fz), (FIN_ROOT_LE - 1.0, FIN_ROOT_Z)]
    half = [0.10, 0.10, 0.09, 0.07, 0.12]
    n = len(outline)
    fv = [(-hh, y, z) for (y, z), hh in zip(outline, half)] + [(hh, y, z) for (y, z), hh in zip(outline, half)]
    ff = [tuple(range(n)), tuple(reversed(range(n, 2 * n)))]
    ff += [(i, n + i, n + (i + 1) % n, (i + 1) % n) for i in range(n)]

    fin = [
        kit.panel(*g, 0.0, RUDDER_HINGE, 0, 1, 10, 10),
        kit.panel(*g, RUDDER_HINGE, 1.0, 0, frac(RUDDER_SPAN[0]), 2, 4),
        kit.panel(*g, RUDDER_HINGE, 1.0, frac(RUDDER_SPAN[1]), 1, 1, 4),
        (fv, ff),
    ]
    v, f = kit.merge(*fin)
    kit.make_object("Fin", v, f, col_body, "Body")
    v, f = kit.panel(*g, RUDDER_HINGE, 1.0, frac(RUDDER_SPAN[0]), frac(RUDDER_SPAN[1]), 8, 5)
    a, b = kit.hinge_line(*g[:4], RUDDER_HINGE, frac(RUDDER_SPAN[0]), frac(RUDDER_SPAN[1]))
    kit.make_object("Rudder", v, f, col_body, "Body", "ControlSurface", origin=tuple(a.lerp(b, 0.5)),
                    hinge={"axis": tuple(b - a), "min": -25, "max": 25, "control": "Rudder"})


def build_vanes(col):
    parts = []
    c, s = math.cos(VANE["dihedral"]), math.sin(VANE["dihedral"])
    x0, z0 = VANE["root_x"], VANE["z"]
    x1, z1 = x0 + VANE["span"] * c, z0 + VANE["span"] * s
    normal = (-s, 0, c)
    for side in (1, -1):
        v, f = kit.panel((x0, Y(VANE["root"][0]), z0), (x0, Y(VANE["root"][1]), z0), (x1, Y(VANE["tip"][0]), z1),
                         (x1, Y(VANE["tip"][1]), z1), normal, 0.06, 0.0, 1.0, 0, 1, 2, 6)
        parts.append((v, f) if side > 0 else (kit.mirror_x(v), kit.flip_faces(f)))
    v, f = kit.merge(*parts)
    kit.make_object("Vanes", v, f, col, "Body")


def build_engines(col):
    for side, name in ((1, "R"), (-1, "L")):
        nozzles, cones = [], []
        for ex in ENGINE_X:
            x = side * ex
            p0, p1 = (x, NOZZLE_Y0, NOZZLE_Z), (x, NOZZLE_Y1, NOZZLE_Z)
            n = 20
            nv, nf = kit.cylinder(p0, p1, NOZZLE_R + 0.03, n, radius1=NOZZLE_R, caps=False)
            iv, i_f = kit.cylinder(p0, p1, NOZZLE_R - 0.03, n, radius1=NOZZLE_R - 0.04, caps=False)
            lip = [(n + i, n + (i + 1) % n, len(nv) + n + (i + 1) % n, len(nv) + n + i) for i in range(n)]
            verts, faces = kit.merge((nv, nf), (iv, kit.flip_faces(i_f)))
            nozzles.append((verts, faces + lip))
            cones.append(kit.cylinder((x, NOZZLE_Y1 + 0.25, NOZZLE_Z), (x, NOZZLE_Y0 - 0.05, NOZZLE_Z), NOZZLE_R - 0.08, 16,
                                      radius1=0.06, caps=True))
        v, f = kit.merge(*nozzles)
        kit.make_object(f"Nozzle{name}", v, f, col, "Details", "Nozzle", extra={"engine": name})
        v, f = kit.merge(*cones)
        kit.make_object(f"Afterburner{name}", v, f, col, "Details", "Afterburner", extra={"engine": name})


def build_pitot(col):
    parts = []
    for side in (1, -1):
        base = surface_point(210, side * math.radians(80), -0.05)
        tip = (base[0] + side * 0.10, base[1] + 0.55, base[2])
        parts.append(kit.cylinder(base, tip, 0.025, 8))
    v, f = kit.merge(*parts)
    kit.make_object("Pitot", v, f, col, "Details")


def main():
    import bpy

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

    a = kit.AIRFRAME
    root = kit.collection(a)
    cols = {name: kit.collection(f"{a}_{name}", root) for name in ("Body", "Wings", "Details", "Glass", "Attachments")}

    kit.build_fuselage(cols["Body"])
    build_glove(cols["Body"])
    build_nacelles(cols["Body"])
    build_windows(cols["Glass"], cols["Body"])
    build_vanes(cols["Body"])
    build_wings(cols["Wings"])
    build_tail(cols["Wings"], cols["Body"])
    build_engines(cols["Details"])
    build_pitot(cols["Details"])
    kit.add_attachment_empties(cols["Attachments"])

    kit.smooth_all()
    kit.unwrap_sets()
    counts = kit.triangle_counts()
    manifest = kit.write_manifest(os.path.join(args.out, f"{a}_manifest.json"), args.manifest_luau, counts)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(args.out, f"{a}_base.blend"))
    kit.export(args.out)

    # Spans at the three sweeps, from the built wing's tip corners
    def span(sweep):
        turn = math.radians(sweep - SPREAD_SWEEP)
        tips = [turned((WING_TIP_X, y, WING_Z), turn) for y in (WING_TIP_LE, WING_TIP_LE - WING_TIP_CHORD)]
        return 2 * max(p[0] for p in tips)

    print("=" * 60)
    print(f"{a}: {len(kit.PARTS)} parts, {manifest['triangles']} triangles")
    print(f"  span {span(SPREAD_SWEEP):.2f} m spread, {span(MODEL_SWEEP):.2f} m as modelled, {span(FULL_SWEEP):.2f} m swept")
    print(f"  height {FIN_TIP_Z - GROUND_Z:.2f} m, length {Y(0) - Y(4450):.2f} m; pivot (Roblox) "
          f"{kit.to_roblox((PIVOT[0], PIVOT[1], WING_Z))}")
    for name, tris in sorted(counts.items(), key=lambda kv: -kv[1]):
        print(f"  {name:22s} {tris:6d}")
    print("=" * 60)


if __name__ == "__main__":
    main()
