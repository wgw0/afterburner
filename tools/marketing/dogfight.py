"""
Afterburner marketing: the scripted fight the cover and trailer show. An Su-57 in a hard left turn round the
valley with an F-22A on its tail; the F-22A fires a Sidewinder, the Su-57 pumps flares, and the missile goes
for the flares and misses. The paths are plain functions of time, so a shot can be framed by reading them. Times are seconds from the start.
"""

import math

import bpy
from mathutils import Vector

import scene as sc

R_SU, R_F22 = 1100.0, 1060.0
SPEED = 215.0  # the Su-57's, m/s; the F-22A matches its turn rate, so the gap stays the same
RATE = SPEED / R_SU  # rad/s, turning left (anticlockwise seen from above)
LAG = 0.20  # how far round the circle the F-22A sits behind, radians (~215 m)

LAUNCH = 4.4  # the F-22A fires
FLARES = (4.45, 5.45, 0.1)  # from, to, every
SEDUCED = 4.7  # the missile switches to the first flare
BURN = 2.6  # motor burn, seconds
END = 16.0
DT = 1 / 120


def su57(t):
    th = RATE * t
    return Vector((R_SU * math.cos(th), R_SU * math.sin(th), 470 + 35 * math.sin(0.45 * t)))


def f22(t):
    th = RATE * t - LAG
    return Vector((R_F22 * math.cos(th), R_F22 * math.sin(th), 455 + 30 * math.sin(0.45 * t - 0.3)))


def _history(sample):
    """[(t, value)] every DT from 0 to END."""
    return [(i * DT, sample(i * DT)) for i in range(int(END / DT) + 1)]


def simulate():
    """Flares and the missile: lists of (time, position) samples (None while not yet launched / burnt out)."""
    flares = []
    t = FLARES[0]
    side = 1
    while t <= FLARES[1] + 1e-9:
        p, m, vel = sc.frame_of(su57, t)
        pos = p + m @ Vector((1.6 * side, -7.5, -0.6))
        v = vel * 0.8 + m @ Vector((20 * side, -12, -24))
        track = []
        tt = t
        while tt <= END and tt - t <= 3.5:
            track.append((tt, pos.copy()))
            v = v - v * 1.3 * DT + Vector((0, 0, -sc.G)) * DT
            pos = pos + v * DT
            tt += DT
        flares.append({"born": t, "track": track})
        side = -side
        t += FLARES[2]

    def flare_at(f, t):
        tr = f["track"]
        i = int(round((t - f["born"]) / DT))
        return tr[max(0, min(i, len(tr) - 1))][1]

    p, m, vel = sc.frame_of(f22, LAUNCH)
    pos = p + m @ Vector((0, 1.0, -1.8))
    v = vel.copy()
    track = []
    t = LAUNCH
    guiding = True
    best = math.inf
    while t <= END:
        track.append((t, pos.copy(), v.normalized()))
        speed = v.length
        if t - LAUNCH < BURN:
            speed = min(speed + 320 * DT, 680)
        else:
            speed = max(speed - 25 * DT, 300)
        if guiding:
            target = flare_at(flares[0], t) if t >= SEDUCED else su57(t)
            to = target - pos
            if to.length > best + 1:  # past it: fly on straight
                guiding = False
            best = min(best, to.length)
            want = to.normalized()
            cur = v.normalized()
            max_turn = 30 * sc.G / speed * DT
            ang = cur.angle(want) if cur.dot(want) < 0.999999 else 0
            if ang > 1e-6:
                k = min(1.0, max_turn / ang)
                cur = cur.slerp(want, k) if hasattr(cur, "slerp") else (cur * (1 - k) + want * k).normalized()
            v = cur * speed
        else:
            v = v.normalized() * speed
        pos = pos + v * DT
        t += DT
    return {"flares": flares, "missile": track}


def at(track, t):
    """The sample of a track nearest t, or None outside it."""
    if not track or t < track[0][0] - 1e-9 or t > track[-1][0] + 1e-9:
        return None
    i = int(round((t - track[0][0]) / DT))
    return track[max(0, min(i, len(track) - 1))]


def recent(track, t, life, step=1 / 60, until=math.inf):
    """(position, age) samples of a track from t back to t - life, newest first; only points laid down
    before `until` (when the motor or flare stopped smoking)."""
    out = []
    a = 0.0
    while a <= life:
        s = at(track, t - a)
        if s is None:
            break
        if s[0] <= until:
            out.append((s[1], a))
        a += step
    return out


class Fight:
    """All the fight's objects in a scene, and `pose(t)` to put them where they are at time t."""

    def __init__(self, scene, wingtip_vapour=True):
        self.sim = simulate()
        self.su = sc.Jet(scene, "Su57", "Grey")
        self.f22 = sc.Jet(scene, "F22A", "AirDominance", canopy="#b08a3a")
        self.missile = sc.missile(scene)
        vapour = sc.trail_material("Vapour", "#ffffff", lit=False, opacity=0.6)
        smoke = sc.trail_material("Smoke", "#f4f4f2", lit=True, opacity=0.85)
        flare_smoke = sc.trail_material("FlareSmoke", "#fbfaf7", lit=True, opacity=0.45)
        self.vapour = []
        if wingtip_vapour:
            for name in ("SuTipR", "SuTipL", "F22TipR", "F22TipL"):
                self.vapour.append(sc.Trail(scene, name, vapour, 0.12, 1.4, 1.1))
        self.smoke = sc.Trail(scene, "MissileSmoke", smoke, 0.5, 5.0, 4.0, sides=12, power=1.1)
        self.flare_balls, self.flare_smoke = [], []
        for i, _f in enumerate(self.sim["flares"]):
            bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=0.7)
            ball = bpy.context.active_object
            ball.name = f"Flare{i}"
            mat = bpy.data.materials.new(f"FlareCore{i}")
            mat.use_nodes = True
            b = mat.node_tree.nodes.get("Principled BSDF")
            b.inputs["Emission Color"].default_value = (1, 0.85, 0.55, 1)
            b.inputs["Emission Strength"].default_value = 40
            ball.data.materials.append(mat)
            ball.visible_shadow = False
            light = bpy.data.objects.new(f"FlareLight{i}", bpy.data.lights.new(f"FlareLight{i}", "POINT"))
            light.data.energy = 60000
            light.data.use_shadow = False
            light.data.color = (1, 0.8, 0.5)
            light.parent = ball
            scene.collection.objects.link(light)
            self.flare_balls.append(ball)
            self.flare_smoke.append(sc.Trail(scene, f"FlareSmoke{i}", flare_smoke, 0.3, 3.2, 1.4, sides=8, power=2.2))

    def pose(self, t):
        self.su.place(sc.world_matrix(su57, t))
        self.f22.place(sc.world_matrix(f22, t))
        # Wingtip vapour: where each tip was over the last second
        for k, (jet, path) in enumerate(((self.su, su57), (self.f22, f22))):
            for side in range(2):
                if not self.vapour:
                    break
                tip = jet.wingtips[side]
                pts = []
                a = 0.0
                while a <= 1.1:
                    pts.append((sc.world_matrix(path, t - a) @ tip, a))
                    a += 1 / 60
                self.vapour[k * 2 + side].build(pts)
        # The missile
        track = self.sim["missile"]
        s = at(track, t)
        if s is None or t - LAUNCH > 6:
            self.missile.hide_render = True
            for c in self.missile.children:
                c.hide_render = True
        else:
            for c in [self.missile, *self.missile.children]:
                c.hide_render = False
            pos, d = s[1], s[2]
            self.missile.matrix_world = sc.Matrix.Translation(pos) @ d.to_track_quat("Y", "Z").to_matrix() \
                .to_4x4() @ sc.Matrix.Scale(sc.MISSILE_SCALE, 4)
            # the glow only while the motor burns
            for c in self.missile.children:
                if c.name.startswith("Sphere"):
                    c.hide_render = t - LAUNCH > BURN
        self.smoke.build(recent(track, t, 4.0, until=LAUNCH + BURN))
        # Flares
        for f, ball, trail in zip(self.sim["flares"], self.flare_balls, self.flare_smoke):
            s = at(f["track"], t)
            alive = s is not None and t - f["born"] < 3.0
            ball.hide_render = not alive
            for c in ball.children:
                c.hide_render = not alive
            if alive:
                ball.location = s[1]
                fade = 1 - max(0.0, (t - f["born"] - 2.0))
                ball.scale = (max(fade, 0.05),) * 3
            trail.build(recent(f["track"], t, 1.4, until=f["born"] + 3.0) if s is not None or
                        t - f["born"] < 4.4 else [])
