--!strict
-- Pure gun ballistics (DEVELOPMENT.md §11.2). Shared by the server's authoritative bullet simulation,
-- every client's tracers, and the HUD pipper.
--
-- Rounds live in world studs (position) with real-world velocities (m/s), the same convention as the
-- flight model. Spread is deterministic from (seed, shot index), so the shooter's tracers, other
-- players' tracers and the server's bullets all agree without sending each round over the network.

local Flight = require(script.Parent.Config.Flight)
local Units = require(script.Parent.Units)

local G = Flight.GRAVITY
local GRAVITY_VECTOR = Vector3.new(0, -G, 0)

export type Round = {
	position: Vector3, -- studs
	velocity: Vector3, -- real m/s
	age: number, -- seconds
	index: number, -- shot index within the burst
}

export type GunSpec = {
	RateOfFire: number,
	MuzzleVelocity: number,
	Spread: number,
	Drag: number,
	Lifetime: number,
}

local Ballistics = {}

-- Advances one round by dt (gravity plus quadratic drag). Returns a new round.
function Ballistics.step(round: Round, dt: number, drag: number): Round
	local v = round.velocity
	local accel = GRAVITY_VECTOR - v * (drag * v.Magnitude)
	local velocity = v + accel * dt
	-- Integrate position with the average velocity over the step.
	local position = round.position + Units.velocityToStuds((v + velocity) * 0.5) * dt
	return { position = position, velocity = velocity, age = round.age + dt, index = round.index }
end

-- Seconds between shots.
function Ballistics.interval(gun: GunSpec): number
	return 60 / gun.RateOfFire
end

-- Direction of shot `index` in a burst: the muzzle direction plus deterministic spread.
function Ballistics.shotDirection(muzzle: CFrame, gun: GunSpec, seed: number, index: number): Vector3
	local rng = Random.new(seed * 7919 + index)
	local spread = math.rad(gun.Spread)
	local r = spread * math.sqrt(rng:NextNumber()) -- uniform over the cone's disc
	local theta = rng:NextNumber() * 2 * math.pi
	local offset = CFrame.Angles(r * math.sin(theta), r * math.cos(theta), 0)
	return (muzzle.Rotation * offset).LookVector
end

-- A new round leaving the muzzle. shooterVelocity is the jet's real velocity (rounds inherit it).
function Ballistics.fire(muzzle: CFrame, shooterVelocity: Vector3, gun: GunSpec, seed: number, index: number): Round
	local direction = Ballistics.shotDirection(muzzle, gun, seed, index)
	return {
		position = muzzle.Position,
		velocity = shooterVelocity + direction * gun.MuzzleVelocity,
		age = 0,
		index = index,
	}
end

-- Where to point the guns to hit a target (ignores drag; good enough for a sight).
-- Returns (aim direction, time of flight) or nil if no solution within the round's lifetime.
-- targetAccel (real m/s², optional): the LCOS sight (GUN-07) also leads a turning target's curve.
function Ballistics.leadDirection(
	shooterPosition: Vector3, -- studs
	shooterVelocity: Vector3, -- real m/s
	targetPosition: Vector3, -- studs
	targetVelocity: Vector3, -- real m/s
	muzzleVelocity: number,
	lifetime: number,
	targetAccel: Vector3?
): (Vector3?, number?)
	-- Work in real metres relative to the shooter. Rounds inherit the shooter's velocity, so the
	-- target's motion relative to the shooter is what matters.
	local relative = Units.velocityFromStuds(targetPosition - shooterPosition)
	local relativeVelocity = targetVelocity - shooterVelocity
	local accel = targetAccel or Vector3.zero
	local t = relative.Magnitude / muzzleVelocity
	for _ = 1, 4 do
		local future = relative + relativeVelocity * t + accel * (0.5 * t * t)
		t = future.Magnitude / muzzleVelocity
	end
	if t > lifetime or t ~= t then
		return nil, nil
	end
	local future = relative + relativeVelocity * t + accel * (0.5 * t * t)
	-- Aim above the target by the drop over the flight time.
	local aim = future + Vector3.new(0, 0.5 * G * t * t, 0)
	return aim.Unit, t
end

-- Gunsights by tier (DEVELOPMENT.md §11.3, GUN-07): "Simple" (Tier I–II: a lead pipper inside
-- SIMPLE_RANGE), "LCOS" (Tier III–IV: the pipper also leads the target's turn, out to SIGHT_RANGE), "EEGS"
-- (Tier V+: LCOS plus a funnel drawn from the simulated bullet stream).
Ballistics.SIMPLE_RANGE = 1200 -- real metres
Ballistics.SIGHT_RANGE = 1600
Ballistics.FUNNEL_WINGSPAN = 11 -- real metres: the funnel is this wide at each range

function Ballistics.sightFor(tier: number): string
	if tier >= 5 then
		return "EEGS"
	elseif tier >= 3 then
		return "LCOS"
	end
	return "Simple"
end

-- Where a round fired from `muzzle` (with the jet's velocity then) is after `t` seconds: gravity and drag,
-- in steps. The EEGS funnel draws rounds fired over the last second from where the jet pointed then.
function Ballistics.positionAfter(muzzle: CFrame, shooterVelocity: Vector3, gun: GunSpec, t: number): Vector3
	local round: Round = {
		position = muzzle.Position,
		velocity = shooterVelocity + muzzle.LookVector * gun.MuzzleVelocity,
		age = 0,
		index = 0,
	}
	local steps = math.max(1, math.ceil(t / 0.05))
	for _ = 1, steps do
		round = Ballistics.step(round, t / steps, gun.Drag)
	end
	return round.position
end

-- Segment vs oriented box. Returns the fraction (0..1) along the segment where it enters the box,
-- or nil if it misses. boxCFrame is the box's centre; size is its full extent (studs).
function Ballistics.segmentBox(from: Vector3, to: Vector3, boxCFrame: CFrame, size: Vector3): number?
	local a = boxCFrame:PointToObjectSpace(from)
	local b = boxCFrame:PointToObjectSpace(to)
	local d = b - a
	local half = size * 0.5
	local tMin, tMax = 0, 1
	for _, axis in { "X", "Y", "Z" } do
		local origin = (a :: any)[axis]
		local dir = (d :: any)[axis]
		local extent = (half :: any)[axis]
		if math.abs(dir) < 1e-9 then
			if origin < -extent or origin > extent then
				return nil
			end
		else
			local t1 = (-extent - origin) / dir
			local t2 = (extent - origin) / dir
			if t1 > t2 then
				t1, t2 = t2, t1
			end
			tMin = math.max(tMin, t1)
			tMax = math.min(tMax, t2)
			if tMin > tMax then
				return nil
			end
		end
	end
	return tMin
end

return Ballistics
