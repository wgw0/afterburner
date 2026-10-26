--!strict
-- "Strait" blockout (DEVELOPMENT.md §19, MAP-02). Replaces the placeholder terrain from TerrainBuilder.
--   West landmass with a mountain range (valleys cut through it), east landmass with lower hills, and a
--   north-south channel between them with the test range on a central island. In the south the coasts
--   fall away into open sea for long-range fights. One airbase on each landmass, at opposite ends.
-- Deterministic. Run each step in Edit mode (each yields between chunks, so Studio stays responsive):
--   local S = require(game.ServerStorage.Tools.StraitBuilder)
--   S.clear() S.base() S.island() S.islets() S.relief() S.airbases() S.trim() S.spawns()
-- S.coastX(z) gives the coastline, for checks and props.

local CollectionService = game:GetService("CollectionService")

local Terrain = workspace.Terrain

local HALF = 20480 -- terrain edge (the play area ends at 20,000)
local STRIP = 128 -- coast resolution along z
local GROUND_TOP = -2 -- just under the baseplate and runway
local LAND_BOTTOM = -12 -- keep land thin: buried voxels still have to be downloaded
local WATER_TOP = -6
local SEABED = -20
local SEED = 2026
local ISLAND_RADIUS = 3000
local SPAWN_ALTITUDE = 1200

local StraitBuilder = {}

StraitBuilder.AIRBASES = {
	West = { position = Vector3.new(-11500, 0, -9000), heading = 0 },
	East = { position = Vector3.new(12000, 0, 8500), heading = 0 },
}

-- x of the west and east coastlines at z. South of z = 9000 both coasts curve away into open sea.
function StraitBuilder.coastX(z: number): (number, number)
	local recede = math.max(z - 9000, 0) ^ 2 / 10000
	local west = -8200 + 900 * math.sin(z / 2600) + 450 * math.sin(z / 900 + 1.3) - recede
	local east = 8200 + 900 * math.sin(z / 2900 + 2) + 450 * math.sin(z / 1000 + 0.4) + recede
	return west, east
end

local function isLand(p: Vector3, margin: number): boolean
	local west, east = StraitBuilder.coastX(p.Z)
	return p.X < west - margin or p.X > east + margin
end

local function nearAirbase(p: Vector3, radius: number): boolean
	for _, base in StraitBuilder.AIRBASES do
		if (Vector3.new(p.X, 0, p.Z) - base.position).Magnitude < radius then
			return true
		end
	end
	return false
end

local function block(material: Enum.Material, x0: number, x1: number, z0: number, z1: number, y0: number, y1: number)
	x0, x1 = math.min(x0, x1), math.max(x0, x1)
	if x1 - x0 < 1 or z1 - z0 < 1 then
		return
	end
	Terrain:FillBlock(
		CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2),
		Vector3.new(x1 - x0, y1 - y0, z1 - z0),
		material
	)
end

function StraitBuilder.clear(): string
	Terrain:Clear()
	return "terrain cleared"
end

-- Land, beaches and sea, one strip at a time. Pass (part, parts) to build in pieces, e.g. base(1, 4).
function StraitBuilder.base(part: number?, parts: number?): string
	local count = parts or 1
	local index = part or 1
	local strips = (2 * HALF) // STRIP
	local first = (index - 1) * strips // count
	local last = index * strips // count - 1
	for i = first, last do
		local z0 = -HALF + i * STRIP
		local z1 = z0 + STRIP
		local west, east = StraitBuilder.coastX(z0 + STRIP / 2)
		west = math.max(west, -HALF)
		east = math.min(east, HALF)
		block(Enum.Material.Grass, -HALF, west - 300, z0, z1, LAND_BOTTOM, GROUND_TOP)
		block(Enum.Material.Sand, west - 300, west + 150, z0, z1, LAND_BOTTOM, GROUND_TOP - 2)
		block(Enum.Material.Sand, west + 150, east - 150, z0, z1, SEABED - 4, SEABED)
		block(Enum.Material.Water, west + 150, east - 150, z0, z1, SEABED, WATER_TOP)
		block(Enum.Material.Sand, east - 150, east + 300, z0, z1, LAND_BOTTOM, GROUND_TOP - 2)
		block(Enum.Material.Grass, east + 300, HALF, z0, z1, LAND_BOTTOM, GROUND_TOP)
		if i % 2 == 0 then
			task.wait()
		end
	end
	return `base {index}/{count} done`
end

-- The central island keeps the test range (it spans about x -600..1200, z -1800..900).
function StraitBuilder.island(): string
	-- Strips like base(), so the surface matches the land (FillCylinder rounds the top up a voxel).
	local outer = ISLAND_RADIUS + 350
	for z0 = -outer, outer - 1, STRIP do
		local zc = z0 + STRIP / 2
		local sandHalf = math.sqrt(math.max(outer * outer - zc * zc, 0))
		local grassHalf = math.sqrt(math.max(ISLAND_RADIUS * ISLAND_RADIUS - zc * zc, 0))
		block(Enum.Material.Air, -sandHalf, sandHalf, z0, z0 + STRIP, GROUND_TOP, GROUND_TOP + 16)
		block(Enum.Material.Sand, -sandHalf, sandHalf, z0, z0 + STRIP, LAND_BOTTOM, GROUND_TOP - 2)
		block(Enum.Material.Grass, -grassHalf, grassHalf, z0, z0 + STRIP, LAND_BOTTOM, GROUND_TOP)
		task.wait()
	end
	-- A rocky headland on the island's north side, clear of the range, as a landmark.
	Terrain:FillBall(Vector3.new(-1600, GROUND_TOP - 120, -2300), 380, Enum.Material.Rock)
	return "island done"
end

-- Rocky islets in the channel for terrain masking at sea level.
function StraitBuilder.islets(): string
	local rng = Random.new(SEED + 3)
	for _ = 1, 9 do
		local z = rng:NextNumber(-17000, 8000)
		local west, east = StraitBuilder.coastX(z)
		local x = if rng:NextNumber() < 0.5
			then rng:NextNumber(west + 1200, -ISLAND_RADIUS - 900)
			else rng:NextNumber(ISLAND_RADIUS + 900, east - 1200)
		if math.abs(z) < ISLAND_RADIUS + 900 and math.abs(x) < ISLAND_RADIUS + 900 then
			continue
		end
		local r = rng:NextNumber(160, 420)
		Terrain:FillBall(Vector3.new(x, GROUND_TOP - r * 0.55, z), r, Enum.Material.Rock)
		task.wait()
	end
	return "islets done"
end

-- Mountains on the west (with passes cut through for low flying), lower hills on the east, scattered
-- hills on both landmasses away from the coast and the airbases.
function StraitBuilder.relief(): string
	local rng = Random.new(SEED)
	local peaks = 0
	for i = 0, 50 do
		local z = -19500 + i * 560
		local west = StraitBuilder.coastX(z)
		if i % 7 == 3 or i % 7 == 4 or west < -15500 then
			continue -- a pass through the range, or the coast has curved away
		end
		local x = -16200 + math.sin(i * 0.4) * 900 + rng:NextNumber(-300, 300)
		local r = rng:NextNumber(420, 680)
		local lift = rng:NextNumber(0.1, 0.4)
		local centre = Vector3.new(x, GROUND_TOP + r * lift, z)
		Terrain:FillBall(centre, r, Enum.Material.Rock)
		Terrain:FillBall(centre + Vector3.new(rng:NextNumber(-800, -450), -r * 0.55, 0), r * 0.75, Enum.Material.Ground)
		Terrain:FillBall(centre + Vector3.new(rng:NextNumber(450, 800), -r * 0.55, 0), r * 0.75, Enum.Material.Ground)
		if lift > 0.28 then
			Terrain:FillBall(centre + Vector3.new(0, r * 0.62, 0), r * 0.42, Enum.Material.Snow)
		end
		peaks += 1
		task.wait()
	end
	-- East: a lower, broken ridge
	for i = 0, 34 do
		local z = -19500 + i * 640
		local _, east = StraitBuilder.coastX(z)
		if i % 5 == 2 or east > 15500 then
			continue
		end
		local x = 16500 + math.sin(i * 0.55) * 700 + rng:NextNumber(-300, 300)
		local r = rng:NextNumber(300, 480)
		local centre = Vector3.new(x, GROUND_TOP - r * rng:NextNumber(0.1, 0.4), z)
		Terrain:FillBall(centre, r, Enum.Material.Ground)
		Terrain:FillBall(centre + Vector3.new(0, r * 0.35, 0), r * 0.6, Enum.Material.Rock)
		peaks += 1
		task.wait()
	end
	local hills = 0
	for _ = 1, 320 do
		local p = Vector3.new(rng:NextNumber(-HALF + 500, HALF - 500), 0, rng:NextNumber(-HALF + 500, HALF - 500))
		if not isLand(p, 900) or nearAirbase(p, 5000) then
			continue
		end
		local r = rng:NextNumber(150, 480)
		local material = if rng:NextNumber() < 0.3 then Enum.Material.LeafyGrass else Enum.Material.Grass
		Terrain:FillBall(Vector3.new(p.X, GROUND_TOP - r * 0.65, p.Z), r, material)
		hills += 1
		if hills % 6 == 0 then
			task.wait()
		end
	end
	return `relief done ({peaks} peaks, {hills} hills)`
end

-- Clears buried voxels nobody can see (hills and mountains are balls reaching far underground).
-- Pass (part, parts) to clear one west-to-east strip at a time, e.g. trim(1, 4) ... trim(4, 4).
function StraitBuilder.trim(part: number?, parts: number?): string
	local count = parts or 1
	local index = part or 1
	local width = (2 * HALF) / count
	local x0 = -HALF + (index - 1) * width
	local before = Terrain:CountCells()
	for x = x0, x0 + width - 1, 1024 do
		for z = -HALF, HALF - 1, 1024 do
			block(Enum.Material.Air, x, math.min(x + 1024, x0 + width), z, z + 1024, -1000, SEABED - 4)
			task.wait()
		end
	end
	return `trim {index}/{count}: {before} -> {Terrain:CountCells()} cells`
end

local function prop(parent: Instance, name: string, size: Vector3, cf: CFrame, colour: Color3, material: Enum.Material?)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.CFrame = cf
	part.Color = colour
	part.Material = material or Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- Runways (terrain asphalt), aprons and low-poly blocks for hangars and a control tower.
function StraitBuilder.airbases(): string
	local map = workspace:FindFirstChild("Map") or Instance.new("Folder")
	map.Name = "Map"
	map.Parent = workspace
	for name, base in StraitBuilder.AIRBASES do
		local old = map:FindFirstChild(`Airbase{name}`)
		if old then
			old:Destroy()
		end
		local folder = Instance.new("Folder")
		folder.Name = `Airbase{name}`
		local p = base.position
		-- The runway (north-south, about 1.7 km), a taxiway and the apron. relief() keeps hills away.
		block(Enum.Material.Asphalt, p.X - 90, p.X + 90, p.Z - 3000, p.Z + 3000, LAND_BOTTOM, GROUND_TOP)
		local side = if name == "West" then 1 else -1
		block(
			Enum.Material.Concrete,
			p.X + side * 250,
			p.X + side * 1050,
			p.Z - 700,
			p.Z + 700,
			LAND_BOTTOM,
			GROUND_TOP
		)
		block(
			Enum.Material.Asphalt,
			math.min(p.X, p.X + side * 250),
			math.max(p.X, p.X + side * 250),
			p.Z - 40,
			p.Z + 40,
			LAND_BOTTOM,
			GROUND_TOP
		)
		task.wait()
		local grey = Color3.fromRGB(120, 125, 130)
		for h = -1, 1 do
			prop(
				folder,
				"Hangar",
				Vector3.new(220, 90, 180),
				CFrame.new(p.X + side * 1250, GROUND_TOP + 45, p.Z + h * 260),
				grey,
				Enum.Material.Metal
			)
		end
		prop(
			folder,
			"Tower",
			Vector3.new(50, 170, 50),
			CFrame.new(p.X + side * 1150, GROUND_TOP + 85, p.Z - 560),
			Color3.fromRGB(205, 200, 190),
			Enum.Material.Concrete
		)
		prop(
			folder,
			"TowerCab",
			Vector3.new(80, 30, 80),
			CFrame.new(p.X + side * 1150, GROUND_TOP + 185, p.Z - 560),
			Color3.fromRGB(60, 90, 110),
			Enum.Material.Glass
		)
		folder.Parent = map
	end
	return "airbases done"
end

-- Airborne spawn points (tagged SpawnPoint, Type "Air"): six over each landmass, facing the channel.
function StraitBuilder.spawns(): string
	local map = workspace:FindFirstChild("Map") or Instance.new("Folder")
	map.Name = "Map"
	map.Parent = workspace
	local old = map:FindFirstChild("SpawnPoints")
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "SpawnPoints"
	local function add(name: string, team: string, position: Vector3)
		local part = Instance.new("Part")
		part.Name = name
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Transparency = 1
		part.Size = Vector3.new(8, 8, 8)
		part.CFrame = CFrame.lookAt(position, Vector3.new(0, position.Y, position.Z * 0.5))
		part:SetAttribute("Type", "Air")
		part:SetAttribute("Team", team)
		part:SetAttribute("Altitude", position.Y)
		CollectionService:AddTag(part, "SpawnPoint")
		part.Parent = folder
	end
	for i = 0, 5 do
		local z = -15000 + i * 3600
		local west, east = StraitBuilder.coastX(z)
		add(`West{i + 1}`, "West", Vector3.new(math.max(west - 2500, -17500), SPAWN_ALTITUDE, z))
		add(`East{i + 1}`, "East", Vector3.new(math.min(east + 2500, 17500), SPAWN_ALTITUDE, z + 1800))
	end
	folder.Parent = map
	return "spawns done (12)"
end

return StraitBuilder
