--!strict
-- Radar scope and RWR display (DEVELOPMENT.md §14, SNS-02 / SNS-05). Screen-space panels at the bottom.
--   Radar (B-scope): left-right is bearing across the radar cone, bottom-to-top is range. Contacts your
--     radar sees are blips; your lock is a boxed, brighter blip.
--   Situation display (the round scope): top-down and heading-up, with your jet in the middle.
--     * The wedge ahead is where the selected missile can lock (heat-seeker: seeker cone out to its
--       range; radar missile: the radar cone out to the missile's range).
--     * Dots are jets you know about: red = locked, green = lockable, amber = the rest.
--     * RWR around the rim: threats at their bearing, S = search radar, L = locked on you (flashing),
--       M = missile guiding on you (red, fast flashing). Coarse RWRs only give 8 directions.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Progression = require(Shared.Progression)
local WeaponData = require(Shared.WeaponData)

local FlightController = require(script.Parent.FlightController)
local InputController = require(script.Parent.InputController)
local SensorController = require(script.Parent.SensorController)

local GREEN = Color3.fromRGB(110, 255, 150)
local AMBER = Color3.fromRGB(255, 190, 80)
local RED = Color3.fromRGB(255, 80, 70)
local PANEL = Color3.fromRGB(6, 16, 10)
local FONT = Enum.Font.RobotoMono

local SCOPE_W, SCOPE_H = 220, 170
local RWR_SIZE = 170

local ScopesController = {
	Priority = 62,
}

local gui: ScreenGui
local radarPanel: Frame
local radarLabel: TextLabel
local blips: { Frame } = {}
local rwrPanel: Frame
local rwrMarks: { TextLabel } = {}
local tsdDots: { Frame } = {}
local coneLeft: Frame
local coneRight: Frame
local coneEnd: Frame
local tsdLabel: TextLabel
local DEFAULT_TSD_RANGE = 10000 -- real metres shown from the centre to the rim without a radar

local function panel(name: string, size: Vector2, position: UDim2, anchor: Vector2): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.AnchorPoint = anchor
	f.Position = position
	f.Size = UDim2.fromOffset(size.X, size.Y)
	f.BackgroundColor3 = PANEL
	f.BackgroundTransparency = 0.35
	f.BorderSizePixel = 0
	local stroke = Instance.new("UIStroke")
	stroke.Color = GREEN
	stroke.Transparency = 0.5
	stroke.Parent = f
	f.Parent = gui
	return f
end

local function label(parent: Instance, text: string, size: number): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = FONT
	l.TextSize = size
	l.TextColor3 = GREEN
	l.Text = text
	l.Size = UDim2.fromOffset(40, size + 2)
	l.AnchorPoint = Vector2.new(0.5, 0.5)
	l.Parent = parent
	return l
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "AfterburnerScopes"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 6
	gui.Enabled = false

	radarPanel = panel("Radar", Vector2.new(SCOPE_W, SCOPE_H), UDim2.new(0.5, -130, 1, -16), Vector2.new(0.5, 1))
	radarLabel = label(radarPanel, "RADAR", 12)
	radarLabel.AnchorPoint = Vector2.new(0, 0)
	radarLabel.Position = UDim2.fromOffset(6, 4)
	radarLabel.Size = UDim2.fromOffset(200, 14)
	radarLabel.TextXAlignment = Enum.TextXAlignment.Left
	for _, fraction in { 0.25, 0.5, 0.75 } do
		local line = Instance.new("Frame")
		line.BackgroundColor3 = GREEN
		line.BackgroundTransparency = 0.8
		line.BorderSizePixel = 0
		line.Position = UDim2.fromScale(0, 1 - fraction)
		line.Size = UDim2.new(1, 0, 0, 1)
		line.Parent = radarPanel
	end
	local centre = Instance.new("Frame")
	centre.BackgroundColor3 = GREEN
	centre.BackgroundTransparency = 0.8
	centre.BorderSizePixel = 0
	centre.Position = UDim2.fromScale(0.5, 0)
	centre.Size = UDim2.new(0, 1, 1, 0)
	centre.Parent = radarPanel

	rwrPanel = panel("RWR", Vector2.new(RWR_SIZE, RWR_SIZE), UDim2.new(0.5, 130, 1, -16), Vector2.new(0.5, 1))
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = rwrPanel
	local function bar(size: Vector2, position: UDim2, anchor: Vector2?): Frame
		local f = Instance.new("Frame")
		f.AnchorPoint = anchor or Vector2.new(0.5, 0.5)
		f.BackgroundColor3 = GREEN
		f.BorderSizePixel = 0
		f.Size = UDim2.fromOffset(size.X, size.Y)
		f.Position = position
		f.Parent = rwrPanel
		return f
	end
	-- Half-range ring
	local ring = Instance.new("Frame")
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.fromScale(0.5, 0.5)
	ring.BackgroundTransparency = 1
	local ringCorner = Instance.new("UICorner")
	ringCorner.CornerRadius = UDim.new(0.5, 0)
	ringCorner.Parent = ring
	local ringStroke = Instance.new("UIStroke")
	ringStroke.Color = GREEN
	ringStroke.Transparency = 0.75
	ringStroke.Parent = ring
	ring.Parent = rwrPanel
	-- Lock cone (two edges and an end line), drawn under the jet symbol
	coneLeft = bar(Vector2.new(1, 10), UDim2.fromScale(0.5, 0.5))
	coneRight = bar(Vector2.new(1, 10), UDim2.fromScale(0.5, 0.5))
	coneEnd = bar(Vector2.new(10, 1), UDim2.fromScale(0.5, 0.5))
	for _, f in { coneLeft, coneRight, coneEnd } do
		f.BackgroundTransparency = 0.35
	end
	-- Own jet, line-art like the HUD: fuselage, swept-looking wings, tailplane
	local centre = UDim2.fromScale(0.5, 0.5)
	bar(Vector2.new(3, 24), centre)
	bar(Vector2.new(22, 3), centre + UDim2.fromOffset(0, 1))
	bar(Vector2.new(10, 2), centre + UDim2.fromOffset(0, 10))
	bar(Vector2.new(3, 3), centre + UDim2.fromOffset(0, -13)) -- nose
	local title = label(rwrPanel, "RWR", 11)
	title.Position = UDim2.new(0.5, 0, 0, 12)
	title.TextTransparency = 0.4
	tsdLabel = label(rwrPanel, "", 10)
	tsdLabel.Size = UDim2.fromOffset(80, 12)
	tsdLabel.Position = UDim2.new(0.5, 0, 1, -12)
	tsdLabel.TextTransparency = 0.3

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

local function blip(i: number): Frame
	local b = blips[i]
	if not b then
		b = Instance.new("Frame")
		b.AnchorPoint = Vector2.new(0.5, 0.5)
		b.BorderSizePixel = 0
		local stroke = Instance.new("UIStroke")
		stroke.Color = AMBER
		stroke.Thickness = 1.5
		stroke.Parent = b
		b.Parent = radarPanel
		blips[i] = b
	end
	return b
end

local function tsdDot(i: number): Frame
	local d = tsdDots[i]
	if not d then
		d = Instance.new("Frame")
		d.AnchorPoint = Vector2.new(0.5, 0.5)
		d.Size = UDim2.fromOffset(6, 6)
		d.BorderSizePixel = 0
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = d
		d.Parent = rwrPanel
		tsdDots[i] = d
	end
	return d
end

-- Draws the selected missile's lock wedge: half-angle in degrees, length as a fraction of the radius.
local function drawCone(halfAngle: number?, reach: number)
	local visible = halfAngle ~= nil and reach > 0
	coneLeft.Visible, coneRight.Visible, coneEnd.Visible = visible, visible, visible
	if not halfAngle then
		return
	end
	local radius = RWR_SIZE / 2
	local length = math.clamp(reach, 0, 1) * radius
	local a = math.rad(math.min(halfAngle, 80))
	-- GUI objects rotate about their centre, so each edge is centred halfway along its line.
	local midX, midY = length / 2 * math.sin(a), -length / 2 * math.cos(a)
	coneLeft.Size = UDim2.fromOffset(1, length)
	coneLeft.Position = UDim2.new(0.5, -midX, 0.5, midY)
	coneLeft.Rotation = -math.deg(a)
	coneRight.Size = UDim2.fromOffset(1, length)
	coneRight.Position = UDim2.new(0.5, midX, 0.5, midY)
	coneRight.Rotation = math.deg(a)
	coneEnd.Size = UDim2.fromOffset(2 * length * math.sin(a), 1)
	coneEnd.Position = UDim2.new(0.5, 0, 0.5, -length * math.cos(a))
end

local function rwrMark(i: number): TextLabel
	local m = rwrMarks[i]
	if not m then
		m = label(rwrPanel, "S", 16)
		m.Font = Enum.Font.GothamBold
		rwrMarks[i] = m
	end
	return m
end

local function update()
	local jet, root = FlightController.jet, FlightController.root
	gui.Enabled = jet ~= nil and not FlightController:IsUnconscious()
	if not (jet and root) then
		return
	end
	local airframe = Progression.airframeForModel(jet) :: any
	local radar = airframe and airframe.Radar
	local myCF = root.CFrame
	local flash = os.clock() % 0.5 < 0.25
	local fastFlash = os.clock() % 0.2 < 0.1

	-- Radar scope
	radarPanel.Visible = radar ~= nil
	local used = 0
	if radar then
		local lockText = if SensorController.lockId ~= 0 then "  LOCK" else ""
		radarLabel.Text = string.format("RADAR %d km%s", math.round(radar.Range / 1000), lockText)
		for id, contact in SensorController.contacts do
			if contact.onRadar or id == SensorController.lockId then
				local rel = myCF:PointToObjectSpace(contact.position)
				local bearing = math.atan2(rel.X, -rel.Z)
				local x = 0.5 + bearing / (2 * math.rad(radar.Cone))
				local y = 1 - math.clamp(contact.range / radar.Range, 0, 1)
				if x >= 0 and x <= 1 then
					used += 1
					local b = blip(used)
					local locked = id == SensorController.lockId
					b.Position = UDim2.fromScale(x, y)
					b.Size = UDim2.fromOffset(if locked then 12 else 7, if locked then 12 else 7)
					b.BackgroundColor3 = if locked then RED else AMBER
					b.BackgroundTransparency = if locked then 0.6 else 0
					(b:FindFirstChildOfClass("UIStroke") :: UIStroke).Enabled = locked
					b.Visible = true
				end
			end
		end
	end
	for i = used + 1, #blips do
		blips[i].Visible = false
	end

	-- Situation display: lock cone and contacts
	local tsdRange = if radar then radar.Range else DEFAULT_TSD_RANGE
	tsdLabel.Text = string.format("%d km", math.round(tsdRange / 1000))
	local missile = SensorController:SelectedMissile()
	if missile and WeaponData.isRadar(missile) and radar then
		drawCone(radar.Cone, math.min(missile.MaxRange, radar.Range) / tsdRange)
	elseif missile then
		drawCone(missile.SeekerCone, missile.MaxRange / tsdRange)
	else
		drawCone(nil, 0)
	end
	local dots = 0
	for id, contact in SensorController.contacts do
		local rel = myCF:PointToObjectSpace(contact.position)
		local flat = Vector2.new(rel.X, -rel.Z)
		local distance = contact.range / tsdRange
		if distance <= 0.95 and flat.Magnitude > 1e-3 then
			dots += 1
			local d = tsdDot(dots)
			local p = flat.Unit * distance * 0.5
			d.Position = UDim2.fromScale(0.5 + p.X, 0.5 - p.Y)
			local locked = id == SensorController.lockId
				or (id == SensorController.irTargetId and SensorController.irLocked)
			d.BackgroundColor3 = if locked then RED elseif SensorController.lockable[id] then GREEN else AMBER
			d.Size = if locked then UDim2.fromOffset(8, 8) else UDim2.fromOffset(6, 6)
			d.Visible = true
		end
	end
	for i = dots + 1, #tsdDots do
		tsdDots[i].Visible = false
	end

	-- RWR
	local coarse = not (airframe and airframe.RWR and airframe.RWR.Resolution == "Fine")
	local shown = 0
	for _, threat in SensorController.threats do
		local rel = myCF:PointToObjectSpace(threat.position)
		local bearing = math.atan2(rel.X, -rel.Z) -- 0 = ahead, positive = right
		if coarse then
			bearing = math.round(bearing / (math.pi / 4)) * (math.pi / 4)
		end
		local radius = 0.42 -- around the rim, clear of the contacts
		shown += 1
		local m = rwrMark(shown)
		m.Position = UDim2.fromScale(0.5 + math.sin(bearing) * radius, 0.5 - math.cos(bearing) * radius)
		if threat.kind == "Launch" then
			m.Text, m.TextColor3, m.Visible = "M", RED, fastFlash
		elseif threat.kind == "Lock" then
			m.Text, m.TextColor3, m.Visible = "L", AMBER, flash
		else
			m.Text, m.TextColor3, m.Visible = "S", GREEN, true
		end
	end
	for i = shown + 1, #rwrMarks do
		rwrMarks[i].Visible = false
	end
end

-- HUD-06: on touch the bottom of the screen belongs to the stick and buttons, so the scopes shrink and
-- move to the top corners.
local function applyLayout()
	local compact = InputController.device == "Touch"
	for _, f in { radarPanel, rwrPanel } do
		local scale = f:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
		scale.Scale = if compact then 0.7 else 1
		scale.Parent = f
	end
	if compact then
		radarPanel.AnchorPoint = Vector2.new(0, 0)
		radarPanel.Position = UDim2.fromOffset(12, 130)
		rwrPanel.AnchorPoint = Vector2.new(1, 0)
		rwrPanel.Position = UDim2.new(1, -12, 0, 130)
	else
		radarPanel.AnchorPoint = Vector2.new(0.5, 1)
		radarPanel.Position = UDim2.new(0.5, -130, 1, -16)
		rwrPanel.AnchorPoint = Vector2.new(0.5, 1)
		rwrPanel.Position = UDim2.new(0.5, 130, 1, -16)
	end
end

function ScopesController:Start()
	build()
	applyLayout()
	InputController.DeviceChanged:Connect(applyLayout)
	RunService.RenderStepped:Connect(update)
end

return ScopesController
