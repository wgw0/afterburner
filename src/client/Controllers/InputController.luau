--!strict
-- Turns keyboard and mouse into a ControlInput every frame (DEVELOPMENT.md §7).
--   Mouse Aim (default): the mouse moves an aim direction; the Instructor flies the jet to it.
--   Direct: the mouse is a self-centring stick for pitch and roll.
-- Keys: W/S throttle (hold W at 100% for afterburner), Q/E roll, A/D rudder, arrows pitch/roll,
--       RMB free look, LeftShift override G/AoA limits, M switch scheme.
-- Gamepad and touch come in Phase 4 (INP-03/04).

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Instructor = require(Shared.Instructor)
local Signal = require(Shared.Util.Signal)
local Types = require(Shared.Types)

type ControlInput = Types.ControlInput
type FlightState = Types.FlightState

local MOUSE_AIM_SENSITIVITY = 0.0035 -- radians per pixel
local DIRECT_SENSITIVITY = 0.006 -- stick travel per pixel
local DIRECT_RECENTRE = 1.5 -- per second
local THROTTLE_RATE = 0.6 -- per second
local AFTERBURNER_HOLD = 0.3 -- seconds at 100% before the afterburner lights
local FREE_LOOK_SENSITIVITY = 0.004

local InputController = {
	Priority = 20,
	scheme = "MouseAim" :: "MouseAim" | "Direct",
	aimDirection = Vector3.new(0, 0, -1),
	throttle = 0.8,
	afterburner = false,
	freeLook = false,
	freeLookYaw = 0,
	freeLookPitch = 0,
	override = false,
	enabled = false, -- true while flying (mouse locked)
	uiOpen = false, -- a panel is open: free the mouse and freeze aim/stick
	padlocked = false, -- the camera is padlocked on a target: mouse aim holds still
	SchemeChanged = Signal.new(),
	LastInput = nil :: ControlInput?,
}

local stick = Vector2.zero -- Direct mode: x = roll, y = pitch
local abHold = 0

local function keyAxis(positive: Enum.KeyCode, negative: Enum.KeyCode): number
	local value = 0
	if UserInputService:IsKeyDown(positive) then
		value += 1
	end
	if UserInputService:IsKeyDown(negative) then
		value -= 1
	end
	return value
end

-- Rotates the aim direction by a screen-space mouse delta, relative to the current camera.
local function rotateAim(delta: Vector2)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local camCF = camera.CFrame
	local yaw = CFrame.fromAxisAngle(camCF.UpVector, -delta.X * MOUSE_AIM_SENSITIVITY)
	local pitch = CFrame.fromAxisAngle(camCF.RightVector, -delta.Y * MOUSE_AIM_SENSITIVITY)
	InputController.aimDirection = (yaw * pitch * InputController.aimDirection).Unit
end

local function applyMouseMode()
	local locked = InputController.enabled and not InputController.uiOpen
	UserInputService.MouseBehavior = if locked then Enum.MouseBehavior.LockCenter else Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = not locked
end

function InputController:SetEnabled(enabled: boolean)
	self.enabled = enabled
	applyMouseMode()
end

function InputController:SetUIOpen(open: boolean)
	self.uiOpen = open
	applyMouseMode()
end

function InputController:ResetForJet(cframe: CFrame)
	self.aimDirection = cframe.LookVector
	self.throttle = 0.8
	self.afterburner = false
	stick = Vector2.zero
	self.freeLookYaw, self.freeLookPitch = 0, 0
end

function InputController:SetScheme(scheme: "MouseAim" | "Direct")
	self.scheme = scheme
	stick = Vector2.zero
	self.SchemeChanged:Fire(scheme)
end

-- The ControlInput for this frame.
function InputController:GetControlInput(state: FlightState, airframe: any): ControlInput
	-- Arrows fly the jet unless Left Alt is held (then they're snap views, see CameraController).
	local arrows = not UserInputService:IsKeyDown(Enum.KeyCode.LeftAlt)
	local keyRoll = keyAxis(Enum.KeyCode.E, Enum.KeyCode.Q)
		+ (if arrows then keyAxis(Enum.KeyCode.Right, Enum.KeyCode.Left) else 0)
	local keyYaw = keyAxis(Enum.KeyCode.D, Enum.KeyCode.A)
	local keyPitch = if arrows then keyAxis(Enum.KeyCode.Down, Enum.KeyCode.Up) else 0 -- pull back = nose up

	local result: ControlInput
	if self.scheme == "MouseAim" then
		result = Instructor.compute(state, self.aimDirection, airframe, {
			allowOverG = self.override,
			throttle = self.throttle,
			afterburner = self.afterburner,
		})
		-- Keys override the instructor on their axis while held.
		if keyRoll ~= 0 then
			result.roll = keyRoll
		end
		if keyPitch ~= 0 then
			result.pitch = keyPitch
		end
		if keyYaw ~= 0 then
			result.yaw = keyYaw
		end
	else
		result = {
			pitch = math.clamp(stick.Y + keyPitch, -1, 1),
			roll = math.clamp(stick.X + keyRoll, -1, 1),
			yaw = keyYaw,
			throttle = self.throttle,
			afterburner = self.afterburner,
			protections = not self.override,
		}
	end
	self.LastInput = result
	return result
end

local function update(dt: number)
	local self = InputController
	if not self.enabled then
		return
	end

	-- Throttle and afterburner
	local throttleAxis = keyAxis(Enum.KeyCode.W, Enum.KeyCode.S)
	if throttleAxis < 0 and self.afterburner then
		self.afterburner = false
	end
	self.throttle = math.clamp(self.throttle + throttleAxis * THROTTLE_RATE * dt, 0, 1)
	if throttleAxis > 0 and self.throttle >= 1 then
		abHold += dt
		if abHold >= AFTERBURNER_HOLD then
			self.afterburner = true
		end
	else
		abHold = 0
	end

	self.override = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
	self.freeLook = UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)

	-- Re-assert the lock every frame: Roblox can release it (e.g. when the window loses focus).
	applyMouseMode()
	local delta = if self.uiOpen then Vector2.zero else UserInputService:GetMouseDelta()
	if self.freeLook and not self.uiOpen then
		self.freeLookYaw = math.clamp(self.freeLookYaw - delta.X * FREE_LOOK_SENSITIVITY, -math.rad(160), math.rad(160))
		self.freeLookPitch =
			math.clamp(self.freeLookPitch - delta.Y * FREE_LOOK_SENSITIVITY, -math.rad(30), math.rad(90))
	else
		if self.scheme == "MouseAim" and not self.padlocked then
			rotateAim(delta)
		else
			stick = Vector2.new(
				math.clamp(stick.X + delta.X * DIRECT_SENSITIVITY, -1, 1),
				math.clamp(stick.Y + delta.Y * DIRECT_SENSITIVITY, -1, 1)
			)
		end
		-- Free look springs back once released (the camera smooths it).
		self.freeLookYaw, self.freeLookPitch = 0, 0
	end

	if self.scheme == "Direct" then
		local decay = math.max(0, 1 - DIRECT_RECENTRE * dt)
		stick *= decay
	end
end

function InputController:Init()
	ContextActionService:BindAction("AfterburnerSwitchScheme", function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			self:SetScheme(if self.scheme == "MouseAim" then "Direct" else "MouseAim")
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.M)
end

function InputController:Start()
	RunService:BindToRenderStep("AfterburnerInput", Enum.RenderPriority.Input.Value, update)
end

return InputController
