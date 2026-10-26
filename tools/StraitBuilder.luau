--!strict
--!native
-- "Strait" terrain (DEVELOPMENT.md §19, MAP-02). A height field written straight into voxels:
--   * West landmass: rolling lowland and river valleys rising into a ridged mountain range (peaks up to
--     ~1,750 studs, about 1,300 m real) with passes cut through it for low flying.
--   * East landmass: hills rising into a lower, broken range.
--   * A north-south channel between them with the island runway in the middle, rocky islets for terrain
--     masking, and open sea in the south where the coasts fall away.
--   * One airbase on each landmass (flattened, asphalt runway, concrete apron, low-poly buildings).
-- Only a thin shell under the surface is filled (thick enough to close steep slopes) and the sea is
-- shallow, so the data a client streams stays small. Heights are rounded to whole studs and each column
-- uses one material: free-floating heights gave every surface voxel a different fill level, which
-- doesn't compress (the place file was 80 MB before rounding).
-- Deterministic. Run each step in Edit mode; terrain() yields as it goes and can be split into parts:
--   local S = require(game.ServerStorage.Tools.StraitBuilder)
--   S.clear() S.terrain(1, 8) ... S.terrain(8, 8) S.airbases() S.spawns()
-- S.height(x, z) gives the surface height in studs at any point (spawns and checks use it).

local CollectionService = game:GetService("CollectionService")

local Terrain = workspace.Terrain

local HALF = 20480 -- terrain edge (the play area ends at 20,000)
local CHUNK = 128 -- studs per WriteVoxels call (small chunks keep the vertical span low on slopes)
local GRID = 16 -- the height field is sampled every 16 studs and interpolated per 4-stud column
local WATER = -6 -- sea surface
local SEED = 2026
local ISLAND_RADIUS = 3000
local ISLAND_FLAT = 1500 -- the runway area stays flat at y = 0
local BASE_HEIGHT = 20 -- airbase ground level
local SPAWN_CLEARANCE = 700 -- spawn at least this far above the ground

local StraitBuilder = {}

StraitBuilder.AIRBASES = {
	West = { position = Vector3.new(-11500, 0, -9000) },
	East = { position = Vector3.new(12000, 0, 8500) },
}

local function smoothstep(a: number, b: number, x: number): number
	local t = math.clamp((x - a) / (b - a), 0, 1)
	return t * t * (3 - 2 * t)
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- Fractal noise, roughly -1..1
local function fbm(x: number, z: number, scale: number, octaves: number, seed: number): number
	local total, amplitude, frequency, norm = 0, 1, 1 / scale, 0
	for _ = 1, octaves do
		total += math.noise(x * frequency, z * frequency, seed) * amplitude
		norm += amplitude
		amplitude *= 0.5
		frequency *= 2.03
	end
	return total / norm * 1.6
end

-- Ridged noise, 0..1: sharp crests where the noise crosses zero
local function ridged(x: number, z: number, scale: number, octaves: number, seed: number): number
	local total, amplitude, frequency, norm, weight = 0, 1, 1 / scale, 0, 1
	for _ = 1, octaves do
		local n = 1 - math.abs(math.noise(x * frequency, z * frequency, seed))
		n = n * n * weight
		weight = math.clamp(n * 1.6, 0, 1)
		total += n * amplitude
		norm += amplitude
		amplitude *= 0.5
		frequency *= 2.1
	end
	return total / norm
end

-- x of the west and east coastlines at z. South of z = 9000 both coasts curve away into open sea.
function StraitBuilder.coastX(z: number): (number, number)
	local recede = math.max(z - 9000, 0) ^ 2 / 10000
	local west = -8200 + 900 * math.sin(z / 2600) + 450 * math.sin(z / 900 + 1.3) - recede
	local east = 8200 + 900 * math.sin(z / 2900 + 2) + 450 * math.sin(z / 1000 + 0.4) + recede
	return west, east
end

-- Islets in the channel: { x, z, radius, peak }
local ISLETS = {}
do
	local rng = Random.new(SEED + 3)
	while #ISLETS < 10 do
		local z = rng:NextNumber(-17000, 8000)
		local west, east = StraitBuilder.coastX(z)
		local x = if rng:NextNumber() < 0.5
			then rng:NextNumber(west + 1400, -ISLAND_RADIUS - 900)
			else rng:NextNumber(ISLAND_RADIUS + 900, east - 1400)
		if not (math.abs(z) < ISLAND_RADIUS + 900 and math.abs(x) < ISLAND_RADIUS + 900) then
			table.insert(ISLETS, { x, z, rng:NextNumber(220, 520), rng:NextNumber(60, 260) })
		end
	end
end

-- 0 outside an airbase, 1 on it (with an 800-stud blend), plus whether the point is on the runway/apron.
local function airbaseAt(x: number, z: number): (number, Enum.Material?)
	for name, base in StraitBuilder.AIRBASES do
		local dx, dz = x - base.position.X, z - base.position.Z
		local outside = math.max(math.abs(dx) - 1400, math.abs(dz) - 3800, 0)
		if outside < 800 then
			local material: Enum.Material? = nil
			local side = if name == "West" then 1 else -1
			local runway = math.abs(dx) < 90 and math.abs(dz) < 3000
			local taxiway = dx * side >= 0 and dx * side <= 250 and math.abs(dz) < 40
			if runway or taxiway then
				material = Enum.Material.Asphalt
			elseif dx * side > 250 and dx * side < 1050 and math.abs(dz) < 700 then
				material = Enum.Material.Concrete
			end
			return 1 - smoothstep(0, 800, outside), material
		end
	end
	return 0, nil
end

-- Surface height (studs) at a point.
function StraitBuilder.height(x: number, z: number): number
	-- Central island: flat runway area, a low rim of hills, a rocky headland, beaches.
	local r = math.sqrt(x * x + z * z)
	local islandEdge = ISLAND_RADIUS + 260 * fbm(x, z, 1400, 2, SEED + 11)
	if r < islandEdge + 900 then
		local s = math.clamp((r - ISLAND_FLAT) / (islandEdge - ISLAND_FLAT), 0, 1)
		local rim = math.sin(s * math.pi) * (40 + 70 * math.max(fbm(x, z, 700, 3, SEED + 12), 0))
		local headland = 330 * math.exp(-((x + 1600) ^ 2 + (z + 2300) ^ 2) / (420 * 420))
		local land = rim * smoothstep(0, 0.15, s) + headland
		if r <= islandEdge then
			return math.max(land - smoothstep(0.85, 1, s) * 8, WATER + 1 + (1 - s) * 2)
		end
		-- Shelving into the sea
		return lerp(WATER - 2, WATER - 16, smoothstep(islandEdge, islandEdge + 900, r))
	end

	local west, east = StraitBuilder.coastX(z)
	local d = math.max(west - x, x - east) + 380 * fbm(x, z, 2200, 3, SEED + 1) -- distance inland

	if d < 0 then
		-- Sea: shallow shelf, islets
		local h = lerp(WATER - 2, WATER - 16, smoothstep(0, 700, -d))
		for _, islet in ISLETS do
			local dist = math.sqrt((x - islet[1]) ^ 2 + (z - islet[2]) ^ 2)
			if dist < islet[3] * 1.3 then
				local shape = 1 - (dist / islet[3]) ^ 2
				local rough = 1 + 0.35 * fbm(x, z, 120, 2, SEED + 13)
				h = math.max(h, WATER - 3 + (islet[4] + 6) * shape * rough)
			end
		end
		return h
	end

	local inland = smoothstep(0, 900, d)
	local deep = smoothstep(800, 4000, d)

	-- Lowland: gentle rise from the beach, rolling hills, hilly patches
	local h = WATER + 3 + 60 * inland
	h += inland * (55 + 70 * fbm(x, z, 2600, 4, SEED + 2))
	local hilly = smoothstep(-0.2, 0.5, fbm(x, z, 7000, 2, SEED + 3))
	h += inland * hilly * 260 * math.max(fbm(x, z, 1500, 4, SEED + 4), 0) ^ 1.4

	-- Mountains (west high, east lower), with passes
	local ridgeW = -15600 + 900 * math.sin(z / 3100)
	local ridgeE = 15800 + 700 * math.sin(z / 2700 + 1)
	local maskW = math.exp(-((x - ridgeW) / 2900) ^ 2)
	local maskE = math.exp(-((x - ridgeE) / 2300) ^ 2)
	local passes = 0.25 + 0.75 * smoothstep(-0.25, 0.35, math.noise(z / 4300, 3.1, SEED + 5))
	local crest = ridged(x, z, 2600, 5, SEED + 6)
	h += deep * passes * (maskW * (300 + 1450 * crest) + maskE * (160 + 620 * crest))

	-- River valleys wind down toward the sea
	local v = math.abs(math.noise(x / 5600, z / 5600, SEED + 7) + 0.25 * math.noise(x / 1400, z / 1400, SEED + 8))
	local valley = 1 - smoothstep(0.02, 0.14, v)
	h = lerp(h, WATER + 10 + 0.15 * (h - WATER), valley * inland * 0.75)

	-- Airbases are flattened
	local base = airbaseAt(x, z)
	if base > 0 then
		h = lerp(h, BASE_HEIGHT, base)
	end
	return h
end

local function surfaceMaterial(x: number, z: number, h: number, slope: number): Enum.Material
	local _, baseMaterial = airbaseAt(x, z)
	if baseMaterial then
		return baseMaterial
	end
	if h < WATER + 0.5 then
		return Enum.Material.Sand
	end
	if h < WATER + 6 and slope < 0.5 then
		return Enum.Material.Sand
	end
	local jitter = 120 * math.noise(x / 400, z / 400, SEED + 20)
	if h > 1250 + jitter and slope < 0.85 then
		return Enum.Material.Snow
	end
	if slope > 0.85 or h > 950 + jitter then
		return Enum.Material.Rock
	end
	if slope > 0.5 or h > 650 + jitter then
		return Enum.Material.Ground
	end
	if math.noise(x / 900, z / 900, SEED + 21) > 0.25 then
		return Enum.Material.LeafyGrass
	end
	return Enum.Material.Grass
end

function StraitBuilder.clear(): string
	Terrain:Clear()
	return "terrain cleared"
end

-- Writes one CHUNK × CHUNK area whose corner is (x0, z0).
local function writeChunk(x0: number, z0: number)
	local columns = CHUNK // 4
	-- Height field samples covering the chunk plus one grid step around it
	local samples = CHUNK // GRID + 3
	local grid = table.create(samples)
	for i = 1, samples do
		local row = table.create(samples)
		local gx = x0 + (i - 2) * GRID
		for k = 1, samples do
			row[k] = StraitBuilder.height(gx, z0 + (k - 2) * GRID)
		end
		grid[i] = row
	end
	local function at(px: number, pz: number): number
		local fx = (px - x0) / GRID + 2
		local fz = (pz - z0) / GRID + 2
		local i, k = math.floor(fx), math.floor(fz)
		local tx, tz = fx - i, fz - k
		local a = grid[i][k] + (grid[i + 1][k] - grid[i][k]) * tx
		local b = grid[i][k + 1] + (grid[i + 1][k + 1] - grid[i][k + 1]) * tx
		return a + (b - a) * tz
	end

	-- Column heights including a one-column border (for slopes and shell thickness)
	local heights = table.create(columns + 2)
	for i = 0, columns + 1 do
		local row = table.create(columns + 2)
		for k = 0, columns + 1 do
			row[k + 1] = math.round(at(x0 + (i - 1) * 4 + 2, z0 + (k - 1) * 4 + 2))
		end
		heights[i + 1] = row
	end

	local low, high = math.huge, -math.huge
	local bottoms = table.create(columns)
	local slopes = table.create(columns)
	for i = 1, columns do
		local bRow, sRow = table.create(columns), table.create(columns)
		for k = 1, columns do
			local h = heights[i + 1][k + 1]
			local n1, n2 = heights[i][k + 1], heights[i + 2][k + 1]
			local n3, n4 = heights[i + 1][k], heights[i + 1][k + 2]
			local drop = math.max(h - n1, h - n2, h - n3, h - n4, 0)
			local bottom = h - math.max(8, drop + 6)
			bRow[k] = bottom
			sRow[k] = math.sqrt((n2 - n1) ^ 2 + (n4 - n3) ^ 2) / 8
			low = math.min(low, bottom)
			high = math.max(high, h, WATER)
		end
		bottoms[i], slopes[i] = bRow, sRow
	end

	local y0 = math.floor(low / 4) * 4
	local y1 = math.ceil(high / 4) * 4 + 4
	local layers = (y1 - y0) // 4
	local materials = table.create(columns)
	local occupancy = table.create(columns)
	local air, water = Enum.Material.Air, Enum.Material.Water
	for i = 1, columns do
		local mx, ox = table.create(layers), table.create(layers)
		local px = x0 + (i - 1) * 4 + 2
		for j = 1, layers do
			mx[j] = table.create(columns, air)
			ox[j] = table.create(columns, 0)
		end
		for k = 1, columns do
			local h = heights[i + 1][k + 1]
			local bottom = bottoms[i][k]
			local surface = surfaceMaterial(px, z0 + (k - 1) * 4 + 2, h, slopes[i][k])
			for j = 1, layers do
				local yb = y0 + (j - 1) * 4
				local solid = math.clamp((h - yb) / 4, 0, 1)
				if yb + 4 > bottom and solid > 0 then
					mx[j][k] = surface
					ox[j][k] = solid
				end
				if solid < 0.5 and yb < WATER then
					-- Water above the ground, up to the sea surface (partial in the top voxel)
					mx[j][k] = water
					ox[j][k] = math.clamp((WATER - yb) / 4, 0, 1)
				end
			end
		end
		materials[i], occupancy[i] = mx, ox
	end
	local region = Region3.new(Vector3.new(x0, y0, z0), Vector3.new(x0 + CHUNK, y1, z0 + CHUNK))
	Terrain:WriteVoxels(region, 4, materials, occupancy)
end

-- Builds the terrain, one west-to-east strip of the map per part: terrain(1, 8) ... terrain(8, 8).
function StraitBuilder.terrain(part: number?, parts: number?): string
	local count = parts or 1
	local index = part or 1
	local strips = (2 * HALF) // CHUNK
	local first = (index - 1) * strips // count
	local last = index * strips // count - 1
	local started = os.clock()
	local budget = os.clock()
	for sx = first, last do
		for sz = 0, strips - 1 do
			writeChunk(-HALF + sx * CHUNK, -HALF + sz * CHUNK)
			if os.clock() - budget > 0.05 then
				task.wait()
				budget = os.clock()
			end
		end
	end
	return string.format("terrain %d/%d done in %.0f s", index, count, os.clock() - started)
end

local function prop(parent: Instance, name: string, size: Vector3, cf: CFrame, colour: Color3, material: Enum.Material)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.CFrame = cf
	part.Color = colour
	part.Material = material
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- Low-poly hangars and a control tower at each airbase (the runway and apron are terrain).
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
		local side = if name == "West" then 1 else -1
		local grey = Color3.fromRGB(120, 125, 130)
		for h = -1, 1 do
			prop(
				folder,
				"Hangar",
				Vector3.new(220, 90, 180),
				CFrame.new(p.X + side * 1250, BASE_HEIGHT + 45, p.Z + h * 260),
				grey,
				Enum.Material.Metal
			)
		end
		prop(
			folder,
			"Tower",
			Vector3.new(50, 170, 50),
			CFrame.new(p.X + side * 1150, BASE_HEIGHT + 85, p.Z - 560),
			Color3.fromRGB(205, 200, 190),
			Enum.Material.Concrete
		)
		prop(
			folder,
			"TowerCab",
			Vector3.new(80, 30, 80),
			CFrame.new(p.X + side * 1150, BASE_HEIGHT + 185, p.Z - 560),
			Color3.fromRGB(60, 90, 110),
			Enum.Material.Glass
		)
		folder.Parent = map
	end
	return "airbases done"
end

-- Airborne spawn points (tagged SpawnPoint, Type "Air"): six over each landmass, facing the channel,
-- at least SPAWN_CLEARANCE above the ground under and ahead of them.
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
	local function add(name: string, team: string, x: number, z: number)
		local facing = Vector3.new(-x, 0, -z * 0.5).Unit
		local highest = 0
		for step = 0, 4 do
			local p = Vector3.new(x, 0, z) + facing * step * 500
			highest = math.max(highest, StraitBuilder.height(p.X, p.Z))
		end
		local position = Vector3.new(x, math.max(1200, highest + SPAWN_CLEARANCE), z)
		local part = Instance.new("Part")
		part.Name = name
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Transparency = 1
		part.Size = Vector3.new(8, 8, 8)
		part.CFrame = CFrame.lookAt(position, position + facing)
		part:SetAttribute("Type", "Air")
		part:SetAttribute("Team", team)
		part:SetAttribute("Altitude", position.Y)
		CollectionService:AddTag(part, "SpawnPoint")
		part.Parent = folder
	end
	for i = 0, 5 do
		local z = -15000 + i * 3600
		local west, east = StraitBuilder.coastX(z)
		add(`West{i + 1}`, "West", math.max(west - 2500, -17500), z)
		add(`East{i + 1}`, "East", math.min(east + 2500, 17500), z + 1800)
	end
	folder.Parent = map
	return "spawns done (12)"
end

return StraitBuilder
