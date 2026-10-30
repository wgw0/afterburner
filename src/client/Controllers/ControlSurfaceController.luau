--!strict
-- Moves every nearby jet's control surfaces (art pipeline §5). Surfaces hang off Root on Motor6Ds; this
-- sets each Motor6D's Transform on this client only, so it costs no network traffic. The local pilot's
-- jet follows the stick; everyone else's follows how the jet is actually moving (body rates), which
-- needs no extra replication and also works for AI.
-- Swing wings (FLT-08): on a jet with VariableGeometry each wing's weld becomes a Motor6D at its pivot and
-- sweeps toward FlightModel.sweep for the jet's Mach (at SWEEP_RATE, like the real actuators); the flaps
-- and slats are re-hung on the wing so they swing with it, and the wingtip attachments (contrails, vapour)
-- follow the tips.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Atmosphere = require(Shared.Atmosphere)
local ControlSurfaces = require(Shared.ControlSurfaces)
local FlightModel = require(Shared.FlightModel)
local Progression = require(Shared.Progression)
local Units = require(Shared.Units)

local FlightController = require(script.Parent.FlightController)

local CULL_DISTANCE = 420 -- studs (~420 m) from the camera; further away nobody can see the surfaces move
local RATE = 120 -- degrees per second of surface travel (actuator speed)
local SWEEP_RATE = 15 -- degrees per second of wing sweep
local ON_WING = { "Flap", "LEFlap", "Slat", "Spoiler", "Aileron" } -- surfaces that ride on a swing wing

type Surface = {
	motor: Motor6D,
	control: string,
	axis: Vector3,
	min: number,
	max: number,
	current: number,
}

type Wing = {
	motor: Motor6D,
	side: number, -- +1 left, -1 right: the sign that sweeps the tip aft
	pivot: Vector3, -- in Root space
	tips: { [Attachment]: Vector3 }, -- wingtip attachments on Root and their positions at the model's sweep
}

type Rig = {
	root: BasePart,
	airframe: any,
	surfaces: { Surface },
	wings: { Wing },
	sweep: number, -- degrees, as drawn now
	tipScan: number, -- when Root was last checked for new wingtip attachments
}

-- Re-hangs a Motor6D on a new Part0 without moving anything.
local function rehang(motor: Motor6D, part0: BasePart)
	local joint = (motor.Part0 :: BasePart).CFrame * motor.C0
	motor.Part0 = part0
	motor.C0 = part0.CFrame:ToObjectSpace(joint)
end

-- Turns a swing wing's weld into a Motor6D at its pivot and moves its flaps and slats onto it.
local function rigWing(model: Model, root: BasePart, vg: any, letter: string): Wing?
	local wing = model:FindFirstChild("Wing" .. letter)
	if not (wing and wing:IsA("BasePart")) then
		return nil
	end
	local side = if letter == "L" then 1 else -1
	local pivot = Vector3.new(vg.Pivot.X * side, vg.Pivot.Y, vg.Pivot.Z)
	local pivotWorld = root.CFrame * CFrame.new(pivot)
	for _, child in wing:GetChildren() do
		if child:IsA("WeldConstraint") then
			child.Enabled = false
		end
	end
	local motor = Instance.new("Motor6D")
	motor.Name = "Sweep"
	motor.Part0 = root
	motor.Part1 = wing
	motor.C0 = CFrame.new(pivot)
	motor.C1 = wing.CFrame:ToObjectSpace(pivotWorld)
	motor.Parent = wing
	for _, d in model:GetDescendants() do
		local part = d:IsA("Motor6D") and d.Part1
		if part and d.Part0 == root then
			for _, prefix in ON_WING do
				if part.Name == prefix .. letter then
					rehang(d, wing)
				end
			end
		end
	end
	return { motor = motor, side = side, pivot = pivot, tips = {} }
end

-- Wingtip attachments on Root (the jet's own, and the contrail / vapour ones EffectsController adds),
-- remembered at the model's sweep so they can be swung with the wing.
local function scanTips(rig: Rig, modelSweep: number)
	for _, child in rig.root:GetChildren() do
		if child:IsA("Attachment") and string.sub(child.Name, 1, 7) == "Wingtip" then
			for _, wing in rig.wings do
				local letter = if wing.side > 0 then "L" else "R"
				if string.sub(child.Name, 8, 8) == letter and not wing.tips[child] then
					-- Where it would be at the model's sweep (undo any sweep already drawn)
					local angle = math.rad(rig.sweep - modelSweep) * wing.side
					local undo = CFrame.new(wing.pivot) * CFrame.Angles(0, -angle, 0) * CFrame.new(-wing.pivot)
					wing.tips[child] = undo * child.Position
				end
			end
		end
	end
end

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
	local wings: { Wing } = {}
	local vg = (airframe :: any).VariableGeometry
	if vg then
		for _, letter in { "L", "R" } do
			local wing = rigWing(model, root, vg, letter)
			if wing then
				table.insert(wings, wing)
			end
		end
	end
	if #surfaces > 0 or #wings > 0 then
		rigs[model] = {
			root = root,
			airframe = airframe,
			surfaces = surfaces,
			wings = wings,
			sweep = if vg then vg.ModelSweep else 0,
			tipScan = 0,
		}
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

-- Sweeps a swing-wing jet's wings toward the scheduled sweep for its Mach.
local function sweepWings(model: Model, rig: Rig, dt: number)
	local vg = rig.airframe.VariableGeometry
	local mach: number
	if model == FlightController.jet and FlightController.state then
		mach = FlightController.state.mach
	else
		local speed = Units.velocityFromStuds(rig.root.AssemblyLinearVelocity).Magnitude
		mach = speed / Atmosphere.speedOfSound(Units.altitudeMetres(rig.root.Position.Y))
	end
	local target = FlightModel.sweep(rig.airframe, mach) or vg.ModelSweep
	rig.sweep += math.clamp(target - rig.sweep, -SWEEP_RATE * dt, SWEEP_RATE * dt)
	local now = os.clock()
	if now - rig.tipScan > 1 then
		rig.tipScan = now
		scanTips(rig, vg.ModelSweep)
	end
	for _, wing in rig.wings do
		local angle = math.rad(rig.sweep - vg.ModelSweep) * wing.side
		wing.motor.Transform = CFrame.Angles(0, angle, 0)
		local turn = CFrame.new(wing.pivot) * CFrame.Angles(0, angle, 0) * CFrame.new(-wing.pivot)
		for attachment, base in wing.tips do
			if attachment.Parent then
				attachment.Position = turn * base
			else
				wing.tips[attachment] = nil
			end
		end
	end
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
		if #rig.wings > 0 then
			sweepWings(model, rig, dt)
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
