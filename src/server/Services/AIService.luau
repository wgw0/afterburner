--!strict
-- AI pilots (DEVELOPMENT.md §18, AI-01/02/03). Server-flown jets using the same FlightModel and Instructor
-- as players, steered by AIBrain: patrol, engage, attack with guns, defend missiles (break, flares, chaff,
-- notch), extend for energy, and avoid terrain and the map edge.
--
-- MatchService decides how many AI pilots there should be and when they may (re)spawn; this service owns
-- their identities, flies their jets and pulls their triggers.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AIBrain = require(Shared.AIBrain)
local AircraftData = require(Shared.AircraftData)
local DamageModel = require(Shared.DamageModel)
local FlightModel = require(Shared.FlightModel)
local Guidance = require(Shared.Guidance)
local Instructor = require(Shared.Instructor)
local Scale = require(Shared.Config.Scale)
local Units = require(Shared.Units)
local WeaponData = require(Shared.WeaponData)

local AircraftService = require(script.Parent.AircraftService)
local CombatService = require(script.Parent.CombatService)
local MissileService = require(script.Parent.MissileService)
local SensorService = require(script.Parent.SensorService)
local Teams = require(ServerScriptService.Server.Lib.Teams)

type Jet = AircraftService.Jet

export type Pilot = {
	identity: { Name: string, UserId: number, IsAI: boolean, Difficulty: string },
	profile: AIBrain.Profile,
	jet: Jet?,
	airframe: any,
	state: any,
	memory: AIBrain.Memory,
	decision: AIBrain.Decision?,
	targetId: number?,
	groundClearance: number, -- real metres
	seed: number,
	triggerDown: boolean,
	timers: { decide: number, target: number, ground: number, attributes: number, missile: number },
	linear: LinearVelocity?,
	angular: AngularVelocity?,
	training: Player?, -- a training bout (lesson 6): fights only this player and isn't part of the match
}

local CALLSIGNS = {
	"Viper",
	"Raven",
	"Ghost",
	"Falcon",
	"Hawk",
	"Cobra",
	"Jester",
	"Maverick",
	"Iceman",
	"Talon",
	"Blaze",
	"Saber",
	"Wolf",
	"Lynx",
	"Comet",
	"Spectre",
	"Havoc",
	"Nomad",
	"Reaper",
	"Banshee",
	"Crow",
	"Kestrel",
	"Vandal",
	"Rogue",
}
local AIRFRAMES = { "F5E", "MiG21bis" }
local DECIDE_INTERVAL = 0.1
local TARGET_INTERVAL = 1
local GROUND_INTERVAL = 0.25
local ATTRIBUTE_INTERVAL = 0.2
local TARGET_RANGE = 9000 -- real metres

local AIService = {
	Priority = 36,
	-- Set by MatchService in Air Superiority: the zone this pilot should take or hold (nil = none)
	objectiveFor = nil :: ((pilot: any) -> { position: Vector3, radius: number }?)?,
}

local pilots: { Pilot } = {}
local nextSeed = 0
local groundParams: RaycastParams

function AIService:GetPilots(): { Pilot }
	return pilots
end

-- The match's AI pilots: everyone except training-bout opponents (MatchService fills, spawns and scores
-- only these).
function AIService:GetMatchPilots(): { Pilot }
	local list = {}
	for _, pilot in pilots do
		if not pilot.training then
			table.insert(list, pilot)
		end
	end
	return list
end

-- A training-bout opponent (TUT-03 lesson 6): an Easy pilot that fights only `trainee`.
function AIService:CreateTrainingPilot(trainee: Player, airframeId: string): Pilot
	local pilot = self:CreatePilot("Easy", airframeId)
	pilot.training = trainee
	return pilot
end

-- Creates a new AI pilot (not yet flying). Returns its record.
function AIService:CreatePilot(difficulty: string?, airframeId: string?): Pilot
	nextSeed += 1
	local profileName = difficulty or "Normal"
	local name = `{CALLSIGNS[(nextSeed - 1) % #CALLSIGNS + 1]} [AI]`
	airframeId = airframeId or AIRFRAMES[(nextSeed - 1) % #AIRFRAMES + 1]
	local pilot: Pilot = {
		identity = { Name = name, UserId = 0, IsAI = true, Difficulty = profileName },
		profile = (AIBrain.PROFILES :: any)[profileName] or AIBrain.PROFILES.Normal,
		jet = nil,
		airframe = AircraftData.get(airframeId),
		state = nil,
		memory = AIBrain.newMemory(nextSeed * 31),
		decision = nil,
		targetId = nil,
		groundClearance = 3000,
		seed = nextSeed,
		triggerDown = false,
		timers = { decide = 0, target = 0, ground = 0, attributes = 0, missile = 5 },
		linear = nil,
		angular = nil,
	}
	table.insert(pilots, pilot)
	return pilot
end

-- Changes the jet an AI pilot flies next time it spawns (BR matching).
function AIService:SetAirframe(pilot: Pilot, airframeId: string)
	local airframe = AircraftData.get(airframeId)
	if airframe then
		pilot.airframe = airframe
	end
end

function AIService:RemovePilot(pilot: Pilot)
	if pilot.jet then
		AircraftService:Despawn(pilot.jet, "Despawn")
	end
	local index = table.find(pilots, pilot)
	if index then
		table.remove(pilots, index)
	end
end

function AIService:RemoveAll()
	for i = #pilots, 1, -1 do
		self:RemovePilot(pilots[i])
	end
end

function AIService:SpawnPilot(pilot: Pilot, cframe: CFrame)
	local jet =
		AircraftService:Spawn(nil, pilot.airframe.Id, cframe, { identity = pilot.identity, name = pilot.identity.Name })
	if not jet then
		return
	end
	pilot.jet = jet
	pilot.state = FlightModel.newState(cframe, 220, pilot.airframe)
	pilot.memory = AIBrain.newMemory(pilot.seed * 31 + math.floor(os.clock()))
	pilot.linear = jet.root:FindFirstChild("FlightLinear") :: LinearVelocity
	pilot.angular = jet.root:FindFirstChild("FlightAngular") :: AngularVelocity
	pilot.triggerDown = false
end

local function chooseTarget(pilot: Pilot): Jet?
	local me = pilot.jet :: Jet
	if pilot.training then
		return AircraftService:GetJet(pilot.training) -- a training opponent only fights its trainee
	end
	local best, bestCost = nil, math.huge
	for id, other in AircraftService:GetJets() do
		if
			id ~= me.id
			and other.identity ~= pilot.identity
			and not Teams.areFriends(pilot.identity, other.identity)
		then
			local offset = other.root.Position - me.root.Position
			local range = Units.toMetres(offset.Magnitude)
			if range <= TARGET_RANGE then
				local angle = math.acos(math.clamp(me.root.CFrame.LookVector:Dot(offset.Unit), -1, 1))
				local cost = range * (1 + angle / math.pi * 1.5)
				if cost < bestCost then
					best, bestCost = other, cost
				end
			end
		end
	end
	return best
end

-- Missiles (AI-04): heat-seekers when the seeker sees the target, radar missiles once locked. Paced by
-- the profile's MissileInterval; retries shortly while a seeker is still settling or a lock is building.
local function tryMissile(pilot: Pilot, jet: any, target: any)
	local range = Units.toMetres((target.root.Position - jet.root.Position).Magnitude)
	local options = {}
	for _, slot in MissileService:Slots(jet) do
		local isIR = WeaponData.isIR(slot.spec)
		table.insert(options, {
			index = slot.index,
			class = if isIR then "IR" else "Radar",
			count = slot.count,
			minRange = slot.spec.MinRange,
			maxRange = slot.spec.MaxRange,
			irLockable = isIR and Guidance.irLockable(
				slot.spec,
				jet.root.CFrame,
				target.root.CFrame,
				(target.model:GetAttribute("Throttle") :: number?) or 0.85,
				target.model:GetAttribute("Afterburner") == true
			),
		})
	end
	local airframe = pilot.airframe :: any
	local choice, needsLock = AIBrain.chooseMissile(pilot.profile, options, range, airframe.Radar ~= nil)
	if not choice then
		pilot.timers.missile = 1
		return
	end
	MissileService:SelectSlot(jet, choice.index)
	if needsLock and SensorService:GetLock(jet.id) ~= target.id then
		SensorService:RequestLock(jet, target)
		pilot.timers.missile = 1 -- give the lock a moment
		return
	end
	if choice.class == "IR" and not MissileService:SeekerReady(jet, target.id) then
		pilot.timers.missile = 0.3 -- the seeker is still settling on the target
		return
	end
	if MissileService:FireFor(jet, target.id) then
		pilot.timers.missile = pilot.profile.MissileInterval
	else
		pilot.timers.missile = 1
	end
end

local function stepPilot(pilot: Pilot, dt: number)
	local jet = pilot.jet
	if not (jet and AircraftService:GetJetById(jet.id) and pilot.linear and pilot.angular) then
		pilot.jet = nil
		return
	end
	local root = jet.root
	local state = pilot.state
	state.cframe = root.CFrame
	state.velocity = Units.velocityFromStuds(root.AssemblyLinearVelocity)

	local timers = pilot.timers
	timers.decide -= dt
	timers.target -= dt
	timers.ground -= dt
	timers.attributes -= dt
	timers.missile -= dt

	if timers.ground <= 0 then
		timers.ground = GROUND_INTERVAL
		local hit = workspace:Raycast(root.Position, Vector3.new(0, -Units.toStuds(4000), 0), groundParams)
		pilot.groundClearance = if hit
			then Units.toMetres(root.Position.Y - hit.Position.Y)
			else Units.altitudeMetres(root.Position.Y)
		-- Terrain ahead (hillsides, mountains): the distance to it along the next 5 s of flight counts as
		-- clearance too, so the brain pulls up before the slope instead of over it.
		local path = root.AssemblyLinearVelocity * 5
		if path.Magnitude > 1 then
			local ahead = workspace:Raycast(root.Position, path, groundParams)
			if ahead then
				local distance = Units.toMetres((ahead.Position - root.Position).Magnitude)
				pilot.groundClearance = math.min(pilot.groundClearance, distance * 0.3)
			end
		end
	end
	if timers.target <= 0 then
		timers.target = TARGET_INTERVAL
		local target = chooseTarget(pilot)
		pilot.targetId = target and target.id
	end

	if timers.decide <= 0 or not pilot.decision then
		timers.decide = DECIDE_INTERVAL
		local target = if pilot.targetId then AircraftService:GetJetById(pilot.targetId) else nil
		local fractions = CombatService:GetFractions(jet.id)
		local airframe = pilot.airframe
		local gun = WeaponData.get(airframe.Gun)
		pilot.decision = AIBrain.decide(pilot.memory, pilot.profile, {
			now = os.clock(),
			me = {
				cframe = root.CFrame,
				velocity = state.velocity,
				speed = state.velocity.Magnitude,
				altitude = Units.altitudeMetres(root.Position.Y),
				groundClearance = pilot.groundClearance,
				damaged = fractions ~= nil and (fractions.Engine or 1) < 0.5,
				aoa = state.aoa,
			},
			target = if target
				then {
					id = target.id,
					cframe = target.root.CFrame,
					velocity = Units.velocityFromStuds(target.root.AssemblyLinearVelocity),
				}
				else nil,
			missile = MissileService:IncomingFor(jet.id),
			gun = gun,
			mapHalfExtent = Scale.MAP_HALF_EXTENT,
			ceiling = Scale.CEILING,
			maxG = airframe.MaxG,
			cornerSpeed = FlightModel.cornerSpeed(airframe, Units.altitudeMetres(root.Position.Y)),
			objective = if AIService.objectiveFor then AIService.objectiveFor(pilot) else nil,
		})
		local decision = pilot.decision :: AIBrain.Decision
		if decision.fire ~= pilot.triggerDown then
			pilot.triggerDown = decision.fire
			CombatService:SetTrigger(jet, decision.fire, pilot.seed * 1000 + math.floor(os.clock()))
		end
		if decision.flare then
			MissileService:DeployCountermeasure(jet, "Flare")
		end
		if target and timers.missile <= 0 and (decision.state == "Attack" or decision.state == "Engage") then
			tryMissile(pilot, jet, target)
		end
		if decision.chaff then
			MissileService:DeployCountermeasure(jet, "Chaff")
		end
	end

	local decision = pilot.decision :: AIBrain.Decision
	local input = Instructor.compute(state, decision.aim, pilot.airframe, {
		allowOverG = decision.overG,
		gLimit = decision.gLimit,
		pointNose = decision.pointNose,
		throttle = decision.throttle,
		afterburner = decision.afterburner,
	})
	local fractions = CombatService:GetFractions(jet.id)
	local mods = if fractions then DamageModel.modifiers(fractions) else nil
	pilot.state = FlightModel.step(state, input, pilot.airframe, dt, mods)
	pilot.linear.VectorVelocity = Units.velocityToStuds(pilot.state.velocity)
	pilot.angular.AngularVelocity = pilot.state.angularVelocity

	-- Effects attributes for clients (players send these as telemetry; AI jets are server-owned)
	if timers.attributes <= 0 then
		timers.attributes = ATTRIBUTE_INTERVAL
		jet.model:SetAttribute("Throttle", math.round(input.throttle * 100) / 100)
		jet.model:SetAttribute("Afterburner", input.afterburner)
		jet.model:SetAttribute("GLoad", math.round(pilot.state.gLoad * 10) / 10)
	end
end

function AIService:Init()
	groundParams = RaycastParams.new()
	groundParams.FilterType = Enum.RaycastFilterType.Exclude
	groundParams.FilterDescendantsInstances = { workspace:WaitForChild("Jets") }
	AircraftService.JetDestroyed:Connect(function(jet)
		for _, pilot in pilots do
			if pilot.jet == jet then
				pilot.jet = nil
				pilot.triggerDown = false
			end
		end
	end)
end

function AIService:Start()
	RunService.Heartbeat:Connect(function(dt)
		debug.profilebegin("AIService.step")
		for _, pilot in pilots do
			if pilot.jet then
				stepPilot(pilot, dt)
			end
		end
		debug.profileend()
	end)
end

return AIService
