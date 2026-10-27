--!strict
-- Radar scope and RWR display (DEVELOPMENT.md §14, SNS-02 / SNS-05). Screen-space panels at the bottom.
--   Radar (the cone): top-down and heading-up, your jet at the bottom and the radar's beam fanning out
--     ahead of it, with a ring at half range. It zooms (SCALES) so the nearest contact in the beam, or
--     your lock, sits in its outer part, never past the radar's range; the scale is in the title.
--     Contacts are drawn where they are, your lock as a boxed red blip; ones past the scale sit faint on
--     the edge. (It was a B-scope, then a cone at the radar's full range: both read as useless dots.)
--   Situation display (the round scope): everyone around you, top-down and heading-up, your jet in the
--     middle. It zooms to the nearest contact in any direction, but never in past the selected weapon's
--     lock range, so with enemies close the lock wedge reaches the rim; further out it's to scale.
--     The rim's range is written at the bottom; jets beyond it sit on it, faint.
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
local CONE_ORIGIN_Y = SCOPE_H - 10 -- your jet, in the radar panel (pixels from the top)
local CONE_LENGTH = SCOPE_H - 32 -- pixels from your jet to the edge of the beam (full range)
local ARC_SEGMENTS = 10

local ScopesController = {
	Priority = 62,
}

local gui: ScreenGui
local radarPanel: Frame
local radarLabel: TextLabel
local blips: { Frame } = {}
local beam: { Frame } = {} -- the cone's edges and range arcs
local beamHalfAngle = -1
local rwrPanel: Frame
local rwrMarks: { TextLabel } = {}
local tsdDots: { Frame } = {}
local coneLeft: Frame
local coneRight: Frame
local coneEnd: Frame
local tsdLabel: TextLabel
local DEFAULT_TSD_RANGE = 10000 -- real metres shown from the centre to the rim without a radar
local SCALES = { 2500, 5000, 10000, 20000, 40000, 80000 } -- metres: the zoom steps
local FILL = 0.75 -- the nearest contact sits at about this fraction of the scale
local radarScale = 10000
local tsdScale = 10000

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
	-- Own jet at the bottom of the cone
	local own = Instance.new("Frame")
	own.AnchorPoint = Vector2.new(0.5, 0.5)
	own.Position = UDim2.fromOffset(SCOPE_W / 2, CONE_ORIGIN_Y)
	own.Size = UDim2.fromOffset(9, 9)
	own.Rotation = 45
	own.BackgroundColor3 = GREEN
	own.BorderSizePixel = 0
	own.Parent = radarPanel

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

-- A line in the radar panel from a to b (pixels).
local function line(i: number, a: Vector2, b: Vector2, transparency: number)
	local f = beam[i]
	if not f then
		f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.BackgroundColor3 = GREEN
		f.BorderSizePixel = 0
		f.Parent = radarPanel
		beam[i] = f
	end
	local d = b - a
	f.Position = UDim2.fromOffset((a.X + b.X) / 2, (a.Y + b.Y) / 2)
	f.Size = UDim2.fromOffset(d.Magnitude + 1, 1)
	f.Rotation = math.deg(math.atan2(d.Y, d.X))
	f.BackgroundTransparency = transparency
end

-- Point in the radar panel at a bearing (radians, 0 = ahead) and range fraction (1 = edge of the beam).
local function conePoint(bearing: number, fraction: number): Vector2
	local r = fraction * CONE_LENGTH
	return Vector2.new(SCOPE_W / 2 + math.sin(bearing) * r, CONE_ORIGIN_Y - math.cos(bearing) * r)
end

-- The beam's two edges and its range arcs (full and half), redrawn only when the cone changes.
local function drawBeam(halfAngle: number)
	if halfAngle == beamHalfAngle then
		return
	end
	beamHalfAngle = halfAngle
	local a = math.rad(halfAngle)
	local n = 0
	for _, side in { -1, 1 } do
		n += 1
		line(n, conePoint(0, 0), conePoint(side * a, 1), 0.5)
	end
	for _, fraction in { 1, 0.5 } do
		for k = 0, ARC_SEGMENTS - 1 do
			n += 1
			local b0 = -a + 2 * a * k / ARC_SEGMENTS
			local b1 = -a + 2 * a * (k + 1) / ARC_SEGMENTS
			line(n, conePoint(b0, fraction), conePoint(b1, fraction), if fraction == 1 then 0.5 else 0.8)
		end
	end
end

-- Picks a zoom step: the smallest that puts `wanted` (metres) inside FILL, between `lo` and `hi`.
-- Zooms out at once, but only zooms in once the contact is well inside the smaller step, so the scale
-- doesn't flick back and forth at a boundary.
local function zoom(current: number, wanted: number?, lo: number, hi: number): number
	local target = SCALES[#SCALES]
	for _, step in SCALES do
		if wanted == nil or wanted <= step * FILL then
			target = step
			break
		end
	end
	target = math.clamp(target, lo, math.max(lo, hi))
	if target < current and wanted and wanted > target * FILL * 0.8 then
		return current
	end
	return target
end

local function formatKm(metres: number): string
	local km = metres / 1000
	return if km < 10 and km % 1 ~= 0 then string.format("%.1f km", km) else string.format("%d km", math.round(km))
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
		-- Zoom to your lock, or else the nearest contact in the beam
		local nearest: number? = nil
		for id, contact in SensorController.contacts do
			if contact.onRadar or id == SensorController.lockId then
				local rel = myCF:PointToObjectSpace(contact.position)
				if math.abs(math.atan2(rel.X, -rel.Z)) <= math.rad(radar.Cone) + 0.02 then
					if id == SensorController.lockId then
						nearest = contact.range
						break
					end
					nearest = math.min(nearest or math.huge, contact.range)
				end
			end
		end
		radarScale = zoom(radarScale, nearest, SCALES[1], radar.Range)
		local lockText = if SensorController.lockId ~= 0 then "  LOCK" else ""
		radarLabel.Text = `RADAR {formatKm(radarScale)}{lockText}`
		drawBeam(radar.Cone)
		for id, contact in SensorController.contacts do
			if contact.onRadar or id == SensorController.lockId then
				local rel = myCF:PointToObjectSpace(contact.position)
				local bearing = math.atan2(rel.X, -rel.Z)
				if math.abs(bearing) <= math.rad(radar.Cone) + 0.02 then
					used += 1
					local b = blip(used)
					local locked = id == SensorController.lockId
					local beyond = contact.range > radarScale
					local p = conePoint(bearing, math.clamp(contact.range / radarScale, 0, 1))
					b.Position = UDim2.fromOffset(p.X, p.Y)
					b.Size = UDim2.fromOffset(
						if locked then 12 elseif beyond then 5 else 7,
						if locked then 12 elseif beyond then 5 else 7
					)
					b.BackgroundColor3 = if locked then RED else AMBER
					b.BackgroundTransparency = if locked then 0.6 elseif beyond then 0.5 else 0
					(b:FindFirstChildOfClass("UIStroke") :: UIStroke).Enabled = locked
					b.Visible = true
				end
			end
		end
	end
	for i = used + 1, #blips do
		blips[i].Visible = false
	end

	-- Situation display: everyone around you, zoomed to the nearest, never in past the weapon's reach
	local missile = SensorController:SelectedMissile()
	local reach: number? = nil
	local coneAngle: number? = nil
	if missile and WeaponData.isRadar(missile) and radar then
		reach, coneAngle = math.min(missile.MaxRange, radar.Range), radar.Cone
	elseif missile then
		reach, coneAngle = missile.MaxRange, missile.SeekerCone
	end
	local nearestAround: number? = nil
	for _, contact in SensorController.contacts do
		nearestAround = math.min(nearestAround or math.huge, contact.range)
	end
	tsdScale = zoom(tsdScale, nearestAround, reach or SCALES[1], SCALES[#SCALES])
	local tsdRange = if nearestAround == nil and reach == nil
		then (if radar then radar.Range else DEFAULT_TSD_RANGE)
		else tsdScale
	if reach and coneAngle then
		drawCone(coneAngle, reach / tsdRange)
	else
		drawCone(nil, 0)
	end
	tsdLabel.Text = formatKm(tsdRange)
	local dots = 0
	for id, contact in SensorController.contacts do
		local rel = myCF:PointToObjectSpace(contact.position)
		local flat = Vector2.new(rel.X, -rel.Z)
		local distance = contact.range / tsdRange
		if flat.Magnitude > 1e-3 then
			dots += 1
			local d = tsdDot(dots)
			local beyond = distance > 1 -- outside the weapon's reach: on the rim, faint
			local p = flat.Unit * math.min(distance, 0.96) * 0.5
			d.Position = UDim2.fromScale(0.5 + p.X, 0.5 - p.Y)
			local locked = id == SensorController.lockId
				or (id == SensorController.irTargetId and SensorController.irLocked)
			d.BackgroundColor3 = if locked then RED elseif SensorController.lockable[id] then GREEN else AMBER
			d.Size = if locked
				then UDim2.fromOffset(8, 8)
				elseif beyond then UDim2.fromOffset(4, 4)
				else UDim2.fromOffset(6, 6)
			d.BackgroundTransparency = if beyond and not locked then 0.5 else 0
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
