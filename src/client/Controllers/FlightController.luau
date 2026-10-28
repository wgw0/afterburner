--!strict
-- Flies the local player's jet (DEVELOPMENT.md §6.3). Every frame before physics:
--   read the jet's real CFrame/velocity -> FlightModel.step -> write LinearVelocity/AngularVelocity.
-- The pilot owns the jet's physics, so Roblox replicates the result to everyone else.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Progression = require(Shared.Progression)
local DamageModel = require(Shared.DamageModel)
local Flight = require(Shared.Config.Flight)
local FlightModel = require(Shared.FlightModel)
local Instructor = require(Shared.Instructor)
local Net = require(Shared.Net)
local Signal = require(Shared.Util.Signal)
local Types = require(Shared.Types)
local Units = require(Shared.Units)

local InputController = require(script.Parent.InputController)

type FlightState = Types.FlightState

local TELEMETRY_INTERVAL = 0.2
local localPlayer = Players.LocalPlayer

local FlightController = {
	Priority = 30,
	jet = nil :: Model?,
	root = nil :: BasePart?,
	airframe = nil :: any, -- a mutable copy, so the debug panel can tune it live
	state = nil :: FlightState?,
	input = nil :: Types.ControlInput?,
	glocUntil = 0,
	damage = {} :: { [string]: number }, -- component health fractions from the server
	mods = nil :: any, -- flight model modifiers from damage
	JetChanged = Signal.new(), -- (jet or nil)
	Crashed = Signal.new(),
}

local linear: LinearVelocity?
local angular: AngularVelocity?
local telemetryTimer = 0
local crashed = false

local function clearJet()
	FlightController.jet = nil
	FlightController.root = nil
	FlightController.state = nil
	linear, angular = nil, nil
	InputController:SetEnabled(false)
	FlightController.JetChanged:Fire(nil)
end

local function adoptJet(model: Model)
	local airframe = Progression.airframeForModel(model)
	local root = model.PrimaryPart or model:WaitForChild("Root", 5) :: BasePart?
	if not (airframe and root) then
		return
	end
	FlightController.jet = model
	FlightController.root = root
	FlightController.airframe = table.clone(airframe)
	linear = root:WaitForChild("FlightLinear", 5) :: LinearVelocity?
	angular = root:WaitForChild("FlightAngular", 5) :: AngularVelocity?
	local speed = Units.velocityFromStuds(root.AssemblyLinearVelocity.Magnitude)
	FlightController.state = FlightModel.newState(root.CFrame, math.max(speed, Flight.SPAWN_SPEED), airframe)
	FlightController.glocUntil = 0
	FlightController.damage = {}
	FlightController.mods = nil
	crashed = false
	InputController:ResetForJet(root.CFrame)
	InputController:SetEnabled(true)
	FlightController.JetChanged:Fire(model)

	model.AncestryChanged:Connect(function()
		if not model:IsDescendantOf(workspace) and FlightController.jet == model then
			clearJet()
		end
	end)
end

local function isMine(model: Instance): boolean
	return model:IsA("Model") and model:GetAttribute("PilotUserId") == localPlayer.UserId
end

-- During G-LOC the pilot is out: hold the wings level and keep the throttle.
local function unconsciousInput(state: FlightState, airframe: any): Types.ControlInput
	local flat = Vector3.new(state.cframe.LookVector.X, 0, state.cframe.LookVector.Z)
	local aim = if flat.Magnitude > 1e-3 then flat.Unit else state.cframe.LookVector
	return Instructor.compute(state, aim, airframe, {
		throttle = InputController.throttle,
		afterburner = false,
	})
end

local function step(dt: number)
	local root, state, airframe = FlightController.root, FlightController.state, FlightController.airframe
	if not (root and state and linear and angular) or crashed then
		return
	end

	-- Physics is the source of truth for position and velocity (collisions included).
	state.cframe = root.CFrame
	state.velocity = Units.velocityFromStuds(root.AssemblyLinearVelocity)

	local now = os.clock()
	if state.gStress >= 1 and now >= FlightController.glocUntil then
		FlightController.glocUntil = now + Flight.GLOC_DURATION
	end
	local unconscious = now < FlightController.glocUntil
	local input = if unconscious
		then unconsciousInput(state, airframe)
		else InputController:GetControlInput(state, airframe)
	FlightController.input = input

	local nextState = FlightModel.step(state, input, airframe, dt, FlightController.mods)
	if unconscious then
		-- Recovery begins as consciousness returns.
		nextState.gStress = if now + dt >= FlightController.glocUntil then Flight.GLOC_RECOVERY_STRESS else 1
	end
	FlightController.state = nextState

	linear.VectorVelocity = Units.velocityToStuds(nextState.velocity)
	angular.AngularVelocity = nextState.angularVelocity

	-- Ground impact: look ahead along the flight path (Phase 2 moves crash rules to the server).
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { FlightController.jet :: Model }
	local travel = Units.velocityToStuds(nextState.velocity) * dt * 1.5
	local hit = workspace:Raycast(root.Position, travel + travel.Unit * 2.2, params)
	if hit then
		crashed = true
		linear.VectorVelocity = Vector3.zero
		angular.AngularVelocity = Vector3.zero
		FlightController.Crashed:Fire(hit.Position)
		Net.Client.fire("ReportCrash")
		return
	end

	telemetryTimer += dt
	if telemetryTimer >= TELEMETRY_INTERVAL then
		telemetryTimer = 0
		Net.Client.fire(
			"FlightTelemetry",
			math.clamp(input.throttle, 0, 1),
			input.afterburner,
			math.clamp(nextState.gLoad, -20, 20)
		)
	end
end

function FlightController:IsUnconscious(): boolean
	return os.clock() < self.glocUntil
end

function FlightController:Init()
	Net.Client.on("DamageState", function(fractions: { [string]: number })
		self.damage = fractions
		self.mods = DamageModel.modifiers(fractions)
	end)
end

function FlightController:Start()
	local jets = workspace:WaitForChild("Jets")
	jets.ChildAdded:Connect(function(child)
		if isMine(child) then
			adoptJet(child :: Model)
		end
	end)
	for _, child in jets:GetChildren() do
		if isMine(child) then
			adoptJet(child :: Model)
		end
	end
	RunService.PreSimulation:Connect(function(dt)
		debug.profilebegin("FlightController.step")
		step(dt)
		debug.profileend()
	end)
end

return FlightController
