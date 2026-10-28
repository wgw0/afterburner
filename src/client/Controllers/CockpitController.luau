--!strict
-- The pilot's cockpit (DEVELOPMENT.md §8.2–8.3, CAM-02 / CAM-07). Built on the client only, welded to the
-- pilot's own jet, so nobody else sees it. Four live gauges (airspeed, altimeter, G-meter, RPM) and, in
-- jets with a radar, a radar scope.
--   * A jet with a cockpit model (ReplicatedStorage.Assets.Cockpits.<AirframeId>, made in Blender and
--     installed by tools/AircraftAssembler.luau, art pipeline §7) gets a copy of it: tub, consoles,
--     panel, glareshield, sight and the canopy frames' insides, fitted to that jet's canopy. Its Faces
--     folder says where each live instrument sits on the panel; the gauges are drawn there.
--   * Any other jet gets the greybox kit: a panel on top of the forward fuselage, sills, a coaming and
--     a gunsight glass, built from parts.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Spring = require(Shared.Util.Spring)
local Units = require(Shared.Units)

local CameraController = require(script.Parent.CameraController)
local FlightController = require(script.Parent.FlightController)

local PANEL_COLOUR = Color3.fromRGB(38, 40, 44)
local FRAME_COLOUR = Color3.fromRGB(55, 58, 62)
local DIAL_COLOUR = Color3.fromRGB(16, 16, 18)
local NEEDLE_COLOUR = Color3.fromRGB(240, 240, 230)
local MARK_COLOUR = Color3.fromRGB(200, 200, 190)
local DIGITAL_COLOUR = Color3.fromRGB(120, 255, 160)
local SCOPE_COLOUR = Color3.fromRGB(8, 26, 14)
local DIAL_SIZE = 84 -- pixels on the greybox panel (714 per stud), and across each model face
local DIAL_TOP = 14 -- pixels from the panel top to the dials

type Gauge = {
	key: string,
	needle: Frame,
	readout: TextLabel,
	spring: Spring.Spring<number>,
	minValue: number,
	maxValue: number,
	sweep: number, -- degrees of needle travel
	startAngle: number,
}

-- What each live gauge shows: title, scale and the tick marks
local GAUGES: { [string]: { title: string, minValue: number, maxValue: number, ticks: { number } } } = {
	Speed = { title = "KT", minValue = 0, maxValue = 800, ticks = { 0, 100, 200, 300, 400, 500, 600, 700, 800 } },
	Altitude = { title = "ALT ×1000", minValue = 0, maxValue = 10, ticks = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 } },
	G = { title = "G", minValue = -3, maxValue = 9, ticks = { -3, 0, 3, 6, 9 } },
	RPM = { title = "RPM %", minValue = 0, maxValue = 110, ticks = { 0, 50, 70, 90, 100, 110 } },
}

local CockpitController = {
	Priority = 50,
}

local cockpit: Model?
local fromModel = false -- the cockpit is a copy of an installed cockpit model
local gauges: { Gauge } = {}
local sweeps: { Frame } = {} -- radar scope sweep lines
local surfaces: { SurfaceGui } = {}

local function part(name: string, size: Vector3, offset: CFrame, eye: CFrame, root: BasePart, colour: Color3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = eye * offset
	p.Color = colour
	p.Material = Enum.Material.SmoothPlastic
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Massless = true
	p.CastShadow = false
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = p
	weld.Parent = p
	return p
end

-- A needle gauge filling `holder`. Digital style: square, green on black, for glass cockpits.
local function makeGauge(holder: Instance, key: string, digital: boolean): Gauge
	local config = GAUGES[key]
	local minValue, maxValue = config.minValue, config.maxValue
	local markColour = if digital then DIGITAL_COLOUR else MARK_COLOUR
	local dial = Instance.new("Frame")
	dial.Name = key
	dial.AnchorPoint = Vector2.new(0.5, 0.5)
	dial.Position = UDim2.fromScale(0.5, 0.5)
	dial.Size = UDim2.fromScale(1, 1)
	dial.BackgroundColor3 = DIAL_COLOUR
	if not digital then
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = dial
	end
	local stroke = Instance.new("UIStroke")
	stroke.Color = FRAME_COLOUR
	stroke.Thickness = 6
	stroke.Parent = dial
	dial.Parent = holder

	local sweep, startAngle = 270, -135
	for _, t in config.ticks do
		local angle = startAngle + (t - minValue) / (maxValue - minValue) * sweep
		local tickHolder = Instance.new("Frame")
		tickHolder.AnchorPoint = Vector2.new(0.5, 0.5)
		tickHolder.Position = UDim2.fromScale(0.5, 0.5)
		tickHolder.Size = UDim2.fromScale(1, 1)
		tickHolder.BackgroundTransparency = 1
		tickHolder.Rotation = angle
		tickHolder.Parent = dial
		local mark = Instance.new("Frame")
		mark.AnchorPoint = Vector2.new(0.5, 0)
		mark.Position = UDim2.fromScale(0.5, 0.04)
		mark.Size = UDim2.fromScale(0.025, 0.1)
		mark.BackgroundColor3 = markColour
		mark.BorderSizePixel = 0
		mark.Parent = tickHolder
	end

	local needleHolder = Instance.new("Frame")
	needleHolder.AnchorPoint = Vector2.new(0.5, 0.5)
	needleHolder.Position = UDim2.fromScale(0.5, 0.5)
	needleHolder.Size = UDim2.fromScale(1, 1)
	needleHolder.BackgroundTransparency = 1
	needleHolder.Rotation = startAngle
	needleHolder.Parent = dial
	local needle = Instance.new("Frame")
	needle.AnchorPoint = Vector2.new(0.5, 1)
	needle.Position = UDim2.fromScale(0.5, 0.5)
	needle.Size = UDim2.fromScale(0.035, 0.42)
	needle.BackgroundColor3 = if digital then DIGITAL_COLOUR else NEEDLE_COLOUR
	needle.BorderSizePixel = 0
	needle.Parent = needleHolder

	local titleLabel = Instance.new("TextLabel")
	titleLabel.BackgroundTransparency = 1
	titleLabel.AnchorPoint = Vector2.new(0.5, 0)
	titleLabel.Position = UDim2.fromScale(0.5, 0.2)
	titleLabel.Size = UDim2.fromScale(0.8, 0.12)
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextScaled = true
	titleLabel.TextColor3 = markColour
	titleLabel.Text = config.title
	titleLabel.Parent = dial

	local readout = Instance.new("TextLabel")
	readout.BackgroundTransparency = 1
	readout.AnchorPoint = Vector2.new(0.5, 0)
	readout.Position = UDim2.fromScale(0.5, 0.68)
	readout.Size = UDim2.fromScale(0.7, 0.14)
	readout.Font = Enum.Font.Code
	readout.TextScaled = true
	readout.TextColor3 = if digital then DIGITAL_COLOUR else Color3.fromRGB(255, 190, 90)
	readout.Parent = dial

	local gauge = {
		key = key,
		needle = needleHolder,
		readout = readout,
		spring = Spring.new(minValue, 12, 0.9),
		minValue = minValue,
		maxValue = maxValue,
		sweep = sweep,
		startAngle = startAngle,
	}
	table.insert(gauges, gauge)
	return gauge
end

-- A radar scope filling `holder`: a dark green screen with a range grid and a sweeping bearing line.
-- The radar's picture itself is the screen-space scope (ScopesController); this is the cockpit's display.
local function makeScope(holder: Instance)
	local screen = Instance.new("Frame")
	screen.Name = "Radar"
	screen.Size = UDim2.fromScale(1, 1)
	screen.BackgroundColor3 = SCOPE_COLOUR
	screen.BorderSizePixel = 0
	screen.ClipsDescendants = true
	screen.Parent = holder
	for i = 1, 3 do
		for _, vertical in { true, false } do
			local line = Instance.new("Frame")
			line.BackgroundColor3 = DIGITAL_COLOUR
			line.BackgroundTransparency = 0.75
			line.BorderSizePixel = 0
			line.Position = if vertical then UDim2.fromScale(i / 4, 0) else UDim2.fromScale(0, i / 4)
			line.Size = if vertical then UDim2.new(0, 1, 1, 0) else UDim2.new(1, 0, 0, 1)
			line.Parent = screen
		end
	end
	local sweepLine = Instance.new("Frame")
	sweepLine.Name = "Sweep"
	sweepLine.AnchorPoint = Vector2.new(0.5, 0)
	sweepLine.Size = UDim2.new(0, 2, 1, 0)
	sweepLine.BackgroundColor3 = DIGITAL_COLOUR
	sweepLine.BackgroundTransparency = 0.2
	sweepLine.BorderSizePixel = 0
	sweepLine.Parent = screen
	table.insert(sweeps, sweepLine)
end

local function surfaceFor(adornee: BasePart, pixelsPerStud: number): SurfaceGui
	local surface = Instance.new("SurfaceGui")
	surface.Name = `Cockpit{adornee.Name}`
	surface.Face = Enum.NormalId.Back -- the face toward the pilot
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.PixelsPerStud = pixelsPerStud
	surface.LightInfluence = 0.2
	surface.Adornee = adornee
	surface.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	table.insert(surfaces, surface)
	return surface
end

-- Greybox kit ----------------------------------------------------------------------------------------

local PANEL_DISTANCE = -0.64 -- studs ahead of the eye
local PANEL_TOP_BELOW_EYE = -0.17 -- studs (eye space): about 15° below the line of sight, for a view over the nose
local PANEL_CLEARANCE = 0.017 -- studs above the fuselage top
local PANEL_MIN_HEIGHT = 0.15

-- Height of the jet's forward fuselage top under the panel, in eye space (negative = below the eye).
-- Looks at the jet's own solid parts on the centreline that span the panel's distance ahead.
local function fuselageTopBelowEye(jet: Model, root: BasePart, eye: Attachment): number
	local eyePos = eye.Position -- root space
	-- The canopy glass sits on the cockpit sill, so its lowest point is the fuselage top around the
	-- pilot. Bounding boxes can't tell: a one-piece mesh fuselage's box reaches up to the spine.
	local canopy = jet:FindFirstChild("Canopy")
	if canopy and canopy:IsA("BasePart") then
		local localCF = root.CFrame:ToObjectSpace(canopy.CFrame)
		local half = canopy.Size / 2
		local lowest = math.huge
		for _, sx in { -1, 1 } do
			for _, sy in { -1, 1 } do
				for _, sz in { -1, 1 } do
					lowest = math.min(lowest, (localCF * Vector3.new(half.X * sx, half.Y * sy, half.Z * sz)).Y)
				end
			end
		end
		if lowest < eyePos.Y then
			return lowest - eyePos.Y
		end
	end
	local zNear, zFar = eyePos.Z + PANEL_DISTANCE + 0.28, eyePos.Z + PANEL_DISTANCE - 0.28
	local highest = -math.huge
	for _, child in jet:GetChildren() do
		if not child:IsA("BasePart") or child == root or child.Transparency >= 0.3 then
			continue -- skips the invisible root, hull and the glass canopy
		end
		local localCF = root.CFrame:ToObjectSpace(child.CFrame)
		if math.abs(localCF.Position.X) > 1.12 then
			continue
		end
		local half = child.Size / 2
		local minZ, maxZ, maxY = math.huge, -math.huge, -math.huge
		for _, sx in { -1, 1 } do
			for _, sy in { -1, 1 } do
				for _, sz in { -1, 1 } do
					local corner = localCF * Vector3.new(half.X * sx, half.Y * sy, half.Z * sz)
					minZ, maxZ, maxY = math.min(minZ, corner.Z), math.max(maxZ, corner.Z), math.max(maxY, corner.Y)
				end
			end
		end
		if minZ <= zNear and maxZ >= zFar then
			highest = math.max(highest, maxY)
		end
	end
	if highest == -math.huge then
		return -0.34
	end
	return highest - eyePos.Y
end

local function buildGreybox(jet: Model, root: BasePart, eye: Attachment): Model
	local eyeCF = eye.WorldCFrame
	local model = Instance.new("Model")
	model.Name = "LocalCockpit"

	-- The panel sits on top of the jet's forward fuselage, like a real instrument panel, so the
	-- airframe never covers it: bottom just above the fuselage top, top a little below eye level.
	local top, bottom = PANEL_TOP_BELOW_EYE, fuselageTopBelowEye(jet, root, eye) + PANEL_CLEARANCE
	local height = math.max(top - bottom, PANEL_MIN_HEIGHT)
	local panel = part(
		"Panel",
		Vector3.new(0.95, height, 0.034),
		CFrame.new(0, bottom + height / 2, PANEL_DISTANCE) * CFrame.Angles(math.rad(-12), 0, 0),
		eyeCF,
		root,
		PANEL_COLOUR
	)
	panel.Parent = model
	part(
		"Coaming",
		Vector3.new(1.0, 0.034, 0.098),
		CFrame.new(0, top + 0.02, PANEL_DISTANCE - 0.056),
		eyeCF,
		root,
		FRAME_COLOUR
	).Parent =
		model
	part("SillL", Vector3.new(0.05, 0.14, 1.12), CFrame.new(-0.46, -0.22, -0.17), eyeCF, root, FRAME_COLOUR).Parent =
		model
	part("SillR", Vector3.new(0.05, 0.14, 1.12), CFrame.new(0.46, -0.22, -0.17), eyeCF, root, FRAME_COLOUR).Parent =
		model
	-- Canopy bow and rails, unless the jet's model has its own canopy frame
	if not jet:FindFirstChild("CanopyFrame") then
		part(
			"BowL",
			Vector3.new(0.014, 0.48, 0.014),
			CFrame.new(-0.27, 0.07, -0.56) * CFrame.Angles(0, 0, math.rad(-18)),
			eyeCF,
			root,
			FRAME_COLOUR
		).Parent =
			model
		part(
			"BowR",
			Vector3.new(0.014, 0.48, 0.014),
			CFrame.new(0.27, 0.07, -0.56) * CFrame.Angles(0, 0, math.rad(18)),
			eyeCF,
			root,
			FRAME_COLOUR
		).Parent =
			model
		part("BowTop", Vector3.new(0.36, 0.014, 0.014), CFrame.new(0, 0.29, -0.53), eyeCF, root, FRAME_COLOUR).Parent =
			model
	end
	-- Gunsight glass (analogue kit)
	local sight = part(
		"Gunsight",
		Vector3.new(0.084, 0.073, 0.006),
		CFrame.new(0, -0.042, -0.59),
		eyeCF,
		root,
		Color3.fromRGB(150, 200, 170)
	)
	-- SmoothPlastic, not Glass: Roblox draws Glass parts opaque in front of water.
	sight.Transparency = 0.9
	sight.Material = Enum.Material.SmoothPlastic
	sight.CastShadow = false
	sight.Parent = model

	local surface = surfaceFor(panel, 714)
	for i, key in { "Speed", "Altitude", "G", "RPM" } do
		local holder = Instance.new("Frame")
		holder.Name = key
		holder.AnchorPoint = Vector2.new(0.5, 0.5)
		-- A fixed size near the top of the panel: the panel's height depends on how far the fuselage
		-- sits below the eye, and the dials shouldn't grow with it.
		holder.Position = UDim2.new(0.14 + 0.24 * (i - 1), 0, 0, DIAL_TOP + DIAL_SIZE / 2)
		holder.Size = UDim2.fromOffset(DIAL_SIZE, DIAL_SIZE)
		holder.BackgroundTransparency = 1
		holder.Parent = surface
		makeGauge(holder, key, false)
	end
	return model
end

-- Cockpit models ---------------------------------------------------------------------------------------

local function cockpitTemplate(jet: Model): Model?
	local id = jet:GetAttribute("AirframeId")
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local folder = assets and assets:FindFirstChild("Cockpits")
	local template = folder and type(id) == "string" and folder:FindFirstChild(id)
	if template and template:IsA("Model") and template.PrimaryPart then
		return template
	end
	return nil
end

local function buildFromTemplate(template: Model, root: BasePart): Model
	local model = template:Clone()
	model.Name = "LocalCockpit"
	local base = model.PrimaryPart :: BasePart
	-- The template is laid out in the jet's Root space, with its CockpitRoot at the origin
	model:PivotTo(root.CFrame)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = base
	weld.Parent = base

	local faces = model:FindFirstChild("Faces")
	for _, face in if faces then faces:GetChildren() else {} do
		if not face:IsA("BasePart") then
			continue
		end
		local key = face:GetAttribute("Gauge")
		local surface = surfaceFor(face, DIAL_SIZE / math.max(face.Size.X, 0.014))
		if key == "Radar" then
			makeScope(surface)
		elseif type(key) == "string" and GAUGES[key] then
			makeGauge(surface, key, face:GetAttribute("Style") == "Digital")
		end
	end
	return model
end

local function destroyCockpit()
	if cockpit then
		cockpit:Destroy()
		cockpit = nil
	end
	for _, surface in surfaces do
		surface:Destroy()
	end
	table.clear(surfaces)
	table.clear(gauges)
	table.clear(sweeps)
end

local function buildCockpit(jet: Model)
	destroyCockpit()
	local root = jet.PrimaryPart
	local eye = root and root:FindFirstChild("CockpitEye") :: Attachment?
	if not (root and eye) then
		return
	end
	local template = cockpitTemplate(jet)
	fromModel = template ~= nil
	local model = if template then buildFromTemplate(template, root) else buildGreybox(jet, root, eye)
	model.Parent = jet
	cockpit = model
end

local function setGauge(gauge: Gauge, value: number, dt: number, text: string)
	local v = gauge.spring:Update(dt, math.clamp(value, gauge.minValue, gauge.maxValue))
	gauge.needle.Rotation = gauge.startAngle + (v - gauge.minValue) / (gauge.maxValue - gauge.minValue) * gauge.sweep
	gauge.readout.Text = text
end

local function update(dt: number)
	local state = FlightController.state
	if not (cockpit and state) then
		return
	end
	local visible = CameraController.mode == "Cockpit"
	-- The greybox kit floats in front of the eye, so it hides in the chase view. A cockpit model sits
	-- inside the jet like the real thing and stays.
	if not fromModel then
		for _, d in cockpit:GetDescendants() do
			if d:IsA("BasePart") then
				d.LocalTransparencyModifier = if visible then 0 else 1
			end
		end
	end
	-- From inside, the jet's own canopy just tints the view (and its Glass goes opaque over water).
	local canopy = FlightController.jet and FlightController.jet:FindFirstChild("Canopy", true)
	if canopy and canopy:IsA("BasePart") then
		canopy.LocalTransparencyModifier = if visible then 1 else 0
	end
	if not visible then
		return
	end
	local knots = Units.knots(state.speed)
	local feet = Units.feet(state.altitude)
	local input = FlightController.input
	local throttle = if input then input.throttle else 0
	local rpm = 65 + 35 * throttle + (if input and input.afterburner then 5 else 0)
	for _, gauge in gauges do
		if gauge.key == "Speed" then
			setGauge(gauge, knots, dt, tostring(math.round(knots)))
		elseif gauge.key == "Altitude" then
			-- Altimeter needle: one turn per 10,000 ft
			setGauge(gauge, (feet % 10000) / 1000, dt, tostring(math.round(feet)))
		elseif gauge.key == "G" then
			setGauge(gauge, state.gLoad, dt, string.format("%.1f", state.gLoad))
		elseif gauge.key == "RPM" then
			setGauge(gauge, rpm, dt, tostring(math.round(rpm)))
		end
	end
	local sweep = 0.5 + 0.45 * math.sin(os.clock() * 1.6)
	for _, line in sweeps do
		line.Position = UDim2.fromScale(sweep, 0)
	end
end

function CockpitController:Start()
	FlightController.JetChanged:Connect(function(jet)
		if jet then
			buildCockpit(jet)
		else
			destroyCockpit()
		end
	end)
	if FlightController.jet then
		buildCockpit(FlightController.jet)
	end
	RunService.RenderStepped:Connect(update)
end

return CockpitController
