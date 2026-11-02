--!strict
--!native
-- Writes a height-field map into terrain voxels (MAP-05): the machinery of StraitBuilder, shared so every
-- map's builder only has to say how high the ground is and what it's made of. A map gives:
--   height(x, z) -> studs            the surface (already eased into the world outside at the edges)
--   material(x, z, h, slope) -> Enum.Material
--   water: number?                   the sea surface (nil: no water)
-- Heights are rounded to whole studs and each column uses one material (it compresses far better), and only
-- a thin shell under the surface is filled, so what a client streams stays small (see StraitBuilder).
--   local Kit = require(game.ServerStorage.Tools.TerrainKit)
--   Kit.build(map, part, parts)   -- one west-to-east strip of the map per part; yields as it goes

local Terrain = workspace.Terrain

local TerrainKit = {}

TerrainKit.CHUNK = 128 -- studs per WriteVoxels call
TerrainKit.GRID = 8 -- the height field is sampled every 8 studs and interpolated per 4-stud column
TerrainKit.SHELL = 4 -- studs of solid terrain under the surface, at least

export type Map = {
	height: (x: number, z: number) -> number,
	material: (x: number, z: number, h: number, slope: number) -> Enum.Material,
	water: number?,
	half: number, -- the terrain runs from -half to +half on both axes
}

-- Writes one CHUNK × CHUNK area whose corner is (x0, z0).
local function writeChunk(map: Map, x0: number, z0: number)
	local CHUNK, GRID = TerrainKit.CHUNK, TerrainKit.GRID
	local columns = CHUNK // 4
	local samples = CHUNK // GRID + 3
	local grid = table.create(samples)
	for i = 1, samples do
		local row = table.create(samples)
		local gx = x0 + (i - 2) * GRID
		for k = 1, samples do
			row[k] = map.height(gx, z0 + (k - 2) * GRID)
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

	local heights = table.create(columns + 2)
	for i = 0, columns + 1 do
		local row = table.create(columns + 2)
		for k = 0, columns + 1 do
			row[k + 1] = math.round(at(x0 + (i - 1) * 4 + 2, z0 + (k - 1) * 4 + 2))
		end
		heights[i + 1] = row
	end

	local water = map.water
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
			local bottom = h - math.max(TerrainKit.SHELL, drop + 4)
			bRow[k] = bottom
			sRow[k] = math.sqrt((n2 - n1) ^ 2 + (n4 - n3) ^ 2) / 8
			low = math.min(low, bottom)
			high = math.max(high, h, water or -math.huge)
		end
		bottoms[i], slopes[i] = bRow, sRow
	end

	local y0 = math.floor(low / 4) * 4
	local y1 = math.ceil(high / 4) * 4 + 4
	local layers = (y1 - y0) // 4
	local materials = table.create(columns)
	local occupancy = table.create(columns)
	local air, waterMaterial = Enum.Material.Air, Enum.Material.Water
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
			local surface = map.material(px, z0 + (k - 1) * 4 + 2, h, slopes[i][k])
			for j = 1, layers do
				local yb = y0 + (j - 1) * 4
				local solid = math.clamp((h - yb) / 4, 0, 1)
				if yb + 4 > bottom and solid > 0 then
					mx[j][k] = surface
					ox[j][k] = solid
				end
				if water and solid < 0.5 and yb < water then
					mx[j][k] = waterMaterial
					ox[j][k] = math.clamp((water - yb) / 4, 0, 1)
				end
			end
		end
		materials[i], occupancy[i] = mx, ox
	end
	local region = Region3.new(Vector3.new(x0, y0, z0), Vector3.new(x0 + CHUNK, y1, z0 + CHUNK))
	Terrain:WriteVoxels(region, 4, materials, occupancy)
end

-- Builds the terrain, one west-to-east strip of the map per part: build(map, 1, 8) ... build(map, 8, 8).
function TerrainKit.build(map: Map, part: number?, parts: number?): string
	local CHUNK = TerrainKit.CHUNK
	local count = parts or 1
	local index = part or 1
	local strips = (2 * map.half) // CHUNK
	local first = (index - 1) * strips // count
	local last = index * strips // count - 1
	local started = os.clock()
	local budget = os.clock()
	for sx = first, last do
		for sz = 0, strips - 1 do
			local x0, z0 = -map.half + sx * CHUNK, -map.half + sz * CHUNK
			-- Clear first: writeChunk only writes from the new shell's bottom up
			Terrain:FillRegion(
				Region3.new(Vector3.new(x0, -64, z0), Vector3.new(x0 + CHUNK, 704, z0 + CHUNK)),
				4,
				Enum.Material.Air
			)
			writeChunk(map, x0, z0)
			if os.clock() - budget > 0.05 then
				task.wait()
				budget = os.clock()
			end
		end
	end
	return string.format("terrain %d/%d done in %.0f s", index, count, os.clock() - started)
end

return TerrainKit
