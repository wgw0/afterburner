--!strict
-- Flares and chaff (DEVELOPMENT.md §15). Pure maths, shared by the server and the test simulator.
-- Decoy decisions are rolled ONCE per (missile, decoy) pair from a seeded generator, never per tick,
-- so results are fair, repeatable and testable.

local Flight = require(script.Parent.Config.Flight)
local Units = require(script.Parent.Units)

local Countermeasures = {}

Countermeasures.FLARE_HEAT = 1.4 -- relative to a jet at military power seen from behind (≈1)
Countermeasures.FLARE_BURN = 3.0 -- seconds
Countermeasures.FLARE_DRAG = 0.004 -- 1/m: flares stop dead in the airstream
Countermeasures.FLARE_EJECT = 25 -- m/s, downward and back
Countermeasures.SEEKER_FOV = math.rad(6) -- a flare must appear this close to the tracked target to tempt the seeker
Countermeasures.DECOY_FACTOR = 0.22 -- per-flare decoy strength (tuned in Engagement.spec: proper defence ≈ 80%)

export type Flare = {
	id: number,
	position: Vector3, -- studs
	velocity: Vector3, -- real m/s
	age: number,
}

function Countermeasures.newFlare(id: number, dispenser: CFrame, jetVelocity: Vector3): Flare
	local eject = (-dispenser.UpVector * 0.8 + dispenser.LookVector * -0.6).Unit * Countermeasures.FLARE_EJECT
	return { id = id, position = dispenser.Position, velocity = jetVelocity + eject, age = 0 }
end

function Countermeasures.stepFlare(flare: Flare, dt: number): Flare
	local v = flare.velocity
	local accel = Vector3.new(0, -Flight.GRAVITY, 0) - v * (Countermeasures.FLARE_DRAG * v.Magnitude)
	local velocity = v + accel * dt
	return {
		id = flare.id,
		position = flare.position + Units.velocityToStuds((v + velocity) * 0.5) * dt,
		velocity = velocity,
		age = flare.age + dt,
	}
end

-- Heat of a flare at its age (bright at first, fading out).
function Countermeasures.flareHeat(flare: Flare): number
	if flare.age >= Countermeasures.FLARE_BURN then
		return 0
	end
	return Countermeasures.FLARE_HEAT * math.exp(-flare.age / 1.2)
end

-- Chance an IR seeker switches to a flare that just appeared in its field of view.
--   flareHeat vs targetHeat: cutting the throttle (and never using afterburner) makes flares work.
--   separation: how far apart they look to the seeker; a hard break opens the gap quickly.
function Countermeasures.flareDecoyChance(
	resistance: number,
	flareHeat: number,
	targetHeat: number,
	separation: number
): number
	if flareHeat <= 0 then
		return 0
	end
	local share = flareHeat / (flareHeat + math.max(targetHeat, 0))
	local nearness = math.clamp(1 - separation / Countermeasures.SEEKER_FOV, 0, 1)
	return math.clamp((1 - resistance) * share * Countermeasures.DECOY_FACTOR * (0.3 + 0.7 * nearness), 0, 1)
end

-- Chance a radar missile loses its target to a chaff bundle. Much better while notching.
function Countermeasures.chaffDecoyChance(resistance: number, notching: boolean): number
	return math.clamp((1 - resistance) * (if notching then 0.8 else 0.25), 0, 1)
end

-- Chance a chaff bundle breaks a radar lock (smaller than decoying a missile).
function Countermeasures.chaffLockBreakChance(notching: boolean): number
	return if notching then 0.35 else 0.08
end

-- A repeatable roll in [0, 1) for a pair of ids.
function Countermeasures.roll(a: number, b: number): number
	return Random.new((a % 1e6) * 100003 + (b % 1e6)):NextNumber()
end

return Countermeasures
