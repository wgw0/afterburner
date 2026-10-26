--!strict
-- Cockpit-first camera (DEVELOPMENT.md §8.1).
--   Cockpit (default): eye at CockpitEye. In Mouse Aim the head looks along the aim direction, so the
--     jet visibly chases where you look, and the horizon stays mostly level (the cockpit tilts around
--     you, with a little of the jet's roll kept for feel). A view that rolled fully with the jet turned
--     the mouse's "right" into "down" mid-turn and made Mouse Aim hard to fly from the cockpit.
--     Free look (RMB) turns the head; G pushes the head down.
--   Chase (V): the camera sits a fixed distance behind and above the jet *along the camera's own view*,
--     so the jet always stays centred on screen. In Mouse Aim the view follows the aim with a level
--     horizon; in Direct it follows the jet's nose, smoothed.
-- Field of view widens a little with speed and G for a sense of speed (Z zooms in).
-- Snap views (CAM-03): hold Left Alt + an arrow to look left / right / back / up.
-- Padlock (CAM-04): hold X or the middle mouse button to keep your head on the target (your lock, your
--   heat-seeker's target, or the nearest spotted jet), within realistic head limits.
-- When your jet is destroyed (AIR-03 / CAM-06): a short orbit of the explosion, then the kill cam follows
-- whoever shot you down. While waiting to respawn you spectate other jets (Left/Right arrows to switch).
-- With nothing to watch, or with the menus open, the camera slowly orbits the map centre.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Signal = require(Shared.Util.Signal)
local Spring = require(Shared.Util.Spring)
local Units = require(Shared.Units)

local FlightController = require(script.Parent.FlightController)
local InputController = require(script.Parent.InputController)
local SensorController = require(script.Parent.SensorController)

local BASE_FOV = 70
local ZOOM_FOV = 35
local SPEED_FOV = 10 -- extra degrees at high speed
local G_FOV = 6 -- extra degrees in a hard pull
local DEATH_CAM_SECONDS = 4.5
local WRECK_SECONDS = 1.5 -- of the death cam spent on the wreck before following the killer
local PADLOCK_YAW_LIMIT = math.rad(160)
local PADLOCK_PITCH_MIN, PADLOCK_PITCH_MAX = math.rad(-25), math.rad(90)
local SNAP_VIEWS: { [Enum.KeyCode]: Vector2 } = { -- (yaw, pitch) in degrees
	[Enum.KeyCode.Left] = Vector2.new(100, 5),
	[Enum.KeyCode.Right] = Vector2.new(-100, 5),
	[Enum.KeyCode.Down] = Vector2.new(170, 25),
	[Enum.KeyCode.Up] = Vector2.new(0, 70),
}
local COCKPIT_ROLL_FOLLOW = 0.25 -- how much of the jet's roll the cockpit view keeps in Mouse Aim
local DEFAULT_CHASE_OFFSET = Vector3.new(0, 12, 80) -- studs (up, behind) if the model has no ChaseCam

local CameraController = {
	Priority = 40,
	mode = "Cockpit" :: "Cockpit" | "Chase",
	baseFov = BASE_FOV, -- settings: field of view at rest
	defaultMode = "Cockpit" :: "Cockpit" | "Chase", -- settings: the view each new jet starts in
	ModeChanged = Signal.new(),
}

local headYaw = Spring.new(0, 14, 1)
local headPitch = Spring.new(0, 14, 1)
local gShift = Spring.new(0, 8, 0.8)
local chaseLook = Spring.new(Vector3.new(0, 0, -1), 7, 1)
local chaseUp = Spring.new(Vector3.new(0, 1, 0), 5, 1)
local cockpitUp = Spring.new(Vector3.new(0, 1, 0), 6, 1)
local fov = Spring.new(BASE_FOV, 4, 1)
local orbitAngle = 0
local myJetId: number? = nil
local deathUntil = 0
local deathPosition = Vector3.zero
local killerJetId = 0
local spectateIndex = 1
local spectateLabel: TextLabel

local function jetById(id: number): Model?
	for _, m in workspace.Jets:GetChildren() do
		if m:IsA("Model") and m:GetAttribute("JetId") == id then
			return m
		end
	end
	return nil
end

-- A follow camera behind any jet (kill cam, spectating).
local function followCamera(model: Model, dt: number): CFrame?
	local root = model.PrimaryPart
	if not root then
		return nil
	end
	local look = chaseLook:Update(dt, root.CFrame.LookVector)
	look = if look.Magnitude > 1e-3 then look.Unit else root.CFrame.LookVector
	local position = root.Position - look * 90 + Vector3.new(0, 22, 0)
	return CFrame.lookAt(position, root.Position + look * 60)
end

-- Head angles (yaw, pitch) that keep the padlock target in view, or nil when not padlocking.
local function padlockView(jetCF: CFrame): Vector2?
	local held = UserInputService:IsKeyDown(Enum.KeyCode.X)
		or UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton3)
		or UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, Enum.KeyCode.ButtonR3)
	local target = if held then SensorController:PadlockTarget() else nil
	local targetRoot = target and target.PrimaryPart
	InputController.padlocked = targetRoot ~= nil
	if not targetRoot then
		return nil
	end
	local rel = jetCF:VectorToObjectSpace((targetRoot.Position - jetCF.Position).Unit)
	local yaw = math.clamp(math.atan2(-rel.X, -rel.Z), -PADLOCK_YAW_LIMIT, PADLOCK_YAW_LIMIT)
	local pitch = math.clamp(math.asin(math.clamp(rel.Y, -1, 1)), PADLOCK_PITCH_MIN, PADLOCK_PITCH_MAX)
	return Vector2.new(yaw, pitch)
end

-- Snap view offsets while Left Alt is held, else nil.
local function snapView(): Vector2?
	if not UserInputService:IsKeyDown(Enum.KeyCode.LeftAlt) then
		return nil
	end
	for key, view in SNAP_VIEWS do
		if UserInputService:IsKeyDown(key) then
			return Vector2.new(math.rad(view.X), math.rad(view.Y))
		end
	end
	return nil
end

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
		return CameraController.baseFov
	end
	local speedPart = math.clamp((Units.knots(state.speed) - 250) / 450, 0, 1) * SPEED_FOV
	local gPart = math.clamp((state.gLoad - 2) / 5, 0, 1) * G_FOV
	return CameraController.baseFov + speedPart + gPart
end

local function cockpitView(root: BasePart, dt: number): CFrame
	local jetCF = root.CFrame
	local state = FlightController.state
	local eye = root:FindFirstChild("CockpitEye") :: Attachment?
	local eyeCF = if eye then eye.WorldCFrame else jetCF
	local g = if state then state.gLoad else 1
	local shift = gShift:Update(dt, math.clamp((g - 1) * 0.04, -0.15, 0.35))
	local position = eyeCF.Position - jetCF.UpVector * shift

	local snap = padlockView(jetCF) or snapView()
	local yaw = headYaw:Update(dt, if snap then snap.X else InputController.freeLookYaw)
	local pitch = headPitch:Update(dt, if snap then snap.Y else InputController.freeLookPitch)
	local base: CFrame
	if InputController.scheme == "MouseAim" and not InputController.freeLook and not snap then
		-- Mostly level horizon; inverted, the jet's up points down, so fall back to world up.
		local wanted = Vector3.new(0, 1, 0):Lerp(jetCF.UpVector, COCKPIT_ROLL_FOLLOW)
		local up = cockpitUp:Update(dt, if wanted.Magnitude > 0.1 then wanted.Unit else Vector3.yAxis)
		base = safeLookAt(position, InputController.aimDirection, if up.Magnitude > 1e-3 then up else Vector3.yAxis)
	else
		cockpitUp:Update(dt, jetCF.UpVector)
		base = CFrame.new(position) * jetCF.Rotation
	end
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

-- The menus cover the screen while you're not flying; a slow orbit of the map is their backdrop.
local function menuOpen(): boolean
	local menu = Players.LocalPlayer:FindFirstChild("PlayerGui")
		and Players.LocalPlayer.PlayerGui:FindFirstChild("AfterburnerMenu")
	return menu ~= nil and (menu :: ScreenGui).Enabled
end

local function update(dt: number)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = fov:Update(dt, targetFov())

	local root = FlightController.root
	spectateLabel.Visible = false
	if os.clock() < deathUntil then
		local killer = if killerJetId ~= 0 then jetById(killerJetId) else nil
		local follow = killer
			and os.clock() > deathUntil - DEATH_CAM_SECONDS + WRECK_SECONDS
			and followCamera(killer, dt)
		if follow then
			camera.CFrame = follow
			spectateLabel.Text = `Shot down by {killer and killer:GetAttribute("PilotName") or "?"}`
			spectateLabel.Visible = true
		else
			orbitAngle += dt * 0.25
			local offset = Vector3.new(math.cos(orbitAngle) * 160, 60, math.sin(orbitAngle) * 160)
			camera.CFrame = CFrame.lookAt(deathPosition + offset, deathPosition)
		end
		return
	end
	if not (root and FlightController.jet) then
		-- Behind the menus: a slow, high orbit of the map (following a jet behind the hangar looked odd)
		if menuOpen() then
			orbitAngle += dt * 0.03
			local focus = Vector3.new(300, 100, 0)
			local position = focus + Vector3.new(math.cos(orbitAngle) * 1800, 700, math.sin(orbitAngle) * 1800)
			camera.CFrame = CFrame.lookAt(position, focus)
			return
		end
		-- Spectate while waiting to (re)spawn
		local jets = {}
		for _, m in workspace.Jets:GetChildren() do
			if m:IsA("Model") and m.PrimaryPart then
				table.insert(jets, m)
			end
		end
		table.sort(jets, function(a, b)
			return (a:GetAttribute("JetId") :: number) < (b:GetAttribute("JetId") :: number)
		end)
		if #jets > 0 then
			spectateIndex = (spectateIndex - 1) % #jets + 1
			local target = jets[spectateIndex]
			local follow = followCamera(target, dt)
			if follow then
				camera.CFrame = follow
				spectateLabel.Text = `Spectating {target:GetAttribute("PilotName") or "?"}  ·  ◀ ▶ to switch`
				spectateLabel.Visible = not menuOpen()
				return
			end
		end
		orbitAngle += dt * 0.05
		local focus = Vector3.new(300, 100, 0)
		local position = focus + Vector3.new(math.cos(orbitAngle) * 1400, 600, math.sin(orbitAngle) * 1400)
		camera.CFrame = CFrame.lookAt(position, focus)
		return
	end

	camera.CFrame = if CameraController.mode == "Cockpit" then cockpitView(root, dt) else chaseView(root, dt)
end

function CameraController:InDeathCam(): boolean
	return os.clock() < deathUntil
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
		if input.KeyCode == Enum.KeyCode.V or input.KeyCode == Enum.KeyCode.ButtonSelect then
			self:SetMode(if self.mode == "Cockpit" then "Chase" else "Cockpit")
		end
	end)
	local gui = Instance.new("ScreenGui")
	gui.Name = "AfterburnerSpectate"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 22
	spectateLabel = Instance.new("TextLabel")
	spectateLabel.AnchorPoint = Vector2.new(0.5, 1)
	spectateLabel.Position = UDim2.new(0.5, 0, 1, -24)
	spectateLabel.Size = UDim2.fromOffset(520, 28)
	spectateLabel.BackgroundTransparency = 1
	spectateLabel.Font = Enum.Font.GothamBold
	spectateLabel.TextSize = 18
	spectateLabel.TextColor3 = Color3.new(1, 1, 1)
	spectateLabel.TextStrokeTransparency = 0.4
	spectateLabel.Visible = false
	spectateLabel.Parent = gui
	gui.Parent = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or FlightController.jet then
			return
		end
		if input.KeyCode == Enum.KeyCode.Right or input.KeyCode == Enum.KeyCode.DPadRight then
			spectateIndex += 1
		elseif input.KeyCode == Enum.KeyCode.Left or input.KeyCode == Enum.KeyCode.DPadLeft then
			spectateIndex -= 1
		end
	end)

	Net.Client.on(
		"JetDestroyed",
		function(jetId: number, _killer: number, cause: string, position: Vector3, killerJet: number)
			local died = cause == "Shot" or cause == "Crash" or cause == "Collision" or cause == "OutOfBounds"
			if jetId == myJetId and died then
				deathUntil = os.clock() + DEATH_CAM_SECONDS
				deathPosition = position
				killerJetId = killerJet or 0
			end
		end
	)
	FlightController.JetChanged:Connect(function(jet)
		if jet then
			myJetId = jet:GetAttribute("JetId") :: number?
			self:SetMode(self.defaultMode)
		end
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
