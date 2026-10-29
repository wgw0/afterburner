"""
Afterburner: the missile models (Blender 4.x / 5.x). Six families cover every missile in src/shared/WeaponData;
each missile names its family (`Model`) and its real length (`Length`), and the game scales the family's model
to that length.

  Sidewinder    AIM-9L/M/P, R-3R, R-13M      thin body, double-delta canards, tail fins with rollerons
  CanardIR      R-73, R-74M, R-60, R.550s    thicker body, small vanes ahead of the canards, tail fins
  TailIR        AIM-9X, ASRAAM, IRIS-T, MICA  long clean body, small mid-body strakes, small tail fins
  MediumRadar   AIM-120s, R-77s, Meteor      clipped mid-body wings, tail control fins
  LargeRadar    AIM-7F, Skyflash, Super 530s, R-24R, R-27s   big delta mid-body wings, tail fins
  Phoenix       AIM-54A                      fat body, long low wings, tail fins

Each family is modelled at the real size of the missile in brackets in FAMILIES (from published lengths,
diameters and spans) and has two parts: <Family>_Body (the white airframe and fins) and <Family>_Trim (the
seeker window or radome tip, the nozzle and the guidance-section band, dark grey). Fins are cruciform at 45
degrees, as the missiles hang on their rails.

Axes as the jets': Blender X right, Y forward (nose to +Y), Z up, metres (1 stud = 1 m). Each family is centred
lengthwise on its own origin; the families are laid out on a grid (FAMILIES[...]["at"]) so that the Studio
builder (tools/MissileBuilder.luau) can undo any scale or axis change the importer makes, as the Ground Roamer's
builder does with its wheels.

  blender -b --python tools/blender/missiles_generate.py -- --out <abs>/tools/blender/out --manifest-luau tools/Manifests/Missiles.luau
  blender -b <abs>/tools/blender/out/Missiles.blend --python tools/blender/render_views.py -- --out <abs>/tools/blender/out
"""

import argparse
import math
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import f5e_generate as kit  # noqa: E402  (shared helpers; its module settings are switched below)

kit.AIRFRAME = "Missiles"
kit.LENGTH = 3.96
kit.TEXTURE_SETS = {
    "Body": (0.85, 0.85, 0.83, 0.0, 0.45),
    "Trim": (0.20, 0.21, 0.22, 0.1, 0.5),
}
kit.PARTS.clear()
kit.HULL = {}
kit.HITBOXES = {}
kit.ATTACHMENTS = {}

SEGMENTS = 20  # round the body
FIN_T = 0.012  # fin thickness at the root (metres)

# Fins: (root leading edge, metres back from the nose), root chord, tip chord, tip leading-edge sweep back,
# semispan out from the body surface, roll angle offset (degrees, 45 = X layout).
# Body profile: (metres back from the nose, radius) from the nose tip to the tail.
# nose: where the Trim nose piece (seeker window or radome tip) ends; band: (from, to) metres back from the nose.
FAMILIES = {
    "Sidewinder": {  # AIM-9L: 2.87 m, 127 mm, 0.64 m span; canards 0.51 m span
        "at": (0.0, 0.0),
        "length": 2.87,
        "radius": 0.0635,
        "profile": [(0.0, 0.0), (0.02, 0.035), (0.05, 0.052), (0.09, 0.061), (0.14, 0.0635), (2.84, 0.0635), (2.87, 0.055)],
        "nose": 0.06,
        "band": (0.52, 0.56),
        "fins": [
            (0.30, 0.22, 0.03, 0.17, 0.19),  # double-delta canards
            (2.45, 0.39, 0.20, 0.17, 0.255),  # tail fins with rollerons
        ],
        "rollerons": True,
    },
    "CanardIR": {  # R-73: 2.90 m, 170 mm, 0.51 m span
        "at": (1.0, 0.0),
        "length": 2.90,
        "radius": 0.085,
        "profile": [(0.0, 0.0), (0.03, 0.048), (0.07, 0.068), (0.13, 0.080), (0.22, 0.085), (2.86, 0.085), (2.90, 0.075)],
        "nose": 0.08,
        "band": (0.62, 0.66),
        "fins": [
            (0.13, 0.05, 0.03, 0.02, 0.05),  # destabiliser vanes ahead of the canards
            (0.28, 0.20, 0.06, 0.12, 0.17),  # canards
            (2.45, 0.40, 0.22, 0.16, 0.17),  # tail fins with ailerons
        ],
    },
    "TailIR": {  # AIM-9X: 3.02 m, 127 mm, 0.45 m tail span
        "at": (2.0, 0.0),
        "length": 3.02,
        "radius": 0.0635,
        "profile": [(0.0, 0.0), (0.03, 0.036), (0.08, 0.054), (0.15, 0.062), (0.22, 0.0635), (2.99, 0.0635), (3.02, 0.055)],
        "nose": 0.07,
        "band": (0.56, 0.60),
        "fins": [
            (0.65, 0.30, 0.18, 0.10, 0.045),  # small fixed strakes
            (2.68, 0.26, 0.12, 0.12, 0.16),  # tail control fins
        ],
    },
    "MediumRadar": {  # AIM-120C: 3.66 m, 178 mm, 0.45 m wing span
        "at": (0.0, 6.0),
        "length": 3.66,
        "radius": 0.089,
        "profile": [(0.0, 0.0), (0.06, 0.030), (0.18, 0.058), (0.34, 0.077), (0.50, 0.086), (0.62, 0.089), (3.62, 0.089), (3.66, 0.078)],
        "nose": 0.10,
        "band": (0.62, 0.66),
        "fins": [
            (1.38, 0.34, 0.10, 0.22, 0.135),  # clipped mid-body wings
            (3.28, 0.34, 0.12, 0.20, 0.135),  # tail control fins
        ],
    },
    "LargeRadar": {  # AIM-7F: 3.66 m, 203 mm, 1.0 m wing span, 0.81 m tail span
        "at": (1.0, 6.0),
        "length": 3.66,
        "radius": 0.1015,
        "profile": [(0.0, 0.0), (0.06, 0.034), (0.18, 0.064), (0.34, 0.086), (0.52, 0.098), (0.66, 0.1015), (3.62, 0.1015), (3.66, 0.09)],
        "nose": 0.10,
        "band": (0.70, 0.74),
        "fins": [
            (1.10, 0.62, 0.04, 0.58, 0.40),  # delta mid-body wings
            (3.20, 0.44, 0.16, 0.24, 0.30),  # tail fins
        ],
    },
    "Phoenix": {  # AIM-54A: 3.96 m, 380 mm, 0.92 m span
        "at": (2.0, 6.0),
        "length": 3.96,
        "radius": 0.19,
        "profile": [(0.0, 0.0), (0.08, 0.055), (0.24, 0.11), (0.45, 0.15), (0.70, 0.177), (0.95, 0.19), (3.90, 0.19), (3.96, 0.17)],
        "nose": 0.14,
        "band": (1.02, 1.07),
        "fins": [
            (2.10, 1.10, 0.40, 0.70, 0.27),  # long low-aspect wings
            (3.48, 0.46, 0.22, 0.22, 0.27),  # tail fins
        ],
    },
}


def ring(y, radius, cx, cz=0.0):
    return [
        (cx + radius * math.cos(2 * math.pi * i / SEGMENTS), y, cz + radius * math.sin(2 * math.pi * i / SEGMENTS))
        for i in range(SEGMENTS)
    ]


def revolve(stations, ox, oy, nose_y):
    """Body of revolution from (metres back from the nose, radius) stations, nose at nose_y (+Y forward).
    A zero radius closes the end with a point."""
    rings, tip, verts, faces = [], None, [], []
    for back, r in stations:
        y = oy + nose_y - back
        if r <= 1e-6:
            tip = (ox, y, 0.0)
        else:
            rings.append(ring(y, r, ox))
    v, f = kit.lofted(rings, cap_start=tip is None, cap_end=True)
    verts, faces = list(v), list(f)
    if tip is not None:  # a point nose
        c = len(verts)
        verts.append(tip)
        for i in range(SEGMENTS):
            faces.append((c, i, (i + 1) % SEGMENTS))
    return verts, faces


def radius_at(profile, back):
    for (b0, r0), (b1, r1) in zip(profile, profile[1:]):
        if b0 <= back <= b1:
            t = (back - b0) / max(b1 - b0, 1e-6)
            return r0 + (r1 - r0) * t
    return profile[-1][1]


def section(profile, a, b):
    """The stations between a and b metres back from the nose, with the ends interpolated."""
    out = [(a, radius_at(profile, a))]
    out += [(s, r) for s, r in profile if a < s < b]
    out.append((b, radius_at(profile, b)))
    return out


def fin(ox, oy, nose_y, body_r, le, root, tip, sweep, span, angle):
    """A tapered fin with a diamond section, standing out radially at roll angle `angle` (radians)."""
    out = (math.cos(angle), math.sin(angle))  # radial direction in the X-Z plane
    side = (-math.sin(angle), math.cos(angle))  # thickness direction

    def point(r, back, t):
        return (ox + out[0] * r + side[0] * t, oy + nose_y - back, out[1] * r + side[1] * t)

    sections = []
    for r, lead, chord, thick in (
        (body_r - 0.005, le, root, FIN_T),
        (body_r + span, le + sweep, tip, FIN_T * 0.5),
    ):
        mid = lead + chord / 2
        sections.append([point(r, lead, 0), point(r, mid, thick / 2), point(r, lead + chord, 0), point(r, mid, -thick / 2)])
    return kit.lofted(sections)


def merge_into(verts, faces, part):
    v, f = part
    base = len(verts)
    verts.extend(v)
    faces.extend(tuple(base + i for i in face) for face in f)


def build_family(name, spec, cols):
    ox, oy = spec["at"]
    length = spec["length"]
    nose_y = length / 2
    profile = spec["profile"]
    a0 = math.radians(45)

    body_v, body_f = revolve(section(profile, spec["nose"], length - 0.02), ox, oy, nose_y)
    for le, root, tip, sweep, span in spec["fins"]:
        for k in range(4):
            r = radius_at(profile, le + root / 2)
            merge_into(body_v, body_f, fin(ox, oy, nose_y, r, le, root, tip, sweep, span, a0 + k * math.pi / 2))
    if spec.get("rollerons"):  # the Sidewinder's rolleron wheels in the tail fins' trailing tips
        le, root, tip, sweep, span = spec["fins"][-1]
        for k in range(4):
            ang = a0 + k * math.pi / 2
            r = spec["radius"] + span - 0.02
            back = le + sweep + tip - 0.02
            centre = (ox + math.cos(ang) * r, oy + nose_y - back, math.sin(ang) * r)
            tangent = (-math.sin(ang), math.cos(ang))
            p0 = (centre[0] - tangent[0] * 0.008, centre[1], centre[2] - tangent[1] * 0.008)
            p1 = (centre[0] + tangent[0] * 0.008, centre[1], centre[2] + tangent[1] * 0.008)
            merge_into(body_v, body_f, kit.cylinder(p0, p1, 0.03, 12))
    kit.make_object(f"{name}_Body", body_v, body_f, cols["Body"], "Body", origin=(ox, oy, 0),
                    extra={"family": name, "role": "Body", "length": length, "radius": spec["radius"]})

    trim_v, trim_f = revolve(section(profile, 0.0, spec["nose"] + 0.002), ox, oy, nose_y)  # seeker or radome tip
    b0, b1 = spec["band"]
    merge_into(trim_v, trim_f, revolve(section([(s, r * 1.004) for s, r in profile], b0, b1), ox, oy, nose_y))
    nozzle_r = profile[-1][1]
    tail_y = oy + nose_y - length
    merge_into(trim_v, trim_f, kit.cylinder((ox, tail_y + 0.022, 0), (ox, tail_y - 0.01, 0), nozzle_r, SEGMENTS,
                                            radius1=nozzle_r * 0.85))
    kit.make_object(f"{name}_Trim", trim_v, trim_f, cols["Trim"], "Trim", origin=(ox, oy, 0),
                    extra={"family": name, "role": "Trim"})
    kit.ATTACHMENTS[f"{name}_Tail"] = (ox, tail_y - 0.01, 0)


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
    cols = {name: kit.collection(f"{a}_{name}", root) for name in ("Body", "Trim", "Attachments")}
    for name, spec in FAMILIES.items():
        build_family(name, spec, cols)
    kit.add_attachment_empties(cols["Attachments"])

    kit.smooth_all()
    kit.unwrap_sets()
    counts = kit.triangle_counts()
    manifest = kit.write_manifest(os.path.join(args.out, f"{a}_manifest.json"), args.manifest_luau, counts)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(args.out, f"{a}.blend"))
    kit.export(args.out, f"{a}.fbx")

    print("=" * 60)
    print(f"{a}: {len(kit.PARTS)} parts, {manifest['triangles']} triangles")
    for name, tris in sorted(counts.items()):
        print(f"  {name:20s} {tris:6d}")
    print("=" * 60)


if __name__ == "__main__":
    main()
