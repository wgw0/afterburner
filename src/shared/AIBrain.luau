--!strict
-- AI pilot decision-making (DEVELOPMENT.md §18, AI-02/03). Pure: given what the pilot knows, pick a
-- behaviour state and turn it into stick inputs (via an aim direction for the Instructor), throttle and
-- trigger decisions. The server's AIService feeds it; the tests run whole dogfights with it.
--
-- States, highest priority first:
--   AvoidGround  about to hit terrain or the ceiling: pull away, wings level
--   Defend       a missile is guiding on me (or a gun is on my six): break / notch, flares / chaff
--   Extend       slow or badly damaged: unload, afterburner, rebuild energy
--   Attack       target close: lead pursuit, guns when the solution is good
--   Engage       target known but far: pursue, climb for an energy advantage
--   Patrol       no target: fly to waypoints inside the map
--   Objective    Air Superiority: fly to the zone the match gave it and circle inside; only enemies within
--                OBJECTIVE_ENGAGE pull it away

local Ballistics = require(script.Parent.Ballistics)
local Units = require(script.Parent.Units)

local RAD = math.pi / 180

export type Profile = {
	Name: string,
	ReactionTime: number, -- seconds before reacting to a new threat
	AimError: number, -- degrees of wobble on the gun solution
	FireTolerance: number, -- degrees: fire when the solution is within this
	FlareSkill: number, -- 0..1 chance of defending a missile properly
	EnergySkill: number, -- 0..1: how well it manages speed
	MaxGUse: number, -- 0..1 of the airframe's G limit it's willing to pull
	GunRange: number, -- real metres
	MissileInterval: number, -- seconds between missile launches (AI-04)
	MissileRange: number, -- fraction of a missile's max range it's willing to fire from
}

local AIBrain = {}

-- Air Superiority: enemies closer than this (real metres) pull an AI off its zone
AIBrain.OBJECTIVE_ENGAGE = 4000

AIBrain.PROFILES = table.freeze({
	Easy = table.freeze({
		Name = "Easy",
		ReactionTime = 1.2,
		AimError = 4,
		FireTolerance = 3,
		FlareSkill = 0.25,
		EnergySkill = 0.2,
		MaxGUse = 0.65,
		GunRange = 700,
		MissileInterval = 18,
		MissileRange = 0.5,
	}),
	Normal = table.freeze({
		Name = "Normal",
		ReactionTime = 0.7,
		AimError = 2,
		FireTolerance = 2.2,
		FlareSkill = 0.55,
		EnergySkill = 0.5,
		MaxGUse = 0.85,
		GunRange = 900,
		MissileInterval = 12,
		MissileRange = 0.6,
	}),
	Hard = table.freeze({
		Name = "Hard",
		ReactionTime = 0.4,
		AimError = 1,
		FireTolerance = 1.6,
		FlareSkill = 0.8,
		EnergySkill = 0.75,
		MaxGUse = 0.95,
		GunRange = 1000,
		MissileInterval = 9,
		MissileRange = 0.7,
	}),
	Ace = table.freeze({
		Name = "Ace",
		ReactionTime = 0.25,
		AimError = 0.5,
		FireTolerance = 1.2,
		FlareSkill = 0.95,
		EnergySkill = 0.95,
		MaxGUse = 1,
		GunRange = 1100,
		MissileInterval = 7,
		MissileRange = 0.75,
	}),
})

-- Missile choice (AI-04). A slot the pilot could fire: class "IR" | "Radar", ranges in real metres,
-- irLockable = a heat-seeker could see the target now (caller checks with Guidance.irLockable).
export type MissileOption = {
	index: number,
	class: "IR" | "Radar",
	count: number,
	minRange: number,
	maxRange: number,
	irLockable: boolean?,
}

-- Picks the missile to fire at a target `range` metres away (nil = none). Heat-seekers first when the
-- seeker can see the target (cheaper, fire-and-forget); radar missiles need the jet to have a radar and
-- then a lock (needsLock). Never inside a missile's minimum range or beyond the profile's share of
-- its maximum.
function AIBrain.chooseMissile(
	profile: Profile,
	options: { MissileOption },
	range: number,
	hasRadar: boolean
): (MissileOption?, boolean)
	local best: MissileOption? = nil
	for _, option in options do
		local inRange = option.count > 0
			and range >= option.minRange * 1.2
			and range <= option.maxRange * profile.MissileRange
		if inRange then
			if option.class == "IR" and option.irLockable then
				return option, false
			elseif option.class == "Radar" and hasRadar and not best then
				best = option
			end
		end
	end
	return best, best ~= nil
end

export type Body = {
	cframe: CFrame,
	velocity: Vector3, -- real m/s
}

export type Context = {
	now: number,
	me: Body & { speed: number, altitude: number, groundClearance: number, damaged: boolean, aoa: number? },
	target: (Body & { id: any })?,
	missile: { position: Vector3, velocity: Vector3, kind: string }?, -- kind "IR" | "Radar"
	gun: { MuzzleVelocity: number, Lifetime: number }?,
	mapHalfExtent: number, -- studs
	ceiling: number, -- studs
	maxG: number?, -- airframe G limit (default 7)
	cornerSpeed: number?, -- real m/s (default 180)
	objective: { position: Vector3, radius: number }?, -- a zone to take or hold (studs)
}

export type Memory = {
	state: string,
	stateSince: number,
	threatSeenAt: number?,
	defendRoll: number?, -- decided once per threat: does it defend properly?
	waypoint: Vector3?,
	seed: number,
	lastFlare: number,
	extending: boolean,
}

export type Decision = {
	state: string,
	aim: Vector3,
	throttle: number,
	afterburner: boolean,
	overG: boolean,
	gLimit: number?, -- for the Instructor: the most G this pilot will pull right now
	pointNose: boolean?, -- for the Instructor: put the nose (guns) on the aim, not the flight path
	fire: boolean,
	flare: boolean,
	chaff: boolean,
}

function AIBrain.newMemory(seed: number): Memory
	return {
		state = "Patrol",
		stateSince = 0,
		threatSeenAt = nil,
		defendRoll = nil,
		waypoint = nil,
		seed = seed,
		lastFlare = -math.huge,
		extending = false,
	}
end

local function rng(memory: Memory, salt: number): number
	return Random.new(memory.seed * 7919 + salt):NextNumber()
end

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return if f.Magnitude > 1e-3 then f.Unit else Vector3.new(0, 0, -1)
end

-- Slowly wandering aim error (so the AI doesn't snap perfectly onto target).
local function aimWobble(memory: Memory, profile: Profile, now: number): CFrame
	local t = now * 0.7
	local a = math.noise(t, memory.seed * 0.13) * profile.AimError * RAD * 2
	local b = math.noise(memory.seed * 0.29, t) * profile.AimError * RAD * 2
	return CFrame.Angles(a, b, 0)
end

-- Ground and ceiling: predicted clearance a few seconds ahead.
local function groundDanger(ctx: Context): boolean
	local sinkRate = -ctx.me.velocity.Y -- m/s down
	local lookAhead = 4
	return ctx.me.groundClearance - math.max(sinkRate, 0) * lookAhead < 250 or ctx.me.groundClearance < 150
end

local function ceilingDanger(ctx: Context): boolean
	return ctx.me.cframe.Position.Y > ctx.ceiling * 0.92
end

local function outOfBounds(ctx: Context): boolean
	local p = ctx.me.cframe.Position
	return math.max(math.abs(p.X), math.abs(p.Z)) > ctx.mapHalfExtent * 0.85
end

function AIBrain.chooseState(memory: Memory, profile: Profile, ctx: Context): string
	if groundDanger(ctx) or ceilingDanger(ctx) then
		return "AvoidGround"
	end
	-- Threat reaction is delayed by the pilot's reaction time.
	if ctx.missile then
		memory.threatSeenAt = memory.threatSeenAt or ctx.now
		if memory.defendRoll == nil then
			memory.defendRoll = rng(memory, math.floor(memory.threatSeenAt * 10))
		end
		if ctx.now - (memory.threatSeenAt :: number) >= profile.ReactionTime then
			return "Defend"
		end
	else
		memory.threatSeenAt = nil
		memory.defendRoll = nil
	end

	local slow = 120 + 30 * profile.EnergySkill -- below this, rebuild energy
	-- Start extending when slow (or damaged), keep going until back above 210 m/s.
	memory.extending = (memory.extending or ctx.me.speed < slow or ctx.me.damaged) and ctx.me.speed < 210
	if memory.extending then
		return "Extend"
	end

	if ctx.target then
		local range = Units.toMetres((ctx.target.cframe.Position - ctx.me.cframe.Position).Magnitude)
		if ctx.objective and range > AIBrain.OBJECTIVE_ENGAGE then
			return "Objective" -- the zone matters more than a distant enemy
		end
		return if range <= 1500 then "Attack" else "Engage"
	end
	return if ctx.objective then "Objective" else "Patrol"
end

function AIBrain.decide(memory: Memory, profile: Profile, ctx: Context): Decision
	local state = AIBrain.chooseState(memory, profile, ctx)
	if state ~= memory.state then
		memory.state = state
		memory.stateSince = ctx.now
	end
	local me = ctx.me
	local myPos = me.cframe.Position
	local decision: Decision = {
		state = state,
		aim = me.cframe.LookVector,
		throttle = 0.8,
		afterburner = false,
		overG = false,
		fire = false,
		flare = false,
		chaff = false,
	}

	-- How hard this pilot pulls: its skill limit, eased near corner speed by energy-aware pilots so they
	-- don't bleed all their speed away in a turning fight.
	local maxG = ctx.maxG or 7
	local corner = ctx.cornerSpeed or 180
	local gLimit = maxG * profile.MaxGUse
	if me.speed < corner then
		local sustainable = 1 + (gLimit - 1) * math.clamp((me.speed - 0.6 * corner) / (0.4 * corner), 0, 1)
		gLimit = gLimit + (sustainable - gLimit) * profile.EnergySkill
	end
	decision.gLimit = math.max(gLimit, 2.5)

	if state == "AvoidGround" then
		local heading = flat(me.cframe.LookVector)
		if ceilingDanger(ctx) then
			decision.aim = (heading - Vector3.new(0, 0.35, 0)).Unit
		else
			decision.aim = (heading + Vector3.new(0, 0.6, 0)).Unit
			decision.throttle = 1
			decision.afterburner = me.speed < 180
			decision.overG = true
			decision.gLimit = nil -- pull whatever it takes
		end
	elseif state == "Defend" and ctx.missile then
		local missile = ctx.missile
		local toMissile = flat(missile.position - myPos)
		-- Put the missile on the wing line (3 or 9 o'clock), turning the shorter way.
		local right = Vector3.new(-toMissile.Z, 0, toMissile.X)
		local side = if right:Dot(me.cframe.LookVector) >= 0 then right else -right
		local proper = (memory.defendRoll or 1) <= profile.FlareSkill
		if missile.kind == "IR" then
			decision.aim = (side - Vector3.new(0, 0.1, 0)).Unit
			decision.throttle = if proper then 0 else 1
			decision.afterburner = not proper
			decision.overG = proper
			if proper and ctx.now - memory.lastFlare >= 0.4 then
				memory.lastFlare = ctx.now
				decision.flare = true
			end
		else
			-- Notch: fly perpendicular to the radar missile and dive toward the ground clutter.
			decision.aim = (side - Vector3.new(0, 0.25, 0)).Unit
			decision.throttle = 1
			if proper and ctx.now - memory.lastFlare >= 0.6 then
				memory.lastFlare = ctx.now
				decision.chaff = true
			end
		end
		if outOfBounds(ctx) then
			decision.aim = flat(-myPos)
		end
	elseif state == "Extend" then
		decision.aim = (flat(me.cframe.LookVector) - Vector3.new(0, 0.2, 0)).Unit
		if outOfBounds(ctx) then
			decision.aim = (flat(-myPos) - Vector3.new(0, 0.1, 0)).Unit
		end
		decision.throttle = 1
		decision.afterburner = true
	elseif state == "Objective" and ctx.objective then
		-- Fly to the zone at a working height, then circle inside it
		local centre = Vector3.new(ctx.objective.position.X, Units.toStuds(1200), ctx.objective.position.Z)
		local offset = Vector3.new(myPos.X - centre.X, 0, myPos.Z - centre.Z)
		if offset.Magnitude < ctx.objective.radius * 0.6 then
			local tangent = Vector3.new(-offset.Z, 0, offset.X)
			tangent = if tangent.Magnitude > 1 then tangent.Unit else flat(me.cframe.LookVector)
			local climb = math.clamp((centre.Y - myPos.Y) / Units.toStuds(600), -0.3, 0.3)
			decision.aim = (tangent + Vector3.new(0, climb, 0)).Unit
			decision.throttle = 0.75
		else
			decision.aim = (centre - myPos).Unit
			decision.throttle = 0.9
		end
	elseif (state == "Attack" or state == "Engage") and ctx.target then
		local target = ctx.target
		local targetPos = target.cframe.Position
		local range = Units.toMetres((targetPos - myPos).Magnitude)
		if state == "Engage" then
			-- Pure pursuit, climbing if lower than the target, with afterburner when far.
			local climb = if targetPos.Y > myPos.Y + Units.toStuds(300) then 0.2 else 0
			decision.aim = ((targetPos - myPos).Unit + Vector3.new(0, climb, 0)).Unit
			decision.throttle = 1
			decision.afterburner = range > 3000 and profile.EnergySkill > 0.4
		else
			-- Lead pursuit with the gun solution (plus this pilot's aim error).
			local aim = (targetPos - myPos).Unit
			local tof: number? = nil
			if ctx.gun then
				local lead, t = Ballistics.leadDirection(
					myPos,
					me.velocity,
					targetPos,
					target.velocity,
					ctx.gun.MuzzleVelocity,
					ctx.gun.Lifetime
				)
				if lead then
					aim, tof = lead, t
				end
			end
			aim = (CFrame.lookAt(Vector3.zero, aim) * aimWobble(memory, profile, ctx.now)).LookVector
			-- Guns point along the nose, so steer the nose (not the flight path) onto the lead.
			decision.aim = aim
			decision.pointNose = true
			-- Energy: don't overshoot when closing fast; keep the burner lit if the fight gets slow.
			local closing = (me.velocity - target.velocity):Dot((targetPos - myPos).Unit)
			decision.throttle = if closing > 80 and range < 600 then 0.4 else 1
			decision.afterburner = decision.throttle >= 1 and me.speed < corner * 1.15 and profile.EnergySkill > 0.4
			if tof and range <= profile.GunRange then
				local off = math.acos(math.clamp(me.cframe.LookVector:Dot(aim), -1, 1)) / RAD
				decision.fire = off <= profile.FireTolerance
			end
		end
	else
		-- Patrol: waypoints inside the map, at a sensible altitude.
		local waypoint = memory.waypoint
		if not waypoint or (Vector3.new(waypoint.X, myPos.Y, waypoint.Z) - myPos).Magnitude < Units.toStuds(1500) then
			local r = ctx.mapHalfExtent * 0.55
			local i = math.floor(ctx.now)
			waypoint = Vector3.new(
				(rng(memory, i) * 2 - 1) * r,
				Units.toStuds(1500 + rng(memory, i + 1) * 1500),
				(rng(memory, i + 2) * 2 - 1) * r
			)
			memory.waypoint = waypoint
		end
		decision.aim = ((waypoint :: Vector3) - myPos).Unit
		decision.throttle = 0.8
	end

	return decision
end

return AIBrain
