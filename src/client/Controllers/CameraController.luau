--!strict
-- Cockpit-first camera (DEVELOPMENT.md §8.1).
--   Cockpit (default): eye at CockpitEye. In Mouse Aim the head looks along the aim direction, so the
--     jet visibly chases where you look. Free look (RMB) turns the head; G pushes the head down.
--   Chase (V): the camera sits a fixed distance behind and above the jet *along the camera's own view*,
--     so the jet always stays centred on screen. In Mouse Aim the view follows the aim with a level
--     horizon; in Direct it follows the jet's nose, smoothed.
-- Field of view widens a little with speed and G for a sense of speed (Z zooms in).
-- With no jet, the camera orbits the test range.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Signal = require(Shared.Util.Signal)
local Spring = require(Shared.Util.Spring)
local Units = require(Shared.Units)

local FlightController = require(script.Parent.FlightController)
local InputController = require(script.Parent.InputController)

local BASE_FOV = 70
local ZOOM_FOV = 35
local SPEED_FOV = 10 -- extra degrees at high speed
local G_FOV = 6 -- extra degrees in a hard pull
local DEFAULT_CHASE_OFFSET = Vector3.new(0, 12, 80) -- studs (up, behind) if the model has no ChaseCam

local CameraController = {
	Priority = 40,
	mode = "Cockpit" :: "Cockpit" | "Chase",
	ModeChanged = Signal.new(),
}

local headYaw = Spring.new(0, 14, 1)
local headPitch = Spring.new(0, 14, 1)
local gShift = Spring.new(0, 8, 0.8)
local chaseLook = Spring.new(Vector3.new(0, 0, -1), 7, 1)
local chaseUp = Spring.new(Vector3.new(0, 1, 0), 5, 1)
local fov = Spring.new(BASE_FOV, 4, 1)
local orbitAngle = 0

local function safeLookAt(position: Vector3, direction: Vector3, up: Vector3): CFrame
	if math.abs(direction.Unit:Dot(up.Unit)) > 0.999 then
		up = direction:Cross(Vector3.new(1, 0, 0)) -- looking straight up/down: pick any perpendicular
	end
	return CFrame.lookAt(position, position + direction, up)
end

local function targetFov(): number
	if UserInputService:IsKeyDown(Enum.KeyCode.Z) then
		return ZOOM_FOV
	end
	local state = FlightController.state
	if not state then
		return BASE_FOV
	end
	local speedPart = math.clamp((Units.knots(state.speed) - 250) / 450, 0, 1) * SPEED_FOV
	local gPart = math.clamp((state.gLoad - 2) / 5, 0, 1) * G_FOV
	return BASE_FOV + speedPart + gPart
end

local function cockpitView(root: BasePart, dt: number): CFrame
	local jetCF = root.CFrame
	local state = FlightController.state
	local eye = root:FindFirstChild("CockpitEye") :: Attachment?
	local eyeCF = if eye then eye.WorldCFrame else jetCF
	local g = if state then state.gLoad else 1
	local shift = gShift:Update(dt, math.clamp((g - 1) * 0.04, -0.15, 0.35))
	local position = eyeCF.Position - jetCF.UpVector * shift

	local yaw = headYaw:Update(dt, InputController.freeLookYaw)
	local pitch = headPitch:Update(dt, InputController.freeLookPitch)
	local base = if InputController.scheme == "MouseAim" and not InputController.freeLook
		then safeLookAt(position, InputController.aimDirection, jetCF.UpVector)
		else CFrame.new(position) * jetCF.Rotation
	return base * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)
end

local function chaseView(root: BasePart, dt: number): CFrame
	local jetCF = root.CFrame
	local anchor = root:FindFirstChild("ChaseCam") :: Attachment?
	local offset = if anchor then anchor.Position else DEFAULT_CHASE_OFFSET

	local look: Vector3
	local up: Vector3
	if InputController.scheme == "MouseAim" then
		-- The view is the aim (the mouse is already smooth); keep the horizon level.
		look = InputController.aimDirection
		up = chaseUp:Update(dt, Vector3.new(0, 1, 0))
	else
		look = chaseLook:Update(dt, jetCF.LookVector)
		up = chaseUp:Update(dt, jetCF.UpVector)
	end
	if look.Magnitude < 1e-3 then
		look = jetCF.LookVector
	end
	look = look.Unit
	up = if up.Magnitude > 1e-3 then up.Unit else Vector3.new(0, 1, 0)

	-- Build the camera frame first, then place the camera behind the jet within it: the jet stays
	-- at the same spot on screen (centred, slightly below the middle) whatever it's doing.
	local frame = safeLookAt(Vector3.zero, look, up)
	local position = jetCF.Position - frame.LookVector * offset.Z + frame.UpVector * offset.Y
	if InputController.freeLook then
		local yaw = headYaw:Update(dt, InputController.freeLookYaw)
		local pitch = headPitch:Update(dt, InputController.freeLookPitch)
		local orbit = frame.Rotation * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)
		position = jetCF.Position - orbit.LookVector * offset.Z + orbit.UpVector * offset.Y
		return CFrame.lookAt(position, jetCF.Position, orbit.UpVector)
	end
	headYaw:Update(dt, 0)
	headPitch:Update(dt, 0)
	return CFrame.new(position) * frame.Rotation
end

local function update(dt: number)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = fov:Update(dt, targetFov())

	local root = FlightController.root
	if not (root and FlightController.jet) then
		orbitAngle += dt * 0.05
		local focus = Vector3.new(300, 100, 0)
		local position = focus + Vector3.new(math.cos(orbitAngle) * 1400, 600, math.sin(orbitAngle) * 1400)
		camera.CFrame = CFrame.lookAt(position, focus)
		return
	end

	camera.CFrame = if CameraController.mode == "Cockpit" then cockpitView(root, dt) else chaseView(root, dt)
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
		local root = jet and jet.PrimaryPart
		if root then
			chaseLook:Reset(root.CFrame.LookVector)
			chaseUp:Reset(Vector3.new(0, 1, 0))
		end
	end)
end

function CameraController:Start()
	RunService:BindToRenderStep("AfterburnerCamera", Enum.RenderPriority.Camera.Value + 1, update)
end

return CameraController
