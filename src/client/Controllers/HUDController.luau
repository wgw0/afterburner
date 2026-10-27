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
local Ballistics = require(Shared.Ballistics)
local Net = require(Shared.Net)
local Units = require(Shared.Units)
local Guidance = require(Shared.Guidance)
local WeaponData = require(Shared.WeaponData)

local FlightController = require(script.Parent.FlightController)
local InputController = require(script.Parent.InputController)
local SensorController = require(script.Parent.SensorController)

local GREEN = Color3.fromRGB(110, 255, 150)
local AMBER = Color3.fromRGB(255, 190, 80)
local RED = Color3.fromRGB(255, 85, 70)
local CONTACT = Color3.fromRGB(205, 215, 205) -- jets you can see but not lock
local AIM_WHITE = Color3.fromRGB(230, 255, 235)
local FONT = Enum.Font.RobotoMono

local BOX_WIDTH_DEG = 28
local BOX_HEIGHT_DEG = 22
local LADDER_STEP = 5 -- degrees between pitch rungs

local HUDController = {
	Priority = 60,
	gui = nil :: ScreenGui?,
	pullUp = false, -- the PULL UP warning is up
	warnings = {} :: { string }, -- every active warning, most urgent first (ToneController calls them out)
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
local cautionLabel: TextLabel
local terrainParams: RaycastParams
local terrainCheckAt = 0
local terrainAhead = false
local aimReticle: Frame
local fuelLabel: TextLabel
local helpLabel: TextLabel
-- HUD-02: guns
local leadMarker: Frame
local hitMarker: TextLabel
local hitUntil = 0
local killFeed: Frame
local feedLines: { { label: TextLabel, expires: number } } = {}
local targetMarkers: { [Model]: any } = {}
local markerLayer: Frame
-- HUD-03: missiles
local seekerCircle: Frame
local lockLabel: TextLabel
local zoneBar: Frame
local zoneMarks: { [string]: Frame } = {}
local zoneCaret: TextLabel
local shootCue: TextLabel
local missileWarning: TextLabel
local warningArrow: TextLabel

local TARGET_RANGE = 5000 -- real metres: show markers on jets within this
local LEAD_RANGE = 1600 -- real metres: show the gun lead indicator within this
local LEAD_CONE = 30 -- degrees off the nose
local FEED_SECONDS = 7
local FEED_LINES = 5

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
	for _, name in { "VS", "Throttle", "Gun", "Missile", "CM" } do
		readouts[name] = text(box, 16, Enum.TextXAlignment.Right)
	end

	warningLabel = text(box, 24)
	warningLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	warningLabel.Size = UDim2.fromOffset(240, 28)
	warningLabel.TextColor3 = RED
	cautionLabel = text(box, 15)
	cautionLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	cautionLabel.Size = UDim2.fromOffset(300, 18)
	cautionLabel.TextColor3 = AMBER

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
	helpLabel.Size = UDim2.fromOffset(560, 32) -- two lines: flying and camera, then weapons
	helpLabel.TextYAlignment = Enum.TextYAlignment.Bottom
	helpLabel.TextTransparency = 0.35

	-- IR seeker circle: sits on the boresight while searching, jumps onto the target, solid when locked.
	seekerCircle = circle(box, 46, 1.5, GREEN)
	seekerCircle.Visible = false

	-- Launch zone: a vertical scale left of the altitude tape. Caret = target range.
	zoneBar = line(box, 2, 100)
	zoneBar.Visible = false
	for _, mark in { "Max", "NoEscape", "Min" } do
		local m = line(zoneBar, 12, 2)
		m.AnchorPoint = Vector2.new(0, 0.5)
		zoneMarks[mark] = m
	end
	zoneCaret = text(zoneBar, 16)
	zoneCaret.AnchorPoint = Vector2.new(1, 0.5)
	zoneCaret.Size = UDim2.fromOffset(16, 16)
	zoneCaret.Text = "◀"
	shootCue = text(box, 34)
	shootCue.AnchorPoint = Vector2.new(0.5, 0.5)
	shootCue.Size = UDim2.fromOffset(220, 38)
	shootCue.Font = Enum.Font.GothamBlack
	shootCue.TextStrokeTransparency = 0.4
	shootCue.Text = "FIRE"
	shootCue.Visible = false

	-- Gun lead indicator: put the gun cross on it to hit the target.
	leadMarker = circle(box, 22, 2, GREEN)
	local leadDot = line(leadMarker, 4, 4)
	leadDot.AnchorPoint = Vector2.new(0.5, 0.5)
	leadDot.Position = UDim2.fromScale(0.5, 0.5)
	leadMarker.Visible = false

	hitMarker = text(box, 30)
	hitMarker.AnchorPoint = Vector2.new(0.5, 0.5)
	hitMarker.Size = UDim2.fromOffset(40, 34)
	hitMarker.Text = "✕"
	hitMarker.TextColor3 = AMBER
	hitMarker.Visible = false

	-- Markers on other jets, drawn over the whole screen (not clipped to the HUD box).
	markerLayer = Instance.new("Frame")
	markerLayer.BackgroundTransparency = 1
	markerLayer.Size = UDim2.fromScale(1, 1)
	markerLayer.Parent = gui

	-- Range and closure above a locked target (whole screen, so it shows even outside the HUD)
	lockLabel = text(gui, 14)
	lockLabel.AnchorPoint = Vector2.new(0.5, 1)
	lockLabel.Size = UDim2.fromOffset(200, 16)
	lockLabel.Visible = false

	missileWarning = text(gui, 34)
	missileWarning.AnchorPoint = Vector2.new(0.5, 0.5)
	missileWarning.Position = UDim2.new(0.5, 0, 0.5, 190)
	missileWarning.Size = UDim2.fromOffset(300, 40)
	missileWarning.TextColor3 = RED
	missileWarning.Text = "MISSILE"
	missileWarning.Visible = false
	warningArrow = text(gui, 40)
	warningArrow.AnchorPoint = Vector2.new(0.5, 0.5)
	warningArrow.Size = UDim2.fromOffset(44, 44)
	warningArrow.TextColor3 = RED
	warningArrow.Text = "▲"
	warningArrow.Visible = false

	killFeed = Instance.new("Frame")
	killFeed.BackgroundTransparency = 1
	killFeed.AnchorPoint = Vector2.new(1, 0)
	killFeed.Position = UDim2.new(1, -20, 0, 70)
	killFeed.Size = UDim2.fromOffset(420, FEED_LINES * 22)
	killFeed.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = killFeed

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

type Marker = { box: Frame, label: TextLabel, stroke: UIStroke, corner: UICorner }

local function marker(model: Model): Marker
	local existing = targetMarkers[model]
	if existing then
		return existing
	end
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Size = UDim2.fromOffset(18, 18)
	f.BackgroundTransparency = 1
	local stroke = Instance.new("UIStroke")
	stroke.Color = CONTACT
	stroke.Thickness = 1
	stroke.Parent = f
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 0)
	corner.Parent = f
	f.Parent = markerLayer
	local l = text(markerLayer, 13)
	l.AnchorPoint = Vector2.new(0.5, 0)
	l.Size = UDim2.fromOffset(160, 16)
	l.TextColor3 = CONTACT
	local entry = { box = f, label = l, stroke = stroke, corner = corner }
	targetMarkers[model] = entry
	return entry
end

-- Lock symbology (playtest request): a jet the selected missile could lock gets a green circle, a green
-- square while the lock builds, and a red square once it's locked. Other jets get a small grey box.
local MARKER_STYLES = {
	Contact = { size = 18, circle = false, thickness = 1 },
	Lockable = { size = 34, circle = true, thickness = 2 },
	Locking = { size = 34, circle = false, thickness = 2.5 },
	Locked = { size = 38, circle = false, thickness = 3 },
}

local function styleMarker(m: Marker, state: string)
	local style = MARKER_STYLES[state]
	local colour = if state == "Locked" then RED elseif state == "Contact" then CONTACT else GREEN
	m.box.Size = UDim2.fromOffset(style.size, style.size)
	m.corner.CornerRadius = if style.circle then UDim.new(0.5, 0) else UDim.new(0, 0)
	m.stroke.Color = colour
	m.stroke.Thickness = style.thickness
	m.label.TextColor3 = colour
	m.label.Position = m.box.Position + UDim2.fromOffset(0, style.size / 2 + 4)
end

local function addFeedLine(message: string, colour: Color3)
	local l = text(killFeed, 15, Enum.TextXAlignment.Right)
	l.Size = UDim2.fromOffset(420, 20)
	l.Text = message
	l.TextColor3 = colour
	l.LayoutOrder = math.floor(os.clock() * 1000)
	table.insert(feedLines, { label = l, expires = os.clock() + FEED_SECONDS })
	while #feedLines > FEED_LINES do
		table.remove(feedLines, 1).label:Destroy()
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
		HUDController.pullUp = false
		HUDController.warnings = {}
		return
	end
	gui.Enabled = not FlightController:IsUnconscious()

	local camera = workspace.CurrentCamera :: Camera
	local viewport = camera.ViewportSize
	local jetCF = root.CFrame
	local look = jetCF.LookVector

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

	-- Pitch ladder and horizon: conformal, rotated by the *camera's* bank (the screen's tilt against
	-- the real horizon), which matches whether the view rolls with the jet or stays level.
	local flat = Vector3.new(look.X, 0, look.Z)
	flat = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.new(0, 0, -1)
	local camCF = camera.CFrame
	local bank = math.deg(math.atan2(-camCF.RightVector.Y, camCF.UpVector.Y))
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
	local jetModel = FlightController.jet
	if jetModel then
		readouts.Gun.Position = UDim2.fromOffset(rightX, bottomY)
		local ammo = (jetModel:GetAttribute("Ammo") :: number?) or 0
		local heat = (jetModel:GetAttribute("GunHeat") :: number?) or 0
		local jammed = jetModel:GetAttribute("GunJammed") == true
		readouts.Gun.Text = if jammed then "GUN JAM" elseif heat > 0.75 then `GUN {ammo} HOT` else `GUN {ammo}`
		readouts.Gun.TextColor3 = if jammed or ammo == 0 then RED elseif heat > 0.75 then AMBER else GREEN
		local selected = jetModel:GetAttribute("SelectedMissile") :: string?
		local selectedSpec = if selected and selected ~= "" then WeaponData.getMissile(selected) else nil
		readouts.Missile.Position = UDim2.fromOffset(rightX, bottomY - 20)
		if selectedSpec then
			local count = (jetModel:GetAttribute(`Msl_{selected}`) :: number?) or 0
			local caged = WeaponData.isIR(selectedSpec) and SensorController.seekerCaged and count > 0
			readouts.Missile.Text = `{selectedSpec.DisplayName} x{count}{if caged then "  SEEKER OFF" else ""}`
			readouts.Missile.TextColor3 = if count == 0 then RED elseif caged then AMBER else GREEN
		else
			readouts.Missile.Text = ""
		end
		readouts.CM.Position = UDim2.fromOffset(leftX, bottomY - 20)
		readouts.CM.Text = string.format(
			"FLR %d  CHF %d",
			(jetModel:GetAttribute("Flares") :: number?) or 0,
			(jetModel:GetAttribute("Chaff") :: number?) or 0
		)
	end

	-- Warnings (HUD-04): every active condition, most urgent first. The top one flashes in red; the rest
	-- are listed underneath in amber.
	local now = os.clock()
	if now >= terrainCheckAt then
		-- Terrain ahead: is the ground on the flight path within the next 4 seconds?
		terrainCheckAt = now + 0.2
		local path = Units.velocityToStuds(state.velocity) * 4
		terrainAhead = path.Magnitude > 1 and workspace:Raycast(root.Position, path, terrainParams) ~= nil
	end
	local warnings = {}
	local outAt = jetModel and jetModel:GetAttribute("OutOfBoundsAt") :: number?
	if outAt then
		table.insert(warnings, `RETURN TO BATTLE AREA {math.max(math.ceil(outAt - workspace:GetServerTimeNow()), 0)}`)
	end
	-- Ground on the flight path within 4 s while descending (ToneController also calls it out)
	HUDController.pullUp = terrainAhead and state.velocity.Y < 0
	if HUDController.pullUp then
		table.insert(warnings, "PULL UP")
	end
	-- Someone's radar or heat-seeker has locked you (a launch gets its own MISSILE warning and arrow)
	for _, threat in SensorController.threats do
		if threat.kind == "Lock" then
			table.insert(warnings, "LOCKED")
			break
		end
	end
	if jetModel and jetModel:GetAttribute("OnFire") then
		table.insert(warnings, "ENGINE FIRE")
	end
	if state.stalled then
		table.insert(warnings, "STALL")
	end
	if airframe and state.gLoad > airframe.MaxG * 0.97 then
		table.insert(warnings, "OVER-G")
	end
	if state.gStress > 0.6 then
		table.insert(warnings, "G-LIMIT")
	end
	local damage = FlightController.damage
	if damage and (damage.Engine or 1) < 0.5 then
		table.insert(warnings, "ENGINE DAMAGE")
	end
	if airframe and state.fuel < airframe.Fuel * 0.15 then
		table.insert(warnings, "BINGO FUEL")
	end
	HUDController.warnings = warnings
	warningLabel.Position = UDim2.fromOffset(boxW / 2, boxH * 0.72)
	warningLabel.Text = warnings[1] or ""
	warningLabel.Visible = #warnings > 0 and (now % 0.6) < 0.4
	cautionLabel.Position = UDim2.fromOffset(boxW / 2, boxH * 0.72 + 24)
	cautionLabel.Text = table.concat(warnings, "  ·  ", 2)

	-- Targets: markers on other jets, and the gun lead indicator on the best one ahead
	local myPosition = root.Position
	local myVelocity = state.velocity
	local gun = jetModel and WeaponData.get(jetModel:GetAttribute("Gun") :: string)
	local bestOff, bestModel = math.huge, nil
	local seen: { [Model]: boolean } = {}
	for _, model in workspace.Jets:GetChildren() do
		if not model:IsA("Model") or model == jetModel then
			continue
		end
		local otherRoot = model.PrimaryPart
		if not otherRoot then
			continue
		end
		local range = Units.toMetres((otherRoot.Position - myPosition).Magnitude)
		if range > TARGET_RANGE then
			continue
		end
		seen[model] = true
		local m = marker(model)
		local screen, onScreen = camera:WorldToViewportPoint(otherRoot.Position)
		m.box.Visible = onScreen and screen.Z > 0
		m.label.Visible = m.box.Visible
		m.box.Position = UDim2.fromOffset(screen.X, screen.Y)
		local id = model:GetAttribute("JetId") :: number?
		local markerState = "Contact"
		if id then
			if id == SensorController.lockId or (id == SensorController.irTargetId and SensorController.irLocked) then
				markerState = "Locked"
			elseif id == SensorController.irTargetId or id == SensorController.acquiringId then
				markerState = "Locking"
			elseif SensorController.lockable[id] then
				markerState = "Lockable"
			end
		end
		styleMarker(m, markerState)
		m.label.Text = string.format("%s %.1fkm", (model:GetAttribute("PilotName") :: string?) or "?", range / 1000)
		local off = math.deg(math.acos(math.clamp((otherRoot.Position - myPosition).Unit:Dot(look), -1, 1)))
		if range <= LEAD_RANGE and off <= LEAD_CONE and off < bestOff then
			bestOff, bestModel = off, model
		end
	end
	for model, m in targetMarkers do
		if not seen[model] then
			m.box:Destroy()
			m.label:Destroy()
			targetMarkers[model] = nil
		end
	end

	leadMarker.Visible = false
	if gun and bestModel and bestModel.PrimaryPart then
		local target = bestModel.PrimaryPart
		local dir = Ballistics.leadDirection(
			myPosition,
			myVelocity,
			target.Position,
			Units.velocityFromStuds(target.AssemblyLinearVelocity),
			gun.MuzzleVelocity,
			gun.Lifetime
		)
		if dir then
			local p, visible = project(camera, dir)
			leadMarker.Visible = visible and inside(p, 10, 10)
			leadMarker.Position = toBox(p)
		end
	end

	-- Missiles: seeker circle, lock box, launch zone, shoot cue (HUD-03)
	local selectedId = jetModel and jetModel:GetAttribute("SelectedMissile") :: string?
	local missileSpec = if selectedId and selectedId ~= "" then WeaponData.getMissile(selectedId) else nil
	local isIR = missileSpec ~= nil and WeaponData.isIR(missileSpec)
	local targetModel: Model? = nil
	if missileSpec and isIR and SensorController.irTargetId ~= 0 then
		targetModel = SensorController:GetModel(SensorController.irTargetId)
	elseif missileSpec and not isIR and SensorController.lockId ~= 0 then
		targetModel = SensorController:GetModel(SensorController.lockId)
	end

	-- The seeker circle shows the heat-seeker searching at the boresight; once it sees a target, the
	-- target's own marker (green square, then red) takes over.
	seekerCircle.Visible = isIR and SensorController.irTargetId == 0
	seekerCircle.Position = UDim2.fromOffset(boxW / 2, boxH / 2)

	local ready = if isIR then SensorController.irLocked else SensorController.lockId ~= 0
	local lockModel = if ready then targetModel else nil
	local lockRoot = lockModel and lockModel.PrimaryPart
	lockLabel.Visible = false
	if lockRoot then
		local screen, onScreen = camera:WorldToViewportPoint(lockRoot.Position)
		if onScreen and screen.Z > 0 then
			lockLabel.Visible = true
			lockLabel.TextColor3 = RED
			lockLabel.Position = UDim2.fromOffset(screen.X, screen.Y - 24)
			local rel = lockRoot.Position - myPosition
			local closure = -(Units.velocityFromStuds(lockRoot.AssemblyLinearVelocity) - myVelocity):Dot(rel.Unit)
			lockLabel.Text =
				string.format("%.1f km  %+d kt", Units.toMetres(rel.Magnitude) / 1000, math.round(Units.knots(closure)))
		end
	end

	zoneBar.Visible = false
	shootCue.Visible = false
	local zoneRoot = targetModel and targetModel.PrimaryPart
	if missileSpec and zoneRoot then
		local rMax, rNoEscape, rMin = Guidance.launchZone(
			missileSpec,
			myPosition,
			myVelocity,
			zoneRoot.Position,
			Units.velocityFromStuds(zoneRoot.AssemblyLinearVelocity)
		)
		local range = Units.toMetres((zoneRoot.Position - myPosition).Magnitude)
		local scaleMax = rMax * 1.3
		local barH = math.floor(boxH * 0.5)
		zoneBar.Visible = true
		zoneBar.Size = UDim2.fromOffset(2, barH)
		zoneBar.Position = UDim2.fromOffset(boxW - 108, (boxH - barH) / 2)
		local function y(r: number): number
			return barH * (1 - math.clamp(r / scaleMax, 0, 1))
		end
		zoneMarks.Max.Position = UDim2.fromOffset(0, y(rMax))
		zoneMarks.NoEscape.Position = UDim2.fromOffset(0, y(rNoEscape))
		zoneMarks.Min.Position = UDim2.fromOffset(0, y(rMin))
		zoneCaret.Position = UDim2.fromOffset(-2, y(range))
		-- FIRE in red once locked and inside the launch zone; otherwise say why not.
		local inZone = range >= rMin and range <= rMax
		shootCue.Visible = ready
		shootCue.Position = UDim2.fromOffset(boxW / 2, -34) -- above the heading scale, clear of the target
		if inZone then
			shootCue.Text, shootCue.TextColor3, shootCue.TextSize = "FIRE", RED, 34
		else
			shootCue.Text = if range > rMax then "OUT OF RANGE" else "TOO CLOSE"
			shootCue.TextColor3, shootCue.TextSize = AMBER, 18
		end
	end

	-- Missile warning: any missile guiding on you that your RWR can hear
	local launch: Vector3? = nil
	for _, threat in SensorController.threats do
		if threat.kind == "Launch" then
			launch = threat.position
		end
	end
	missileWarning.Visible = launch ~= nil and (os.clock() % 0.4 < 0.28)
	warningArrow.Visible = launch ~= nil
	if launch then
		-- Arrow around the screen centre, pointing at the threat (camera space)
		local rel = camera.CFrame:PointToObjectSpace(launch)
		local angle = math.atan2(rel.X, rel.Y)
		local radius = math.min(viewport.X, viewport.Y) * 0.32
		warningArrow.Position =
			UDim2.fromOffset(viewport.X / 2 + math.sin(angle) * radius, viewport.Y / 2 - math.cos(angle) * radius)
		warningArrow.Rotation = math.deg(angle)
	end

	hitMarker.Position = UDim2.fromOffset(boxW / 2, boxH / 2)
	hitMarker.Visible = os.clock() < hitUntil

	local now = os.clock()
	for i = #feedLines, 1, -1 do
		local entry = feedLines[i]
		local left = entry.expires - now
		if left <= 0 then
			entry.label:Destroy()
			table.remove(feedLines, i)
		else
			entry.label.TextTransparency = math.clamp(1 - left, 0, 1)
		end
	end

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
	helpLabel.Visible = InputController.device == "KeyboardMouse"
	fuelLabel.Position = if InputController.device == "Touch"
		then UDim2.new(0, 20, 1, -230)
		else UDim2.new(0, 20, 1, -20)
	helpLabel.Text = `{if InputController.scheme == "MouseAim" then "MOUSE AIM" else "DIRECT"} · M scheme · V camera · Z zoom · P tuning`
		.. "\nLMB guns · Space missile · R next missile · T lock/unlock · F flare · C chaff"
end

function HUDController:Start()
	terrainParams = RaycastParams.new()
	terrainParams.FilterType = Enum.RaycastFilterType.Exclude
	terrainParams.FilterDescendantsInstances = { workspace:WaitForChild("Jets") }
	self.gui = build()
	Net.Client.on("HitConfirm", function()
		hitUntil = os.clock() + 0.12
	end)
	Net.Client.on("KillFeed", function(killer: string, victim: string, weapon: string, assists: { string })
		local me = Players.LocalPlayer.Name
		local message = if killer ~= "" then `{killer} ▸ {victim}  [{weapon}]` else `{victim}  [{weapon}]`
		if #assists > 0 then
			message ..= `  +{table.concat(assists, ", ")}`
		end
		local involved = killer == me or victim == me or table.find(assists, me) ~= nil
		addFeedLine(message, if involved then AMBER else GREEN)
	end)
	-- After the camera has moved this frame, so projections match what's on screen.
	RunService:BindToRenderStep("AfterburnerHUD", Enum.RenderPriority.Camera.Value + 2, update)
end

return HUDController
