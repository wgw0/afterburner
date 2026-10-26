--!strict
-- Target drones for solo gun testing (test environment only). Server-flown jets using the same
-- FlightModel and Instructor as players, so they move like real aircraft and fly worse as they're
-- damaged. The foundation for the AI pilots in Phase 4 (AI-01).
--   "ahead":  appears 700 studs ahead along your nose (in your gunsight), same heading, slightly slower
--   "circle": orbits the test range at a steady bank

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
local CIRCLE_CENTRE = Vector3.new(300, 0, 0)
local CIRCLE_RADIUS = 2600 -- studs

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

local function spawnDrone(mode: string, near: AircraftService.Jet?)
	if count() >= MAX_DRONES then
		return
	end
	local airframeId = "MiG21bis"
	local cframe: CFrame
	local speed = 200
	if mode == "ahead" and near then
		local flat = Vector3.new(near.root.CFrame.LookVector.X, 0, near.root.CFrame.LookVector.Z)
		flat = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.new(0, 0, -1)
		local position = near.root.Position + near.root.CFrame.LookVector * 700
		cframe = CFrame.lookAt(position, position + flat)
		speed = math.max(Units.velocityFromStuds(near.root.AssemblyLinearVelocity.Magnitude) - 15, 150)
	else
		local position = CIRCLE_CENTRE + Vector3.new(CIRCLE_RADIUS, 1100, 0)
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
		-- Fly the tangent of the circle, nudged back toward the radius and to 1,100 studs altitude.
		local position = drone.jet.root.Position
		local fromCentre = Vector3.new(position.X - CIRCLE_CENTRE.X, 0, position.Z - CIRCLE_CENTRE.Z)
		local radial = if fromCentre.Magnitude > 1 then fromCentre.Unit else Vector3.new(1, 0, 0)
		local tangent = Vector3.new(radial.Z, 0, -radial.X)
		local radiusError = (fromCentre.Magnitude - CIRCLE_RADIUS) / CIRCLE_RADIUS
		local altitudeError = (1100 - position.Y) / 1100
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
	if not Environment.isTest() then
		return
	end
	Net.Server.on("DebugSpawnDrone", function(player: Player, mode: string)
		if mode ~= "ahead" and mode ~= "circle" then
			return
		end
		spawnDrone(mode, AircraftService:GetJet(player))
	end)
end

function DroneService:Start()
	if not Environment.isTest() then
		return
	end
	RunService.Heartbeat:Connect(step)
end

return DroneService
