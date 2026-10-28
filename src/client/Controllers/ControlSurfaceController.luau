--!strict
-- Moves every nearby jet's control surfaces (art pipeline §5). Surfaces hang off Root on Motor6Ds; this
-- sets each Motor6D's Transform on this client only, so it costs no network traffic. The local pilot's
-- jet follows the stick; everyone else's follows how the jet is actually moving (body rates), which
-- needs no extra replication and also works for AI.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ControlSurfaces = require(Shared.ControlSurfaces)
local Progression = require(Shared.Progression)
local Units = require(Shared.Units)

local FlightController = require(script.Parent.FlightController)

local CULL_DISTANCE = 420 -- studs (~420 m) from the camera; further away nobody can see the surfaces move
local RATE = 120 -- degrees per second of surface travel (actuator speed)

type Surface = {
	motor: Motor6D,
	control: string,
	axis: Vector3,
	min: number,
	max: number,
	current: number,
}

type Rig = {
	root: BasePart,
	airframe: any,
	surfaces: { Surface },
}

local ControlSurfaceController = {
	Priority = 60,
}

local rigs: { [Model]: Rig } = {}

local function buildRig(model: Model)
	local root = model.PrimaryPart
	local airframe = Progression.airframeForModel(model)
	if not (root and airframe) then
		return
	end
	local surfaces: { Surface } = {}
	for _, d in model:GetDescendants() do
		if not d:IsA("Motor6D") then
			continue
		end
		local part = d.Part1
		local control = part and part:GetAttribute("Control")
		local axis = part and part:GetAttribute("HingeAxis")
		if typeof(control) == "string" and ControlSurfaces.ANIMATED[control] and typeof(axis) == "Vector3" then
			table.insert(surfaces, {
				motor = d,
				control = control,
				axis = axis.Unit,
				min = (part :: BasePart):GetAttribute("HingeMin") or -20,
				max = (part :: BasePart):GetAttribute("HingeMax") or 20,
				current = 0,
			})
		end
	end
	if #surfaces > 0 then
		rigs[model] = { root = root, airframe = airframe, surfaces = surfaces }
	end
end

local function commandsFor(model: Model, rig: Rig): ControlSurfaces.Commands
	local root = rig.root
	local velocity = Units.velocityFromStuds(root.AssemblyLinearVelocity)
	local fromMotion = ControlSurfaces.fromMotion(root.CFrame, root.AssemblyAngularVelocity, velocity, rig.airframe)
	local input = FlightController.input
	if model == FlightController.jet and input then
		-- Our own jet answers the stick straight away, before the jet has started to turn
		return { pitch = input.pitch, roll = input.roll, yaw = input.yaw, flap = fromMotion.flap }
	end
	return fromMotion
end

local function update(dt: number)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local eye = camera.CFrame.Position
	local step = RATE * dt
	for model, rig in rigs do
		if not model.Parent then
			rigs[model] = nil
			continue
		end
		if (rig.root.Position - eye).Magnitude > CULL_DISTANCE then
			continue
		end
		local commands = commandsFor(model, rig)
		for _, s in rig.surfaces do
			local target = ControlSurfaces.deflection(s.control, commands, s.min, s.max)
			s.current += math.clamp(target - s.current, -step, step)
			s.motor.Transform = CFrame.fromAxisAngle(s.axis, ControlSurfaces.hingeAngle(s.control, s.axis, s.current))
		end
	end
end

function ControlSurfaceController:Start()
	local jets = workspace:WaitForChild("Jets")
	jets.ChildAdded:Connect(function(child)
		if child:IsA("Model") then
			task.delay(0.5, buildRig, child) -- let the whole model replicate first
		end
	end)
	jets.ChildRemoved:Connect(function(child)
		if child:IsA("Model") then
			rigs[child] = nil
		end
	end)
	for _, child in jets:GetChildren() do
		if child:IsA("Model") then
			buildRig(child)
		end
	end
	RunService.RenderStepped:Connect(function(dt)
		debug.profilebegin("ControlSurfaceController.update")
		update(dt)
		debug.profileend()
	end)
end

return ControlSurfaceController
