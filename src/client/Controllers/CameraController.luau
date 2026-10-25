--!strict
-- Cockpit-first camera (DEVELOPMENT.md §8.1).
--   Cockpit (default): eye at CockpitEye. In Mouse Aim the head looks along the aim direction, so the
--     jet visibly chases where you look. Free look (RMB) turns the head; G pushes the head down.
--   Chase (V, debug/fallback): behind and above, spring-smoothed.
-- With no jet, the camera orbits the test range.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Signal = require(Shared.Util.Signal)
local Spring = require(Shared.Util.Spring)

local FlightController = require(script.Parent.FlightController)
local InputController = require(script.Parent.InputController)

local DEFAULT_FOV = 70
local ZOOM_FOV = 35

local CameraController = {
	Priority = 40,
	mode = "Cockpit" :: "Cockpit" | "Chase",
	ModeChanged = Signal.new(),
}

local headYaw = Spring.new(0, 14, 1)
local headPitch = Spring.new(0, 14, 1)
local gShift = Spring.new(0, 8, 0.8)
local chasePosition = Spring.new(Vector3.zero, 9, 1)
local fov = Spring.new(DEFAULT_FOV, 10, 1)
local orbitAngle = 0

local function lookAlong(position: Vector3, direction: Vector3, up: Vector3): CFrame
	-- Avoid a degenerate up vector when looking straight along it.
	if math.abs(direction.Unit:Dot(up.Unit)) > 0.999 then
		up = up:Cross(Vector3.new(1, 0, 0))
	end
	return CFrame.lookAt(position, position + direction, up)
end

local function update(dt: number)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	camera.CameraType = Enum.CameraType.Scriptable
	local zoomed = UserInputService:IsKeyDown(Enum.KeyCode.Z)
	camera.FieldOfView = fov:Update(dt, if zoomed then ZOOM_FOV else DEFAULT_FOV)

	local root = FlightController.root
	local jet = FlightController.jet
	if not (root and jet) then
		orbitAngle += dt * 0.05
		local focus = Vector3.new(300, 100, 0)
		local position = focus + Vector3.new(math.cos(orbitAngle) * 1400, 600, math.sin(orbitAngle) * 1400)
		camera.CFrame = CFrame.lookAt(position, focus)
		return
	end

	local jetCF = root.CFrame
	local state = FlightController.state

	if CameraController.mode == "Cockpit" then
		local eye = root:FindFirstChild("CockpitEye") :: Attachment?
		local eyeCF = if eye then eye.WorldCFrame else jetCF
		local g = if state then state.gLoad else 1
		local shift = gShift:Update(dt, math.clamp((g - 1) * 0.04, -0.15, 0.35))
		local position = eyeCF.Position - jetCF.UpVector * shift

		local yaw = headYaw:Update(dt, InputController.freeLookYaw)
		local pitch = headPitch:Update(dt, InputController.freeLookPitch)
		local base: CFrame
		if InputController.scheme == "MouseAim" and not InputController.freeLook then
			base = lookAlong(position, InputController.aimDirection, jetCF.UpVector)
		else
			base = CFrame.new(position) * jetCF.Rotation
		end
		camera.CFrame = base * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)
	else
		local anchor = root:FindFirstChild("ChaseCam") :: Attachment?
		local target = if anchor then anchor.WorldPosition else (jetCF * CFrame.new(0, 12, 80)).Position
		local position = chasePosition:Update(dt, target)
		if (position - target).Magnitude > 400 then
			chasePosition:Reset(target)
			position = target
		end
		local lookDirection = if InputController.scheme == "MouseAim"
			then InputController.aimDirection
			else jetCF.LookVector
		local focus = jetCF.Position + lookDirection * 300
		camera.CFrame = CFrame.lookAt(position, focus, jetCF.UpVector)
	end
end

function CameraController:SetMode(mode: "Cockpit" | "Chase")
	self.mode = mode
	self.ModeChanged:Fire(mode)
end

function CameraController:Init()
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.V then
			self:SetMode(if self.mode == "Cockpit" then "Chase" else "Cockpit")
		end
	end)
	FlightController.JetChanged:Connect(function(jet)
		if jet and jet.PrimaryPart then
			chasePosition:Reset(jet.PrimaryPart.Position)
		end
	end)
end

function CameraController:Start()
	RunService:BindToRenderStep("AfterburnerCamera", Enum.RenderPriority.Camera.Value + 1, update)
end

return CameraController
