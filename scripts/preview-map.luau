--!strict
-- Draws a map's shape (tools/<Map>Shape.luau) as a shaded relief image, outside Studio, so a map can be
-- tuned before it's written into terrain. Writes a PPM (convert it with any image tool).
--   lune run scripts/preview-map.luau tools/DesertShape.luau <out.ppm> [size]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

-- The shapes are written for Roblox: give them Vector3 and a seeded Random
local env = getfenv()
env.Vector3 = roblox.Vector3
local Random = {}
Random.__index = Random
function Random.new(seed: number)
	return setmetatable({ state = (seed or 1) % 2147483647 }, Random)
end
function Random:NextNumber(a: number?, b: number?): number
	self.state = (self.state * 48271) % 2147483647
	local u = self.state / 2147483647
	if a and b then
		return a + (b - a) * u
	end
	return u
end
env.Random = Random

local path, out, size = process.args[1], process.args[2], tonumber(process.args[3]) or 384
assert(path and out, "usage: lune run scripts/preview-map.luau tools/DesertShape.luau out.ppm [size]")
local chunk = assert(loadstring(fs.readFile(path), "@" .. path))
setfenv(chunk, env)
local Shape = chunk()

local COLOURS = {
	Sand = { 226, 184, 124 },
	Sandstone = { 196, 116, 72 },
	Ground = { 186, 142, 98 },
	Rock = { 138, 92, 70 },
	Salt = { 238, 232, 220 },
	Asphalt = { 60, 60, 64 },
	Concrete = { 170, 170, 168 },
	Grass = { 96, 150, 60 },
	Snow = { 245, 245, 250 },
}

local half = Shape.HALF
local step = 2 * half / size
local heights = table.create(size)
for j = 1, size do
	local row = table.create(size)
	for i = 1, size do
		row[i] = Shape.height(-half + (i - 0.5) * step, -half + (j - 0.5) * step)
	end
	heights[j] = row
end

local bytes = table.create(size * size * 3)
local lo, hi = math.huge, -math.huge
for j = 1, size do
	for i = 1, size do
		lo, hi = math.min(lo, heights[j][i]), math.max(hi, heights[j][i])
		local x, z = -half + (i - 0.5) * step, -half + (j - 0.5) * step
		local hx = heights[j][math.min(i + 1, size)] - heights[j][math.max(i - 1, 1)]
		local hz = heights[math.min(j + 1, size)][i] - heights[math.max(j - 1, 1)][i]
		local slope = math.sqrt(hx * hx + hz * hz) / (2 * step)
		local colour = COLOURS[Shape.material(x, z, heights[j][i], slope)] or { 255, 0, 255 }
		-- Light from the north-west
		local shade = math.clamp(1 + (-hx + -hz) / (2 * step) * 1.2, 0.45, 1.35)
		for c = 1, 3 do
			table.insert(bytes, string.char(math.clamp(math.floor(colour[c] * shade), 0, 255)))
		end
	end
end
fs.writeFile(out, `P6\n{size} {size}\n255\n` .. table.concat(bytes))
print(string.format("%s: %dx%d, heights %.0f to %.0f studs", out, size, size, lo, hi))
