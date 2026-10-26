--!strict
-- Missile flight and guidance (DEVELOPMENT.md §13.2, MSL-01). Pure: shared by the server's authoritative
-- missile simulation, the HUD (lock and launch zone) and the engagement simulator in tests.
--
--   Motor: thrust for MotorBurnTime, then coast. Drag thins with altitude. Gravity always.
--   Guidance: proportional navigation, limited by MaxG × an energy factor, so a slow missile turns badly
--     and a long shot at a fleeing target simply runs out of energy.
--   Seeker: must keep the target inside its gimbal limit, or guidance is lost.
-- Positions are world studs; velocities are real m/s (the flight model's convention).

local Atmosphere = require(script.Parent.Atmosphere)
local Countermeasures = require(script.Parent.Countermeasures)
local Flight = require(script.Parent.Config.Flight)
local Signature = require(script.Parent.Signature)
local Units = require(script.Parent.Units)

local G = Flight.GRAVITY
local RAD = math.pi / 180
local FULL_ENERGY_SPEED = 700 -- m/s: at or above this the missile can pull its full MaxG

local Guidance = {}

export type MissileState = {
	position: Vector3, -- studs
	velocity: Vector3, -- real m/s
	age: number, -- seconds since launch
	travelled: number, -- real metres since launch (arming)
}

export type Spec = {
	MotorBurnTime: number,
	MotorAccel: number,
	Drag: number,
	MaxG: number,
	MinSpeed: number,
	Gimbal: number,
	NavConstant: number,
}

function Guidance.launch(position: Vector3, velocity: Vector3): MissileState
	return { position = position, velocity = velocity, age = 0, travelled = 0 }
end

-- Is `point` within the missile's seeker gimbal?
function Guidance.inGimbal(missile: MissileState, spec: Spec, point: Vector3): boolean
	local los = point - missile.position
	if los.Magnitude < 1e-3 or missile.velocity.Magnitude < 1e-3 then
		return true
	end
	return missile.velocity.Unit:Dot(los.Unit) >= math.cos(spec.Gimbal * RAD)
end

-- Lateral acceleration (real m/s²) from proportional navigation toward a target.
function Guidance.proNav(missile: MissileState, targetPosition: Vector3, targetVelocity: Vector3, nav: number): Vector3
	local r = Units.velocityFromStuds(targetPosition - missile.position) -- real metres
	local range = r.Magnitude
	if range < 1e-3 then
		return Vector3.zero
	end
	local relativeVelocity = targetVelocity - missile.velocity
	local closing = -relativeVelocity:Dot(r) / range
	local losRate = r:Cross(relativeVelocity) / (range * range) -- rad/s vector
	local accel = losRate:Cross(r / range) * (nav * math.max(closing, 0)) -- a = N·Vc·(Ω × r̂)
	-- Guidance only steers sideways; remove any component along the missile's flight path.
	local v = missile.velocity
	if v.Magnitude > 1e-3 then
		local vhat = v.Unit
		accel -= vhat * accel:Dot(vhat)
	end
	return accel
end

-- Turn limit right now (m/s²): MaxG scaled down as the missile slows.
function Guidance.maxLateral(missile: MissileState, spec: Spec): number
	local speed = missile.velocity.Magnitude
	local energy = math.clamp((speed / FULL_ENERGY_SPEED) ^ 2, 0.15, 1)
	return spec.MaxG * G * energy
end

-- Advances a missile by dt. targetPosition/targetVelocity are what the seeker is tracking (nil = flying dumb).
-- Returns (new state, guiding?).
function Guidance.step(
	missile: MissileState,
	spec: Spec,
	dt: number,
	targetPosition: Vector3?,
	targetVelocity: Vector3?
): (MissileState, boolean)
	local v = missile.velocity
	local speed = v.Magnitude
	local vhat = if speed > 1e-3 then v / speed else Vector3.new(0, 0, -1)
	local altitude = Units.altitudeMetres(missile.position.Y)
	local densityRatio = Atmosphere.density(altitude) / Atmosphere.SEA_LEVEL_DENSITY

	local accel = Vector3.new(0, -G, 0) - vhat * (spec.Drag * densityRatio * speed * speed)
	if missile.age < spec.MotorBurnTime then
		accel += vhat * spec.MotorAccel
	end

	local guiding = false
	if
		targetPosition
		and targetVelocity
		and speed >= spec.MinSpeed
		and Guidance.inGimbal(missile, spec, targetPosition)
	then
		local lateral = Guidance.proNav(missile, targetPosition, targetVelocity, spec.NavConstant)
		-- Counter gravity's sideways pull too, so the missile doesn't sag under the target.
		local gravityLateral = Vector3.new(0, G, 0) - vhat * vhat:Dot(Vector3.new(0, G, 0))
		lateral += gravityLateral
		local limit = Guidance.maxLateral(missile, spec)
		if lateral.Magnitude > limit then
			lateral = lateral.Unit * limit
		end
		accel += lateral
		guiding = true
	end

	local velocity = v + accel * dt
	local stepVelocity = (v + velocity) * 0.5
	return {
		position = missile.position + Units.velocityToStuds(stepVelocity) * dt,
		velocity = velocity,
		age = missile.age + dt,
		travelled = missile.travelled + stepVelocity.Magnitude * dt,
	},
		guiding
end

-- Closest distance (real metres) between two points moving linearly over one step.
function Guidance.closestApproach(
	missileFrom: Vector3,
	missileTo: Vector3,
	targetFrom: Vector3,
	targetTo: Vector3
): number
	local d0 = targetFrom - missileFrom
	local dv = (targetTo - targetFrom) - (missileTo - missileFrom)
	local t = 0
	local dvLen = dv:Dot(dv)
	if dvLen > 1e-9 then
		t = math.clamp(-d0:Dot(dv) / dvLen, 0, 1)
	end
	return Units.toMetres((d0 + dv * t).Magnitude)
end

---------------------------------------------------------------------------
-- Infrared seeker: lock, tracking and flare decoys
---------------------------------------------------------------------------

export type HeatSource = {
	id: any, -- jet id, or "flare:<n>"
	position: Vector3,
	velocity: Vector3,
	heat: number, -- as seen from the seeker
}

export type IRSeeker = {
	trackId: any?, -- what it's following now (target jet id or a flare id)
	rolled: { [any]: boolean }, -- flares already considered (each rolled once)
	seed: number,
}

function Guidance.newIRSeeker(targetId: any?, seed: number): IRSeeker
	return { trackId = targetId, rolled = {}, seed = seed }
end

-- Updates what the seeker is tracking. sources includes the original target (if still alive) and every
-- burning flare. Returns the source being tracked (or nil: the missile goes dumb).
function Guidance.updateIRSeeker(
	seeker: IRSeeker,
	missile: MissileState,
	spec: Spec & { FlareResistance: number },
	sources: { HeatSource }
): HeatSource?
	local tracked: HeatSource? = nil
	for _, source in sources do
		if source.id == seeker.trackId then
			tracked = source
		end
	end
	if not tracked or tracked.heat <= 0 or not Guidance.inGimbal(missile, spec, tracked.position) then
		seeker.trackId = nil
		return nil
	end

	-- Any new flare appearing near the tracked target in the seeker's view gets one roll.
	local trackLos = (tracked.position - missile.position).Unit
	for _, source in sources do
		if type(source.id) == "string" and not seeker.rolled[source.id] and source.heat > 0 then
			local los = (source.position - missile.position).Unit
			local separation = math.acos(math.clamp(los:Dot(trackLos), -1, 1))
			if separation <= Countermeasures.SEEKER_FOV then
				seeker.rolled[source.id] = true
				local chance =
					Countermeasures.flareDecoyChance(spec.FlareResistance, source.heat, tracked.heat, separation)
				local seedB = tonumber(string.match(source.id, "%d+")) or 0
				if Countermeasures.roll(seeker.seed, seedB) < chance then
					seeker.trackId = source.id
					return source
				end
			end
		end
	end
	return tracked
end

-- Can an IR missile lock this target from the shooter? (angle off the nose, aspect, range vs heat)
function Guidance.irLockable(
	spec: { SeekerCone: number, MaxRange: number, Class: string },
	shooterCF: CFrame,
	targetCF: CFrame,
	throttle: number,
	afterburner: boolean
): boolean
	local los = targetCF.Position - shooterCF.Position
	if los.Magnitude < 1e-3 then
		return false
	end
	if shooterCF.LookVector:Dot(los.Unit) < math.cos(spec.SeekerCone * RAD) then
		return false
	end
	local heat = Signature.ir(targetCF, throttle, afterburner, shooterCF.Position, spec.Class == "IR_Rear")
	if heat <= 0 then
		return false
	end
	local reach = spec.MaxRange * math.sqrt(math.clamp(heat, 0.25, 2))
	return Units.toMetres(los.Magnitude) <= reach
end

---------------------------------------------------------------------------
-- Launch zone (for the HUD)
---------------------------------------------------------------------------

-- Effective max range, no-escape range and min range (real metres) against a target right now.
-- Closing fast (head-on) stretches the reach; a fleeing target shrinks it.
function Guidance.launchZone(
	spec: { MaxRange: number, MinRange: number },
	shooterPosition: Vector3,
	shooterVelocity: Vector3,
	targetPosition: Vector3,
	targetVelocity: Vector3
): (number, number, number)
	local los = targetPosition - shooterPosition
	local dir = if los.Magnitude > 1e-3 then los.Unit else Vector3.new(0, 0, -1)
	local closing = (shooterVelocity - targetVelocity):Dot(dir)
	local factor = math.clamp(0.45 + closing / 600, 0.3, 1.25)
	local rMax = spec.MaxRange * factor
	return rMax, rMax * 0.4, spec.MinRange
end

---------------------------------------------------------------------------
-- Active radar homing (MSL-07). Midcourse: the missile flies on the launcher's data link (the true
-- target while the launcher keeps its lock; otherwise the last known position, extrapolated). Within
-- ActiveRange of where it thinks the target is, its own seeker goes active and the launcher can turn
-- away. An active seeker loses the target outside its gimbal, or after the target notches for
-- ARH_NOTCH_SECONDS; a lost ARH stays lost.

Guidance.ARH_NOTCH_SECONDS = 1.0

export type ARHState = {
	active: boolean,
	lost: boolean,
	notchTime: number,
	lastKnown: { position: Vector3, velocity: Vector3, time: number }?,
}

function Guidance.newARH(targetPosition: Vector3?, targetVelocity: Vector3?, now: number): ARHState
	return {
		active = false,
		lost = false,
		notchTime = 0,
		lastKnown = if targetPosition
			then { position = targetPosition, velocity = targetVelocity or Vector3.zero, time = now }
			else nil,
	}
end

-- Where an ARH missile steers this tick (position in studs, velocity real m/s), or nil. Updates arh.
--   target: the real target now (nil if it's gone); linked: the launcher still has its lock;
--   notching: the target is notching the missile's radar right now.
function Guidance.arhTrack(
	arh: ARHState,
	missile: MissileState,
	spec: { Gimbal: number, ActiveRange: number? },
	target: { position: Vector3, velocity: Vector3 }?,
	linked: boolean,
	notching: boolean,
	dt: number,
	now: number
): (Vector3?, Vector3?)
	if arh.lost or not target then
		return nil, nil
	end
	if arh.active then
		local los = target.position - missile.position
		local heading = if missile.velocity.Magnitude > 1 then missile.velocity.Unit else los.Unit
		if los.Magnitude > 1e-3 and heading:Dot(los.Unit) < math.cos(spec.Gimbal * RAD) then
			arh.lost = true
			return nil, nil
		end
		arh.notchTime = if notching then arh.notchTime + dt else 0
		if arh.notchTime > Guidance.ARH_NOTCH_SECONDS then
			arh.lost = true
			return nil, nil
		end
		return target.position, target.velocity
	end
	if linked then
		arh.lastKnown = { position = target.position, velocity = target.velocity, time = now }
	end
	local known = arh.lastKnown
	if not known then
		return nil, nil
	end
	local predicted = known.position + Units.velocityToStuds(known.velocity) * (now - known.time)
	if Units.toMetres((predicted - missile.position).Magnitude) <= (spec.ActiveRange or 0) then
		arh.active = true
		arh.notchTime = 0
	end
	return predicted, known.velocity
end

return Guidance
