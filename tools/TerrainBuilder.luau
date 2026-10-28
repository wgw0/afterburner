--!strict
-- Quick placeholder terrain for flight testing (the real "Strait" map is MAP-02/03).
-- Grass plain with rolling hills, a rocky mountain range to the west, a beach and sea to the east.
-- Deterministic (fixed seed), built in chunks so Studio stays responsive. Run each step in Edit mode:
--   local T = require(game.ServerStorage.Tools.TerrainBuilder)
--   T.ground() T.sea() T.hills() T.mountains() T.trim()
-- Undo with workspace.Terrain:Clear().

local Terrain = workspace.Terrain

local HALF = 3440 -- studs from the origin to the terrain edge
local CHUNK = 2048
local GROUND_TOP = -0.6 -- just under the baseplate and runway
local SHORE_X = 1680 -- sea starts east of here
local SEED = 1985
-- Nothing is kept below this on land. Hills and mountains are balls that reach a hundred studs or more
-- underground; that hidden volume is most of the terrain data a client must download (see trim()).
local BURY_DEPTH = -3.9
local SEABED = -7.3

local TerrainBuilder = {}

local function slab(material: Enum.Material, x0: number, x1: number, z0: number, z1: number, y0: number, y1: number)
	for x = x0, x1 - 1, CHUNK do
		for z = z0, z1 - 1, CHUNK do
			local sx = math.min(CHUNK, x1 - x)
			local sz = math.min(CHUNK, z1 - z)
			local centre = Vector3.new(x + sx / 2, (y0 + y1) / 2, z + sz / 2)
			Terrain:FillBlock(CFrame.new(centre), Vector3.new(sx, y1 - y0, sz), material)
			task.wait()
		end
	end
end

function TerrainBuilder.ground(): string
	slab(Enum.Material.Grass, -HALF, SHORE_X - 140, -HALF, HALF, BURY_DEPTH, GROUND_TOP)
	slab(Enum.Material.Sand, SHORE_X - 140, SHORE_X + 84, -HALF, HALF, BURY_DEPTH, GROUND_TOP - 0.28)
	return "ground done"
end

function TerrainBuilder.sea(): string
	-- Shallow on purpose: only the top of the water is ever seen, and depth costs download size.
	slab(Enum.Material.Sand, SHORE_X + 84, HALF, -HALF, HALF, SEABED - 2.2, SEABED)
	slab(Enum.Material.Water, SHORE_X + 84, HALF, -HALF, HALF, SEABED, GROUND_TOP - 1.1)
	return "sea done"
end

local function landPoint(rng: Random, keepClear: number): Vector3
	while true do
		local p = Vector3.new(rng:NextNumber(-HALF + 168, SHORE_X - 252), 0, rng:NextNumber(-HALF + 168, HALF - 168))
		if p.Magnitude > keepClear then
			return p
		end
	end
end

function TerrainBuilder.hills(): string
	local rng = Random.new(SEED)
	local count = 0
	for _ = 1, 180 do
		local p = landPoint(rng, 504) -- keep the test range and runway flat
		local r = rng:NextNumber(42, 146)
		Terrain:FillBall(Vector3.new(p.X, GROUND_TOP - r * 0.62, p.Z), r, Enum.Material.Grass)
		count += 1
		if count % 4 == 0 then
			task.wait()
		end
	end
	-- A few darker woodland patches for visual reference
	for _ = 1, 60 do
		local p = landPoint(rng, 504)
		local r = rng:NextNumber(34, 90)
		Terrain:FillBall(Vector3.new(p.X, GROUND_TOP - r * 0.8, p.Z), r, Enum.Material.LeafyGrass)
		if count % 4 == 0 then
			task.wait()
		end
		count += 1
	end
	return `hills done ({count})`
end

function TerrainBuilder.mountains(): string
	local rng = Random.new(SEED + 1)
	local count = 0
	-- A ridge running north-south about 6 km (2,200 studs) west of the origin, wiggling as it goes.
	for i = 0, 44 do
		local z = -HALF + 252 + i * ((2 * HALF - 504) / 44)
		local x = -2184 + math.sin(i * 0.45) * 252 + rng:NextNumber(-98, 98)
		local r = rng:NextNumber(106, 174)
		local lift = rng:NextNumber(0.05, 0.35)
		local centre = Vector3.new(x, GROUND_TOP + r * lift, z)
		Terrain:FillBall(centre, r, Enum.Material.Rock)
		-- Foothills either side
		Terrain:FillBall(centre + Vector3.new(rng:NextNumber(-196, -112), -r * 0.55, 0), r * 0.7, Enum.Material.Ground)
		Terrain:FillBall(centre + Vector3.new(rng:NextNumber(112, 196), -r * 0.55, 0), r * 0.7, Enum.Material.Ground)
		-- Snow on the taller peaks
		if lift > 0.22 then
			Terrain:FillBall(centre + Vector3.new(0, r * 0.62, 0), r * 0.42, Enum.Material.Snow)
		end
		count += 1
		task.wait()
	end
	return `mountains done ({count} peaks)`
end

-- Clears every voxel players can never see: below BURY_DEPTH on land, and below the seabed at sea.
-- Cuts the data a client has to download on join without changing what's visible.
-- Hills and mountains reach no deeper than about -252, so -280 is deep enough.
-- Optionally pass (part, parts) to clear one west-to-east strip at a time, e.g. trim(1, 4) ... trim(4, 4).
function TerrainBuilder.trim(part: number?, parts: number?): string
	local count = parts or 1
	local index = part or 1
	local width = (2 * HALF) / count
	local x0 = -HALF + (index - 1) * width
	local x1 = x0 + width
	local before = Terrain:CountCells()
	local landEnd = math.clamp(SHORE_X + 84, x0, x1)
	if landEnd > x0 then
		slab(Enum.Material.Air, x0, landEnd, -HALF, HALF, -280, BURY_DEPTH)
	end
	if x1 > landEnd then
		slab(Enum.Material.Air, landEnd, x1, -HALF, HALF, -280, SEABED - 2.2)
	end
	local after = Terrain:CountCells()
	return `trim {index}/{count}: {before} -> {after} cells`
end

return TerrainBuilder
