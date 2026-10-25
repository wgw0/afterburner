--!strict
-- Quick placeholder terrain for flight testing (the real "Strait" map is MAP-02/03).
-- Grass plain with rolling hills, a rocky mountain range to the west, a beach and sea to the east.
-- Deterministic (fixed seed), built in chunks so Studio stays responsive. Run each step in Edit mode:
--   local T = require(game.ServerStorage.Tools.TerrainBuilder)
--   T.ground() T.sea() T.hills() T.mountains()
-- Undo with workspace.Terrain:Clear().

local Terrain = workspace.Terrain

local HALF = 12288 -- studs from the origin to the terrain edge
local CHUNK = 2048
local GROUND_TOP = -2 -- just under the baseplate and runway
local SHORE_X = 6000 -- sea starts east of here
local SEED = 1985

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
	slab(Enum.Material.Grass, -HALF, SHORE_X - 500, -HALF, HALF, GROUND_TOP - 24, GROUND_TOP)
	slab(Enum.Material.Sand, SHORE_X - 500, SHORE_X + 300, -HALF, HALF, GROUND_TOP - 24, GROUND_TOP - 1)
	return "ground done"
end

function TerrainBuilder.sea(): string
	slab(Enum.Material.Sand, SHORE_X + 300, HALF, -HALF, HALF, -90, -60)
	slab(Enum.Material.Water, SHORE_X + 300, HALF, -HALF, HALF, -60, GROUND_TOP - 4)
	return "sea done"
end

local function landPoint(rng: Random, keepClear: number): Vector3
	while true do
		local p = Vector3.new(rng:NextNumber(-HALF + 600, SHORE_X - 900), 0, rng:NextNumber(-HALF + 600, HALF - 600))
		if p.Magnitude > keepClear then
			return p
		end
	end
end

function TerrainBuilder.hills(): string
	local rng = Random.new(SEED)
	local count = 0
	for _ = 1, 180 do
		local p = landPoint(rng, 1800) -- keep the test range and runway flat
		local r = rng:NextNumber(150, 520)
		Terrain:FillBall(Vector3.new(p.X, GROUND_TOP - r * 0.62, p.Z), r, Enum.Material.Grass)
		count += 1
		if count % 4 == 0 then
			task.wait()
		end
	end
	-- A few darker woodland patches for visual reference
	for _ = 1, 60 do
		local p = landPoint(rng, 1800)
		local r = rng:NextNumber(120, 320)
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
	-- A ridge running north-south about 6 km (8,000 studs) west of the origin, wiggling as it goes.
	for i = 0, 44 do
		local z = -HALF + 900 + i * ((2 * HALF - 1800) / 44)
		local x = -7800 + math.sin(i * 0.45) * 900 + rng:NextNumber(-350, 350)
		local r = rng:NextNumber(380, 620)
		local lift = rng:NextNumber(0.05, 0.35)
		local centre = Vector3.new(x, GROUND_TOP + r * lift, z)
		Terrain:FillBall(centre, r, Enum.Material.Rock)
		-- Foothills either side
		Terrain:FillBall(centre + Vector3.new(rng:NextNumber(-700, -400), -r * 0.55, 0), r * 0.7, Enum.Material.Ground)
		Terrain:FillBall(centre + Vector3.new(rng:NextNumber(400, 700), -r * 0.55, 0), r * 0.7, Enum.Material.Ground)
		-- Snow on the taller peaks
		if lift > 0.22 then
			Terrain:FillBall(centre + Vector3.new(0, r * 0.62, 0), r * 0.42, Enum.Material.Snow)
		end
		count += 1
		task.wait()
	end
	return `mountains done ({count} peaks)`
end

return TerrainBuilder
