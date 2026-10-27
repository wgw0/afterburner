--!strict
-- Scenery for the Strait map (MAP-03): towns, farms, the roads that join them, woods, and the airbase
-- buildings. Props come from the Blender scenery kit (tools/blender/scenery_generate.py), imported into
-- Studio as one Model; pieces are named "<Prop>__<Piece>" and coloured here, so the kit needs no textures.
-- Deterministic (fixed seeds). Run in Edit mode after StraitBuilder, one step at a time:
--   local S = require(game.ServerStorage.Tools.SceneryBuilder)
--   S.templates(workspace.Scenery_kit)  -- once per kit import: builds ServerStorage.SceneryTemplates
--   S.clear() S.roads() S.towns() S.woods() S.airbases()
-- Everything goes in workspace.Map.Scenery, except the airbase buildings, which replace the contents of
-- Map.AirbaseWest / Map.AirbaseEast. Towns, woods and airbases are Models with
-- LevelOfDetail = StreamingMesh, so they still show from the air before they have streamed in.

local ServerStorage = game:GetService("ServerStorage")

local Strait = require(script.Parent.StraitBuilder)

local SEED = 4242
local WATER = -6
local ROAD_TEXTURE = "rbxassetid://88361153151301" -- tools/blender/out/textures/Road_Color.png
local ROAD_WIDTH = 26 -- studs (7.3 m, two lanes)
local ROAD_STEP = 32 -- studs between road segment joints
local GRID = 200 -- road routing grid (studs)

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
	local hit = workspace:Raycast(Vector3.new(x, 2000, z), Vector3.new(0, -2600, 0), terrainOnly)
	return if hit then hit.Position.Y else height(x, z)
end

local function slope(x: number, z: number): number
	local d = 20
	local dx = height(x + d, z) - height(x - d, z)
	local dz = height(x, z + d) - height(x, z - d)
	return math.sqrt(dx * dx + dz * dz) / (2 * d)
end

local function nearAirbase(x: number, z: number, margin: number): boolean
	for _, base in Strait.AIRBASES do
		if math.abs(x - base.position.X) < 1400 + margin and math.abs(z - base.position.Z) < 3800 + margin then
			return true
		end
	end
	return false
end

local function onIsland(x: number, z: number): boolean
	return x * x + z * z < 3600 * 3600
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

local WALLS = { Color3.fromRGB(226, 218, 198), Color3.fromRGB(238, 234, 226), Color3.fromRGB(214, 196, 160), Color3.fromRGB(198, 196, 190) }
local ROOFS = { Color3.fromRGB(150, 70, 52), Color3.fromRGB(122, 62, 48), Color3.fromRGB(84, 86, 92), Color3.fromRGB(104, 78, 62) }
local FOLIAGE = { Color3.fromRGB(58, 92, 40), Color3.fromRGB(70, 104, 46), Color3.fromRGB(48, 80, 42), Color3.fromRGB(84, 110, 52) }
local CONIFER = { Color3.fromRGB(40, 68, 42), Color3.fromRGB(46, 76, 46), Color3.fromRGB(36, 60, 40) }
local AWNINGS = { Color3.fromRGB(160, 40, 36), Color3.fromRGB(40, 90, 60), Color3.fromRGB(40, 70, 130) }

-- Piece look: colour (or a palette picked per instance), material, collides with jets
type Look = { colour: Color3?, palette: { Color3 }?, material: Enum.Material, collide: boolean }

local function look(prop: string, piece: string): Look
	local airbase = prop == "Hangar" or prop == "Shelter" or prop == "Tower" or prop == "OpsBuilding" or prop == "FuelTank"
	if piece == "Trunk" then
		return { colour = Color3.fromRGB(88, 64, 44), material = Enum.Material.Wood, collide = false }
	elseif piece == "Foliage" then
		return { palette = if prop == "TreeConifer" then CONIFER else FOLIAGE, material = Enum.Material.SmoothPlastic, collide = false }
	elseif piece == "Windows" then
		return { colour = Color3.fromRGB(38, 46, 56), material = Enum.Material.SmoothPlastic, collide = true }
	elseif piece == "Glass" then
		return { colour = Color3.fromRGB(46, 84, 96), material = Enum.Material.SmoothPlastic, collide = true }
	elseif piece == "Doors" then
		return { colour = if airbase then Color3.fromRGB(96, 104, 98) else Color3.fromRGB(90, 76, 62), material = Enum.Material.Metal, collide = true }
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
local function place(name: string, parent: Instance, x: number, z: number, yaw: number, rng: Random, scale: number?, sink: number?)
	local t = template(name)
	local s = scale or 1
	local ground = math.min(height(x, z), height(x + 8, z + 8), height(x - 8, z - 8)) - (sink or 1.5)
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
local roadHash: { [number]: { Vector2 } } = {} -- road sample points by 64-stud cell

local function hashKey(x: number, z: number): number
	return math.floor(x / 64) * 100000 + math.floor(z / 64)
end

-- True if (x, z) is within clearance of a road's edge.
local function nearRoad(x: number, z: number, clearance: number): boolean
	local reach = clearance + ROAD_WIDTH / 2 + ROAD_STEP / 2
	local r = math.ceil(reach / 64)
	local cx, cz = math.floor(x / 64), math.floor(z / 64)
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
	if length < 1 then
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
	p.Size = Vector3.new(ROAD_WIDTH, 2, length + 3)
	p.CFrame = CFrame.lookAt((a + b) / 2, b)
	local tex = Instance.new("Texture")
	tex.Texture = ROAD_TEXTURE
	tex.Face = Enum.NormalId.Top
	tex.StudsPerTileU = ROAD_WIDTH
	tex.StudsPerTileV = 64
	tex.Parent = p
	p.Parent = parent
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
	local prev: Vector3? = nil
	for _, s in samples do
		if height(s.X, s.Y) < WATER + 1 then
			prev = nil
			continue
		end
		-- highest of the centre and the edges, so a camber in the ground doesn't swallow one side
		local h = surface(s.X, s.Y)
		for _, o in { Vector2.new(10, 0), Vector2.new(-10, 0), Vector2.new(0, 10), Vector2.new(0, -10) } do
			h = math.max(h, surface(s.X + o.X, s.Y + o.Y))
		end
		local here = Vector3.new(s.X, h + 1.6, s.Y) -- 2 studs thick: the drawn terrain sits above its collision surface
		if prev then
			roadPart(parent, prev, here)
			table.insert(roadSegments, { a = prev, b = here })
			local k = hashKey(here.X, here.Z)
			roadHash[k] = roadHash[k] or {}
			table.insert(roadHash[k], Vector2.new(here.X, here.Z))
		end
		prev = here
	end
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
					if nh > WATER + 4 and nh < 520 and not onIsland(ni * GRID, nj * GRID) and not nearAirbase(ni * GRID, nj * GRID, 100) then
						local dist = GRID * math.sqrt(di * di + dj * dj)
						local grade = math.abs(nh - here) / dist
						if grade < 0.18 then
							local nk = key(ni, nj)
							local c = cost[key(i, j)] + dist * (1 + 30 * grade + nh / 500)
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
	for x = -19000, 19000, 900 do
		for z = -19000, 19000, 900 do
			local px, pz = x + rng:NextNumber(-300, 300), z + rng:NextNumber(-300, 300)
			if math.abs(px) > 4500 and not nearAirbase(px, pz, 2500) then
				local h0 = height(px, pz)
				if h0 > 15 and h0 < 260 then
					local lo, hi = h0, h0
					for _, o in { Vector2.new(300, 0), Vector2.new(-300, 0), Vector2.new(0, 300), Vector2.new(0, -300) } do
						local hh = height(px + o.X, pz + o.Y)
						lo, hi = math.min(lo, hh), math.max(hi, hh)
					end
					if hi - lo < 45 and lo > WATER + 4 then
						table.insert(candidates, { x = px, z = pz, score = (hi - lo) + rng:NextNumber(0, 25) })
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
				if (t.centre - Vector2.new(c.x, c.z)).Magnitude < 4200 then
					ok = false
					break
				end
			end
			if ok then
				table.insert(towns, {
					centre = Vector2.new(c.x, c.z),
					radius = rng:NextNumber(420, 760),
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
		table.insert(out, { pos = Vector2.new(base.position.X + side * 1700, base.position.Z), west = name == "West" })
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
		local cr = math.ceil(r / 32)
		local cx, cz = math.floor(x / 32), math.floor(z / 32)
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
		local cr = math.ceil(r / 32)
		local cx, cz = math.floor(x / 32), math.floor(z / 32)
		for i = -cr, cr do
			for j = -cr, cr do
				occupied[(cx + i) * 100000 + cz + j] = true
			end
		end
	end
	local SIZES = { House = 24, Apartment = 56, Shop = 26, Warehouse = 76, Church = 56, Barn = 34 }
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
		table.insert(streets, { c + across * 240 - along * t.radius * 0.6, c + across * 240 + along * t.radius * 0.6 })
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
			for d = 30, length - 30, 64 do
				for _, sideSign in { -1, 1 } do
					local p = s[1] + dir * d + normal * sideSign * 48
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
				kind = if not churchDone then "Church" elseif roll < 0.45 then "Apartment" elseif roll < 0.8 then "Shop" else "House"
			elseif plot.fromCentre > 0.8 then
				kind = if roll < 0.3 then "Warehouse" else "House"
			elseif roll < 0.08 then
				kind = "Shop"
			end
			local r = SIZES[kind]
			local q = plot.p + plot.out * (r - 24)
			if rng:NextNumber() < 0.85 and free(q.X, q.Y, r) and not nearRoad(q.X, q.Y, r - 8) then
				local h = height(q.X, q.Y)
				if h > WATER + 3 and slope(q.X, q.Y) < 0.25 then
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
			if free(x, z, 12) and not nearRoad(x, z, 20) and height(x, z) > WATER + 3 then
				place(if rng:NextNumber() < 0.6 then "TreeBroadleaf" else "TreePoplar", model, x, z, rng:NextNumber(0, 6.28), rng, rng:NextNumber(0.9, 1.3))
			end
		end
	end
	-- Farms along the country roads
	local farms = lodModel("Farms", root)
	for i = 1, #roadSegments, 30 do
		local seg = roadSegments[i]
		if rng:NextNumber() < 0.35 then
			local dir = Vector2.new(seg.b.X - seg.a.X, seg.b.Z - seg.a.Z)
			if dir.Magnitude > 1 then
				dir = dir.Unit
				local normal = Vector2.new(-dir.Y, dir.X) * (if rng:NextNumber() < 0.5 then 1 else -1)
				local p = Vector2.new(seg.a.X, seg.a.Z) + normal * 110
				local farFromTowns = true
				for _, t in towns do
					if (t.centre - p).Magnitude < t.radius + 300 then
						farFromTowns = false
					end
				end
				if farFromTowns and not nearAirbase(p.X, p.Y, 400) and not onIsland(p.X, p.Y) and free(p.X, p.Y, 90) and slope(p.X, p.Y) < 0.2 and height(p.X, p.Y) > WATER + 3 then
					local yaw = math.atan2(normal.X, normal.Y)
					place("House", farms, p.X, p.Y, yaw, rng)
					local b = p + dir * 70 + normal * 30
					place("Barn", farms, b.X, b.Y, yaw + math.pi / 2, rng)
					claim(p.X, p.Y, 90)
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
		local x, z = rng:NextNumber(-20000, 20000), rng:NextNumber(-20000, 20000)
		local h = height(x, z)
		local ok = h > 10 and h < 820 and not nearAirbase(x, z, 300) and not onIsland(x, z)
		if ok then
			for _, t in findTowns() do
				if (t.centre - Vector2.new(x, z)).Magnitude < t.radius + 150 then
					ok = false
				end
			end
		end
		if ok and slope(x, z) < 0.5 then
			clumps += 1
			local count = rng:NextInteger(10, 30)
			local radius = rng:NextNumber(70, 220)
			for _ = 1, count do
				local a, r = rng:NextNumber(0, 2 * math.pi), radius * math.sqrt(rng:NextNumber())
				local tx, tz = x + math.cos(a) * r, z + math.sin(a) * r
				local th = height(tx, tz)
				if th > WATER + 4 and not nearRoad(tx, tz, 30) then
					local roll = rng:NextNumber()
					local kind = if th > 380
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
			place("Hangar", model, p.X + side * 1250, p.Z + h * 260, towardRunway, rng, 1, 0.5)
		end
		place("Tower", model, p.X + side * 1150, p.Z - 600, towardRunway, rng, 1, 0.5)
		place("OpsBuilding", model, p.X + side * 1230, p.Z - 820, towardRunway, rng, 1, 0.5)
		for _, dz in { -1250, -950, 950, 1250 } do
			place("Shelter", model, p.X + side * 700, p.Z + dz, towardRunway, rng, 1, 0.5)
		end
		for i = 0, 2 do
			place("FuelTank", model, p.X + side * 1320, p.Z + 640 + i * 80, 0, rng, 1, 0.5)
		end
	end
	return "airbases rebuilt"
end

return SceneryBuilder
