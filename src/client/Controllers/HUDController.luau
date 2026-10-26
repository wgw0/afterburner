--!strict
-- Flight HUD (DEVELOPMENT.md §9, HUD-01 + HUD-07 design pass).
--
-- A collimated HUD: the symbology lives in a box centred on the jet's boresight (where the nose points)
-- and is conformal, so the pitch ladder and flight path marker line up with the real world. The box is
-- sized in degrees (about 28° × 22°), like a real HUD's field of view, and moves with the nose when you
-- free-look. It's a CanvasGroup so rotated ladder rungs are clipped to the box.
--
-- Inside the box: heading tape (top), speed tape (left), altitude tape (right), pitch ladder, horizon,
-- flight path marker, gun cross, G / Mach / AoA (bottom left), vertical speed and throttle (bottom
-- right), warnings. Outside the box: the Mouse Aim reticle, fuel and the key help line.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Units = require(Shared.Units)

local FlightController = require(script.Parent.FlightController)
local InputController = require(script.Parent.InputController)

local GREEN = Color3.fromRGB(110, 255, 150)
local AMBER = Color3.fromRGB(255, 190, 80)
local RED = Color3.fromRGB(255, 85, 70)
local AIM_WHITE = Color3.fromRGB(230, 255, 235)
local FONT = Enum.Font.RobotoMono

local BOX_WIDTH_DEG = 28
local BOX_HEIGHT_DEG = 22
local LADDER_STEP = 5 -- degrees between pitch rungs

local HUDController = {
	Priority = 60,
	gui = nil :: ScreenGui?,
}

type Tape = { frame: Frame, labels: { TextLabel }, ticks: { Frame }, valueBox: TextLabel }
type Rung = { holder: Frame, pitch: number }

local box: CanvasGroup
local rungs: { Rung } = {}
local horizon: Frame
local fpm: Frame
local gunCross: TextLabel
local speedTape: Tape
local altTape: Tape
local headingTape: Tape
local readouts: { [string]: TextLabel } = {}
local warningLabel: TextLabel
local aimReticle: Frame
local fuelLabel: TextLabel
local helpLabel: TextLabel

---------------------------------------------------------------------------
-- Building blocks
---------------------------------------------------------------------------

local function glow(obj: GuiObject)
	local stroke = Instance.new("UIStroke")
	stroke.Color = GREEN
	stroke.Transparency = 0.82
	stroke.Thickness = 2
	stroke.ApplyStrokeMode = if obj:IsA("TextLabel")
		then Enum.ApplyStrokeMode.Contextual
		else Enum.ApplyStrokeMode.Border
	stroke.Parent = obj
end

local function text(parent: Instance, size: number, align: Enum.TextXAlignment?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = FONT
	l.TextColor3 = GREEN
	l.TextSize = size
	l.TextXAlignment = align or Enum.TextXAlignment.Center
	l.Size = UDim2.fromOffset(120, size + 4)
	l.Parent = parent
	glow(l)
	return l
end

local function line(parent: Instance, w: number, h: number): Frame
	local f = Instance.new("Frame")
	f.BackgroundColor3 = GREEN
	f.BorderSizePixel = 0
	f.Size = UDim2.fromOffset(w, h)
	f.Parent = parent
	return f
end

local function circle(parent: Instance, size: number, thickness: number, colour: Color3): Frame
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Size = UDim2.fromOffset(size, size)
	f.BackgroundTransparency = 1
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = f
	local stroke = Instance.new("UIStroke")
	stroke.Color = colour
	stroke.Thickness = thickness
	stroke.Parent = f
	f.Parent = parent
	return f
end

-- A scrolling tape. vertical = speed/altitude, otherwise heading.
local function makeTape(parent: Instance, vertical: boolean, count: number): Tape
	local frame = Instance.new("Frame")
	frame.BackgroundTransparency = 1
	frame.ClipsDescendants = true
	frame.Parent = parent
	local labels, ticks = {}, {}
	for _ = 1, count do
		table.insert(ticks, line(frame, 2, 2))
		local l = text(frame, 15)
		l.Size = UDim2.fromOffset(if vertical then 54 else 40, 18)
		table.insert(labels, l)
	end
	local valueBox = text(parent, 20)
	valueBox.BackgroundColor3 = Color3.new(0, 0, 0)
	valueBox.BackgroundTransparency = 0.55
	valueBox.Size = UDim2.fromOffset(if vertical then 74 else 56, 26)
	local border = Instance.new("UIStroke")
	border.Color = GREEN
	border.Thickness = 1.5
	border.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	border.Parent = valueBox
	return { frame = frame, labels = labels, ticks = ticks, valueBox = valueBox }
end

local function makeRung(pitch: number): Frame
	local holder = Instance.new("Frame")
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromOffset(220, 16)
	holder.Parent = box
	local dashed = pitch < 0 -- below the horizon: dashed rungs, like a real HUD
	for _, side in { -1, 1 } do
		if dashed then
			for i = 1, 3 do
				local bar = line(holder, 18, 2)
				bar.AnchorPoint = Vector2.new(0.5, 0.5)
				bar.Position = UDim2.new(0.5, side * (75 + (i - 2) * 26), 0.5, 0)
			end
		else
			local bar = line(holder, 70, 2)
			bar.AnchorPoint = Vector2.new(0.5, 0.5)
			bar.Position = UDim2.new(0.5, side * 75, 0.5, 0)
		end
		-- End tick points toward the horizon
		local tick = line(holder, 2, 8)
		tick.AnchorPoint = Vector2.new(0.5, if pitch > 0 then 0 else 1)
		tick.Position = UDim2.new(0.5, side * 110, 0.5, 0)
	end
	for _, side in { -1, 1 } do
		local label = text(holder, 13, if side < 0 then Enum.TextXAlignment.Right else Enum.TextXAlignment.Left)
		label.AnchorPoint = Vector2.new(if side < 0 then 1 else 0, 0.5)
		label.Size = UDim2.fromOffset(28, 14)
		label.Position = if side < 0 then UDim2.new(0, -6, 0.5, 0) else UDim2.new(1, 6, 0.5, 0)
		label.Text = tostring(math.abs(pitch))
	end
	return holder
end

---------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------

local function build(): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "AfterburnerHUD"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 5
	gui.Enabled = false

	box = Instance.new("CanvasGroup")
	box.Name = "HUDBox"
	box.BackgroundTransparency = 1
	box.Parent = gui

	for pitch = -85, 85, LADDER_STEP do
		if pitch ~= 0 then
			table.insert(rungs, { holder = makeRung(pitch), pitch = pitch })
		end
	end

	horizon = Instance.new("Frame")
	horizon.AnchorPoint = Vector2.new(0.5, 0.5)
	horizon.BackgroundTransparency = 1
	horizon.Size = UDim2.fromOffset(260, 4)
	horizon.Parent = box
	for _, side in { -1, 1 } do
		local bar = line(horizon, 100, 2)
		bar.AnchorPoint = Vector2.new(0.5, 0.5)
		bar.Position = UDim2.new(0.5, side * 80, 0.5, 0)
	end

	-- Flight path marker: circle with wings and a tail.
	fpm = circle(box, 16, 2, GREEN)
	local wingL = line(fpm, 14, 2)
	wingL.AnchorPoint = Vector2.new(1, 0.5)
	wingL.Position = UDim2.fromScale(0, 0.5)
	local wingR = line(fpm, 14, 2)
	wingR.AnchorPoint = Vector2.new(0, 0.5)
	wingR.Position = UDim2.fromScale(1, 0.5)
	local tail = line(fpm, 2, 8)
	tail.AnchorPoint = Vector2.new(0.5, 1)
	tail.Position = UDim2.fromScale(0.5, 0)

	gunCross = text(box, 22)
	gunCross.AnchorPoint = Vector2.new(0.5, 0.5)
	gunCross.Size = UDim2.fromOffset(60, 24)
	gunCross.Text = "─w─"

	speedTape = makeTape(box, true, 16)
	altTape = makeTape(box, true, 16)
	headingTape = makeTape(box, false, 16)

	for _, name in { "G", "Mach", "AoA" } do
		readouts[name] = text(box, 16, Enum.TextXAlignment.Left)
	end
	for _, name in { "VS", "Throttle" } do
		readouts[name] = text(box, 16, Enum.TextXAlignment.Right)
	end

	warningLabel = text(box, 24)
	warningLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	warningLabel.Size = UDim2.fromOffset(240, 28)
	warningLabel.TextColor3 = RED

	-- Outside the HUD box
	aimReticle = circle(gui, 30, 1.5, AIM_WHITE)
	local dot = Instance.new("Frame")
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.fromScale(0.5, 0.5)
	dot.Size = UDim2.fromOffset(3, 3)
	dot.BackgroundColor3 = AIM_WHITE
	dot.BorderSizePixel = 0
	dot.Parent = aimReticle

	fuelLabel = text(gui, 15, Enum.TextXAlignment.Left)
	fuelLabel.AnchorPoint = Vector2.new(0, 1)
	fuelLabel.Position = UDim2.new(0, 20, 1, -20)
	fuelLabel.Size = UDim2.fromOffset(320, 18)

	helpLabel = text(gui, 13, Enum.TextXAlignment.Right)
	helpLabel.AnchorPoint = Vector2.new(1, 1)
	helpLabel.Position = UDim2.new(1, -20, 1, -20)
	helpLabel.Size = UDim2.fromOffset(560, 16)
	helpLabel.TextTransparency = 0.35

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	return gui
end

---------------------------------------------------------------------------
-- Update
---------------------------------------------------------------------------

type TapeLayout = {
	value: number,
	tickStep: number,
	labelEvery: number,
	pxPerUnit: number,
	vertical: boolean,
	length: number,
	format: (number) -> string,
}

local function layoutTape(tape: Tape, t: TapeLayout)
	local base = math.floor(t.value / t.tickStep) * t.tickStep
	local half = math.floor(#tape.ticks / 2)
	local stepsPerLabel = math.round(t.labelEvery / t.tickStep)
	for i, tick in tape.ticks do
		local index = math.round(base / t.tickStep) + (i - half)
		local tickValue = index * t.tickStep
		local offset = (tickValue - t.value) * t.pxPerUnit
		local labelled = index % stepsPerLabel == 0
		local label = tape.labels[i]
		if t.vertical then
			local y = t.length / 2 - offset
			tick.Position = UDim2.fromOffset(0, y)
			tick.Size = UDim2.fromOffset(if labelled then 14 else 7, 2)
			label.Position = UDim2.fromOffset(16, y - 9)
		else
			local x = t.length / 2 + offset
			tick.Position = UDim2.fromOffset(x, 0)
			tick.Size = UDim2.fromOffset(2, if labelled then 12 else 6)
			label.Position = UDim2.fromOffset(x - 20, 12)
		end
		label.Visible = labelled
		if labelled then
			label.Text = t.format(tickValue)
		end
	end
end

local function project(camera: Camera, direction: Vector3): (Vector2, boolean)
	local p, onScreen = camera:WorldToViewportPoint(camera.CFrame.Position + direction * 5000)
	return Vector2.new(p.X, p.Y), onScreen and p.Z > 0
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
	local viewport = camera.ViewportSize
	local jetCF = root.CFrame
	local look, up = jetCF.LookVector, jetCF.UpVector

	-- Size the box in degrees, using pixels-per-degree at the screen centre.
	local focal = (viewport.Y / 2) / math.tan(math.rad(camera.FieldOfView / 2))
	local pxPerDeg = focal * math.tan(math.rad(1))
	local boxW = math.min(math.floor(pxPerDeg * BOX_WIDTH_DEG), viewport.X - 40)
	local boxH = math.min(math.floor(pxPerDeg * BOX_HEIGHT_DEG), viewport.Y - 60)

	-- The box follows the boresight (the nose), like symbology on the HUD glass.
	local nose, noseVisible = project(camera, look)
	box.Visible = noseVisible
	box.Size = UDim2.fromOffset(boxW, boxH)
	local boxOrigin = nose - Vector2.new(boxW / 2, boxH / 2)
	box.Position = UDim2.fromOffset(boxOrigin.X, boxOrigin.Y)
	local function toBox(screen: Vector2): UDim2
		local p = screen - boxOrigin
		return UDim2.fromOffset(p.X, p.Y)
	end

	-- Clip by hand: CanvasGroup clipping isn't reliable on every device (it can fall back to drawing
	-- unclipped), so anything outside the box's inner area is simply hidden.
	local function inside(screen: Vector2, marginX: number, marginY: number): boolean
		local p = screen - boxOrigin
		return p.X >= marginX and p.X <= boxW - marginX and p.Y >= marginY and p.Y <= boxH - marginY
	end

	gunCross.Position = UDim2.fromOffset(boxW / 2, boxH / 2)

	-- Pitch ladder and horizon: conformal, rotated by bank
	local flat = Vector3.new(look.X, 0, look.Z)
	flat = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.new(0, 0, -1)
	local bank = math.deg(math.atan2(-jetCF.RightVector.Y, up.Y))
	local h, hVisible = project(camera, flat)
	horizon.Visible = hVisible and inside(h, 90, 24)
	horizon.Position = toBox(h)
	horizon.Rotation = -bank
	for _, rung in rungs do
		local p = math.rad(rung.pitch)
		local screen, visible = project(camera, flat * math.cos(p) + Vector3.new(0, math.sin(p), 0))
		rung.holder.Visible = visible and inside(screen, 90, 24)
		rung.holder.Position = toBox(screen)
		rung.holder.Rotation = -bank
	end

	if state.velocity.Magnitude > 1 then
		local v, vVisible = project(camera, state.velocity.Unit)
		fpm.Visible = vVisible and inside(v, 10, 10)
		fpm.Position = toBox(v)
	end

	-- Tapes
	local tapeH = math.floor(boxH * 0.62)
	local knots = Units.knots(state.speed)
	local feet = Units.feet(state.altitude)
	speedTape.frame.Size = UDim2.fromOffset(70, tapeH)
	speedTape.frame.Position = UDim2.fromOffset(16, (boxH - tapeH) / 2)
	layoutTape(speedTape, {
		value = knots,
		tickStep = 10,
		labelEvery = 50,
		pxPerUnit = tapeH / 140,
		vertical = true,
		length = tapeH,
		format = function(v)
			return tostring(math.max(v, 0))
		end,
	})
	speedTape.valueBox.Position = UDim2.fromOffset(12, boxH / 2 - 13)
	speedTape.valueBox.Text = tostring(math.round(knots))

	altTape.frame.Size = UDim2.fromOffset(70, tapeH)
	altTape.frame.Position = UDim2.fromOffset(boxW - 86, (boxH - tapeH) / 2)
	layoutTape(altTape, {
		value = feet,
		tickStep = 100,
		labelEvery = 500,
		pxPerUnit = tapeH / 1400,
		vertical = true,
		length = tapeH,
		format = tostring,
	})
	altTape.valueBox.Position = UDim2.fromOffset(boxW - 90, boxH / 2 - 13)
	altTape.valueBox.Text = tostring(math.round(feet / 10) * 10)

	local heading = (math.deg(math.atan2(look.X, -look.Z)) + 360) % 360
	local tapeW = math.floor(boxW * 0.5)
	headingTape.frame.Size = UDim2.fromOffset(tapeW, 32)
	headingTape.frame.Position = UDim2.fromOffset((boxW - tapeW) / 2, 8)
	layoutTape(headingTape, {
		value = heading,
		tickStep = 5,
		labelEvery = 10,
		pxPerUnit = tapeW / 50,
		vertical = false,
		length = tapeW,
		format = function(v)
			return string.format("%02d", math.round((v % 360) / 10) % 36)
		end,
	})
	headingTape.valueBox.Position = UDim2.fromOffset(boxW / 2 - 28, 42)
	headingTape.valueBox.Text = string.format("%03d", math.round(heading) % 360)

	-- Corner readouts
	local airframe = FlightController.airframe
	local input = FlightController.input
	local leftX, bottomY = 18, boxH - 92
	readouts.G.Position = UDim2.fromOffset(leftX, bottomY)
	readouts.G.Text = string.format("G  %4.1f", state.gLoad)
	readouts.G.TextColor3 = if airframe and state.gLoad > airframe.MaxG * 0.95 then RED else GREEN
	readouts.Mach.Position = UDim2.fromOffset(leftX, bottomY + 20)
	readouts.Mach.Text = string.format("M  %.2f", state.mach)
	readouts.AoA.Position = UDim2.fromOffset(leftX, bottomY + 40)
	readouts.AoA.Text = string.format("α  %4.1f", math.deg(state.aoa))
	readouts.AoA.TextColor3 = if state.stalled then RED else GREEN

	local rightX = boxW - 18 - 120
	readouts.VS.Position = UDim2.fromOffset(rightX, bottomY + 20)
	readouts.VS.Text = string.format("%+d VS", math.round(Units.feet(state.velocity.Y) * 60 / 100) * 100)
	if input then
		readouts.Throttle.Position = UDim2.fromOffset(rightX, bottomY + 40)
		readouts.Throttle.Text = if input.afterburner then "AB" else `THR {math.round(input.throttle * 100)}`
		readouts.Throttle.TextColor3 = if input.afterburner then AMBER else GREEN
	end

	-- Warnings, most urgent first
	local warning = ""
	if state.velocity.Y < -30 and Units.feet(state.altitude) < 2500 then
		warning = "PULL UP"
	elseif state.stalled then
		warning = "STALL"
	elseif airframe and state.gLoad > airframe.MaxG * 0.97 then
		warning = "OVER-G"
	elseif state.gStress > 0.6 then
		warning = "G-LIMIT"
	elseif airframe and state.fuel < airframe.Fuel * 0.15 then
		warning = "BINGO"
	end
	warningLabel.Position = UDim2.fromOffset(boxW / 2, boxH * 0.72)
	warningLabel.Text = warning
	warningLabel.Visible = warning ~= "" and (os.clock() % 0.6) < 0.4

	-- Outside the box
	if InputController.scheme == "MouseAim" then
		local aim, aimVisible = project(camera, InputController.aimDirection)
		aimReticle.Visible = aimVisible
		aimReticle.Position = UDim2.fromOffset(aim.X, aim.Y)
	else
		aimReticle.Visible = false
	end
	if airframe then
		fuelLabel.Text =
			string.format("FUEL %d KG  %d%%", math.round(state.fuel), math.round(state.fuel / airframe.Fuel * 100))
	end
	helpLabel.Text =
		`{if InputController.scheme == "MouseAim" then "MOUSE AIM" else "DIRECT"} · M scheme · V camera · Z zoom · P tuning`
end

function HUDController:Start()
	self.gui = build()
	-- After the camera has moved this frame, so projections match what's on screen.
	RunService:BindToRenderStep("AfterburnerHUD", Enum.RenderPriority.Camera.Value + 2, update)
end

return HUDController
