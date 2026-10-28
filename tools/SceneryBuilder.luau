--!strict
-- Scenery for the Strait map (MAP-03): towns, farms, the roads that join them, woods, and the airbase
-- buildings. Props come from the Blender scenery kit (tools/blender/scenery_generate.py), imported into
-- Studio as one Model; pieces are named "<Prop>__<Piece>" and coloured here, so the kit needs no textures.
-- Deterministic (fixed seeds). Run in Edit mode after StraitBuilder, one step at a time:
--   local S = require(game.ServerStorage.Tools.SceneryBuilder)
--   S.templates(workspace.Scenery_kit)  -- once per kit import: builds ServerStorage.SceneryTemplates
--   S.clear() S.roads() S.towns() S.woods() S.airbases()
-- The woods are then merged into a few dozen meshes (15,000 trees as 30,000 parts loaded and drew slowly):
--   S.exportTrees(i) for i = 1, n until it returns "" -> tools/blender/out/trees.txt (concatenated)
--   tools/blender/woods_merge.py bakes Woods_merged.fbx; import it, upload Woods_Palette.png, then
--   S.installMergedWoods(workspace.Woods_merged, paletteAssetId) replaces the tree parts.
-- Everything goes in workspace.Map.Scenery, except the airbase buildings, which replace the contents of
-- Map.AirbaseWest / Map.AirbaseEast. Towns, woods and airbases are Models with
-- LevelOfDetail = StreamingMesh, so they still show from the air before they have streamed in.

local ServerStorage = game:GetService("ServerStorage")

local Strait = require(script.Parent.StraitBuilder)

local SEED = 4242
local WATER = -1.68 -- sea surface (WorldEdge.WATER)
local ROAD_TEXTURE = "rbxassetid://88361153151301" -- tools/blender/out/textures/Road_Color.png
local ROAD_WIDTH = 7.3 -- studs (7.3 m, two lanes)
local ROAD_STEP = 9 -- studs between road segment joints
local GRID = 56 -- road routing grid (studs)
local MERGE_SIDE = 0.42 -- studs a merged road part may stray sideways from the road's true line
local MERGE_UP = 0.6 -- ...and up or down
local MERGE_MAX = 2000 -- studs: the longest road part (parts top out at 2,048)

local mergeRun: (Instance, { Vector3 }) -> ()

local SceneryBuilder = {}

local function height(x: number, z: number): number
	return Strait.height(x, z)
end

-- The voxel terrain's actual surface, which can sit a stud or two off the height field it was built from
local terrainOnly = RaycastParams.new()
terrainOnly.FilterType = Enum.RaycastFilterType.Include
terrainOnly.FilterDescendantsInstances = { workspace.Terrain }
terrainOnly.IgnoreWater = true

local function surface(x: number, z: number): number
	local hit = workspace:Raycast(Vector3.new(x, 560, z), Vector3.new(0, -730, 0), terrainOnly)
	return if hit then hit.Position.Y else height(x, z)
end

local function slope(x: number, z: number): number
	local d = 5.6
	local dx = height(x + d, z) - height(x - d, z)
	local dz = height(x, z + d) - height(x, z - d)
	return math.sqrt(dx * dx + dz * dz) / (2 * d)
end

local function nearAirbase(x: number, z: number, margin: number): boolean
	for _, base in Strait.AIRBASES do
		if math.abs(x - base.position.X) < 392 + margin and math.abs(z - base.position.Z) < 1064 + margin then
			return true
		end
	end
	return false
end

local function onIsland(x: number, z: number): boolean
	return x * x + z * z < 1008 * 1008
end

-- Distance in from the terrain's edge: the outer band eases into the flat world outside (WorldEdge)
local function fromEdge(x: number, z: number): number
	return 5760 - math.max(math.abs(x), math.abs(z))
end

local function folder(parent: Instance, name: string, className: string?): Instance
	local existing = parent:FindFirstChild(name)
	if existing then
		return existing
	end
	local f = Instance.new(className or "Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local function lodModel(name: string, parent: Instance): Model
	local m = Instance.new("Model")
	m.Name = name
	m.LevelOfDetail = Enum.ModelLevelOfDetail.StreamingMesh
	m.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	m.Parent = parent
	return m
end

-- Colours ----------------------------------------------------------------------------------------------

local WALLS = {
	Color3.fromRGB(226, 218, 198),
	Color3.fromRGB(238, 234, 226),
	Color3.fromRGB(214, 196, 160),
	Color3.fromRGB(198, 196, 190),
}
local ROOFS = {
	Color3.fromRGB(150, 70, 52),
	Color3.fromRGB(122, 62, 48),
	Color3.fromRGB(84, 86, 92),
	Color3.fromRGB(104, 78, 62),
}
local FOLIAGE =
	{ Color3.fromRGB(58, 92, 40), Color3.fromRGB(70, 104, 46), Color3.fromRGB(48, 80, 42), Color3.fromRGB(84, 110, 52) }
local CONIFER = { Color3.fromRGB(40, 68, 42), Color3.fromRGB(46, 76, 46), Color3.fromRGB(36, 60, 40) }
local AWNINGS = { Color3.fromRGB(160, 40, 36), Color3.fromRGB(40, 90, 60), Color3.fromRGB(40, 70, 130) }

-- Piece look: colour (or a palette picked per instance), material, collides with jets
type Look = { colour: Color3?, palette: { Color3 }?, material: Enum.Material, collide: boolean }

local function look(prop: string, piece: string): Look
	local airbase = prop == "Hangar"
		or prop == "Shelter"
		or prop == "Tower"
		or prop == "OpsBuilding"
		or prop == "FuelTank"
	if piece == "Trunk" then
		return { colour = Color3.fromRGB(88, 64, 44), material = Enum.Material.Wood, collide = false }
	elseif piece == "Foliage" then
		return {
			palette = if prop == "TreeConifer" then CONIFER else FOLIAGE,
			material = Enum.Material.SmoothPlastic,
			collide = false,
		}
	elseif piece == "Windows" then
		return { colour = Color3.fromRGB(38, 46, 56), material = Enum.Material.SmoothPlastic, collide = true }
	elseif piece == "Glass" then
		return { colour = Color3.fromRGB(46, 84, 96), material = Enum.Material.SmoothPlastic, collide = true }
	elseif piece == "Doors" then
		return {
			colour = if airbase then Color3.fromRGB(96, 104, 98) else Color3.fromRGB(90, 76, 62),
			material = Enum.Material.Metal,
			collide = true,
		}
	elseif piece == "Awning" then
		return { palette = AWNINGS, material = Enum.Material.Fabric, collide = true }
	elseif piece == "Shell" then
		return { colour = Color3.fromRGB(150, 148, 140), material = Enum.Material.Concrete, collide = true }
	elseif piece == "Tank" then
		return { colour = Color3.fromRGB(205, 208, 204), material = Enum.Material.Metal, collide = true }
	elseif piece == "Roof" then
		if airbase then
			return { colour = Color3.fromRGB(92, 98, 94), material = Enum.Material.Metal, collide = true }
		end
		return { palette = ROOFS, material = Enum.Material.SmoothPlastic, collide = true }
	end
	if airbase then -- walls
		return { colour = Color3.fromRGB(150, 156, 148), material = Enum.Material.Concrete, collide = true }
	end
	return { palette = WALLS, material = Enum.Material.SmoothPlastic, collide = true }
end

-- Templates ------------------------------------------------------------------------------------------------

-- Builds ServerStorage.SceneryTemplates from the imported kit: one Model per prop, its pivot on the ground
-- at the prop's centre. Props with doors record which way the doors face (FrontYaw, radians), so the
-- importer's axis handling doesn't matter.
function SceneryBuilder.templates(kit: Instance): string
	local out = ServerStorage:FindFirstChild("SceneryTemplates")
	if out then
		out:Destroy()
	end
	out = Instance.new("Folder")
	out.Name = "SceneryTemplates"
	local groups: { [string]: { MeshPart } } = {}
	for _, d in kit:GetDescendants() do
		if d:IsA("MeshPart") then
			local prop = string.match(d.Name, "^(.-)__") or d.Name
			groups[prop] = groups[prop] or {}
			table.insert(groups[prop], d)
		end
	end
	local count = 0
	for prop, parts in groups do
		local model = Instance.new("Model")
		model.Name = prop
		local lo, hi = Vector3.new(math.huge, math.huge, math.huge), -Vector3.new(math.huge, math.huge, math.huge)
		for _, src in parts do
			local piece = string.match(src.Name, "__(.+)$") or "Walls"
			local p = src:Clone()
			p:ClearAllChildren()
			p.Name = piece
			p.Anchored = true
			p.CanTouch = false
			p.TextureID = ""
			local l = look(prop, piece)
			p.Material = l.material
			p.Color = l.colour or (l.palette :: { Color3 })[1]
			p.CanCollide = l.collide
			p.CanQuery = true
			pcall(function()
				p.CollisionFidelity = Enum.CollisionFidelity.Box
				p.RenderFidelity = Enum.RenderFidelity.Automatic
			end)
			p.Parent = model
			local half = p.Size / 2
			lo = lo:Min(p.Position - half)
			hi = hi:Max(p.Position + half)
		end
		local centre = (lo + hi) / 2
		model.WorldPivot = CFrame.new(centre.X, lo.Y, centre.Z)
		local doors = model:FindFirstChild("Doors") :: BasePart?
		if doors then
			local front = (doors.Position - centre) * Vector3.new(1, 0, 1)
			model:SetAttribute("FrontYaw", math.atan2(-front.X, -front.Z))
		end
		model.Parent = out
		count += 1
	end
	out.Parent = ServerStorage
	return `{count} templates`
end

local function template(name: string): Model
	local f = ServerStorage:FindFirstChild("SceneryTemplates")
	local t = f and f:FindFirstChild(name)
	assert(t and t:IsA("Model"), `No scenery template {name}: run templates() first`)
	return t
end

-- Places a prop with its base on the ground at (x, z). yaw is where its front should face (radians,
-- 0 = -Z). scale > 1 makes it bigger. Returns nothing: the parts go straight into parent.
local function place(
	name: string,
	parent: Instance,
	x: number,
	z: number,
	yaw: number,
	rng: Random,
	scale: number?,
	sink: number?
)
	local t = template(name)
	local s = scale or 1
	local ground = math.min(height(x, z), height(x + 2.2, z + 2.2), height(x - 2.2, z - 2.2)) - (sink or 1.5)
	local cf = CFrame.new(x, ground, z) * CFrame.Angles(0, yaw - (t:GetAttribute("FrontYaw") or 0) :: number, 0)
	local pivot = t.WorldPivot
	local picks: { [string]: Color3 } = {}
	for _, src in t:GetChildren() do
		if src:IsA("BasePart") then
			local p = src:Clone()
			local rel = pivot:ToObjectSpace(src.CFrame)
			if s ~= 1 then
				p.Size = src.Size * s
				rel = CFrame.new(rel.Position * s) * rel.Rotation
			end
			p.CFrame = cf * rel
			local l = look(name, src.Name)
			if l.palette then
				local key = if src.Name == "Foliage" then "Foliage" else src.Name
				picks[key] = picks[key] or l.palette[rng:NextInteger(1, #l.palette)]
				p.Color = picks[key]
			end
			p.Parent = parent
		end
	end
end

-- Roads ------------------------------------------------------------------------------------------------------

local roadSegments: { { a: Vector3, b: Vector3 } } = {}
local roadHash: { [number]: { Vector2 } } = {} -- road sample points by 18-stud cell

local function hashKey(x: number, z: number): number
	return math.floor(x / 18) * 100000 + math.floor(z / 18)
end

-- True if (x, z) is within clearance of a road's edge.
local function nearRoad(x: number, z: number, clearance: number): boolean
	local reach = clearance + ROAD_WIDTH / 2 + ROAD_STEP / 2
	local r = math.ceil(reach / 18)
	local cx, cz = math.floor(x / 18), math.floor(z / 18)
	local here = Vector2.new(x, z)
	for i = -r, r do
		for j = -r, r do
			for _, p in roadHash[(cx + i) * 100000 + cz + j] or {} do
				if (p - here).Magnitude < reach then
					return true
				end
			end
		end
	end
	return false
end

local function roadPart(parent: Instance, a: Vector3, b: Vector3)
	local length = (b - a).Magnitude
	if length < 0.28 then
		return
	end
	local p = Instance.new("Part")
	p.Name = "Road"
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	p.Color = Color3.fromRGB(60, 62, 66)
	p.Size = Vector3.new(ROAD_WIDTH, 2, length + 0.84)
	p.CFrame = CFrame.lookAt((a + b) / 2, b)
	local tex = Instance.new("Texture")
	tex.Texture = ROAD_TEXTURE
	tex.Face = Enum.NormalId.Top
	tex.StudsPerTileU = ROAD_WIDTH
	tex.StudsPerTileV = 18
	tex.Parent = p
	p.Parent = parent
end

-- Lays a stretch of road as few parts as it can: each part runs as far as the road stays within
-- MERGE_SIDE of a straight line sideways and MERGE_UP up or down, so the ground never pokes through and
-- the road never floats. (One part per ROAD_STEP was 3,178 parts and as many textures.)
mergeRun = function(parent: Instance, run: { Vector3 })
	local i = 1
	while i < #run do
		local j = i + 1
		while j < #run do
			local a, b = run[i], run[j + 1]
			if (b - a).Magnitude > MERGE_MAX then
				break
			end
			local flat = Vector2.new(b.X - a.X, b.Z - a.Z)
			local fits = true
			for k = i + 1, j do
				local p = run[k]
				local t = math.clamp((Vector2.new(p.X - a.X, p.Z - a.Z)):Dot(flat) / flat:Dot(flat), 0, 1)
				local onLine = a:Lerp(b, t)
				local side = (Vector2.new(p.X, p.Z) - Vector2.new(onLine.X, onLine.Z)).Magnitude
				if side > MERGE_SIDE or math.abs(p.Y - onLine.Y) > MERGE_UP then
					fits = false
					break
				end
			end
			if not fits then
				break
			end
			j += 1
		end
		roadPart(parent, run[i], run[j])
		i = j
	end
end

-- Lays a road along a list of (x, z) points: resampled every ROAD_STEP studs and set on the terrain.
local function layRoad(parent: Instance, points: { Vector2 })
	local samples: { Vector2 } = {}
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		local n = math.max(math.ceil((b - a).Magnitude / ROAD_STEP), 1)
		for k = 0, n - 1 do
			table.insert(samples, a:Lerp(b, k / n))
		end
	end
	table.insert(samples, points[#points])
	local run: { Vector3 } = {} -- an unbroken stretch of road, one point per ROAD_STEP
	local prev: Vector3? = nil
	for _, s in samples do
		if height(s.X, s.Y) < WATER + 0.28 then
			mergeRun(parent, run)
			run = {}
			prev = nil
			continue
		end
		-- highest of the centre and the edges, so a camber in the ground doesn't swallow one side
		local h = surface(s.X, s.Y)
		for _, o in { Vector2.new(2.8, 0), Vector2.new(-2.8, 0), Vector2.new(0, 2.8), Vector2.new(0, -2.8) } do
			h = math.max(h, surface(s.X + o.X, s.Y + o.Y))
		end
		local here = Vector3.new(s.X, h + 1.6, s.Y) -- 2 studs thick: the drawn terrain sits above its collision surface
		table.insert(run, here)
		if prev then
			table.insert(roadSegments, { a = prev, b = here })
			local k = hashKey(here.X, here.Z)
			roadHash[k] = roadHash[k] or {}
			table.insert(roadHash[k], Vector2.new(here.X, here.Z))
		end
		prev = here
	end
	mergeRun(parent, run)
end

-- Chaikin smoothing (corner cutting) keeps the grid's staircase out of the road.
local function smoothPath(points: { Vector2 }, passes: number): { Vector2 }
	for _ = 1, passes do
		local out = { points[1] }
		for i = 1, #points - 1 do
			local a, b = points[i], points[i + 1]
			table.insert(out, a:Lerp(b, 0.25))
			table.insert(out, a:Lerp(b, 0.75))
		end
		table.insert(out, points[#points])
		points = out
	end
	return points
end

-- A* over a coarse grid, avoiding the sea, mountains and steep ground. Heights are cached per cell.
local function route(from: Vector2, to: Vector2, cache: { [number]: number }): { Vector2 }?
	local function key(i: number, j: number): number
		return (i + 1000) * 10000 + (j + 1000) -- offset keeps both halves positive, so a key decodes
	end
	local function h(i: number, j: number): number
		local k = key(i, j)
		local v = cache[k]
		if v == nil then
			v = height(i * GRID, j * GRID)
			cache[k] = v
		end
		return v
	end
	local si, sj = math.round(from.X / GRID), math.round(from.Y / GRID)
	local ti, tj = math.round(to.X / GRID), math.round(to.Y / GRID)
	local open: { { number } } = { { 0, si, sj } }
	local cost: { [number]: number } = { [key(si, sj)] = 0 }
	local came: { [number]: number } = {}
	local function push(item: { number })
		table.insert(open, item)
		local i = #open
		while i > 1 do
			local parent = i // 2
			if open[parent][1] <= open[i][1] then
				break
			end
			open[parent], open[i] = open[i], open[parent]
			i = parent
		end
	end
	local function pop(): { number }
		local top = open[1]
		local last = table.remove(open) :: { number }
		if #open > 0 then
			open[1] = last
			local i = 1
			while true do
				local l, r, m = i * 2, i * 2 + 1, i
				if l <= #open and open[l][1] < open[m][1] then
					m = l
				end
				if r <= #open and open[r][1] < open[m][1] then
					m = r
				end
				if m == i then
					break
				end
				open[m], open[i] = open[i], open[m]
				i = m
			end
		end
		return top
	end
	local steps = 0
	while #open > 0 do
		local node = pop()
		local i, j = node[2], node[3]
		if i == ti and j == tj then
			local path = {}
			local k = key(i, j)
			while k do
				table.insert(path, 1, Vector2.new((k // 10000 - 1000) * GRID, (k % 10000 - 1000) * GRID))
				k = came[k]
			end
			path[1] = from
			path[#path] = to
			return path
		end
		steps += 1
		if steps > 60000 then
			return nil
		end
		if steps % 4000 == 0 then
			task.wait()
		end
		local here = h(i, j)
		for di = -1, 1 do
			for dj = -1, 1 do
				if di ~= 0 or dj ~= 0 then
					local ni, nj = i + di, j + dj
					local nh = h(ni, nj)
					if
						nh > WATER + 1.1
						and nh < 146
						and not onIsland(ni * GRID, nj * GRID)
						and not nearAirbase(ni * GRID, nj * GRID, 28)
						and fromEdge(ni * GRID, nj * GRID) > 420
					then
						local dist = GRID * math.sqrt(di * di + dj * dj)
						local grade = math.abs(nh - here) / dist
						if grade < 0.18 then
							local nk = key(ni, nj)
							local c = cost[key(i, j)] + dist * (1 + 30 * grade + nh / 140)
							if cost[nk] == nil or c < cost[nk] then
								cost[nk] = c
								came[nk] = key(i, j)
								local est = math.sqrt((ti - ni) ^ 2 + (tj - nj) ^ 2) * GRID
								push({ c + est, ni, nj })
							end
						end
					end
				end
			end
		end
	end
	return nil
end

-- Towns ------------------------------------------------------------------------------------------------------

export type Town = { centre: Vector2, radius: number, angle: number, west: boolean }
local towns: { Town } = {}

-- Flat lowland sites, spread out, on both landmasses.
local function findTowns(): { Town }
	if #towns > 0 then
		return towns
	end
	local rng = Random.new(SEED)
	local candidates = {}
	for x = -5320, 5320, 252 do
		for z = -5320, 5320, 252 do
			local px, pz = x + rng:NextNumber(-84, 84), z + rng:NextNumber(-84, 84)
			if math.abs(px) > 1260 and fromEdge(px, pz) > 840 and not nearAirbase(px, pz, 700) then
				local h0 = height(px, pz)
				if h0 > 4.2 and h0 < 73 then
					local lo, hi = h0, h0
					for _, o in { Vector2.new(84, 0), Vector2.new(-84, 0), Vector2.new(0, 84), Vector2.new(0, -84) } do
						local hh = height(px + o.X, pz + o.Y)
						lo, hi = math.min(lo, hh), math.max(hi, hh)
					end
					if hi - lo < 12.6 and lo > WATER + 1.1 then
						table.insert(candidates, { x = px, z = pz, score = (hi - lo) + rng:NextNumber(0, 7) })
					end
				end
			end
		end
	end
	table.sort(candidates, function(a, b)
		return a.score < b.score
	end)
	local perSide = { west = 0, east = 0 }
	for _, c in candidates do
		local west = c.x < 0
		local sideKey = if west then "west" else "east"
		if perSide[sideKey] < 6 then
			local ok = true
			for _, t in towns do
				if (t.centre - Vector2.new(c.x, c.z)).Magnitude < 1176 then
					ok = false
					break
				end
			end
			if ok then
				table.insert(towns, {
					centre = Vector2.new(c.x, c.z),
					radius = rng:NextNumber(118, 213),
					angle = rng:NextNumber(0, math.pi),
					west = west,
				})
				perSide[sideKey] += 1
			end
		end
	end
	return towns
end

local function gates(): { { pos: Vector2, west: boolean } }
	local out = {}
	for name, base in Strait.AIRBASES do
		local side = if name == "West" then 1 else -1
		table.insert(out, { pos = Vector2.new(base.position.X + side * 476, base.position.Z), west = name == "West" })
	end
	return out
end

local function sceneryFolder(): Instance
	local map = folder(workspace, "Map")
	return folder(map, "Scenery")
end

function SceneryBuilder.clear(): string
	local map = workspace:FindFirstChild("Map")
	local s = map and map:FindFirstChild("Scenery")
	if s then
		s:Destroy()
	end
	table.clear(roadSegments)
	table.clear(roadHash)
	table.clear(towns)
	return "scenery cleared"
end

-- Roads joining the towns and airbase of each landmass (a minimum spanning tree plus one extra link).
function SceneryBuilder.roads(): string
	local parent = folder(sceneryFolder(), "Roads")
	local placedBefore = #roadSegments
	for _, west in { true, false } do
		local nodes: { Vector2 } = {}
		for _, t in findTowns() do
			if t.west == west then
				table.insert(nodes, t.centre)
			end
		end
		for _, g in gates() do
			if g.west == west then
				table.insert(nodes, g.pos)
			end
		end
		-- Prim's MST
		local inTree = { [1] = true }
		local edges = {}
		for _ = 2, #nodes do
			local best, bi, bj = math.huge, 0, 0
			for i in inTree do
				for j = 1, #nodes do
					if not inTree[j] then
						local d = (nodes[i] - nodes[j]).Magnitude
						if d < best then
							best, bi, bj = d, i, j
						end
					end
				end
			end
			inTree[bj] = true
			table.insert(edges, { bi, bj })
		end
		-- one loop: join the two closest nodes not already joined
		local cache = {}
		for _, e in edges do
			local path = route(nodes[e[1]], nodes[e[2]], cache)
			if path then
				layRoad(parent, smoothPath(path, 3))
			end
			task.wait()
		end
	end
	return `{#roadSegments - placedBefore} road segments`
end

-- Buildings along a street grid in each town, farms along the country roads, a few trees in town.
function SceneryBuilder.towns(): string
	local root = sceneryFolder()
	local rng = Random.new(SEED + 1)
	local placed = 0
	local occupied: { [number]: boolean } = {}
	local function free(x: number, z: number, r: number): boolean
		local cr = math.ceil(r / 9)
		local cx, cz = math.floor(x / 9), math.floor(z / 9)
		for i = -cr, cr do
			for j = -cr, cr do
				if occupied[(cx + i) * 100000 + cz + j] then
					return false
				end
			end
		end
		return true
	end
	local function claim(x: number, z: number, r: number)
		local cr = math.ceil(r / 9)
		local cx, cz = math.floor(x / 9), math.floor(z / 9)
		for i = -cr, cr do
			for j = -cr, cr do
				occupied[(cx + i) * 100000 + cz + j] = true
			end
		end
	end
	local SIZES = { House = 6.7, Apartment = 15.7, Shop = 7.3, Warehouse = 21.3, Church = 15.7, Barn = 9.5 }
	for index, t in findTowns() do
		local model = lodModel(`Town{index}`, root)
		local roads = folder(model, "Streets")
		local c = t.centre
		local along = Vector2.new(math.cos(t.angle), math.sin(t.angle))
		local across = Vector2.new(-along.Y, along.X)
		-- Streets: a main street, cross streets and one parallel street
		local streets: { { Vector2 } } = { { c - along * t.radius, c + along * t.radius } }
		for _, k in { -0.6, -0.25, 0.15, 0.5 } do
			local o = c + along * (k * t.radius)
			table.insert(streets, { o - across * t.radius * 0.65, o + across * t.radius * 0.65 })
		end
		table.insert(streets, { c + across * 67 - along * t.radius * 0.6, c + across * 67 + along * t.radius * 0.6 })
		for _, s in streets do
			layRoad(roads, s)
		end
		-- Plots along both sides of every street, filled from the centre out so the church and the big
		-- buildings in the middle get their space before the houses around them
		local plots = {}
		for _, s in streets do
			local dir = (s[2] - s[1]).Unit
			local normal = Vector2.new(-dir.Y, dir.X)
			local length = (s[2] - s[1]).Magnitude
			for d = 8.4, length - 8.4, 18 do
				for _, sideSign in { -1, 1 } do
					local p = s[1] + dir * d + normal * sideSign * 13.4
					table.insert(plots, { p = p, out = normal * sideSign, fromCentre = (p - c).Magnitude / t.radius })
				end
			end
		end
		table.sort(plots, function(a, b)
			return a.fromCentre < b.fromCentre
		end)
		local churchDone = false
		for _, plot in plots do
			local kind = "House"
			local roll = rng:NextNumber()
			if plot.fromCentre < 0.35 then
				kind = if not churchDone
					then "Church"
					elseif roll < 0.45 then "Apartment"
					elseif roll < 0.8 then "Shop"
					else "House"
			elseif plot.fromCentre > 0.8 then
				kind = if roll < 0.3 then "Warehouse" else "House"
			elseif roll < 0.08 then
				kind = "Shop"
			end
			local r = SIZES[kind]
			local q = plot.p + plot.out * (r - 6.7)
			if rng:NextNumber() < 0.85 and free(q.X, q.Y, r) and not nearRoad(q.X, q.Y, r - 2.2) then
				local h = height(q.X, q.Y)
				if h > WATER + 0.84 and slope(q.X, q.Y) < 0.25 then
					place(kind, model, q.X, q.Y, math.atan2(plot.out.X, plot.out.Y), rng)
					claim(q.X, q.Y, r)
					placed += 1
					churchDone = churchDone or kind == "Church"
				end
			end
		end
		task.wait()
		-- Trees in gardens and squares
		for _ = 1, 14 do
			local a, r = rng:NextNumber(0, 2 * math.pi), rng:NextNumber(0.2, 1.05) * t.radius
			local x, z = c.X + math.cos(a) * r, c.Y + math.sin(a) * r
			if free(x, z, 3.4) and not nearRoad(x, z, 5.6) and height(x, z) > WATER + 0.84 then
				place(
					if rng:NextNumber() < 0.6 then "TreeBroadleaf" else "TreePoplar",
					model,
					x,
					z,
					rng:NextNumber(0, 6.28),
					rng,
					rng:NextNumber(0.9, 1.3)
				)
			end
		end
	end
	-- Farms along the country roads
	local farms = lodModel("Farms", root)
	for i = 1, #roadSegments, 30 do
		local seg = roadSegments[i]
		if rng:NextNumber() < 0.35 then
			local dir = Vector2.new(seg.b.X - seg.a.X, seg.b.Z - seg.a.Z)
			if dir.Magnitude > 0.28 then
				dir = dir.Unit
				local normal = Vector2.new(-dir.Y, dir.X) * (if rng:NextNumber() < 0.5 then 1 else -1)
				local p = Vector2.new(seg.a.X, seg.a.Z) + normal * 31
				local farFromTowns = true
				for _, t in towns do
					if (t.centre - p).Magnitude < t.radius + 84 then
						farFromTowns = false
					end
				end
				if
					farFromTowns
					and not nearAirbase(p.X, p.Y, 112)
					and not onIsland(p.X, p.Y)
					and free(p.X, p.Y, 25)
					and slope(p.X, p.Y) < 0.2
					and height(p.X, p.Y) > WATER + 0.84
				then
					local yaw = math.atan2(normal.X, normal.Y)
					place("House", farms, p.X, p.Y, yaw, rng)
					local b = p + dir * 20 + normal * 8.4
					place("Barn", farms, b.X, b.Y, yaw + math.pi / 2, rng)
					claim(p.X, p.Y, 25)
					placed += 2
				end
			end
		end
	end
	return `{placed} buildings in {#towns} towns and the countryside`
end

-- Woods: clumps of trees on the lowland and hills, conifers higher up, kept off roads and out of towns.
function SceneryBuilder.woods(): string
	local root = sceneryFolder()
	local rng = Random.new(SEED + 2)
	local trees, clumps = 0, 0
	local woods = lodModel("Woods1", root)
	for attempt = 1, 2600 do
		if clumps >= 760 then
			break
		end
		local x, z = rng:NextNumber(-5600, 5600), rng:NextNumber(-5600, 5600)
		local h = height(x, z)
		local ok = h > 2.8 and h < 230 and fromEdge(x, z) > 84 and not nearAirbase(x, z, 84) and not onIsland(x, z)
		if ok then
			for _, t in findTowns() do
				if (t.centre - Vector2.new(x, z)).Magnitude < t.radius + 42 then
					ok = false
				end
			end
		end
		if ok and slope(x, z) < 0.5 then
			clumps += 1
			local count = rng:NextInteger(10, 30)
			local radius = rng:NextNumber(20, 62)
			for _ = 1, count do
				local a, r = rng:NextNumber(0, 2 * math.pi), radius * math.sqrt(rng:NextNumber())
				local tx, tz = x + math.cos(a) * r, z + math.sin(a) * r
				local th = height(tx, tz)
				if th > WATER + 1.1 and not nearRoad(tx, tz, 8.4) then
					local roll = rng:NextNumber()
					local kind = if th > 106
						then (if roll < 0.85 then "TreeConifer" else "TreeBroadleaf")
						elseif roll < 0.5 then "TreeBroadleaf"
						elseif roll < 0.78 then "TreeConifer"
						else "TreePoplar"
					place(kind, woods, tx, tz, rng:NextNumber(0, 6.28), rng, rng:NextNumber(1.0, 1.6), 1.0)
					trees += 1
				end
			end
			if clumps % 40 == 0 then
				woods = lodModel(`Woods{clumps // 40 + 1}`, root)
				task.wait()
			end
		end
		if attempt % 200 == 0 then
			task.wait()
		end
	end
	return `{trees} trees in {clumps} woods`
end

-- Airbase buildings: three maintenance hangars, the tower and ops block, hardened shelters by the runway,
-- fuel tanks. Replaces the old box buildings in Map.AirbaseWest / Map.AirbaseEast.
function SceneryBuilder.airbases(): string
	local map = folder(workspace, "Map")
	local rng = Random.new(SEED + 3)
	for name, base in Strait.AIRBASES do
		local old = map:FindFirstChild(`Airbase{name}`)
		if old then
			old:Destroy()
		end
		local model = lodModel(`Airbase{name}`, map)
		local p = base.position
		local side = if name == "West" then 1 else -1
		local towardRunway = if side > 0 then math.pi / 2 else -math.pi / 2 -- yaw facing -side * X
		for h = -1, 1 do
			place("Hangar", model, p.X + side * 350, p.Z + h * 73, towardRunway, rng, 1, 0.5)
		end
		place("Tower", model, p.X + side * 322, p.Z - 168, towardRunway, rng, 1, 0.5)
		place("OpsBuilding", model, p.X + side * 344, p.Z - 230, towardRunway, rng, 1, 0.5)
		for _, dz in { -350, -266, 266, 350 } do
			place("Shelter", model, p.X + side * 196, p.Z + dz, towardRunway, rng, 1, 0.5)
		end
		for i = 0, 2 do
			place("FuelTank", model, p.X + side * 370, p.Z + 179 + i * 22, 0, rng, 1, 0.5)
		end
	end
	return "airbases rebuilt"
end

-- Tree placements for the woods merge, a page at a time (page 1, 2, ... until it returns ""). One tree
-- per line: kind (C conifer, B broadleaf, P poplar), ground x y z (studs), yaw (degrees), scale (x100),
-- foliage colour as hex.
local KIND_CODE = { TreeConifer = "C", TreeBroadleaf = "B", TreePoplar = "P" }
local TREES_PER_PAGE = 1500

function SceneryBuilder.exportTrees(page: number): string
	local templates = ServerStorage:FindFirstChild("SceneryTemplates")
	assert(templates, "No SceneryTemplates: run templates() first")
	local byMesh: { [string]: string } = {}
	local trunkHeight: { [string]: number } = {}
	for kind in KIND_CODE do
		local t = templates:FindFirstChild(kind)
		local trunk = t and t:FindFirstChild("Trunk") :: MeshPart?
		if trunk then
			byMesh[trunk.MeshId] = kind
			trunkHeight[kind] = trunk.Size.Y
		end
	end
	local lines = {}
	local index = 0
	local first, last = (page - 1) * TREES_PER_PAGE + 1, page * TREES_PER_PAGE
	for _, model in sceneryFolder():GetChildren() do
		if not string.match(model.Name, "^Woods%d+$") then
			continue
		end
		local parts = model:GetChildren()
		-- place() adds each tree's parts together, so a tree is its Trunk plus the Foliage beside it
		for i, trunk in parts do
			if not (trunk:IsA("MeshPart") and trunk.Name == "Trunk") then
				continue
			end
			local foliage = parts[i + 1]
			if not (foliage and foliage.Name == "Foliage") then
				foliage = parts[i - 1]
			end
			local kind = byMesh[trunk.MeshId]
			if not (kind and foliage and foliage:IsA("BasePart")) then
				continue
			end
			index += 1
			if index < first or index > last then
				continue
			end
			local scale = trunk.Size.Y / trunkHeight[kind]
			local ground = trunk.CFrame * Vector3.new(0, -trunk.Size.Y / 2, 0)
			local _, yaw = trunk.CFrame:ToEulerAnglesYXZ()
			table.insert(
				lines,
				string.format(
					"%s %.1f %.1f %.1f %d %d %s",
					KIND_CODE[kind],
					ground.X,
					ground.Y,
					ground.Z,
					math.round(math.deg(yaw)),
					math.round(scale * 100),
					foliage.Color:ToHex()
				)
			)
		end
	end
	return table.concat(lines, "\n")
end

-- Swaps the woods' tree parts for the merged meshes from woods_merge.py. Blender names each mesh
-- "Woods_<n>@x,y,z" with the centre of its bounding box in map studs. Import 3D does two things to them,
-- both measured in Studio: it shrinks the whole import to fit (it spans the map; 0.354 last time, so the
-- factor is measured here from how far apart the meshes landed), and it turns each mesh half round about
-- its own centre. Both are undone, the palette texture applied, and each mesh put at its centre.
function SceneryBuilder.installMergedWoods(source: Instance, paletteAssetId: number): string
	local root = sceneryFolder()
	local removed = 0
	for _, model in root:GetChildren() do
		if string.match(model.Name, "^Woods%d+$") or model.Name == "WoodsMerged" then
			removed += #model:GetChildren()
			model:Destroy()
		end
	end
	local meshes = {}
	for _, d in source:GetDescendants() do
		local x, y, z = string.match(d.Name, "@(%-?[%d%.]+),(%-?[%d%.]+),(%-?[%d%.]+)$")
		if d:IsA("MeshPart") and x then
			table.insert(meshes, { part = d, centre = Vector3.new(tonumber(x), tonumber(y), tonumber(z)) })
		end
	end
	-- The importer's shrink: imported distances between meshes over their true distances (the median)
	local ratios = {}
	for i, a in meshes do
		local b = meshes[(i + #meshes // 2 - 1) % #meshes + 1]
		local want = (a.centre - b.centre).Magnitude
		if want > 560 then
			table.insert(ratios, (a.part.Position - b.part.Position).Magnitude / want)
		end
	end
	table.sort(ratios)
	local grow = if #ratios > 0 then 1 / ratios[math.ceil(#ratios / 2)] else 1
	local folder = Instance.new("Folder")
	folder.Name = "WoodsMerged"
	local placed = 0
	for _, mesh in meshes do
		local part = mesh.part:Clone()
		part.Name = "Trees"
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false -- one box around a whole wood would catch rays far from any tree
		part.CastShadow = true
		part.Material = Enum.Material.SmoothPlastic
		part.Color = Color3.new(1, 1, 1)
		part.TextureID = `rbxassetid://{paletteAssetId}`
		part.Size = mesh.part.Size * grow
		part.CFrame = CFrame.new(mesh.centre) * CFrame.Angles(0, math.pi, 0)
		local model = lodModel(`Woods_{placed + 1}`, folder)
		part.Parent = model
		placed += 1
	end
	folder.Parent = root
	return string.format(
		"removed %d tree parts; placed %d merged wood meshes (scaled up x%.3f, turned half round)",
		removed,
		placed,
		grow
	)
end

return SceneryBuilder
