--!strict
-- "Desert Range" (MAP-05): builds the second map into the place it belongs to (its own place in the
-- experience, made as a copy of the main one). The shape is tools/DesertShape (previewable outside Studio:
-- scripts/preview-map.luau); the voxels are written by tools/TerrainKit. Airbases and spawn points use the
-- Strait's names and layout (AirbaseWest/East, tagged SpawnPoints with a Team), so every mode, streaming and
-- the Strike Escort targets work unchanged. Run each step in Edit mode:
--   local D = require(game.ServerStorage.Tools.DesertBuilder)
--   D.prepare()          -- marks the place as the Desert, sets aside the Strait's map parts, clears terrain
--   D.colours()          -- desert terrain colours
--   D.terrain(1, 8) ... D.terrain(8, 8)
--   D.airbases() D.spawns() D.lighting()

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Maps = require(ReplicatedStorage.Shared.Config.Maps)
local WorldEdge = require(ReplicatedStorage.Shared.WorldEdge)
local DesertShape = require(script.Parent.DesertShape)
local TerrainKit = require(script.Parent.TerrainKit)

local Terrain = workspace.Terrain
local PLAIN = Maps.LIST.Desert.edge.plainHeight
local SPAWN_CLEARANCE = 196

local DesertBuilder = {}

-- Surface height, eased at the edges into the flat desert outside (WorldEdge, Config/Maps)
function DesertBuilder.height(x: number, z: number): number
	local h = DesertShape.height(x, z)
	local fade = WorldEdge.fade(x, z)
	if fade > 0 then
		h += (PLAIN - h) * fade
	end
	return h
end

local MATERIALS: { [string]: Enum.Material } = {
	Sand = Enum.Material.Sand,
	Sandstone = Enum.Material.Sandstone,
	Ground = Enum.Material.Ground,
	Rock = Enum.Material.Rock,
	Salt = Enum.Material.Salt,
	Asphalt = Enum.Material.Asphalt,
	Concrete = Enum.Material.Concrete,
}

local MAP: TerrainKit.Map = {
	height = DesertBuilder.height,
	material = function(x: number, z: number, h: number, slope: number): Enum.Material
		return MATERIALS[DesertShape.material(x, z, h, slope)] or Enum.Material.Ground
	end,
	water = nil,
	half = WorldEdge.TERRAIN_HALF,
}

-- Marks this place as the Desert and sets the Strait's map parts aside (moved to ServerStorage, not deleted).
function DesertBuilder.prepare(): string
	workspace:SetAttribute("Map", "Desert")
	local aside = ServerStorage:FindFirstChild("StraitMap") or Instance.new("Folder")
	aside.Name = "StraitMap"
	aside.Parent = ServerStorage
	local moved = {}
	local map = workspace:FindFirstChild("Map")
	if map then
		for _, child in map:GetChildren() do
			child.Parent = aside
			table.insert(moved, child.Name)
		end
	end
	local range = workspace:FindFirstChild("TestRange")
	if range then
		range.Parent = aside
		table.insert(moved, "TestRange")
	end
	Terrain:Clear()
	return `Desert prepared; set aside: {table.concat(moved, ", ")}`
end

-- Sun-baked colours: orange sand, red sandstone, tan ground, brown rock, white salt.
function DesertBuilder.colours(): string
	Terrain:SetMaterialColor(Enum.Material.Sand, Color3.fromRGB(226, 182, 122))
	Terrain:SetMaterialColor(Enum.Material.Sandstone, Color3.fromRGB(194, 112, 68))
	Terrain:SetMaterialColor(Enum.Material.Ground, Color3.fromRGB(184, 140, 96))
	Terrain:SetMaterialColor(Enum.Material.Rock, Color3.fromRGB(132, 88, 66))
	Terrain:SetMaterialColor(Enum.Material.Salt, Color3.fromRGB(236, 230, 216))
	return "colours set"
end

function DesertBuilder.terrain(part: number?, parts: number?): string
	return TerrainKit.build(MAP, part, parts)
end

local function prop(parent: Instance, name: string, size: Vector3, cf: CFrame, colour: Color3, material: Enum.Material)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = colour
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- Hangars and a control tower at each airbase, sand-coloured (the runway and apron are terrain).
function DesertBuilder.airbases(): string
	local map = workspace:FindFirstChild("Map") or Instance.new("Folder")
	map.Name = "Map"
	map.Parent = workspace
	local ground = DesertShape.BASE_HEIGHT
	for name, base in DesertShape.AIRBASES do
		local old = map:FindFirstChild(`Airbase{name}`)
		if old then
			old:Destroy()
		end
		local model = Instance.new("Model")
		model.Name = `Airbase{name}`
		local p = base.position
		local side = if name == "West" then 1 else -1
		local tan = Color3.fromRGB(196, 170, 130)
		for h = -1, 1 do
			prop(
				model,
				"Hangar",
				Vector3.new(61.6, 25.2, 50.4),
				CFrame.new(p.X + side * 350, ground + 12.6, p.Z + h * 72.8),
				tan,
				Enum.Material.Metal
			)
		end
		prop(
			model,
			"Tower",
			Vector3.new(14, 47.6, 14),
			CFrame.new(p.X + side * 322, ground + 23.8, p.Z - 156.8),
			Color3.fromRGB(214, 196, 166),
			Enum.Material.Concrete
		)
		prop(
			model,
			"TowerCab",
			Vector3.new(22.4, 8.4, 22.4),
			CFrame.new(p.X + side * 322, ground + 51.8, p.Z - 156.8),
			Color3.fromRGB(70, 90, 100),
			Enum.Material.Glass
		)
		model.Parent = map
	end
	return "airbases done"
end

-- Airborne spawn points (tagged SpawnPoint, Type "Air"): six over each side, facing the middle, at least
-- SPAWN_CLEARANCE above the ground under and ahead of them.
function DesertBuilder.spawns(): string
	local map = workspace:FindFirstChild("Map") or Instance.new("Folder")
	map.Name = "Map"
	map.Parent = workspace
	local old = map:FindFirstChild("SpawnPoints")
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "SpawnPoints"
	local function add(name: string, team: string, x: number, z: number)
		local facing = Vector3.new(-x, 0, -z * 0.5).Unit
		local highest = 0
		for step = 0, 4 do
			local q = Vector3.new(x, 0, z) + facing * step * 140
			highest = math.max(highest, DesertBuilder.height(q.X, q.Z))
		end
		local position = Vector3.new(x, math.max(336, highest + SPAWN_CLEARANCE), z)
		local part = Instance.new("Part")
		part.Name = name
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Transparency = 1
		part.Size = Vector3.new(2, 2, 2)
		part.CFrame = CFrame.lookAt(position, position + facing)
		part:SetAttribute("Type", "Air")
		part:SetAttribute("Team", team)
		part:SetAttribute("Altitude", position.Y)
		CollectionService:AddTag(part, "SpawnPoint")
		part.Parent = folder
	end
	for i = 0, 5 do
		local z = -3800 + i * 1008
		add(`West{i + 1}`, "West", -4300, z)
		add(`East{i + 1}`, "East", 4100, z + 504)
	end
	folder.Parent = map
	return "spawns done (12)"
end

-- The skybox, after Albert Bierstadt (Will): tools/blender/sky_paint_bierstadt.py, painted for this sun
local SKY = {
	Ft = "rbxassetid://110374860954881",
	Bk = "rbxassetid://98673553887859",
	Lf = "rbxassetid://90537453937445",
	Rt = "rbxassetid://88457134357621",
	Up = "rbxassetid://111734507831705",
	Dn = "rbxassetid://128638330104396",
}

-- Late, golden light over the American West: a low sun (the skybox's glow is painted where it sits), warm
-- haze and long shadows across the mesas. Returns the sun direction (repaint the sky if it changes).
function DesertBuilder.lighting(): string
	Lighting.GeographicLatitude = 30
	Lighting.ClockTime = 16.9
	Lighting.Brightness = 3.2
	Lighting.ExposureCompensation = 0.15
	Lighting.Ambient = Color3.fromRGB(120, 104, 96)
	Lighting.OutdoorAmbient = Color3.fromRGB(160, 132, 112)
	Lighting.ColorShift_Top = Color3.fromRGB(255, 214, 160) -- golden low sun
	Lighting.ColorShift_Bottom = Color3.fromRGB(70, 56, 64)
	local sky = Lighting:FindFirstChildOfClass("Sky") or Instance.new("Sky")
	sky.Name = "Sky"
	sky.SkyboxFt, sky.SkyboxBk, sky.SkyboxLf = SKY.Ft, SKY.Bk, SKY.Lf
	sky.SkyboxRt, sky.SkyboxUp, sky.SkyboxDn = SKY.Rt, SKY.Up, SKY.Dn
	sky.CelestialBodiesShown = false -- the sun is painted into the skybox
	sky.Parent = Lighting
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	atmosphere.Density = 0.3
	atmosphere.Offset = 0.12
	atmosphere.Color = Color3.fromRGB(255, 214, 160)
	atmosphere.Decay = Color3.fromRGB(196, 132, 96)
	atmosphere.Glare = 0.6
	atmosphere.Haze = 1.8
	atmosphere.Parent = Lighting
	local clouds = Terrain:FindFirstChildOfClass("Clouds")
	if clouds then
		-- Only a few: the painted sky carries the clouds, and Roblox's own read too white against it
		clouds.Cover = 0.12
		clouds.Density = 0.3
		clouds.Color = Color3.fromRGB(255, 214, 160)
	end
	local sun = Lighting:GetSunDirection()
	return string.format("lighting done; sun %.4f %.4f %.4f", sun.X, sun.Y, sun.Z)
end

return DesertBuilder
