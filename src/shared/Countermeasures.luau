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

-- Flare programmes (CMS-04): from Tier V a press fires a short programme instead of one flare: SALVOS
-- salvos of PER_SALVO flares, INTERVAL seconds apart (2 × 2 over 0.5 s: 4 flares, ~7 defences from 30).
-- With the AutoFlares setting on, a heat-seeker guiding on you also fires it once, AUTO_TIME seconds
-- before it would arrive: flares burn out in FLARE_BURN, so one fired at launch from range would be cold.
Countermeasures.PROGRAMME_TIER = 5
Countermeasures.PROGRAMME = table.freeze({ salvos = 2, perSalvo = 2, interval = 0.5 })
Countermeasures.AUTO_TIME = 2.0

function Countermeasures.hasProgramme(tier: number): boolean
	return tier >= Countermeasures.PROGRAMME_TIER
end

-- Whether an incoming heat-seeker is close enough to fire the automatic programme: (distance in metres,
-- closing speed in m/s; nothing if it isn't closing).
function Countermeasures.autoDue(distanceMetres: number, closingSpeed: number): boolean
	return closingSpeed > 0 and distanceMetres / closingSpeed <= Countermeasures.AUTO_TIME
end

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

-- Imaging seekers (IR_Adv, MSL-09) see the jet's shape, not just a hot spot, so a single flare never fools
-- them. A burst does: BURST_FLARES flares appearing in the seeker's view within BURST_WINDOW seconds get one
-- roll, much better while the target is beaming the missile (breaking hard across its view) than flying
-- straight away from it. Then the count starts again: each burst rolls once.
Countermeasures.BURST_FLARES = 3
Countermeasures.BURST_WINDOW = 1.0 -- seconds
Countermeasures.BURST_BASE = 0.12 -- per-burst decoy strength flying straight (times 1 - resistance)
Countermeasures.BURST_BEAM = 2.2 -- extra strength with the target fully on the beam

-- Chance one flare burst decoys an imaging seeker. beam: 0 (target flying straight at or away from the
-- missile) to 1 (crossing its view at right angles).
function Countermeasures.burstDecoyChance(resistance: number, beam: number): number
	local strength = Countermeasures.BURST_BASE + Countermeasures.BURST_BEAM * math.clamp(beam, 0, 1)
	return math.clamp((1 - resistance) * strength, 0, 1)
end

-- Chance a radar missile loses its target to a chaff bundle. Much better while notching.
function Countermeasures.chaffDecoyChance(resistance: number, notching: boolean): number
	return math.clamp((1 - resistance) * (if notching then 0.8 else 0.08), 0, 1) -- spamming chaff without notching rarely works
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
