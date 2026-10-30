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
--
-- Era variants (HUD-05, Config/HUDStyles): the jet's Era picks the box size, tapes or plain numbers, ladder
-- detail, flight path marker, readouts, a bank scale and speed trend, and whether the symbology sits on the
-- HUD glass (fixed to the nose) or on the helmet (fixed to your view, Tier VII-VIII).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Bindings = require(Shared.Config.Bindings)
local Cosmetics = require(Shared.Cosmetics)
local CosmeticsCatalogue = require(Shared.Config.Cosmetics)
local Ballistics = require(Shared.Ballistics)
local HUDStyles = require(Shared.Config.HUDStyles)
local Net = require(Shared.Net)
local Units = require(Shared.Units)
local Guidance = require(Shared.Guidance)
local WeaponData = require(Shared.WeaponData)

local BindingsController = require(script.Parent.BindingsController)
local FlightController = require(script.Parent.FlightController)
local InputController = require(script.Parent.InputController)
local PlayerDataController = require(script.Parent.PlayerDataController)
local SensorController = require(script.Parent.SensorController)
local SettingsController = require(script.Parent.SettingsController)

local DamageDiagram = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("DamageDiagram"))

local GREEN = Color3.fromRGB(110, 255, 150) -- the HUD colour: changes with the HUDColour setting
-- HUDColour presets (SET-03): cyan and white stay clear of the red and amber warnings for red-green
-- colour blindness
local HUD_COLOURS = {
	Green = Color3.fromRGB(110, 255, 150),
	Cyan = Color3.fromRGB(90, 220, 255),
	White = Color3.fromRGB(235, 240, 245),
	Pink = Color3.fromRGB(255, 150, 215),
	Blue = Color3.fromRGB(120, 170, 255),
	Violet = Color3.fromRGB(200, 150, 255),
}
local AMBER = Color3.fromRGB(255, 190, 80)
local RED = Color3.fromRGB(255, 85, 70)
local CONTACT = Color3.fromRGB(205, 215, 205) -- jets you can see but not lock
local FRIENDLY = Color3.fromRGB(90, 165, 255) -- teammates (team modes)
local AIM_WHITE = Color3.fromRGB(230, 255, 235)
local FONT = Enum.Font.RobotoMono

local LADDER_STEP = 5 -- degrees between the pitch rungs built (an era's style may show fewer)
local BANK_MARKS = { -45, -30, -20, -10, 0, 10, 20, 30, 45 } -- bank scale ticks (degrees)
local BANK_RADIUS = 60 -- px: small enough to sit between the corner readouts
local TREND_SECONDS = 5 -- the speed trend shows where your speed will be this long from now

local HUDController = {
	Priority = 60,
	gui = nil :: ScreenGui?,
	pullUp = false, -- the PULL UP warning is up
	warnings = {} :: { string }, -- every active warning, most urgent first (ToneController calls them out)
}

type Tape = { frame: Frame, labels: { TextLabel }, ticks: { Frame }, valueBox: TextLabel }
type Rung = { holder: Frame, pitch: number, labels: { TextLabel } }

local box: CanvasGroup
local rungs: { Rung } = {}
local horizon: Frame
local fpm: Frame
local gunCross: TextLabel
local speedTape: Tape
local altTape: Tape
local headingTape: Tape
local bankScale: Frame -- FullGlass / WAD: ticks on an arc under the box centre, and a caret for the bank
local bankCaret: TextLabel
local speedTrend: Frame -- FullGlass / WAD: a line from the speed box to where the speed will be
local lastSpeed: number? = nil
local smoothedAccel = 0
local readouts: { [string]: TextLabel } = {}
local warningLabel: TextLabel
local cautionLabel: TextLabel
local terrainParams: RaycastParams
local terrainCheckAt = 0
local terrainAhead = false
local aimReticle: Frame
local fuelLabel: TextLabel
local damageDiagram: DamageDiagram.Diagram -- above the fuel readout once you're damaged (DMG-05)
local helpLabel: TextLabel
-- HUD-02: guns
local leadMarker: Frame
local hitMarker: TextLabel
local hitUntil = 0
local killFeed: Frame
local feedLines: { { label: TextLabel, expires: number } } = {}
local targetMarkers: { [Model]: any } = {}
-- Gunsights (GUN-07): each target's smoothed acceleration for the LCOS pipper, and the last second of where
-- your gun pointed for the EEGS funnel
local targetMotion: { [Model]: { velocity: Vector3, time: number, accel: Vector3 } } = {}
local gunHistory: { { time: number, muzzle: CFrame, velocity: Vector3 } } = {}
local FUNNEL_TIMES = { 0.15, 0.3, 0.45, 0.6, 0.75, 0.9, 1.05, 1.2 } -- seconds of flight drawn
local funnelDots: { { Frame } } = {} -- { left, right } per FUNNEL_TIMES entry
local fixedRing: Frame -- Simple sight (Tier I–II): the fixed reflector-sight ring around the gun cross
local lcosRing: Frame -- LCOS / EEGS pipper: a ring with a range scale that shrinks as you close
local lcosTicks: { Frame } = {}
local LCOS_TICKS = 12
local markerLayer: Frame
-- HUD-03: missiles
local seekerCircle: Frame
local helmetSight: Frame -- MSL-09: where your head is pointing, with a helmet-cued heat-seeker selected
local lockLabel: TextLabel
local zoneBar: Frame
local zoneMarks: { [string]: Frame } = {}
local zoneCaret: TextLabel
local shootCue: TextLabel
local missileWarning: TextLabel
local warningArrow: TextLabel

local TARGET_RANGE = 5000 -- real metres: show markers on jets within this
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

local function makeRung(pitch: number): (Frame, { TextLabel })
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
	local labels = {}
	for _, side in { -1, 1 } do
		local label = text(holder, 13, if side < 0 then Enum.TextXAlignment.Right else Enum.TextXAlignment.Left)
		label.AnchorPoint = Vector2.new(if side < 0 then 1 else 0, 0.5)
		label.Size = UDim2.fromOffset(28, 14)
		label.Position = if side < 0 then UDim2.new(0, -6, 0.5, 0) else UDim2.new(1, 6, 0.5, 0)
		label.Text = tostring(math.abs(pitch))
		table.insert(labels, label)
	end
	return holder, labels
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
			local holder, labels = makeRung(pitch)
			table.insert(rungs, { holder = holder, pitch = pitch, labels = labels })
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

	-- Bank scale (FullGlass / WAD): ticks on an arc below the box centre, a caret at your bank angle
	bankScale = Instance.new("Frame")
	bankScale.AnchorPoint = Vector2.new(0.5, 0.5)
	bankScale.BackgroundTransparency = 1
	bankScale.Size = UDim2.fromOffset(0, 0)
	bankScale.Visible = false
	bankScale.Parent = box
	for _, mark in BANK_MARKS do
		local angle = math.rad(mark)
		local tick = line(bankScale, 2, if mark % 30 == 0 then 10 else 6)
		tick.AnchorPoint = Vector2.new(0.5, 0)
		tick.Position = UDim2.fromOffset(-math.sin(angle) * BANK_RADIUS, math.cos(angle) * BANK_RADIUS)
		tick.Rotation = mark
	end
	bankCaret = text(bankScale, 14)
	bankCaret.AnchorPoint = Vector2.new(0.5, 1)
	bankCaret.Size = UDim2.fromOffset(16, 14)
	bankCaret.Text = "▲"
	speedTrend = line(box, 3, 0)
	speedTrend.Visible = false

	for _, name in { "G", "Mach", "AoA" } do
		readouts[name] = text(box, 16, Enum.TextXAlignment.Left)
	end
	for _, name in { "VS", "Throttle", "Gun", "Missile", "LockNote", "CM" } do
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
	damageDiagram = DamageDiagram.create(gui)

	helpLabel = text(gui, 13, Enum.TextXAlignment.Right)
	helpLabel.AnchorPoint = Vector2.new(1, 1)
	helpLabel.Position = UDim2.new(1, -20, 1, -20)
	helpLabel.Size = UDim2.fromOffset(560, 32) -- two lines: flying and camera, then weapons
	helpLabel.TextYAlignment = Enum.TextYAlignment.Bottom
	helpLabel.TextTransparency = 0.35

	-- IR seeker circle: sits on the boresight while searching, jumps onto the target, solid when locked.
	seekerCircle = circle(box, 46, 1.5, GREEN)
	seekerCircle.Visible = false
	helmetSight = circle(gui, 30, 1.5, GREEN)
	helmetSight.Position = UDim2.fromScale(0.5, 0.5)
	helmetSight.Visible = false
	local hmd = text(helmetSight, 12)
	hmd.Text = "HMD"
	hmd.AnchorPoint = Vector2.new(0.5, 0)
	hmd.Position = UDim2.new(0.5, 0, 1, 4)

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
	-- Gunsights by tier (GUN-07): each looks different, so you can tell which one your jet has
	fixedRing = circle(box, 74, 1.5, GREEN)
	fixedRing.Visible = false
	lcosRing = circle(box, 44, 2, GREEN)
	local lcosDot = line(lcosRing, 4, 4)
	lcosDot.AnchorPoint = Vector2.new(0.5, 0.5)
	lcosDot.Position = UDim2.fromScale(0.5, 0.5)
	for i = 1, LCOS_TICKS do
		local angle = math.rad(i / LCOS_TICKS * 360)
		local tick = line(lcosRing, 3, 3)
		tick.AnchorPoint = Vector2.new(0.5, 0.5)
		tick.Position = UDim2.new(0.5, math.sin(angle) * 29, 0.5, -math.cos(angle) * 29)
		lcosTicks[i] = tick
	end
	lcosRing.Visible = false
	-- EEGS funnel (Tier V+): a dot each side per FUNNEL_TIMES entry, a wingspan apart at that range
	for i = 1, #FUNNEL_TIMES do
		local pair = {}
		for side = 1, 2 do
			local dot = line(box, 6, 6)
			dot.AnchorPoint = Vector2.new(0.5, 0.5)
			dot.Visible = false
			pair[side] = dot
		end
		funnelDots[i] = pair
	end

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
	l.RichText = true -- the VIP tag is gold
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
	Track = { size = 30, circle = false, thickness = 2 }, -- the TWS target: an active radar missile goes here (SNS-07)
	Friendly = { size = 14, circle = true, thickness = 1.5 }, -- a teammate (team modes)
}

local function styleMarker(m: Marker, state: string)
	local style = MARKER_STYLES[state]
	local colour = if state == "Locked"
		then RED
		elseif state == "Contact" then CONTACT
		elseif state == "Friendly" then FRIENDLY
		else GREEN
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

local function update(dt: number)
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
	local style = HUDStyles.forEra(FlightController.airframe and FlightController.airframe.Era)
	local boxW = math.min(math.floor(pxPerDeg * style.boxWidth), viewport.X - 40)
	local boxH = math.min(math.floor(pxPerDeg * style.boxHeight), viewport.Y - 60)

	-- The box follows the boresight (the nose), like symbology on the HUD glass; a helmet display (WAD)
	-- stays at the centre of your view instead.
	local nose, noseVisible = project(camera, look)
	local centre = if style.helmet then viewport / 2 else nose
	box.Visible = style.helmet or noseVisible
	box.Size = UDim2.fromOffset(boxW, boxH)
	local boxOrigin = centre - Vector2.new(boxW / 2, boxH / 2)
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

	-- The gun cross always marks the nose (on a helmet display it moves around inside the box)
	local boresight = toBox(nose)
	gunCross.Position = boresight
	gunCross.Visible = noseVisible and inside(nose, 20, 20)
	fixedRing.Position = boresight

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
		rung.holder.Visible = rung.pitch % style.ladderStep == 0 and visible and inside(screen, 90, 24)
		rung.holder.Position = toBox(screen)
		rung.holder.Rotation = -bank
		for _, label in rung.labels do
			label.Visible = style.ladderNumbers
		end
	end

	fpm.Visible = false
	if style.flightPath and state.velocity.Magnitude > 1 then
		local v, vVisible = project(camera, state.velocity.Unit)
		fpm.Visible = vVisible and inside(v, 10, 10)
		fpm.Position = toBox(v)
	end

	-- Bank scale: the jet's own bank against the horizon, caret on the arc
	bankScale.Visible = style.bankScale
	if style.bankScale then
		bankScale.Position = UDim2.fromOffset(boxW / 2, boxH / 2)
		local jetBank = math.deg(math.atan2(-jetCF.RightVector.Y, jetCF.UpVector.Y))
		local shown = math.rad(math.clamp(jetBank, -50, 50))
		local r = BANK_RADIUS - 2
		bankCaret.Position = UDim2.fromOffset(-math.sin(shown) * r, math.cos(shown) * r)
		bankCaret.Rotation = math.deg(shown)
	end

	-- Tapes
	local tapeH = math.floor(boxH * 0.62)
	-- Units setting: knots and feet, or km/h and metres
	local metric = SettingsController:Get("Units") == "Metric"
	local knots = if metric then state.speed * 3.6 else Units.knots(state.speed)
	local feet = if metric then state.altitude else Units.feet(state.altitude)
	speedTape.frame.Visible = style.tapes
	altTape.frame.Visible = style.tapes
	headingTape.frame.Visible = style.headingTape
	speedTape.frame.Size = UDim2.fromOffset(70, tapeH)
	speedTape.frame.Position = UDim2.fromOffset(16, (boxH - tapeH) / 2)
	layoutTape(speedTape, {
		value = knots,
		tickStep = if metric then 20 else 10,
		labelEvery = if metric then 100 else 50,
		pxPerUnit = tapeH / (if metric then 260 else 140),
		vertical = true,
		length = tapeH,
		format = function(v)
			return tostring(math.max(v, 0))
		end,
	})
	speedTape.valueBox.Position = UDim2.fromOffset(12, boxH / 2 - 13)
	speedTape.valueBox.Text = tostring(math.round(knots))

	-- Speed trend: smoothed acceleration, drawn up (faster) or down (slower) beside the speed box
	if lastSpeed and dt > 0 then
		smoothedAccel += ((state.speed - lastSpeed) / dt - smoothedAccel) * math.min(dt * 3, 1)
	end
	lastSpeed = state.speed
	speedTrend.Visible = false
	if style.speedTrend and style.tapes then
		local change = smoothedAccel * TREND_SECONDS * (if metric then 3.6 else Units.knots(1))
		local pixels = math.clamp(change * tapeH / (if metric then 260 else 140), -tapeH / 2, tapeH / 2)
		if math.abs(pixels) > 3 then
			speedTrend.Visible = true
			speedTrend.AnchorPoint = Vector2.new(0.5, if pixels > 0 then 1 else 0)
			speedTrend.Position = UDim2.fromOffset(92, boxH / 2)
			speedTrend.Size = UDim2.fromOffset(3, math.abs(pixels))
		end
	end

	altTape.frame.Size = UDim2.fromOffset(70, tapeH)
	altTape.frame.Position = UDim2.fromOffset(boxW - 86, (boxH - tapeH) / 2)
	layoutTape(altTape, {
		value = feet,
		tickStep = if metric then 50 else 100,
		labelEvery = if metric then 250 else 500,
		pxPerUnit = tapeH / (if metric then 430 else 1400),
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
	headingTape.valueBox.Position = UDim2.fromOffset(boxW / 2 - 28, if style.headingTape then 42 else 8)
	headingTape.valueBox.Text = string.format("%03d", math.round(heading) % 360)

	-- Corner readouts
	local airframe = FlightController.airframe
	local input = FlightController.input
	local leftX, bottomY = 18, boxH - 92
	readouts.G.Position = UDim2.fromOffset(leftX, bottomY)
	readouts.G.Text = string.format("G  %4.1f", state.gLoad)
	readouts.G.TextColor3 = if airframe and state.gLoad > airframe.MaxG * 0.95 then RED else GREEN
	readouts.Mach.Visible = style.fullReadouts
	readouts.AoA.Visible = style.fullReadouts
	readouts.VS.Visible = style.fullReadouts
	readouts.Mach.Position = UDim2.fromOffset(leftX, bottomY + 20)
	readouts.Mach.Text = string.format("M  %.2f", state.mach)
	readouts.AoA.Position = UDim2.fromOffset(leftX, bottomY + 40)
	readouts.AoA.Text = string.format("α  %4.1f", math.deg(state.aoa))
	readouts.AoA.TextColor3 = if state.stalled then RED else GREEN

	local rightX = boxW - 18 - 120
	readouts.VS.Position = UDim2.fromOffset(rightX, bottomY + 20)
	readouts.VS.Text = if SettingsController:Get("Units") == "Metric"
		then string.format("%+d m/s", math.round(state.velocity.Y))
		else string.format("%+d VS", math.round(Units.feet(state.velocity.Y) * 60 / 100) * 100)
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
		local sightName = Ballistics.sightFor(if airframe then airframe.Tier else 1)
		readouts.Gun.Text = if jammed
			then "GUN JAM"
			elseif heat > 0.75 then `GUN {ammo} HOT`
			else `GUN {ammo} · {string.upper(sightName)}`
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
		-- Why the last lock failed or broke, for a few seconds, above the missile
		readouts.LockNote.Position = UDim2.fromOffset(rightX, bottomY - 40)
		readouts.LockNote.Text = if os.clock() < SensorController.messageUntil then SensorController.message else ""
		readouts.LockNote.TextColor3 = AMBER
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
	-- Reduce flashing: the top warning stays lit instead of blinking
	warningLabel.Visible = #warnings > 0 and (SettingsController:Get("ReduceFlashing") or (now % 0.6) < 0.4)
	cautionLabel.Position = UDim2.fromOffset(boxW / 2, boxH * 0.72 + 24)
	cautionLabel.Text = table.concat(warnings, "  ·  ", 2)

	-- Targets: markers on other jets, and the gun lead indicator on the best one ahead
	local myPosition = root.Position
	local myVelocity = state.velocity
	local gun = jetModel and WeaponData.get(jetModel:GetAttribute("Gun") :: string)
	-- The gunsight for this jet's tier (GUN-07): Simple, LCOS or EEGS
	local sight = Ballistics.sightFor(if airframe then airframe.Tier else 1)
	local leadRange = if sight == "Simple" then Ballistics.SIMPLE_RANGE else Ballistics.SIGHT_RANGE
	local now = os.clock()
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
		local contact = id and SensorController.contacts[id]
		if contact and contact.friendly then
			markerState = "Friendly"
		elseif id then
			if id == SensorController.lockId or (id == SensorController.irTargetId and SensorController.irLocked) then
				markerState = "Locked"
			elseif id == SensorController.irTargetId or id == SensorController.acquiringId then
				markerState = "Locking"
			elseif id == SensorController.twsTargetId then
				markerState = "Track"
			elseif SensorController.lockable[id] then
				markerState = "Lockable"
			end
		end
		styleMarker(m, markerState)
		local pilot = Players:GetPlayerByUserId((model:GetAttribute("PilotUserId") :: number?) or 0)
		m.label.Text = string.format(
			"%s%s%s %.1fkm",
			if markerState == "Track" then "TWS · " else "",
			if pilot and pilot:GetAttribute("Pass_VIP") == true then '<font color="#FFC93C"><b>VIP</b></font> ' else "", -- the VIP Pilot pass
			(model:GetAttribute("PilotName") :: string?) or "?",
			range / 1000
		)
		local off = math.deg(math.acos(math.clamp((otherRoot.Position - myPosition).Unit:Dot(look), -1, 1)))
		if range <= leadRange and off <= LEAD_CONE and off < bestOff then
			bestOff, bestModel = off, model
		end
		-- Smoothed acceleration for the LCOS pipper
		local velocity = Units.velocityFromStuds(otherRoot.AssemblyLinearVelocity)
		local motion = targetMotion[model]
		if motion and now - motion.time > 1e-3 then
			local raw = (velocity - motion.velocity) / (now - motion.time)
			motion.accel = motion.accel:Lerp(raw, 0.15)
			motion.velocity, motion.time = velocity, now
		elseif not motion then
			targetMotion[model] = { velocity = velocity, time = now, accel = Vector3.zero }
		end
	end
	for model, m in targetMarkers do
		if not seen[model] then
			m.box:Destroy()
			m.label:Destroy()
			targetMarkers[model] = nil
		end
	end
	for model in targetMotion do
		if not seen[model] then
			targetMotion[model] = nil
		end
	end

	leadMarker.Visible = false
	lcosRing.Visible = false
	fixedRing.Visible = gun ~= nil and sight == "Simple"
	if gun and bestModel and bestModel.PrimaryPart then
		local target = bestModel.PrimaryPart
		local motion = targetMotion[bestModel]
		local dir = Ballistics.leadDirection(
			myPosition,
			myVelocity,
			target.Position,
			Units.velocityFromStuds(target.AssemblyLinearVelocity),
			gun.MuzzleVelocity,
			gun.Lifetime,
			if sight ~= "Simple" and motion then motion.accel else nil
		)
		if dir then
			local p, visible = project(camera, dir)
			-- Simple: the small pipper. LCOS / EEGS: the ring, its range scale lit in proportion to the range
			local pipper = if sight == "Simple" then leadMarker else lcosRing
			pipper.Visible = visible and inside(p, 10, 10)
			pipper.Position = toBox(p)
			if sight ~= "Simple" then
				local range = Units.toMetres((target.Position - myPosition).Magnitude)
				local lit = math.ceil(LCOS_TICKS * math.clamp(range / Ballistics.SIGHT_RANGE, 0, 1))
				for i, tick in lcosTicks do
					tick.Visible = i <= lit
				end
			end
		end
	end

	-- EEGS funnel (Tier V+, always on): where rounds fired over the last second are now, from where the gun
	-- pointed then, a wingspan wide at each range. Put the target's wings across it and fire.
	local muzzle = root:FindFirstChild("GunMuzzle") :: Attachment?
	table.insert(gunHistory, {
		time = now,
		muzzle = if muzzle then muzzle.WorldCFrame else root.CFrame,
		velocity = myVelocity,
	})
	while #gunHistory > 0 and now - gunHistory[1].time > FUNNEL_TIMES[#FUNNEL_TIMES] + 0.1 do
		table.remove(gunHistory, 1)
	end
	local showFunnel = gun ~= nil and sight == "EEGS" -- always on in Tier V+ jets
	local right = camera.CFrame.RightVector * Units.toStuds(Ballistics.FUNNEL_WINGSPAN / 2)
	local h = #gunHistory
	for i, t in FUNNEL_TIMES do
		local pair = funnelDots[i]
		-- The history entry from about t seconds ago (newest last)
		local entry = nil
		for j = h, 1, -1 do
			if now - gunHistory[j].time >= t then
				entry = gunHistory[j]
				break
			end
		end
		local point = if showFunnel
				and entry
				and gun
			then Ballistics.positionAfter(entry.muzzle, entry.velocity, gun, t)
			else nil
		for side = 1, 2 do
			local dot = pair[side]
			dot.Visible = false
			if point then
				local p = camera:WorldToViewportPoint(point + right * (if side == 1 then -1 else 1))
				local screen = Vector2.new(p.X, p.Y)
				if p.Z > 0 and inside(screen, 6, 6) then
					dot.Visible = true
					dot.Position = toBox(screen)
				end
			end
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
	elseif missileSpec and not isIR and SensorController.twsTargetId ~= 0 then
		targetModel = SensorController:GetModel(SensorController.twsTargetId)
	end

	-- The seeker circle shows the heat-seeker searching at the boresight; once it sees a target, the
	-- target's own marker (green square, then red) takes over.
	seekerCircle.Visible = isIR and SensorController.irTargetId == 0
	seekerCircle.Position = boresight
	-- Helmet sight: shown once your head is off the nose, so you can see where the seeker will be cued
	local offNose = jetModel ~= nil
		and jetModel.PrimaryPart ~= nil
		and camera.CFrame.LookVector:Dot(jetModel.PrimaryPart.CFrame.LookVector) < math.cos(math.rad(4))
	helmetSight.Visible = missileSpec ~= nil
		and Guidance.isImaging(missileSpec)
		and not SensorController.seekerCaged
		and SensorController.irTargetId == 0
		and offNose

	local ready = if isIR
		then SensorController.irLocked
		else SensorController.lockId ~= 0 or SensorController.twsTargetId ~= 0
	local lockModel = if ready then targetModel else nil
	local lockRoot = lockModel and lockModel.PrimaryPart
	lockLabel.Visible = false
	if lockRoot then
		local screen, onScreen = camera:WorldToViewportPoint(lockRoot.Position)
		if onScreen and screen.Z > 0 then
			lockLabel.Visible = true
			lockLabel.TextColor3 = if isIR or SensorController.lockId ~= 0 then RED else GREEN -- green: a TWS track
			lockLabel.Position = UDim2.fromOffset(screen.X, screen.Y - 24)
			local rel = lockRoot.Position - myPosition
			local closure = -(Units.velocityFromStuds(lockRoot.AssemblyLinearVelocity) - myVelocity):Dot(rel.Unit)
			lockLabel.Text = if SettingsController:Get("Units") == "Metric"
				then string.format("%.1f km  %+d km/h", Units.toMetres(rel.Magnitude) / 1000, math.round(closure * 3.6))
				else string.format(
					"%.1f km  %+d kt",
					Units.toMetres(rel.Magnitude) / 1000,
					math.round(Units.knots(closure))
				)
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
	damageDiagram.frame.Position = fuelLabel.Position - UDim2.fromOffset(0, 24)
	local jet = FlightController.jet
	DamageDiagram.update(
		damageDiagram,
		FlightController.damage,
		jet ~= nil and jet:GetAttribute("OnFire") == true,
		GREEN
	)
	local function key(id: string): string
		return Bindings.label(BindingsController:Name(id, "keyboard"))
	end
	local scheme = if InputController.scheme == "MouseAim" then "MOUSE AIM" else "DIRECT"
	helpLabel.Text = `{scheme} · {key("SwitchScheme")} scheme · {key("Camera")} camera · {key("Zoom")} zoom · P tuning`
		.. "\n"
		.. `{key("FireGun")} guns · {key("FireMissile")} missile · {key("NextWeapon")} next missile · `
		.. `{key("RadarLock")} lock/unlock · {key("Flares")} flare · {key("Chaff")} chaff`
end

-- Swaps the HUD colour on everything already drawn, then for everything drawn from now on.
local function setHudColour(colour: Color3)
	local hud = HUDController.gui
	if colour == GREEN or not hud then
		return
	end
	for _, d in hud:GetDescendants() do
		if d:IsA("TextLabel") and d.TextColor3 == GREEN then
			d.TextColor3 = colour
		elseif d:IsA("Frame") and d.BackgroundColor3 == GREEN then
			d.BackgroundColor3 = colour
		elseif d:IsA("UIStroke") and d.Color == GREEN then
			d.Color = colour
		end
	end
	GREEN = colour
end

function HUDController:Start()
	terrainParams = RaycastParams.new()
	terrainParams.FilterType = Enum.RaycastFilterType.Exclude
	terrainParams.FilterDescendantsInstances = { workspace:WaitForChild("Jets") }
	self.gui = build()
	-- The HUD colour: an equipped HUD theme (SHP-07), else the HUDColour setting
	local function refreshColour()
		local data = PlayerDataController.data
		local theme = data and Cosmetics.equipped(data, "HUD")
		local item = theme and CosmeticsCatalogue.get(theme)
		if item and item.Colours then
			setHudColour(item.Colours[1])
		else
			setHudColour(HUD_COLOURS[SettingsController:Get("HUDColour")] or HUD_COLOURS.Green)
		end
	end
	refreshColour()
	SettingsController.Changed:Connect(function(key: string)
		if key == "HUDColour" then
			refreshColour()
		end
	end)
	PlayerDataController.Changed:Connect(function(keys: { [string]: true })
		if keys.Cosmetics or keys.Passes then
			refreshColour()
		end
	end)
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
