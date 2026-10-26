--!strict
-- Touch controls (DEVELOPMENT.md §7, INP-04). Shown when the device is touch (or forced on from the tuning
-- panel in the test environment).
--   Left: a virtual stick for pitch and roll (drag; releases to centre).
--   Right: a throttle slider (top 12% = afterburner) and big buttons: FIRE (hold), MSL, LOCK, FLR, CHF, CAM.
--   Auto-throttle (on by default): holds about 420 knots until you touch the slider; AUTO turns it back on.
--   Gun aim-assist: while firing with a target close to the nose, the stick leans toward the gun solution.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Ballistics = require(Shared.Ballistics)
local Instructor = require(Shared.Instructor)
local Net = require(Shared.Net)
local WeaponData = require(Shared.WeaponData)

local CameraController = require(script.Parent.CameraController)
local FlightController = require(script.Parent.FlightController)
local InputController = require(script.Parent.InputController)
local SensorController = require(script.Parent.SensorController)
local WeaponController = require(script.Parent.WeaponController)

local STICK_SIZE = 170
local KNOB_SIZE = 70
local BUTTON_SIZE = 74
local ASSIST_CONE = math.rad(10)
local ASSIST_RANGE = 1000 -- real metres
local AUTO_SPEED = 216 -- real m/s (about 420 knots)

local TouchController = {
	Priority = 88,
	firing = false,
	autoThrottle = true,
}

local gui: ScreenGui
local stickBase: Frame
local knob: Frame
local stickInput: InputObject? = nil
local throttleBar: Frame
local throttleFill: Frame
local throttleInput: InputObject? = nil
local autoButton: TextButton

local function round(f: GuiObject, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = f
end

local function button(text: string, position: UDim2, size: number, onDown: () -> (), onUp: (() -> ())?): TextButton
	local b = Instance.new("TextButton")
	b.AnchorPoint = Vector2.new(0.5, 0.5)
	b.Position = position
	b.Size = UDim2.fromOffset(size, size)
	b.BackgroundColor3 = Color3.fromRGB(20, 30, 46)
	b.BackgroundTransparency = 0.3
	b.Font = Enum.Font.GothamBold
	b.TextColor3 = Color3.new(1, 1, 1)
	b.TextSize = math.floor(size * 0.24)
	b.Text = text
	b.AutoButtonColor = true
	round(b, size // 2)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 138, 61)
	stroke.Thickness = 2
	stroke.Transparency = 0.3
	stroke.Parent = b
	b.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1
		then
			onDown()
		end
	end)
	if onUp then
		b.InputEnded:Connect(function(input)
			if
				input.UserInputType == Enum.UserInputType.Touch
				or input.UserInputType == Enum.UserInputType.MouseButton1
			then
				onUp()
			end
		end)
	end
	b.Parent = gui
	return b
end

local function setStick(screen: Vector2?)
	if not screen then
		knob.Position = UDim2.fromScale(0.5, 0.5)
		InputController.padStick = Vector2.zero
		return
	end
	local centre = stickBase.AbsolutePosition + stickBase.AbsoluteSize / 2
	local offset = screen - centre
	local radius = STICK_SIZE / 2
	if offset.Magnitude > radius then
		offset = offset.Unit * radius
	end
	knob.Position = UDim2.new(0.5, offset.X, 0.5, offset.Y)
	local normal = offset / radius
	-- Drag down = pull back = nose up.
	InputController.padStick = Vector2.new(normal.X, normal.Y)
end

local function showThrottle(fraction: number)
	throttleFill.Size = UDim2.fromScale(1, fraction)
	throttleFill.BackgroundColor3 = if InputController.afterburner
		then Color3.fromRGB(255, 150, 60)
		else Color3.fromRGB(110, 255, 150)
end

local function setAuto(on: boolean)
	TouchController.autoThrottle = on
	autoButton.BackgroundColor3 = if on then Color3.fromRGB(40, 110, 70) else Color3.fromRGB(20, 30, 46)
end

local function setThrottle(screen: Vector2)
	setAuto(false)
	local top = throttleBar.AbsolutePosition.Y
	local height = throttleBar.AbsoluteSize.Y
	local fraction = 1 - math.clamp((screen.Y - top) / height, 0, 1)
	InputController.afterburner = fraction >= 0.88
	InputController.throttle = math.clamp(fraction / 0.88, 0, 1)
	showThrottle(fraction)
end

-- Auto-throttle: a simple proportional hold on AUTO_SPEED, afterburner when well below it.
local function updateAutoThrottle()
	local state = FlightController.state
	if not (TouchController.autoThrottle and state and gui.Enabled) then
		return
	end
	local error = AUTO_SPEED - state.speed
	InputController.afterburner = error > 40
	InputController.throttle = math.clamp(0.8 + error / 60, 0.3, 1)
	showThrottle(if InputController.afterburner then 1 else InputController.throttle * 0.88)
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "AfterburnerTouch"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 8
	gui.Enabled = false

	stickBase = Instance.new("Frame")
	stickBase.AnchorPoint = Vector2.new(0, 1)
	stickBase.Position = UDim2.new(0, 40, 1, -40)
	stickBase.Size = UDim2.fromOffset(STICK_SIZE, STICK_SIZE)
	stickBase.BackgroundColor3 = Color3.fromRGB(20, 30, 46)
	stickBase.BackgroundTransparency = 0.5
	stickBase.Active = true
	round(stickBase, STICK_SIZE // 2)
	stickBase.Parent = gui
	knob = Instance.new("Frame")
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Position = UDim2.fromScale(0.5, 0.5)
	knob.Size = UDim2.fromOffset(KNOB_SIZE, KNOB_SIZE)
	knob.BackgroundColor3 = Color3.fromRGB(255, 138, 61)
	knob.BackgroundTransparency = 0.2
	round(knob, KNOB_SIZE // 2)
	knob.Parent = stickBase
	stickBase.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch and not stickInput then
			stickInput = input
			setStick(Vector2.new(input.Position.X, input.Position.Y))
		end
	end)

	throttleBar = Instance.new("Frame")
	throttleBar.AnchorPoint = Vector2.new(1, 1)
	throttleBar.Position = UDim2.new(1, -250, 1, -40)
	throttleBar.Size = UDim2.fromOffset(46, 220)
	throttleBar.BackgroundColor3 = Color3.fromRGB(20, 30, 46)
	throttleBar.BackgroundTransparency = 0.4
	throttleBar.Active = true
	throttleBar.ClipsDescendants = true
	round(throttleBar, 10)
	throttleBar.Parent = gui
	throttleFill = Instance.new("Frame")
	throttleFill.AnchorPoint = Vector2.new(0, 1)
	throttleFill.Position = UDim2.fromScale(0, 1)
	throttleFill.Size = UDim2.fromScale(1, 0.7)
	throttleFill.BackgroundColor3 = Color3.fromRGB(110, 255, 150)
	throttleFill.BackgroundTransparency = 0.4
	throttleFill.BorderSizePixel = 0
	throttleFill.Parent = throttleBar
	local abLine = Instance.new("Frame")
	abLine.Position = UDim2.fromScale(0, 0.12)
	abLine.Size = UDim2.new(1, 0, 0, 2)
	abLine.BackgroundColor3 = Color3.fromRGB(255, 150, 60)
	abLine.BorderSizePixel = 0
	abLine.Parent = throttleBar
	throttleBar.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch and not throttleInput then
			throttleInput = input
			setThrottle(Vector2.new(input.Position.X, input.Position.Y))
		end
	end)

	-- Buttons (right side)
	button("FIRE", UDim2.new(1, -110, 1, -110), BUTTON_SIZE + 26, function()
		TouchController.firing = true
		WeaponController:SetTrigger(true)
	end, function()
		TouchController.firing = false
		WeaponController:SetTrigger(false)
	end)
	button("MSL", UDim2.new(1, -205, 1, -195), BUTTON_SIZE, function()
		WeaponController:FireMissile()
	end)
	button("LOCK", UDim2.new(1, -110, 1, -235), BUTTON_SIZE, function()
		WeaponController:ToggleLock()
	end)
	button("FLR", UDim2.new(1, -205, 1, -285), BUTTON_SIZE - 10, function()
		Net.Client.fire("CountermeasureDeploy", "Flare")
	end)
	button("CHF", UDim2.new(1, -110, 1, -330), BUTTON_SIZE - 10, function()
		Net.Client.fire("CountermeasureDeploy", "Chaff")
	end)
	button("WPN", UDim2.new(1, -40, 1, -330), BUTTON_SIZE - 24, function()
		WeaponController:CycleMissile()
	end)
	button("CAM", UDim2.new(1, -40, 1, -270), BUTTON_SIZE - 24, function()
		CameraController:SetMode(if CameraController.mode == "Cockpit" then "Chase" else "Cockpit")
	end)
	autoButton = button("AUTO", UDim2.new(1, -273, 1, -290), BUTTON_SIZE - 24, function()
		setAuto(not TouchController.autoThrottle)
	end)
	setAuto(true)

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

-- Gun aim-assist: lean toward the lead on the target nearest the nose, while firing.
local function updateAssist()
	InputController.assist = nil
	local state, root, airframe = FlightController.state, FlightController.root, FlightController.airframe
	if not (TouchController.firing and state and root and airframe) then
		return
	end
	local gun = WeaponData.get(airframe.Gun)
	if not gun then
		return
	end
	local best, bestAngle = nil, ASSIST_CONE
	for _, contact in SensorController.contacts do
		local offset = contact.position - root.Position
		local angle = math.acos(math.clamp(root.CFrame.LookVector:Dot(offset.Unit), -1, 1))
		if angle < bestAngle and contact.range <= ASSIST_RANGE then
			best, bestAngle = contact, angle
		end
	end
	if not best then
		return
	end
	local lead = Ballistics.leadDirection(
		root.Position,
		state.velocity,
		best.position,
		best.velocity,
		gun.MuzzleVelocity,
		gun.Lifetime
	)
	if lead then
		InputController.assist = Instructor.compute(state, lead, airframe, { pointNose = true })
	end
end

local function refresh()
	gui.Enabled = InputController.device == "Touch" and FlightController.jet ~= nil
end

function TouchController:Start()
	build()
	UserInputService.TouchMoved:Connect(function(input)
		if input == stickInput then
			setStick(Vector2.new(input.Position.X, input.Position.Y))
		elseif input == throttleInput then
			setThrottle(Vector2.new(input.Position.X, input.Position.Y))
		end
	end)
	UserInputService.TouchEnded:Connect(function(input)
		if input == stickInput then
			stickInput = nil
			setStick(nil)
		elseif input == throttleInput then
			throttleInput = nil
		end
	end)
	InputController.DeviceChanged:Connect(refresh)
	FlightController.JetChanged:Connect(function()
		refresh()
		showThrottle(0.8 * 0.88)
	end)
	RunService.RenderStepped:Connect(function()
		updateAutoThrottle()
		updateAssist()
	end)
	refresh()
end

return TouchController
