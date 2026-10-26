--!strict
-- AI pilots (DEVELOPMENT.md §18, AI-01/02/03). Server-flown jets using the same FlightModel and Instructor
-- as players, steered by AIBrain: patrol, engage, attack with guns, defend missiles (break, flares, chaff,
-- notch), extend for energy, and avoid terrain and the map edge.
--
-- MatchService decides how many AI pilots there should be and when they may (re)spawn; this service owns
-- their identities, flies their jets and pulls their triggers.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AIBrain = require(Shared.AIBrain)
local AircraftData = require(Shared.AircraftData)
local DamageModel = require(Shared.DamageModel)
local FlightModel = require(Shared.FlightModel)
local Instructor = require(Shared.Instructor)
local Scale = require(Shared.Config.Scale)
local Units = require(Shared.Units)
local WeaponData = require(Shared.WeaponData)

local AircraftService = require(script.Parent.AircraftService)
local CombatService = require(script.Parent.CombatService)
local MissileService = require(script.Parent.MissileService)

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
	timers: { decide: number, target: number, ground: number, attributes: number },
	linear: LinearVelocity?,
	angular: AngularVelocity?,
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
}

local pilots: { Pilot } = {}
local nextSeed = 0
local groundParams: RaycastParams

function AIService:GetPilots(): { Pilot }
	return pilots
end

-- Creates a new AI pilot (not yet flying). Returns its record.
function AIService:CreatePilot(difficulty: string?): Pilot
	nextSeed += 1
	local profileName = difficulty or "Normal"
	local name = `{CALLSIGNS[(nextSeed - 1) % #CALLSIGNS + 1]} [AI]`
	local airframeId = AIRFRAMES[(nextSeed - 1) % #AIRFRAMES + 1]
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
		timers = { decide = 0, target = 0, ground = 0, attributes = 0 },
		linear = nil,
		angular = nil,
	}
	table.insert(pilots, pilot)
	return pilot
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
	local best, bestCost = nil, math.huge
	for id, other in AircraftService:GetJets() do
		if id ~= me.id and other.identity ~= pilot.identity then
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
		})
		local decision = pilot.decision :: AIBrain.Decision
		if decision.fire ~= pilot.triggerDown then
			pilot.triggerDown = decision.fire
			CombatService:SetTrigger(jet, decision.fire, pilot.seed * 1000 + math.floor(os.clock()))
		end
		if decision.flare then
			MissileService:DeployCountermeasure(jet, "Flare")
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
