--!strict
-- Radar scope and RWR display (DEVELOPMENT.md §14, SNS-02 / SNS-05). Screen-space panels at the bottom.
--   Radar (B-scope): left-right is bearing across the radar cone, bottom-to-top is range. Contacts your
--     radar sees are blips; your lock is a boxed, brighter blip.
--   RWR: a ring around your jet. Threats show at their bearing: S = search radar, L = locked on you
--     (flashing), M = missile guiding on you (red, fast flashing). Coarse RWRs only give 8 directions.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AircraftData = require(Shared.AircraftData)

local FlightController = require(script.Parent.FlightController)
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
	local me = label(rwrPanel, "✈", 18)
	me.Position = UDim2.fromScale(0.5, 0.5)
	local title = label(rwrPanel, "RWR", 11)
	title.Position = UDim2.new(0.5, 0, 0, 12)
	title.TextTransparency = 0.4

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
	local airframe = AircraftData.get(jet:GetAttribute("AirframeId") :: string) :: any
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

	-- RWR
	local coarse = not (airframe and airframe.RWR and airframe.RWR.Resolution == "Fine")
	local shown = 0
	for _, threat in SensorController.threats do
		local rel = myCF:PointToObjectSpace(threat.position)
		local bearing = math.atan2(rel.X, -rel.Z) -- 0 = ahead, positive = right
		if coarse then
			bearing = math.round(bearing / (math.pi / 4)) * (math.pi / 4)
		end
		local radius = if threat.kind == "Launch" then 0.22 elseif threat.kind == "Lock" then 0.32 else 0.42
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

function ScopesController:Start()
	build()
	RunService.RenderStepped:Connect(update)
end

return ScopesController
