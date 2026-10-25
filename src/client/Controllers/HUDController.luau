--!strict
-- Screen-space flight HUD (DEVELOPMENT.md §9). Built once, updated every frame by setting properties.
-- Phase 1 elements: speed, Mach, altitude, G, throttle/AB, fuel, heading, AoA, flight path marker,
-- boresight (where the nose points), Mouse Aim reticle, and warnings (stall, over-G, pull up, fuel).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Units = require(Shared.Units)

local FlightController = require(script.Parent.FlightController)
local InputController = require(script.Parent.InputController)

local HUD_GREEN = Color3.fromRGB(93, 255, 168)
local WARN_RED = Color3.fromRGB(255, 80, 70)
local FONT = Enum.Font.Code

local HUDController = {
	Priority = 60,
	gui = nil :: ScreenGui?,
}

local elements: { [string]: GuiObject } = {}

local function label(name: string, parent: Instance, props: { [string]: any }): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Font = FONT
	l.TextColor3 = HUD_GREEN
	l.TextStrokeTransparency = 0.6
	l.TextSize = 20
	for k, v in props do
		(l :: any)[k] = v
	end
	l.Parent = parent
	elements[name] = l
	return l
end

local function ring(name: string, parent: Instance, size: number, thickness: number): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Size = UDim2.fromOffset(size, size)
	f.BackgroundTransparency = 1
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = f
	local stroke = Instance.new("UIStroke")
	stroke.Color = HUD_GREEN
	stroke.Thickness = thickness
	stroke.Parent = f
	f.Parent = parent
	elements[name] = f
	return f
end

local function build(): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "AfterburnerHUD"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 5
	gui.Enabled = false

	-- Readouts live in a 1600x900 frame centred on screen. UIScale scales around the frame's anchor
	-- (the screen centre), so the layout stays centred at any resolution. Symbols projected from the
	-- world (boresight, flight path, aim) stay outside it: their positions are real screen pixels.
	local centre = Instance.new("Frame")
	centre.Name = "Centre"
	centre.BackgroundTransparency = 1
	centre.AnchorPoint = Vector2.new(0.5, 0.5)
	centre.Position = UDim2.fromScale(0.5, 0.5)
	centre.Size = UDim2.fromOffset(1600, 900)
	centre.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Name = "Scale"
	scale.Parent = centre

	label("Speed", centre, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(0.5, -260, 0.5, 0),
		Size = UDim2.fromOffset(160, 30),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextSize = 26,
	})
	label("Mach", centre, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(0.5, -260, 0.5, 28),
		Size = UDim2.fromOffset(160, 24),
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	label("Altitude", centre, {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0.5, 260, 0.5, 0),
		Size = UDim2.fromOffset(180, 30),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 26,
	})
	label("Climb", centre, {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0.5, 260, 0.5, 28),
		Size = UDim2.fromOffset(180, 24),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	label("Heading", centre, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 24),
		Size = UDim2.fromOffset(200, 30),
		TextSize = 26,
	})
	label("GLoad", centre, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(0.5, -260, 0.5, -40),
		Size = UDim2.fromOffset(160, 26),
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	label("AoA", centre, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(0.5, -260, 0.5, 56),
		Size = UDim2.fromOffset(160, 24),
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	label("Throttle", gui, {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 24, 1, -24),
		Size = UDim2.fromOffset(260, 26),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	label("Fuel", gui, {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 24, 1, -52),
		Size = UDim2.fromOffset(260, 26),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	label("Scheme", gui, {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -24, 1, -24),
		Size = UDim2.fromOffset(420, 26),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextSize = 16,
		TextTransparency = 0.3,
	})
	label("Warning", centre, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 150),
		Size = UDim2.fromOffset(400, 36),
		TextSize = 30,
		TextColor3 = WARN_RED,
	})

	-- Boresight: where the nose points.
	label("Boresight", gui, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(60, 24),
		Text = "-w-",
		TextSize = 24,
	})
	ring("FlightPath", gui, 18, 2)
	ring("AimReticle", gui, 34, 1.5)

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	return gui
end

local function place(element: GuiObject, worldPoint: Vector3): boolean
	local camera = workspace.CurrentCamera :: Camera
	local screen, onScreen = camera:WorldToViewportPoint(worldPoint)
	element.Visible = onScreen
	element.Position = UDim2.fromOffset(screen.X, screen.Y)
	return onScreen
end

local function update()
	local gui = HUDController.gui
	local state, root = FlightController.state, FlightController.root
	if not (gui and state and root) then
		if gui then
			gui.Enabled = false
		end
		return
	end
	gui.Enabled = not FlightController:IsUnconscious()

	local camera = workspace.CurrentCamera :: Camera
	local viewport = camera.ViewportSize;
	((gui:FindFirstChild("Centre") :: Frame):FindFirstChild("Scale") :: UIScale).Scale =
		math.clamp(math.min(viewport.X / 1600, viewport.Y / 900), 0.6, 1.4)

	local input = FlightController.input
	local airframe = FlightController.airframe;
	(elements.Speed :: TextLabel).Text = `{math.round(Units.knots(state.speed))} KT`
	(elements.Mach :: TextLabel).Text = string.format("M %.2f", state.mach);
	(elements.Altitude :: TextLabel).Text = `{math.round(Units.feet(state.altitude) / 10) * 10} FT`
	local climbFpm = Units.feet(state.velocity.Y) * 60
	(elements.Climb :: TextLabel).Text = string.format("%+d FPM", math.round(climbFpm / 100) * 100)
	local look = root.CFrame.LookVector
	local heading = (math.deg(math.atan2(look.X, -look.Z)) + 360) % 360
	(elements.Heading :: TextLabel).Text = string.format("%03d", math.round(heading) % 360);
	(elements.GLoad :: TextLabel).Text = string.format("%.1f G", state.gLoad);
	(elements.AoA :: TextLabel).Text = string.format("α %.1f°", math.deg(state.aoa))

	if input then
		local pct = math.round(input.throttle * 100);
		(elements.Throttle :: TextLabel).Text = if input.afterburner then `THR {pct}%  AB` else `THR {pct}%`
		(elements.Throttle :: TextLabel).TextColor3 = if input.afterburner
			then Color3.fromRGB(255, 170, 60)
			else HUD_GREEN
	end
	if airframe then
		local fuelPct = math.round(state.fuel / airframe.Fuel * 100);
		(elements.Fuel :: TextLabel).Text = `FUEL {math.round(state.fuel)} KG ({fuelPct}%)`
	end
	(elements.Scheme :: TextLabel).Text =
		`{if InputController.scheme == "MouseAim" then "MOUSE AIM" else "DIRECT"}  [M] scheme  [V] camera  [Z] zoom  [P] tuning`

	-- Warnings, most urgent first
	local warning = ""
	local feetAboveGround = Units.feet(state.altitude)
	if state.velocity.Y < -30 and feetAboveGround < 2500 then
		warning = "PULL UP"
	elseif state.stalled then
		warning = "STALL"
	elseif airframe and state.gLoad > airframe.MaxG * 0.97 then
		warning = "OVER-G"
	elseif state.gStress > 0.6 then
		warning = "G-LIMIT"
	elseif airframe and state.fuel < airframe.Fuel * 0.15 then
		warning = "BINGO FUEL"
	end
	(elements.Warning :: TextLabel).Text = warning;
	(elements.Warning :: TextLabel).Visible = warning ~= "" and (os.clock() % 0.6) < 0.4

	-- Projected symbols
	local origin = camera.CFrame.Position
	place(elements.Boresight, origin + look * 2000)
	local velocity = state.velocity
	if velocity.Magnitude > 1 then
		place(elements.FlightPath, origin + velocity.Unit * 2000)
	end
	local aim = elements.AimReticle
	if InputController.scheme == "MouseAim" then
		place(aim, origin + InputController.aimDirection * 2000)
	else
		aim.Visible = false
	end
end

function HUDController:Start()
	self.gui = build()
	RunService.RenderStepped:Connect(update)
end

return HUDController
