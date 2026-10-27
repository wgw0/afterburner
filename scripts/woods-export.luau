--!strict
-- Woods merge, step 1 (MAP-03): reads every tree in the place file's woods and writes their placements
-- for tools/blender/woods_merge.py. One tree per line: kind (C conifer, B broadleaf, P poplar), ground
-- x y z (studs), yaw (degrees), scale (x100), foliage colour as hex.
-- Usage: lune run scripts/woods-export.luau [place.rbxl] [out.txt]
--   (defaults: Afterburner.rbxl, tools/blender/out/trees.txt)

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local Vector3 = roblox.Vector3

local placePath = process.args[1] or "Afterburner.rbxl"
local outPath = process.args[2] or "tools/blender/out/trees.txt"
local game = roblox.deserializePlace(fs.readFile(placePath))

local KIND_CODE = { TreeConifer = "C", TreeBroadleaf = "B", TreePoplar = "P" }

local templates = game:GetService("ServerStorage"):FindFirstChild("SceneryTemplates")
assert(templates, "No ServerStorage.SceneryTemplates in the place")
-- Lune can't read MeshId, so a tree's kind comes from its foliage's shape (height over width): poplars
-- are tall and thin, conifers about two to one, broadleaves about square.
local foliageShape: { [string]: number } = {}
local trunkHeight: { [string]: number } = {}
for kind in KIND_CODE do
	local t = (templates :: any)[kind]
	foliageShape[kind] = t.Foliage.Size.Y / math.max(t.Foliage.Size.X, t.Foliage.Size.Z)
	trunkHeight[kind] = t.Trunk.Size.Y
end
local function kindOf(foliage: any): string
	local shape = foliage.Size.Y / math.max(foliage.Size.X, foliage.Size.Z)
	local best, bestDiff = "TreeBroadleaf", math.huge
	for kind, ref in foliageShape do
		if math.abs(math.log(shape / ref)) < bestDiff then
			best, bestDiff = kind, math.abs(math.log(shape / ref))
		end
	end
	return best
end

local scenery = (game:GetService("Workspace") :: any).Map.Scenery
local lines = {}
local counts = { C = 0, B = 0, P = 0 }
local missed = 0
for _, model in scenery:GetChildren() do
	if not string.match(model.Name, "^Woods%d+$") then
		continue
	end
	-- A tree's foliage sits straight above its trunk: pair them by position
	local foliageAt: { [string]: any } = {}
	local function key(x: number, z: number): string
		return `{math.round(x * 2)},{math.round(z * 2)}`
	end
	for _, part in model:GetChildren() do
		if part.Name == "Foliage" then
			foliageAt[key(part.CFrame.Position.X, part.CFrame.Position.Z)] = part
		end
	end
	for _, trunk in model:GetChildren() do
		if trunk.Name ~= "Trunk" then
			continue
		end
		local foliage = foliageAt[key(trunk.CFrame.Position.X, trunk.CFrame.Position.Z)]
		if not foliage then
			-- rounding put it in a neighbouring cell
			for dx = -1, 1 do
				for dz = -1, 1 do
					foliage = foliage or foliageAt[key(trunk.CFrame.Position.X + dx * 0.5, trunk.CFrame.Position.Z + dz * 0.5)]
				end
			end
		end
		if not foliage then
			missed += 1
			continue
		end
		local kind = kindOf(foliage)
		local scale = trunk.Size.Y / trunkHeight[kind]
		local ground = trunk.CFrame * Vector3.new(0, -trunk.Size.Y / 2, 0)
		local _, yaw = trunk.CFrame:ToEulerAnglesYXZ()
		local c = foliage.Color
		local code = KIND_CODE[kind]
		counts[code] += 1
		table.insert(
			lines,
			string.format(
				"%s %.1f %.1f %.1f %d %d %02x%02x%02x",
				code,
				ground.X,
				ground.Y,
				ground.Z,
				math.round(math.deg(yaw)),
				math.round(scale * 100),
				math.round(c.R * 255),
				math.round(c.G * 255),
				math.round(c.B * 255)
			)
		)
	end
end

fs.writeFile(outPath, table.concat(lines, "\n") .. "\n")
print(`{#lines} trees, {missed} trunks without foliage ({counts.C} conifer, {counts.B} broadleaf, {counts.P} poplar) -> {outPath}`)
