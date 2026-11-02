--!strict
-- Desert Range scenery (MAP-05): what stands on the desert's terrain, all built from plain parts (no imports):
--   * saguaro cacti, scrub and boulders scattered over the open floor (never on the road, the salt lake, the
--     airbases, the town or steep ground), grouped by area into models that stream as meshes far away;
--   * the town of Dry Wells on its flattened ground: adobe houses along the road, a mission church, a saloon
--     with a false front, a water tower and a gas station;
--   * telegraph poles along the road;
--   * a small oil field of derricks and storage tanks on the edge of the dunes.
-- Deterministic. Run in Edit mode after DesertBuilder has built the terrain:
--   require(game.ServerStorage.Tools.DesertScenery).build()   -- replaces workspace.Map.Scenery

local DesertShape = require(script.Parent.DesertShape)

local CELL = 1024 -- studs per scenery model (each streams on its own)
local HALF = 5400 -- scenery stays inside the play area

local DesertScenery = {}

local CACTUS = Color3.fromRGB(78, 116, 62)
local SCRUB = Color3.fromRGB(122, 116, 70)
local ADOBE = Color3.fromRGB(214, 172, 128)
local ADOBE_DARK = Color3.fromRGB(176, 128, 90)
local WOOD = Color3.fromRGB(110, 78, 52)
local DARK = Color3.fromRGB(46, 36, 32)

local function part(
	parent: Instance,
	size: Vector3,
	cf: CFrame,
	colour: Color3,
	material: Enum.Material?,
	shape: Enum.PartType?
): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false -- jets never touch scenery; terrain is what they crash into
	p.CanTouch = false
	p.CastShadow = true
	p.Size = size
	p.CFrame = cf
	p.Color = colour
	p.Material = material or Enum.Material.SmoothPlastic
	if shape then
		p.Shape = shape
	end
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- A vertical cylinder from y0 up `height` studs (cylinders run along X, so they're turned upright)
local function post(
	parent: Instance,
	x: number,
	y0: number,
	z: number,
	height: number,
	width: number,
	colour: Color3,
	material: Enum.Material?
): Part
	return part(
		parent,
		Vector3.new(height, width, width),
		CFrame.new(x, y0 + height / 2, z) * CFrame.Angles(0, 0, math.pi / 2),
		colour,
		material,
		Enum.PartType.Cylinder
	)
end

local function groundAt(x: number, z: number): number
	return DesertShape.height(x, z)
end

local function slopeAt(x: number, z: number): number
	local dx = DesertShape.height(x + 6, z) - DesertShape.height(x - 6, z)
	local dz = DesertShape.height(x, z + 6) - DesertShape.height(x, z - 6)
	return math.sqrt(dx * dx + dz * dz) / 12
end

-- Whether a prop may stand at (x, z): open floor, not too steep, clear of the road, town, lake and airbases
local function openGround(x: number, z: number): boolean
	if DesertShape.airbaseAt(x, z) > 0 then
		return false
	end
	if DesertShape.roadDistance(x, z) < DesertShape.ROAD_HALF + 14 then
		return false
	end
	local town = math.sqrt((x - DesertShape.TOWN.X) ^ 2 + (z - DesertShape.TOWN.Z) ^ 2)
	if town < DesertShape.TOWN_RADIUS + 30 then
		return false
	end
	local h = groundAt(x, z)
	local material = DesertShape.material(x, z, h, slopeAt(x, z))
	return (material == "Ground" or material == "Sand" or material == "Sandstone") and slopeAt(x, z) < 0.3
end

-- The model for the area a point is in (created on first use)
local function cellFor(root: Instance, cells: { [string]: Model }, x: number, z: number): Model
	local key = `{x // CELL}_{z // CELL}`
	local model = cells[key]
	if not model then
		model = Instance.new("Model")
		model.Name = `Cell_{key}`
		model.LevelOfDetail = Enum.ModelLevelOfDetail.StreamingMesh -- a cheap mesh stand-in from afar
		model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
		model.Parent = root
		cells[key] = model
	end
	return model
end

local function saguaro(parent: Instance, x: number, z: number, rng: Random)
	local y = groundAt(x, z) - 0.5
	local height = rng:NextNumber(7, 15)
	local width = height * 0.14
	post(parent, x, y, z, height, width, CACTUS, Enum.Material.Grass)
	part(
		parent,
		Vector3.new(width, width, width),
		CFrame.new(x, y + height, z),
		CACTUS,
		Enum.Material.Grass,
		Enum.PartType.Ball
	)
	for _ = 1, rng:NextInteger(0, 3) do
		local a = rng:NextNumber(0, math.pi * 2)
		local up = rng:NextNumber(0.35, 0.6) * height
		local out = rng:NextNumber(1.6, 2.6) * width
		local armH = rng:NextNumber(0.25, 0.4) * height
		local ax, az = x + math.cos(a) * out, z + math.sin(a) * out
		-- the elbow out from the trunk, then the arm rising
		part(
			parent,
			Vector3.new(out, width * 0.75, width * 0.75),
			CFrame.lookAt(Vector3.new(x, y + up, z), Vector3.new(ax, y + up, az))
				* CFrame.new(0, 0, -out / 2)
				* CFrame.Angles(0, math.pi / 2, 0),
			CACTUS,
			Enum.Material.Grass,
			Enum.PartType.Cylinder
		)
		post(parent, ax, y + up, az, armH, width * 0.75, CACTUS, Enum.Material.Grass)
	end
end

local function scrub(parent: Instance, x: number, z: number, rng: Random)
	local s = rng:NextNumber(2, 4.5)
	part(
		parent,
		Vector3.new(s * 1.4, s * 0.8, s * 1.2),
		CFrame.new(x, groundAt(x, z) + s * 0.25, z) * CFrame.Angles(0, rng:NextNumber(0, 6.3), 0),
		SCRUB,
		Enum.Material.Grass,
		Enum.PartType.Ball
	)
end

local function boulder(parent: Instance, x: number, z: number, rng: Random)
	local s = rng:NextNumber(4, 14)
	part(
		parent,
		Vector3.new(s * rng:NextNumber(0.8, 1.4), s * rng:NextNumber(0.5, 0.9), s),
		CFrame.new(x, groundAt(x, z) + s * 0.2, z)
			* CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, 6.3), rng:NextNumber(-0.3, 0.3)),
		Color3.fromRGB(150, 98, 72),
		Enum.Material.Slate
	)
end

------------------------------------------------------------------------------------------------ the town

local function house(parent: Instance, at: CFrame, w: number, d: number, h: number, colour: Color3)
	local body = part(parent, Vector3.new(w, h, d), at * CFrame.new(0, h / 2, 0), colour, Enum.Material.Sand)
	body.Name = "Adobe"
	part(parent, Vector3.new(w + 0.6, 1.2, d + 0.6), at * CFrame.new(0, h + 0.6, 0), ADOBE_DARK, Enum.Material.Sand) -- parapet
	part(parent, Vector3.new(2.4, 4.6, 0.3), at * CFrame.new(0, 2.3, -d / 2 - 0.1), DARK) -- door
	for _, side in { -1, 1 } do
		part(parent, Vector3.new(1.8, 1.6, 0.3), at * CFrame.new(side * w * 0.28, h * 0.6, -d / 2 - 0.1), DARK) -- windows
	end
	-- roof beams (vigas) poking out of the front wall
	for i = -2, 2 do
		part(
			parent,
			Vector3.new(0.5, 0.5, 1.4),
			at * CFrame.new(i * w / 6, h - 1, -d / 2 - 0.5),
			WOOD,
			Enum.Material.Wood
		)
	end
end

local function church(parent: Instance, at: CFrame)
	house(parent, at, 16, 26, 11, Color3.fromRGB(232, 210, 178))
	local tower = at * CFrame.new(0, 0, -15)
	part(parent, Vector3.new(8, 20, 8), tower * CFrame.new(0, 10, 0), Color3.fromRGB(232, 210, 178), Enum.Material.Sand)
	part(parent, Vector3.new(5, 5, 8.4), tower * CFrame.new(0, 16, 0), DARK) -- the belfry opening
	part(parent, Vector3.new(0.6, 4, 0.6), tower * CFrame.new(0, 22, 0), WOOD, Enum.Material.Wood) -- cross
	part(parent, Vector3.new(2.6, 0.6, 0.6), tower * CFrame.new(0, 22.8, 0), WOOD, Enum.Material.Wood)
end

local function saloon(parent: Instance, at: CFrame)
	part(
		parent,
		Vector3.new(18, 9, 14),
		at * CFrame.new(0, 4.5, 0),
		Color3.fromRGB(150, 104, 70),
		Enum.Material.WoodPlanks
	)
	part(
		parent,
		Vector3.new(19, 14, 0.8),
		at * CFrame.new(0, 7, -7.2),
		Color3.fromRGB(170, 120, 80),
		Enum.Material.WoodPlanks
	) -- false front
	part(parent, Vector3.new(19, 0.5, 4), at * CFrame.new(0, 4.5, -9), WOOD, Enum.Material.Wood) -- porch roof
	for _, side in { -1, 1 } do
		local foot = at * CFrame.new(side * 9, 0, -10.6)
		post(parent, foot.X, foot.Y, foot.Z, 4.5, 0.5, WOOD) -- porch posts
	end
	part(parent, Vector3.new(4, 5, 0.3), at * CFrame.new(0, 2.5, -7.7), DARK) -- doors
end

local function waterTower(parent: Instance, at: CFrame)
	for _, c in { { -4, -4 }, { 4, -4 }, { -4, 4 }, { 4, 4 } } do
		local leg = at * CFrame.new(c[1], 0, c[2])
		post(parent, leg.X, leg.Y, leg.Z, 22, 0.8, WOOD)
	end
	local tank = at * CFrame.new(0, 27, 0)
	post(parent, tank.X, tank.Y - 5, tank.Z, 10, 12, Color3.fromRGB(150, 110, 80), Enum.Material.WoodPlanks)
	part(parent, Vector3.new(13, 1, 13), tank * CFrame.new(0, 5.5, 0), Color3.fromRGB(90, 70, 60), Enum.Material.Metal)
end

local function gasStation(parent: Instance, at: CFrame)
	part(
		parent,
		Vector3.new(12, 7, 9),
		at * CFrame.new(0, 3.5, 6),
		Color3.fromRGB(236, 232, 220),
		Enum.Material.Concrete
	)
	part(parent, Vector3.new(16, 1, 10), at * CFrame.new(0, 8, -6), Color3.fromRGB(200, 40, 36), Enum.Material.Metal) -- canopy
	for _, side in { -1, 1 } do
		local pillar = at * CFrame.new(side * 6, 0, -6)
		post(parent, pillar.X, pillar.Y, pillar.Z, 7.5, 0.8, Color3.fromRGB(236, 232, 220), Enum.Material.Metal)
		part(
			parent,
			Vector3.new(1.4, 3.6, 1),
			at * CFrame.new(side * 2.5, 1.8, -6),
			Color3.fromRGB(200, 40, 36),
			Enum.Material.Metal
		) -- pumps
	end
end

local function town(root: Instance)
	local folder = Instance.new("Model")
	folder.Name = "DryWells"
	folder.LevelOfDetail = Enum.ModelLevelOfDetail.StreamingMesh
	local centre = DesertShape.TOWN
	local y = DesertShape.TOWN_HEIGHT
	-- The road runs through the town; buildings face it from both sides
	local road = DesertShape.ROAD
	local dir = (road[4] - road[2]).Unit -- the road's heading through town
	local across = Vector3.new(-dir.Z, 0, dir.X)
	local function plot(along: number, side: number): CFrame
		local p = Vector3.new(centre.X, y, centre.Z) + dir * along + across * side * 26
		return CFrame.lookAt(p, p - across * side) -- facing the road
	end
	local rng = Random.new(DesertShape.SEED + 50)
	for i = -5, 5 do
		for _, side in { -1, 1 } do
			if not (i == 0 and side == 1) and not (i == 2 and side == -1) and not (i == -3 and side == 1) then
				local colour = if rng:NextNumber() < 0.5 then ADOBE else Color3.fromRGB(198, 150, 108)
				house(
					folder,
					plot(i * 30 + rng:NextNumber(-4, 4), side),
					rng:NextNumber(12, 18),
					rng:NextNumber(12, 16),
					rng:NextNumber(7, 10),
					colour
				)
			end
		end
	end
	church(folder, plot(0, 1) * CFrame.new(0, 0, 6))
	saloon(folder, plot(60, -1))
	gasStation(folder, plot(-90, 1))
	waterTower(folder, plot(30, -1) * CFrame.new(0, 0, 24))
	folder.Parent = root
	return folder
end

------------------------------------------------------------------------------------------------ road, oil

local function telegraphPoles(root: Instance)
	local folder = Instance.new("Model")
	folder.Name = "TelegraphPoles"
	folder.LevelOfDetail = Enum.ModelLevelOfDetail.StreamingMesh
	local road = DesertShape.ROAD
	for i = 1, #road - 1 do
		local a, b = road[i], road[i + 1]
		local length = (b - a).Magnitude
		local dir = (b - a).Unit
		local side = Vector3.new(-dir.Z, 0, dir.X) * 20
		for d = 0, length, 130 do
			local p = a + dir * d + side
			local y = groundAt(p.X, p.Z)
			post(folder, p.X, y - 1, p.Z, 19, 0.7, WOOD, Enum.Material.Wood)
			part(
				folder,
				Vector3.new(0.5, 0.5, 6),
				CFrame.lookAt(Vector3.new(p.X, y + 16.5, p.Z), Vector3.new(p.X, y + 16.5, p.Z) + side),
				WOOD,
				Enum.Material.Wood
			)
		end
	end
	folder.Parent = root
end

local function derrick(parent: Instance, x: number, z: number)
	local y = groundAt(x, z)
	local steel = Color3.fromRGB(70, 66, 64)
	local base, top, height = 9, 2, 40
	for _, c in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
		local from = Vector3.new(x + c[1] * base, y, z + c[2] * base)
		local to = Vector3.new(x + c[1] * top, y + height, z + c[2] * top)
		part(
			parent,
			Vector3.new(0.6, 0.6, (to - from).Magnitude),
			CFrame.lookAt(from, to) * CFrame.new(0, 0, -(to - from).Magnitude / 2),
			steel,
			Enum.Material.Metal
		)
	end
	for k = 1, 4 do -- cross braces
		local t = k / 5
		local w = (base + (top - base) * t) * 2
		part(
			parent,
			Vector3.new(w, 0.4, 0.4),
			CFrame.new(x, y + height * t, z + (base + (top - base) * t)),
			steel,
			Enum.Material.Metal
		)
		part(
			parent,
			Vector3.new(w, 0.4, 0.4),
			CFrame.new(x, y + height * t, z - (base + (top - base) * t)),
			steel,
			Enum.Material.Metal
		)
	end
	part(parent, Vector3.new(5, 2, 5), CFrame.new(x, y + height + 1, z), steel, Enum.Material.Metal)
end

-- The oil field goes on the first open, flat patch near the edge of the dunes: every derrick's spot clear
local OIL_SPOTS = { { 0, 0 }, { 150, 110 }, { 320, -10 }, { 100, -150 }, { 400, 170 } }
local function oilField(root: Instance)
	local folder = Instance.new("Model")
	folder.Name = "OilField"
	folder.LevelOfDetail = Enum.ModelLevelOfDetail.StreamingMesh
	local origin = nil
	for _, centre in { { 700, 1250 }, { -300, 1900 }, { 2000, 600 }, { -3600, 400 }, { 600, 300 } } do
		local ok = true
		for _, spot in OIL_SPOTS do
			local x, z = centre[1] + spot[1], centre[2] + spot[2]
			if not openGround(x, z) or slopeAt(x, z) > 0.08 then
				ok = false
				break
			end
		end
		if ok then
			origin = centre
			break
		end
	end
	if not origin then
		return -- nowhere flat enough: leave it out rather than put derricks on a slope
	end
	for _, spot in OIL_SPOTS do
		derrick(folder, origin[1] + spot[1], origin[2] + spot[2])
	end
	for i = 0, 2 do -- storage tanks
		local x, z = origin[1] + 220 + i * 30, origin[2] + 250
		post(folder, x, groundAt(x, z) - 1, z, 14, 22, Color3.fromRGB(214, 210, 200), Enum.Material.Metal)
	end
	folder.Parent = root
end

------------------------------------------------------------------------------------------------ build

function DesertScenery.build(): string
	local map = workspace:FindFirstChild("Map") or Instance.new("Folder")
	map.Name = "Map"
	map.Parent = workspace
	local old = map:FindFirstChild("Scenery")
	if old then
		old:Destroy()
	end
	local root = Instance.new("Folder")
	root.Name = "Scenery"
	local cells: { [string]: Model } = {}
	local rng = Random.new(DesertShape.SEED + 40)
	local counts = { cacti = 0, scrub = 0, boulders = 0 }
	local tries = 0
	while (counts.cacti < 1100 or counts.scrub < 1400 or counts.boulders < 320) and tries < 60000 do
		tries += 1
		local x, z = rng:NextNumber(-HALF, HALF), rng:NextNumber(-HALF, HALF)
		if openGround(x, z) then
			local roll = rng:NextNumber()
			local cell = cellFor(root, cells, x, z)
			if roll < 0.38 and counts.cacti < 1100 then
				saguaro(cell, x, z, rng)
				counts.cacti += 1
			elseif roll < 0.88 and counts.scrub < 1400 then
				scrub(cell, x, z, rng)
				counts.scrub += 1
			elseif counts.boulders < 320 then
				boulder(cell, x, z, rng)
				counts.boulders += 1
			end
		end
		if tries % 400 == 0 then
			task.wait()
		end
	end
	town(root)
	telegraphPoles(root)
	oilField(root)
	root.Parent = map
	local parts = 0
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			parts += 1
		end
	end
	return string.format(
		"scenery done: %d cacti, %d scrub, %d boulders, the town, poles, oil field; %d parts",
		counts.cacti,
		counts.scrub,
		counts.boulders,
		parts
	)
end

return DesertScenery
