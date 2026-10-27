--!strict
-- What lies beyond the Strait's terrain (MAP-03). The terrain stops at ±TERRAIN_HALF; past that the world
-- carries on as a flat plain of cheap client-side tiles (WorldEdgeController): low grass where the two
-- coasts run on, sea everywhere else. The last EDGE_FADE studs of terrain ease down to the same profile
-- (tools/StraitBuilder), so there's no seam. Shared so the terrain tool and the client agree.

local WorldEdge = {}

WorldEdge.TERRAIN_HALF = 20480 -- terrain edge (the play area ends at Scale.MAP_HALF_EXTENT)
WorldEdge.EDGE_FADE = 2500 -- studs over which the terrain eases into the plain
WorldEdge.WATER = -6 -- sea surface
WorldEdge.PLAIN_HEIGHT = 24 -- the outside land
WorldEdge.SEA_FLOOR = -22

local function smoothstep(a: number, b: number, x: number): number
	local t = math.clamp((x - a) / (b - a), 0, 1)
	return t * t * (3 - 2 * t)
end

-- x of the west and east coastlines at z. South of z = 9000 both coasts curve away into open sea.
function WorldEdge.coastX(z: number): (number, number)
	local recede = math.max(z - 9000, 0) ^ 2 / 10000
	local west = -8200 + 900 * math.sin(z / 2600) + 450 * math.sin(z / 900 + 1.3) - recede
	local east = 8200 + 900 * math.sin(z / 2900 + 2) + 450 * math.sin(z / 1000 + 0.4) + recede
	return west, east
end

-- The coasts outside the terrain run straight on from where they leave it.
function WorldEdge.outsideCoastX(z: number): (number, number)
	return WorldEdge.coastX(math.clamp(z, -WorldEdge.TERRAIN_HALF, WorldEdge.TERRAIN_HALF))
end

-- Height of the outside world at (x, z): the plain on land, the sea floor offshore, a short beach between.
function WorldEdge.outsideHeight(x: number, z: number): number
	local west, east = WorldEdge.outsideCoastX(z)
	local inland = math.max(west - x, x - east)
	return WorldEdge.SEA_FLOOR + (WorldEdge.PLAIN_HEIGHT - WorldEdge.SEA_FLOOR) * smoothstep(-150, 250, inland)
end

-- 0 well inside the terrain, 1 at its edge: how far a terrain height should be pulled to outsideHeight.
function WorldEdge.fade(x: number, z: number): number
	local toEdge = WorldEdge.TERRAIN_HALF - math.max(math.abs(x), math.abs(z))
	return smoothstep(WorldEdge.EDGE_FADE, 0, toEdge)
end

return table.freeze(WorldEdge)
