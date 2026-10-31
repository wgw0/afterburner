--!strict
-- Air Superiority zones on screen (DEVELOPMENT.md §17.3, MCH-06). From MatchState.zones:
--   * each zone as a faint upright cylinder in its owner's colour (grey when neutral), with its letter
--     floating above it, visible from anywhere on the map;
--   * a ring of glowing posts round its edge: a part is only drawn from outside, so from inside the
--     cylinder can't be seen, but the posts can;
--   * when your jet is inside a zone, a line under the banner: who's taking it, how far along, and how far
--     to the edge.
-- Zone geometry and the rules are in shared AirSuperiority; the server decides everything.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local TeamConfig = require(Shared.Config.Teams)
local Units = require(Shared.Units)

local FlightController = require(script.Parent.FlightController)
local MatchController = require(script.Parent.MatchController)

local NEUTRAL = Color3.fromRGB(200, 205, 215)
local LETTER_HEIGHT = 900 -- studs above the sea, where the fighting is
local POSTS = 32 -- round each zone's edge
local POST_WIDTH = 6 -- studs

local ZonesController = {
	Priority = 86,
}

type Marker = { cylinder: Part, billboard: BillboardGui, letter: TextLabel, posts: { Part } }

local folder: Folder
local markers: { [string]: Marker } = {}
local captureLabel: TextLabel

local function colourOf(team: string?): Color3
	local info = team and (TeamConfig :: any)[team]
	return if info then info.Colour else NEUTRAL
end

local function makeMarker(zone: any): Marker
	local cylinder = Instance.new("Part")
	cylinder.Name = `Zone{zone.id}`
	cylinder.Shape = Enum.PartType.Cylinder
	cylinder.Anchored = true
	cylinder.CanCollide = false
	cylinder.CanQuery = false
	cylinder.CanTouch = false
	cylinder.CastShadow = false
	cylinder.Material = Enum.Material.ForceField
	cylinder.Transparency = 0.2
	-- A cylinder part's axis is its X: stand it up
	cylinder.Size = Vector3.new(zone.top, zone.radius * 2, zone.radius * 2)
	cylinder.CFrame = CFrame.new(zone.position + Vector3.new(0, zone.top / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	cylinder.Parent = folder

	local posts = {}
	for i = 1, POSTS do
		local angle = (i / POSTS) * 2 * math.pi
		local post = Instance.new("Part")
		post.Name = "EdgePost"
		post.Anchored = true
		post.CanCollide = false
		post.CanQuery = false
		post.CanTouch = false
		post.CastShadow = false
		post.Material = Enum.Material.Neon
		post.Transparency = 0.55
		post.Size = Vector3.new(POST_WIDTH, zone.top, POST_WIDTH)
		local edge = Vector3.new(math.cos(angle) * zone.radius, zone.top / 2, math.sin(angle) * zone.radius)
		post.CFrame = CFrame.new(zone.position + edge)
		post.Parent = cylinder
		table.insert(posts, post)
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(60, 60)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.MaxDistance = 1e6
	billboard.StudsOffsetWorldSpace = Vector3.new(0, LETTER_HEIGHT - zone.top / 2, 0) -- at flying height, not up at the top
	billboard.Adornee = cylinder
	billboard.Parent = cylinder
	local letter = Instance.new("TextLabel")
	letter.Size = UDim2.fromScale(1, 1)
	letter.BackgroundTransparency = 1
	letter.Font = Enum.Font.GothamBlack
	letter.TextScaled = true
	letter.TextStrokeTransparency = 0.3
	letter.Text = zone.id
	letter.Parent = billboard
	return { cylinder = cylinder, billboard = billboard, letter = letter, posts = posts }
end

local function clear()
	for id, marker in markers do
		marker.cylinder:Destroy()
		markers[id] = nil
	end
end

local function render(s: any)
	local zones = s and s.state == "InProgress" and s.zones
	if not zones then
		clear()
		return
	end
	for _, zone in zones do
		local marker = markers[zone.id] or makeMarker(zone)
		markers[zone.id] = marker
		local colour = colourOf(zone.owner)
		marker.cylinder.Color = colour
		marker.letter.TextColor3 = colour
		for _, post in marker.posts do
			post.Color = colour
		end
	end
end

-- The capture line: shown while your jet is inside a zone.
local function updateCapture()
	local s = MatchController.state
	local root = FlightController.root
	captureLabel.Visible = false
	if not (s and s.zones and s.state == "InProgress" and root and s.teams) then
		return
	end
	local myTeam = Players.LocalPlayer:GetAttribute("Team")
	for _, zone in s.zones do
		local p = root.Position
		local flat = Vector3.new(p.X - zone.position.X, 0, p.Z - zone.position.Z)
		if flat.Magnitude <= zone.radius and p.Y <= zone.top then
			-- progress runs from -1 (first team) to +1 (second team)
			local towards = if zone.progress < 0 then s.teams[1] elseif zone.progress > 0 then s.teams[2] else nil
			local percent = math.round(math.abs(zone.progress) * 100)
			local text
			if zone.owner == myTeam then
				text = if percent >= 100
					then `ZONE {zone.id}  ·  HELD`
					else `ZONE {zone.id}  ·  UNDER ATTACK {percent}%`
			elseif zone.owner then
				text = `ZONE {zone.id}  ·  ENEMY  ·  NEUTRALISING {100 - percent}%`
			elseif towards == myTeam then
				text = `ZONE {zone.id}  ·  CAPTURING {percent}%`
			elseif towards then
				text = `ZONE {zone.id}  ·  ENEMY CAPTURING {percent}%`
			else
				text = `ZONE {zone.id}  ·  NEUTRAL`
			end
			local edge = Units.toMetres(zone.radius - flat.Magnitude) / 1000
			captureLabel.Text = `{text}  ·  EDGE {string.format("%.1f", edge)} km`
			captureLabel.TextColor3 = colourOf(zone.owner or towards)
			captureLabel.Visible = true
			return
		end
	end
end

function ZonesController:Init()
	folder = Instance.new("Folder")
	folder.Name = "AfterburnerZones"
	folder.Parent = workspace

	local gui = Instance.new("ScreenGui")
	gui.Name = "AfterburnerZones"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 24
	captureLabel = Instance.new("TextLabel")
	captureLabel.AnchorPoint = Vector2.new(0.5, 0)
	captureLabel.Position = UDim2.new(0.5, 0, 0, 32)
	captureLabel.Size = UDim2.fromOffset(520, 22)
	captureLabel.BackgroundTransparency = 1
	captureLabel.Font = Enum.Font.GothamBold
	captureLabel.TextSize = 16
	captureLabel.TextStrokeTransparency = 0.5
	captureLabel.Visible = false
	captureLabel.Parent = gui
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

function ZonesController:Start()
	MatchController.Changed:Connect(render)
	RunService.RenderStepped:Connect(updateCapture)
end

return ZonesController
