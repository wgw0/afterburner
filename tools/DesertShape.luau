--!strict
-- "Desert Range" (MAP-05): the shape of the second map, as pure maths so it can be previewed outside Studio
-- (scripts/preview-map.luau) as well as built (tools/DesertBuilder). Heights in studs (1 stud = 1 m), the
-- same ±5,760-stud square as the Strait, airbases where the Strait's are so every mode works the same.
--   * The desert floor: low and gently rolling, ground and drifts of sand.
--   * A dune sea in the south: long sand ridges across the wind.
--   * A raised tableland across the north-east, cut through by a deep winding canyon you can fly along; the
--     canyon opens out onto the floor at the tableland's west end, near the west airbase.
--   * Mesas and buttes scattered over the floor: flat tops and banded, terraced cliffs (terrain masking).
--   * A dry lake bed of white salt in the west.
--   * A ridge of bare mountains along the north and east edges.

local DesertShape = {}

DesertShape.SEED = 1991
DesertShape.HALF = 5760
DesertShape.FLOOR = 24 -- the desert floor's height
DesertShape.BASE_HEIGHT = 26 -- airbase ground level
DesertShape.LAKE_HEIGHT = 18
DesertShape.PLATEAU_HEIGHT = 170
DesertShape.CANYON_FLOOR = 34
DesertShape.STRATA = 18 -- studs per rock band in the cliffs

DesertShape.AIRBASES = {
	West = { position = Vector3.new(-3220, 0, -2520) },
	East = { position = Vector3.new(3360, 0, 2380) },
}

local SEED = DesertShape.SEED

local function smoothstep(a: number, b: number, x: number): number
	local t = math.clamp((x - a) / (b - a), 0, 1)
	return t * t * (3 - 2 * t)
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

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

-- Terraced cliffs: heights snap towards the bands, so a slope reads as stacked ledges
local function terrace(h: number, step: number, sharpness: number): number
	local band = math.floor(h / step)
	local f = h / step - band
	local eased = f ^ sharpness
	return (band + eased) * step
end

-- The canyon's centre line: z at a given x, winding west to east across the tableland
function DesertShape.canyonZ(x: number): number
	return -2700 + 520 * math.sin(x / 1150) + 260 * math.sin(x / 430 + 1.7)
end

-- The tableland: 1 across the north-east, falling away south of z ≈ -1500 and west of x ≈ -1700 along
-- ragged edges (the west airbase stays on the open floor)
local function plateauMask(x: number, z: number): number
	local south = -1450 + 380 * fbm(x, 0, 1600, 3, SEED + 1)
	local west = -1700 + 520 * fbm(x * 0.3, z, 800, 4, SEED + 16)
	return smoothstep(south + 160, south - 160, z) * smoothstep(west - 160, west + 160, x)
end

-- Mesas and buttes on the open floor: { x, z, radius, height }
local MESAS = {}
do
	local rng = Random.new(SEED + 3)
	local tries = 0
	while #MESAS < 22 and tries < 500 do
		tries += 1
		local x, z = rng:NextNumber(-5000, 5000), rng:NextNumber(-1200, 4700)
		local r = rng:NextNumber(110, 460)
		local clear = true
		for _, base in DesertShape.AIRBASES do
			if math.abs(x - base.position.X) < 900 + r and math.abs(z - base.position.Z) < 1500 + r then
				clear = false
			end
		end
		if ((x + 1500) / 1300) ^ 2 + ((z - 1300) / 850) ^ 2 < 1.5 then
			clear = false -- the dry lake
		end
		for _, m in MESAS do
			if math.sqrt((x - m[1]) ^ 2 + (z - m[2]) ^ 2) < r + m[3] + 260 then
				clear = false
			end
		end
		if clear then
			table.insert(MESAS, { x, z, r, rng:NextNumber(70, 210) })
		end
	end
end
DesertShape.MESAS = MESAS

-- 0 outside an airbase, 1 on it (with a 224-stud blend), and the runway or apron material on it
function DesertShape.airbaseAt(x: number, z: number): (number, string?)
	for name, base in DesertShape.AIRBASES do
		local dx, dz = x - base.position.X, z - base.position.Z
		local outside = math.max(math.abs(dx) - 392, math.abs(dz) - 1064, 0)
		if outside < 224 then
			local material: string? = nil
			local side = if name == "West" then 1 else -1
			local runway = math.abs(dx) < 25.2 and math.abs(dz) < 840
			local taxiway = dx * side >= 0 and dx * side <= 70 and math.abs(dz) < 11.2
			if runway or taxiway then
				material = "Asphalt"
			elseif dx * side > 70 and dx * side < 294 and math.abs(dz) < 196 then
				material = "Concrete"
			end
			return 1 - smoothstep(0, 224, outside), material
		end
	end
	return 0, nil
end

-- How far into the dry lake (1 on its flat bed)
local function lakeAt(x: number, z: number): number
	local d = math.sqrt(((x + 1500) / 1150) ^ 2 + ((z - 1300) / 720) ^ 2) + 0.08 * fbm(x, z, 300, 2, SEED + 9)
	return smoothstep(1.0, 0.82, d)
end

-- Surface height (studs), before any easing into the world outside the terrain.
function DesertShape.height(x: number, z: number): number
	-- The floor: low rolls and a little grain
	local h = DesertShape.FLOOR + 9 * fbm(x, z, 900, 3, SEED + 2) + 2.5 * fbm(x, z, 120, 2, SEED + 4)

	-- The dune sea in the south: long ridges running east-west, broken up
	local dunes = smoothstep(1200, 2600, z + 400 * fbm(x, z, 2400, 2, SEED + 5))
	local ridge = ridged(x * 0.45 + 120 * fbm(x, z, 700, 2, SEED + 6), z * 1.4, 520, 3, SEED + 7)
	h += dunes * (8 + 46 * ridge ^ 1.6)

	-- Mesas and buttes: flat tops, terraced sides
	for _, m in MESAS do
		local d = 0
		-- Ragged, a little stretched (some are long ridges, some round buttes)
		local angle = m[1] * 0.37 + m[2] * 0.11
		local ax = (x - m[1]) * math.cos(angle) + (z - m[2]) * math.sin(angle)
		local az = -(x - m[1]) * math.sin(angle) + (z - m[2]) * math.cos(angle)
		local stretch = 1 + 0.9 * (math.sin(m[1] * 0.013) * 0.5 + 0.5)
		d = math.sqrt((ax / stretch) ^ 2 + az ^ 2)
		local edge = m[3] * (1 + 0.32 * fbm(x, z, 160, 3, SEED + 10))
		if d < edge + 120 then
			local s = smoothstep(edge + 90, edge - 10, d)
			local top = DesertShape.FLOOR + m[4] + 4 * fbm(x, z, 90, 2, SEED + 11)
			h = math.max(h, terrace(lerp(h, top, s), DesertShape.STRATA, 3))
		end
	end

	-- The tableland, with its ragged rim terraced into cliffs
	local plateau = plateauMask(x, z)
	if plateau > 0 then
		local top = DesertShape.PLATEAU_HEIGHT + 22 * fbm(x, z, 700, 3, SEED + 12)
		local raised = terrace(lerp(h, top, plateau), DesertShape.STRATA, 2.5)
		-- The canyon: a winding gorge with a flat floor and stepped walls
		local dz = math.abs(z - DesertShape.canyonZ(x)) + 40 * fbm(x, z, 260, 2, SEED + 13)
		local gorge = smoothstep(260, 110, dz)
		local floor = DesertShape.CANYON_FLOOR + 6 * fbm(x, z, 300, 2, SEED + 14)
		raised = lerp(raised, floor, gorge)
		if gorge > 0.02 and gorge < 0.98 then
			raised = terrace(raised, DesertShape.STRATA, 3)
		end
		h = math.max(h, lerp(h, raised, plateau))
	end

	-- Mountains along the north and east edges
	local north = smoothstep(-4300, -5300, z)
	local east = smoothstep(4300, 5300, x)
	local mountains = math.max(north, east)
	if mountains > 0 then
		local crest = ridged(x, z, 640, 5, SEED + 15)
		h = math.max(h, h + mountains * (60 + 360 * crest))
	end

	-- The dry lake: flat salt
	local lake = lakeAt(x, z)
	if lake > 0 then
		h = lerp(h, DesertShape.LAKE_HEIGHT, lake)
	end

	-- Airbases are flattened
	local base = DesertShape.airbaseAt(x, z)
	if base > 0 then
		h = lerp(h, DesertShape.BASE_HEIGHT, base)
	end
	return h
end

-- What the surface is made of (a material name), from its height and slope (rise per stud).
function DesertShape.material(x: number, z: number, h: number, slope: number): string
	local _, base = DesertShape.airbaseAt(x, z)
	if base then
		return base
	end
	if lakeAt(x, z) > 0.6 then
		return "Salt"
	end
	if slope > 0.55 then
		-- Banded cliffs: alternating rock layers
		return if math.floor(h / DesertShape.STRATA) % 2 == 0 then "Sandstone" else "Rock"
	end
	if h > 300 then
		return "Rock"
	end
	if h > DesertShape.PLATEAU_HEIGHT - 30 or h > DesertShape.FLOOR + 60 then
		return "Sandstone" -- mesa and tableland tops (above the dunes)
	end
	local dunes = smoothstep(1200, 2600, z + 400 * fbm(x, z, 2400, 2, SEED + 5))
	if dunes > 0.5 then
		return "Sand"
	end
	return if math.noise(x / 340, z / 340, SEED + 20) > 0.2 then "Sand" else "Ground"
end

return DesertShape
