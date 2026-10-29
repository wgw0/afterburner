--!strict
-- Target drones for solo gun testing (test environment only). Server-flown jets using the same
-- FlightModel and Instructor as players, so they move like real aircraft and fly worse as they're
-- damaged. The foundation for the AI pilots in Phase 4 (AI-01).
--   "ahead":  appears 200 studs ahead along your nose (in your gunsight), same heading, slightly slower
--   "far":    the same, 600 studs ahead (past heat-seekers' minimum range, for the missile lesson)
--   "circle": orbits the test range at a steady bank
-- Training bouts (TrainingBout, lesson 6): an Easy AI pilot (AIService:CreateTrainingPilot) that turns to
-- fight only you, in Free Flight. It goes when it or you are shot down, or you leave.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AircraftData = require(Shared.AircraftData)
local DamageModel = require(Shared.DamageModel)
local Environment = require(Shared.Config.Environment)
local FlightModel = require(Shared.FlightModel)
local Instructor = require(Shared.Instructor)
local Net = require(Shared.Net)
local Units = require(Shared.Units)

local AIService = require(script.Parent.AIService)
local AircraftService = require(script.Parent.AircraftService)
local CombatService = require(script.Parent.CombatService)

type Drone = {
	jet: AircraftService.Jet,
	airframe: any,
	state: any,
	mode: string,
	heading: Vector3, -- "ahead": the direction to hold
	linear: LinearVelocity,
	angular: AngularVelocity,
}

local MAX_DRONES = 6
local CIRCLE_CENTRE = Vector3.new(84, 0, 0)
local CIRCLE_RADIUS = 730 -- studs

local DroneService = {
	Priority = 40,
}

local drones: { [number]: Drone } = {}

local function count(): number
	local n = 0
	for _ in drones do
		n += 1
	end
	return n
end

local bouts: { [Player]: any } = {} -- training bouts: player → their AI opponent

local function spawnDrone(mode: string, near: AircraftService.Jet?)
	if count() >= MAX_DRONES then
		return
	end
	local airframeId = "MiG21bis"
	local cframe: CFrame
	local speed = 200
	if (mode == "ahead" or mode == "far") and near then
		local flat = Vector3.new(near.root.CFrame.LookVector.X, 0, near.root.CFrame.LookVector.Z)
		flat = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.new(0, 0, -1)
		local position = near.root.Position + near.root.CFrame.LookVector * (if mode == "far" then 600 else 200)
		cframe = CFrame.lookAt(position, position + flat)
		speed = math.max(Units.velocityFromStuds(near.root.AssemblyLinearVelocity.Magnitude) - 15, 150)
	else
		local position = CIRCLE_CENTRE + Vector3.new(CIRCLE_RADIUS, 310, 0)
		cframe = CFrame.lookAt(position, position + Vector3.new(0, 0, -1))
	end

	local jet = AircraftService:Spawn(nil, airframeId, cframe, { name = "Target drone", speed = speed })
	if not jet then
		return
	end
	local airframe = AircraftData.get(airframeId)
	drones[jet.id] = {
		jet = jet,
		airframe = airframe,
		state = FlightModel.newState(cframe, speed, airframe :: any),
		mode = mode,
		heading = cframe.LookVector,
		linear = jet.root:FindFirstChild("FlightLinear") :: LinearVelocity,
		angular = jet.root:FindFirstChild("FlightAngular") :: AngularVelocity,
	}
end

local function aimFor(drone: Drone): Vector3
	if drone.mode == "circle" then
		-- Fly the tangent of the circle, nudged back toward the radius and to 310 studs altitude.
		local position = drone.jet.root.Position
		local fromCentre = Vector3.new(position.X - CIRCLE_CENTRE.X, 0, position.Z - CIRCLE_CENTRE.Z)
		local radial = if fromCentre.Magnitude > 1 then fromCentre.Unit else Vector3.new(1, 0, 0)
		local tangent = Vector3.new(radial.Z, 0, -radial.X)
		local radiusError = (fromCentre.Magnitude - CIRCLE_RADIUS) / CIRCLE_RADIUS
		local altitudeError = (310 - position.Y) / 310
		return (tangent - radial * radiusError * 2 + Vector3.new(0, altitudeError * 0.5, 0)).Unit
	end
	return drone.heading
end

local function step(dt: number)
	for id, drone in drones do
		if AircraftService:GetJetById(id) == nil then
			drones[id] = nil
			continue
		end
		local root = drone.jet.root
		drone.state.cframe = root.CFrame
		drone.state.velocity = Units.velocityFromStuds(root.AssemblyLinearVelocity)
		local input = Instructor.compute(drone.state, aimFor(drone), drone.airframe, { throttle = 0.85 })
		local fractions = CombatService:GetFractions(id)
		local mods = if fractions then DamageModel.modifiers(fractions) else nil
		drone.state = FlightModel.step(drone.state, input, drone.airframe, dt, mods)
		drone.linear.VectorVelocity = Units.velocityToStuds(drone.state.velocity)
		drone.angular.AngularVelocity = drone.state.angularVelocity
	end
end

function DroneService:Init()
	-- Target drones: always in the test environment, and in Free Flight anywhere (the tutorial uses them).
	Net.Server.on("DebugSpawnDrone", function(player: Player, mode: string)
		local freeFlight = ReplicatedStorage:GetAttribute("GameMode") == "FreeFlight"
		if not (Environment.isTest() or freeFlight) or (mode ~= "ahead" and mode ~= "far" and mode ~= "circle") then
			return
		end
		spawnDrone(mode, AircraftService:GetJet(player))
	end)

	-- Training bouts: one Easy opponent per player, Free Flight only
	local function endBout(player: Player)
		local pilot = bouts[player]
		bouts[player] = nil
		if pilot then
			AIService:RemovePilot(pilot)
		end
	end
	Net.Server.on("TrainingBout", function(player: Player, start: boolean)
		endBout(player)
		local jet = AircraftService:GetJet(player)
		if not start or not jet or ReplicatedStorage:GetAttribute("GameMode") ~= "FreeFlight" then
			return
		end
		-- Head-on, 2,500 studs ahead at your height: a merge, then a fight
		local pilot = AIService:CreateTrainingPilot(player, jet.airframeId)
		bouts[player] = pilot
		local flat = Vector3.new(jet.root.CFrame.LookVector.X, 0, jet.root.CFrame.LookVector.Z)
		flat = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.new(0, 0, -1)
		local position = jet.root.Position + flat * 2500
		AIService:SpawnPilot(
			pilot,
			CFrame.lookAt(position, Vector3.new(jet.root.Position.X, position.Y, jet.root.Position.Z))
		)
	end)
	AircraftService.JetDestroyed:Connect(function(jet)
		for player, pilot in bouts do
			if pilot.jet == jet or jet.pilot == player then
				task.defer(endBout, player)
			end
		end
	end)
	Players.PlayerRemoving:Connect(endBout)
end

function DroneService:Start()
	RunService.Heartbeat:Connect(step)
end

return DroneService
