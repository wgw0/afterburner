--!strict
-- Greybox analogue cockpit kit (DEVELOPMENT.md §8.2–8.3, CAM-02). Built on the client only, welded
-- to the pilot's own jet, so nobody else sees it. Four live gauges: airspeed, altimeter, G-meter, RPM.
-- Final art for the four era kits replaces this in Phase 6 (CAM-07).

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
local DIAL_SIZE = 84 -- pixels on the panel (200 per stud)
local DIAL_TOP = 14 -- pixels from the panel top to the dials

type Gauge = {
	needle: Frame,
	readout: TextLabel,
	spring: Spring.Spring<number>,
	minValue: number,
	maxValue: number,
	sweep: number, -- degrees of needle travel
	startAngle: number,
}

local CockpitController = {
	Priority = 50,
}

local cockpit: Model?
local gauges: { [string]: Gauge } = {}

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

local function makeGauge(
	parent: Instance,
	name: string,
	title: string,
	x: number,
	minValue: number,
	maxValue: number,
	ticks: { number }
): Gauge
	local dial = Instance.new("Frame")
	dial.Name = name
	dial.AnchorPoint = Vector2.new(0.5, 0.5)
	-- A fixed size near the top of the panel: the panel's height depends on how far the fuselage sits
	-- below the eye, and the dials shouldn't grow with it.
	dial.Position = UDim2.new(x, 0, 0, DIAL_TOP + DIAL_SIZE / 2)
	dial.Size = UDim2.fromOffset(DIAL_SIZE, DIAL_SIZE)
	dial.BackgroundColor3 = DIAL_COLOUR
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = dial
	local stroke = Instance.new("UIStroke")
	stroke.Color = FRAME_COLOUR
	stroke.Thickness = 6
	stroke.Parent = dial
	dial.Parent = parent

	local sweep, startAngle = 270, -135
	for _, t in ticks do
		local angle = startAngle + (t - minValue) / (maxValue - minValue) * sweep
		local holder = Instance.new("Frame")
		holder.AnchorPoint = Vector2.new(0.5, 0.5)
		holder.Position = UDim2.fromScale(0.5, 0.5)
		holder.Size = UDim2.fromScale(1, 1)
		holder.BackgroundTransparency = 1
		holder.Rotation = angle
		holder.Parent = dial
		local mark = Instance.new("Frame")
		mark.AnchorPoint = Vector2.new(0.5, 0)
		mark.Position = UDim2.fromScale(0.5, 0.04)
		mark.Size = UDim2.fromScale(0.025, 0.1)
		mark.BackgroundColor3 = MARK_COLOUR
		mark.BorderSizePixel = 0
		mark.Parent = holder
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
	needle.BackgroundColor3 = NEEDLE_COLOUR
	needle.BorderSizePixel = 0
	needle.Parent = needleHolder

	local titleLabel = Instance.new("TextLabel")
	titleLabel.BackgroundTransparency = 1
	titleLabel.AnchorPoint = Vector2.new(0.5, 0)
	titleLabel.Position = UDim2.fromScale(0.5, 0.2)
	titleLabel.Size = UDim2.fromScale(0.8, 0.12)
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextScaled = true
	titleLabel.TextColor3 = MARK_COLOUR
	titleLabel.Text = title
	titleLabel.Parent = dial

	local readout = Instance.new("TextLabel")
	readout.BackgroundTransparency = 1
	readout.AnchorPoint = Vector2.new(0.5, 0)
	readout.Position = UDim2.fromScale(0.5, 0.68)
	readout.Size = UDim2.fromScale(0.7, 0.14)
	readout.Font = Enum.Font.Code
	readout.TextScaled = true
	readout.TextColor3 = Color3.fromRGB(255, 190, 90)
	readout.Parent = dial

	return {
		needle = needleHolder,
		readout = readout,
		spring = Spring.new(minValue, 12, 0.9),
		minValue = minValue,
		maxValue = maxValue,
		sweep = sweep,
		startAngle = startAngle,
	}
end

local PANEL_DISTANCE = -2.3 -- studs ahead of the eye
local PANEL_TOP_BELOW_EYE = -0.6 -- studs (eye space): about 15° below the line of sight, for a view over the nose
local PANEL_CLEARANCE = 0.06 -- studs above the fuselage top
local PANEL_MIN_HEIGHT = 0.55

-- Height of the jet's forward fuselage top under the panel, in eye space (negative = below the eye).
-- Looks at the jet's own solid parts on the centreline that span the panel's distance ahead.
local function fuselageTopBelowEye(jet: Model, root: BasePart, eye: Attachment): number
	local eyePos = eye.Position -- root space
	local zNear, zFar = eyePos.Z + PANEL_DISTANCE + 1, eyePos.Z + PANEL_DISTANCE - 1
	local highest = -math.huge
	for _, part in jet:GetChildren() do
		if not part:IsA("BasePart") or part == root or part.Transparency >= 0.3 then
			continue -- skips the invisible root, hull and the glass canopy
		end
		local localCF = root.CFrame:ToObjectSpace(part.CFrame)
		if math.abs(localCF.Position.X) > 4 then
			continue
		end
		local half = part.Size / 2
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
		return -1.2
	end
	return highest - eyePos.Y
end

local function destroyCockpit()
	if cockpit then
		cockpit:Destroy()
		cockpit = nil
	end
	table.clear(gauges)
end

local function buildCockpit(jet: Model)
	destroyCockpit()
	local root = jet.PrimaryPart
	local eye = root and root:FindFirstChild("CockpitEye") :: Attachment?
	if not (root and eye) then
		return
	end
	local eyeCF = eye.WorldCFrame

	local model = Instance.new("Model")
	model.Name = "LocalCockpit"

	-- The panel sits on top of the jet's forward fuselage, like a real instrument panel, so the
	-- airframe never covers it: bottom just above the fuselage top, top a little below eye level.
	local top, bottom = PANEL_TOP_BELOW_EYE, fuselageTopBelowEye(jet, root, eye) + PANEL_CLEARANCE
	local height = math.max(top - bottom, PANEL_MIN_HEIGHT)
	local panel = part(
		"Panel",
		Vector3.new(3.4, height, 0.12),
		CFrame.new(0, bottom + height / 2, PANEL_DISTANCE) * CFrame.Angles(math.rad(-12), 0, 0),
		eyeCF,
		root,
		PANEL_COLOUR
	)
	panel.Parent = model
	part(
		"Coaming",
		Vector3.new(3.6, 0.12, 0.35),
		CFrame.new(0, top + 0.07, PANEL_DISTANCE - 0.2),
		eyeCF,
		root,
		FRAME_COLOUR
	).Parent =
		model
	part("SillL", Vector3.new(0.18, 0.5, 4), CFrame.new(-1.65, -0.8, -0.6), eyeCF, root, FRAME_COLOUR).Parent = model
	part("SillR", Vector3.new(0.18, 0.5, 4), CFrame.new(1.65, -0.8, -0.6), eyeCF, root, FRAME_COLOUR).Parent = model
	-- Canopy bow and rails
	part(
		"BowL",
		Vector3.new(0.05, 1.7, 0.05),
		CFrame.new(-0.95, 0.25, -2.0) * CFrame.Angles(0, 0, math.rad(-18)),
		eyeCF,
		root,
		FRAME_COLOUR
	).Parent =
		model
	part(
		"BowR",
		Vector3.new(0.05, 1.7, 0.05),
		CFrame.new(0.95, 0.25, -2.0) * CFrame.Angles(0, 0, math.rad(18)),
		eyeCF,
		root,
		FRAME_COLOUR
	).Parent =
		model
	part("BowTop", Vector3.new(1.3, 0.05, 0.05), CFrame.new(0, 1.05, -1.9), eyeCF, root, FRAME_COLOUR).Parent = model
	-- Gunsight glass (analogue kit)
	local sight = part(
		"Gunsight",
		Vector3.new(0.3, 0.26, 0.02),
		CFrame.new(0, -0.15, -2.1),
		eyeCF,
		root,
		Color3.fromRGB(150, 200, 170)
	)
	-- SmoothPlastic, not Glass: Roblox draws Glass parts opaque in front of water.
	sight.Transparency = 0.9
	sight.Material = Enum.Material.SmoothPlastic
	sight.CastShadow = false
	sight.Parent = model

	local surface = Instance.new("SurfaceGui")
	surface.Name = "Gauges"
	surface.Face = Enum.NormalId.Back -- the face toward the pilot (+Z in panel space)
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.PixelsPerStud = 200
	surface.LightInfluence = 0.2
	surface.Adornee = panel
	surface.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	model.Destroying:Connect(function()
		surface:Destroy()
	end)

	gauges.Speed = makeGauge(surface, "Airspeed", "KT", 0.14, 0, 800, { 0, 100, 200, 300, 400, 500, 600, 700, 800 })
	gauges.Altitude = makeGauge(surface, "Altimeter", "ALT ×1000", 0.38, 0, 10, { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 })
	gauges.G = makeGauge(surface, "GMeter", "G", 0.62, -3, 9, { -3, 0, 3, 6, 9 })
	gauges.RPM = makeGauge(surface, "RPM", "RPM %", 0.86, 0, 110, { 0, 50, 70, 90, 100, 110 })

	model.Parent = jet
	cockpit = model
end

local function setGauge(gauge: Gauge?, value: number, dt: number, text: string)
	if not gauge then
		return
	end
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
	for _, d in cockpit:GetDescendants() do
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = if visible then 0 else 1
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
	setGauge(gauges.Speed, knots, dt, tostring(math.round(knots)))
	-- Altimeter needle: one turn per 10,000 ft
	setGauge(gauges.Altitude, (feet % 10000) / 1000, dt, tostring(math.round(feet)))
	setGauge(gauges.G, state.gLoad, dt, string.format("%.1f", state.gLoad))
	setGauge(gauges.RPM, rpm, dt, tostring(math.round(rpm)))
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
