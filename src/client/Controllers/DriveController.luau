--!strict
-- Drives the local player's Ground Roamer (DEVELOPMENT.md §36). The server spawns it and gives us its physics;
-- every physics step this reads its state, runs Shared/GroundVehicle with the player's input and applies the
-- returned forces as impulses, so Roblox integrates the body and its collisions. It also turns and spins the
-- wheels (locally), keeps the chase and driver's-eye cameras for CameraController, and shows a small HUD.
--   W / S (or the triggers): throttle, brake and reverse; A / D (or the left stick): steer; Space: handbrake;
--   V: chase or driver's view; L: headlamps; F: put it away (back to the menu).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config.GroundRoamer)
local GroundVehicle = require(Shared.GroundVehicle)
local Net = require(Shared.Net)
local Signal = require(Shared.Util.Signal)

local localPlayer = Players.LocalPlayer
local MPH = 2.23694 -- per m/s

local DriveController = {
	Priority = 35,
	vehicle = nil :: Model?,
	view = "Chase" :: "Chase" | "Driver",
	VehicleChanged = Signal.new(), -- (model or nil)
}

local state: GroundVehicle.State? = nil
local lastStep: GroundVehicle.Step? = nil
local motors: { [string]: Motor6D } = {}
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true -- drive on the sea floor where it's shallow
local hud: ScreenGui
local speedLabel: TextLabel
local cameraCF: CFrame? = nil

local function ground(origin: Vector3, direction: Vector3): (Vector3?, Vector3?)
	local hit = workspace:Raycast(origin, direction, rayParams)
	if hit then
		return hit.Position, hit.Normal
	end
	return nil, nil
end

local function adopt(model: Model?)
	if model == DriveController.vehicle then
		return
	end
	DriveController.vehicle = model
	state = if model then GroundVehicle.newState(Config :: any) else nil
	lastStep = nil
	cameraCF = nil
	table.clear(motors)
	if model then
		for _, wheel in Config.Wheels do
			local motor = model:FindFirstChild(`Wheel{wheel.name}`, true)
			if motor and motor:IsA("Motor6D") then
				motors[wheel.name] = motor
			end
		end
		rayParams.FilterDescendantsInstances =
			{ workspace:FindFirstChild("Vehicles") :: Instance, workspace:FindFirstChild("Jets") :: Instance }
	end
	hud.Enabled = model ~= nil
	DriveController.VehicleChanged:Fire(model)
end

local function mine(model: Instance): boolean
	return model:IsA("Model") and model:GetAttribute("OwnerUserId") == localPlayer.UserId
end

local function readInput(): GroundVehicle.Input
	local throttle, steer = 0, 0
	local keys = UserInputService
	if keys:IsKeyDown(Enum.KeyCode.W) or keys:IsKeyDown(Enum.KeyCode.Up) then
		throttle += 1
	end
	if keys:IsKeyDown(Enum.KeyCode.S) or keys:IsKeyDown(Enum.KeyCode.Down) then
		throttle -= 1
	end
	if keys:IsKeyDown(Enum.KeyCode.D) or keys:IsKeyDown(Enum.KeyCode.Right) then
		steer += 1
	end
	if keys:IsKeyDown(Enum.KeyCode.A) or keys:IsKeyDown(Enum.KeyCode.Left) then
		steer -= 1
	end
	local handbrake = keys:IsKeyDown(Enum.KeyCode.Space)
		or keys:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, Enum.KeyCode.ButtonX)
	for _, input in UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1) do
		if input.KeyCode == Enum.KeyCode.ButtonR2 then
			throttle += input.Position.Z
		elseif input.KeyCode == Enum.KeyCode.ButtonL2 then
			throttle -= input.Position.Z
		elseif input.KeyCode == Enum.KeyCode.Thumbstick1 and math.abs(input.Position.X) > 0.12 then
			steer += input.Position.X
		end
	end
	return { throttle = math.clamp(throttle, -1, 1), steer = math.clamp(steer, -1, 1), handbrake = handbrake }
end

local function physicsStep(dt: number)
	local model = DriveController.vehicle
	local root = model and model.PrimaryPart
	if not (model and root and state) or dt <= 0 then
		return
	end
	local body: GroundVehicle.Body = {
		cframe = model:GetPivot(),
		velocity = root.AssemblyLinearVelocity,
		angularVelocity = root.AssemblyAngularVelocity,
		centreOfMass = root.AssemblyCenterOfMass,
		mass = root.AssemblyMass,
	}
	local step = GroundVehicle.step(Config :: any, state, body, readInput(), ground, dt)
	lastStep = step
	for _, f in step.forces do
		root:ApplyImpulseAtPosition(f.force * dt, f.position)
	end
	-- Studs are metres here, but workspace.Gravity is Roblox's 196.2: cancel all but the real 9.81 m/s²
	root:ApplyImpulse(Vector3.yAxis * body.mass * (workspace.Gravity - Config.Gravity) * dt)
end

local function animate()
	local step = lastStep
	if not step then
		return
	end
	for i, wheel in Config.Wheels do
		local motor = motors[wheel.name]
		local w = step.wheels[i]
		if motor and w then
			motor.Transform = CFrame.new(0, w.compression, 0)
				* CFrame.Angles(0, -w.steer, 0)
				* CFrame.Angles(-w.spin, 0, 0)
		end
	end
	speedLabel.Text = `{math.round(math.abs(step.speed) * MPH)} mph`
end

-- The camera for CameraController while driving: chase (smoothed, level) or from the driver's seat.
function DriveController:CameraCFrame(dt: number): CFrame?
	local model = self.vehicle
	if not model then
		return nil
	end
	local pivot = model:GetPivot()
	if self.view == "Driver" then
		return pivot * CFrame.new(Config.DriverEye)
	end
	local flatLook = Vector3.new(pivot.LookVector.X, 0, pivot.LookVector.Z)
	if flatLook.Magnitude < 1e-3 then
		flatLook = Vector3.zAxis
	end
	flatLook = flatLook.Unit
	local focus = pivot.Position + Vector3.new(0, 1.2, 0)
	local eye = focus - flatLook * Config.ChaseOffset.Z + Vector3.new(0, Config.ChaseOffset.Y, 0)
	local target = CFrame.lookAt(eye, focus)
	cameraCF = if cameraCF then cameraCF:Lerp(target, 1 - math.exp(-6 * dt)) else target
	return cameraCF
end

-- Take the Ground Roamer out (in a skin) or put it away. Returns (ok, reason).
function DriveController:TakeOut(skin: string?): (boolean, string?)
	return Net.Client.invoke("RequestGroundRoamer", true, skin)
end

function DriveController:PutAway(): (boolean, string?)
	return Net.Client.invoke("RequestGroundRoamer", false)
end

function DriveController:Init()
	hud = Instance.new("ScreenGui")
	hud.Name = "GroundRoamerHud"
	hud.ResetOnSpawn = false
	hud.Enabled = false
	speedLabel = Instance.new("TextLabel")
	speedLabel.Name = "Speed"
	speedLabel.Size = UDim2.fromOffset(160, 44)
	speedLabel.Position = UDim2.new(0.5, 0, 1, -96)
	speedLabel.AnchorPoint = Vector2.new(0.5, 0)
	speedLabel.BackgroundTransparency = 1
	speedLabel.Font = Enum.Font.GothamBold
	speedLabel.TextSize = 32
	speedLabel.TextColor3 = Color3.new(1, 1, 1)
	speedLabel.TextStrokeTransparency = 0.5
	speedLabel.Text = "0 mph"
	speedLabel.Parent = hud
	local hint = Instance.new("TextLabel")
	hint.Name = "Hint"
	hint.Size = UDim2.fromOffset(640, 22)
	hint.Position = UDim2.new(0.5, 0, 1, -48)
	hint.AnchorPoint = Vector2.new(0.5, 0)
	hint.BackgroundTransparency = 1
	hint.Font = Enum.Font.Gotham
	hint.TextSize = 15
	hint.TextColor3 = Color3.new(1, 1, 1)
	hint.TextStrokeTransparency = 0.6
	hint.Text = "W/S drive  ·  A/D steer  ·  Space handbrake  ·  V view  ·  L lights  ·  F leave"
	hint.Parent = hud
end

function DriveController:Start()
	hud.Parent = localPlayer:WaitForChild("PlayerGui")
	local folder = workspace:WaitForChild("Vehicles")
	folder.ChildAdded:Connect(function(child)
		if mine(child) then
			adopt(child :: Model)
		end
	end)
	folder.ChildRemoved:Connect(function(child)
		if child == self.vehicle then
			adopt(nil)
		end
	end)
	for _, child in folder:GetChildren() do
		if mine(child) then
			adopt(child :: Model)
		end
	end

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not self.vehicle then
			return
		end
		if input.KeyCode == Enum.KeyCode.V or input.KeyCode == Enum.KeyCode.ButtonY then
			self.view = if self.view == "Chase" then "Driver" else "Chase"
		elseif input.KeyCode == Enum.KeyCode.L then
			for _, d in (self.vehicle :: Model):GetDescendants() do
				if d:IsA("SpotLight") then
					d.Enabled = not d.Enabled
				end
			end
		elseif input.KeyCode == Enum.KeyCode.F or input.KeyCode == Enum.KeyCode.ButtonB then
			task.spawn(function()
				self:PutAway()
			end)
		end
	end)

	RunService.PreSimulation:Connect(physicsStep)
	RunService.RenderStepped:Connect(animate)
end

return DriveController
