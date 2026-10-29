--!strict
-- Turns player input into a ControlInput every frame (DEVELOPMENT.md §7).
-- The device follows whatever was used last: keyboard + mouse, gamepad (INP-03) or touch (INP-04).
--   Keyboard + mouse:
--     Mouse Aim (default): the mouse moves an aim direction; the Instructor flies the jet to it.
--     Direct: the mouse is a self-centring stick for pitch and roll.
--     Keys (rebindable, BindingsController; defaults): W/S throttle (hold W at 100% for afterburner), Q/E
--     roll, A/D rudder, LeftShift override G/AoA limits, M switch scheme. Fixed: arrows pitch/roll, RMB
--     free look.
--   Gamepad: left stick pitch/roll, RT/LT throttle (hold RT at 100% for afterburner), right stick look;
--     buttons as bound (LB/RB rudder, L3 override by default). Weapon and view buttons are handled by
--     WeaponController / CameraController.
--   Touch: the TouchController's virtual stick and throttle slider write into padStick / throttle,
--     with optional gun aim-assist blended in.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Instructor = require(Shared.Instructor)
local Signal = require(Shared.Util.Signal)
local Types = require(Shared.Types)

local BindingsController = require(script.Parent.BindingsController)

type ControlInput = Types.ControlInput
type FlightState = Types.FlightState

local MOUSE_AIM_SENSITIVITY = 0.0035 -- radians per pixel
local DIRECT_SENSITIVITY = 0.006 -- stick travel per pixel
local DIRECT_RECENTRE = 1.5 -- per second
local THROTTLE_RATE = 0.6 -- per second
local AFTERBURNER_HOLD = 0.3 -- seconds at 100% before the afterburner lights
local FREE_LOOK_SENSITIVITY = 0.004
local STICK_DEADZONE = 0.12
local STICK_EXPO = 1.6

export type Device = "KeyboardMouse" | "Gamepad" | "Touch"

local InputController = {
	Priority = 20,
	scheme = "MouseAim" :: "MouseAim" | "Direct",
	sensitivity = 1, -- mouse sensitivity multiplier (settings)
	invertPitch = false, -- settings: mouse up = nose up
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
	device = "KeyboardMouse" :: Device,
	padStick = Vector2.zero, -- gamepad / touch stick: x = roll right, y = pitch up (after expo)
	padLook = Vector2.zero, -- gamepad right stick (free look)
	triggerUp = 0, -- RT
	triggerDown = 0, -- LT
	assist = nil :: Types.ControlInput?, -- touch gun aim-assist, blended in when set
	forceTouch = false, -- debug: keep the touch UI on while using a mouse
	DeviceChanged = Signal.new(),
	SchemeChanged = Signal.new(),
	LastInput = nil :: ControlInput?,
}

local stick = Vector2.zero -- Direct mode: x = roll, y = pitch
local abHold = 0

-- +1 / −1 / 0 from two bound actions (their keys or gamepad buttons, INP-05).
local function actionAxis(positive: string, negative: string): number
	return (if BindingsController:IsDown(positive) then 1 else 0)
		- (if BindingsController:IsDown(negative) then 1 else 0)
end

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
	local scale = MOUSE_AIM_SENSITIVITY * InputController.sensitivity
	local dy = if InputController.invertPitch then -delta.Y else delta.Y
	local yaw = CFrame.fromAxisAngle(camCF.UpVector, -delta.X * scale)
	local pitch = CFrame.fromAxisAngle(camCF.RightVector, -dy * scale)
	InputController.aimDirection = (yaw * pitch * InputController.aimDirection).Unit
end

local function shape(v: number): number
	local magnitude = math.abs(v)
	if magnitude < STICK_DEADZONE then
		return 0
	end
	local scaled = (magnitude - STICK_DEADZONE) / (1 - STICK_DEADZONE)
	return math.sign(v) * scaled ^ STICK_EXPO
end

local function applyMouseMode()
	local locked = InputController.enabled and not InputController.uiOpen and InputController.device == "KeyboardMouse"
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
	local keyRoll = actionAxis("RollRight", "RollLeft")
		+ (if arrows then keyAxis(Enum.KeyCode.Right, Enum.KeyCode.Left) else 0)
	local keyYaw = actionAxis("YawRight", "YawLeft") -- includes the gamepad bumpers (by default)
	local keyPitch = if arrows then keyAxis(Enum.KeyCode.Down, Enum.KeyCode.Up) else 0 -- pull back = nose up

	local result: ControlInput
	if self.device ~= "KeyboardMouse" then
		result = {
			pitch = math.clamp(self.padStick.Y + keyPitch, -1, 1),
			roll = math.clamp(self.padStick.X + keyRoll, -1, 1),
			yaw = keyYaw,
			throttle = self.throttle,
			afterburner = self.afterburner,
			protections = true,
		}
		local assist = self.assist
		if assist then
			-- Touch aim-assist: lean the stick toward the gun solution while firing.
			result.pitch = math.clamp(result.pitch * 0.5 + assist.pitch * 0.5, -1, 1)
			result.roll = math.clamp(result.roll * 0.5 + assist.roll * 0.5, -1, 1)
			result.yaw = math.clamp(result.yaw * 0.5 + assist.yaw * 0.5, -1, 1)
		end
	elseif self.scheme == "MouseAim" then
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

	-- Throttle and afterburner (keys, or the gamepad triggers)
	local throttleAxis = actionAxis("ThrottleUp", "ThrottleDown")
	if self.device == "Gamepad" then
		throttleAxis += (if self.triggerUp > 0.1 then self.triggerUp else 0) - (if self.triggerDown > 0.1
			then self.triggerDown
			else 0)
		throttleAxis = math.clamp(throttleAxis, -1, 1)
	end
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

	self.override = BindingsController:IsDown("Override")
	self.freeLook = UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
	if self.device == "Gamepad" then
		-- Right stick looks around directly (springs back when released).
		self.freeLook = self.padLook.Magnitude > 0.05
		self.freeLookYaw = -self.padLook.X * math.rad(150)
		self.freeLookPitch = self.padLook.Y * math.rad(80)
		applyMouseMode()
		return
	end

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
			local scale = DIRECT_SENSITIVITY * self.sensitivity
			local dy = if self.invertPitch then -delta.Y else delta.Y
			stick = Vector2.new(math.clamp(stick.X + delta.X * scale, -1, 1), math.clamp(stick.Y + dy * scale, -1, 1))
		end
		-- Free look springs back once released (the camera smooths it).
		self.freeLookYaw, self.freeLookPitch = 0, 0
	end

	if self.scheme == "Direct" then
		local decay = math.max(0, 1 - DIRECT_RECENTRE * dt)
		stick *= decay
	end
end

function InputController:SetDevice(device: Device)
	if self.device ~= device then
		self.device = device
		applyMouseMode()
		self.DeviceChanged:Fire(device)
	end
end

function InputController:Init()
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		self.device = "Touch"
	end
	UserInputService.LastInputTypeChanged:Connect(function(inputType)
		if self.forceTouch then
			return
		elseif inputType == Enum.UserInputType.Gamepad1 then
			self:SetDevice("Gamepad")
		elseif inputType == Enum.UserInputType.Touch then
			self:SetDevice("Touch")
		elseif
			inputType == Enum.UserInputType.Keyboard
			or inputType == Enum.UserInputType.MouseMovement
			or inputType == Enum.UserInputType.MouseButton1
		then
			self:SetDevice("KeyboardMouse")
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.Gamepad1 then
			return
		end
		if input.KeyCode == Enum.KeyCode.Thumbstick1 then
			-- Stick forward = nose down (flight convention), so pitch is the inverse of the stick's Y.
			self.padStick = Vector2.new(shape(input.Position.X), -shape(input.Position.Y))
		elseif input.KeyCode == Enum.KeyCode.Thumbstick2 then
			self.padLook = Vector2.new(shape(input.Position.X), shape(input.Position.Y))
		elseif input.KeyCode == Enum.KeyCode.ButtonR2 then
			self.triggerUp = input.Position.Z
		elseif input.KeyCode == Enum.KeyCode.ButtonL2 then
			self.triggerDown = input.Position.Z
		end
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and BindingsController:Matches(input, "SwitchScheme") then
			self:SetScheme(if self.scheme == "MouseAim" then "Direct" else "MouseAim")
		end
	end)
end

function InputController:Start()
	RunService:BindToRenderStep("AfterburnerInput", Enum.RenderPriority.Input.Value, update)
end

return InputController
