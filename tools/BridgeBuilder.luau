--!strict
-- The strait bridges (docs/art/BRIDGE.md): one model, after the Severn Bridge, carrying a road from each landmass
-- to the central island. The model comes from tools/blender/bridge_generate.py (SevernBridge.fbx); its manifest
-- (tools/Manifests/Scenery/SevernBridge.luau) says where every part goes, its deck profile and its texture sets.
-- Run in Edit mode after StraitBuilder, one step at a time:
--   local B = require(game.ServerStorage.Tools.BridgeBuilder)
--   B.template(workspace.SevernBridge)   -- once per import: lays the parts out as ServerStorage.BridgeTemplate
--   B.skin({ Steel = { Color = id, Normal = id, Roughness = id, Metalness = id }, Concrete = ..., Road = ..., Cable = ... })
--   B.plan()                             -- finds where each crossing fits the real coastline (report only)
--   B.place()                            -- puts BridgeWest and BridgeEast in workspace.Map.Bridges
-- B.clear() removes the placed bridges. skin() can run before or after place(): it updates the template and any
-- placed copies. Without skin() the parts keep plain colours by texture set.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Strait = require(script.Parent.StraitBuilder)
local WorldEdge = require(ReplicatedStorage.Shared.WorldEdge)
local STUDS: number = require(ReplicatedStorage.Shared.Config.Scale).STUDS_PER_METRE
local Manifest = require(script.Parent.Manifests.Scenery.SevernBridge) :: any

local WATER = WorldEdge.WATER
local PROFILE = Manifest.profile
local TARGET_GAP = 1700 -- studs of water each crossing fits best (the anchorages then sit near the shores)
local PREFERRED_Z = -400 -- where both channels are about that wide, without the coastline noise
local SCAN_Z = { -1000, 1000, 20 } -- crossing lines tried (studs)
local SCAN_STEP = 4 -- studs between height samples across a channel
local SCAN_REACH = 3800 -- how far from the island centre to look for the far coast
local COAST_RUN = 150 -- studs of unbroken land that count as the coast (islets are shorter)
local SEA_RUN = 60 -- studs of unbroken water that end the island's shore
local DECK_STEP = 8 -- studs between clearance samples along the deck
local END_ALLOWANCE = 60 -- the last studs at each end may sit in rising ground (the abutment)
local ABUTMENT_INSET = 15 -- studs in from the deck's end where the abutment must be on land

-- Collision per part: what a jet (or a car on the deck) can hit. Precise decomposition, because a convex hull
-- would fill the window between the tower legs and span the gaps between far-apart pieces (both piers, both
-- anchorages, all the approach piers are one mesh each).
local SOLID = {
	Deck = true,
	TowerA = true,
	TowerB = true,
	TowerPiers = true,
	Anchorages = true,
	Approaches = true,
}

-- Looks before (or without) the PBR skin
type Look = { colour: Color3, material: Enum.Material }
local LOOKS: { [string]: Look } = {
	Steel = { colour = Color3.fromRGB(216, 212, 200), material = Enum.Material.SmoothPlastic },
	Concrete = { colour = Color3.fromRGB(150, 146, 136), material = Enum.Material.Concrete },
	Road = { colour = Color3.fromRGB(56, 56, 58), material = Enum.Material.Asphalt },
	Cable = { colour = Color3.fromRGB(200, 198, 188), material = Enum.Material.SmoothPlastic },
}
local LIGHT_LOOK: Look = { colour = Color3.fromRGB(255, 40, 30), material = Enum.Material.Neon }

export type Crossing = { name: string, cx: number, z: number, gap: number, report: string }
local planned: { Crossing } = {}

local BridgeBuilder = {}

local function folder(parent: Instance, name: string): Instance
	local existing = parent:FindFirstChild(name)
	if existing then
		return existing
	end
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local function v3(t: { number }): Vector3
	return Vector3.new(t[1], t[2], t[3])
end

-- Road surface height above the water at distance t (studs) from midspan: the deck's vertical curve
local function roadZ(t: number): number
	local s = t / (PROFILE.endY * STUDS)
	return (PROFILE.roadMid - (PROFILE.roadMid - PROFILE.roadEnd) * s * s) * STUDS
end

local function isLand(h: number): boolean
	return h > WATER + 0.1
end

-- Along the line at z, walking outward from the island (dir = -1 west, +1 east): the island's shore (the last
-- land before a long stretch of sea) and the far coast (the first long stretch of land after it). nil when the
-- line misses the island or never reaches a coast.
local function shores(z: number, dir: number): (number?, number?)
	local x = 200 * dir
	if not isLand(Strait.height(x, z)) then
		return nil, nil
	end
	local lastLand: number? = nil
	local seaFrom: number? = nil
	local island: number? = nil
	local landFrom: number? = nil
	while math.abs(x) < SCAN_REACH do
		local land = isLand(Strait.height(x, z))
		if not island then
			if land then
				lastLand, seaFrom = x, nil
			else
				seaFrom = seaFrom or x
				if math.abs(x - (seaFrom :: number)) >= SEA_RUN then
					island = lastLand
				end
			end
		else
			if land then
				landFrom = landFrom or x
				if math.abs(x - (landFrom :: number)) >= COAST_RUN then
					return island, landFrom
				end
			else
				landFrom = nil
			end
		end
		x += SCAN_STEP * dir
	end
	return island, nil
end

-- Checks a crossing centred at (cx, z): nil and a reason when it doesn't fit, else the worst clearance numbers.
local function check(cx: number, z: number): (boolean, string)
	local endY, towerY = PROFILE.endY * STUDS, PROFILE.towerY * STUDS
	local depth = (PROFILE.deckDepth + 0.25) * STUDS -- girder plus the walkway's underside
	for _, s in { -1, 1 } do
		local tx = cx + s * towerY
		for _, dz in { -18, 0, 18 } do
			if isLand(Strait.height(tx, z + dz)) then
				return false, `tower pier at x {math.round(tx)} would stand on land`
			end
		end
		local ax = cx + s * (endY - ABUTMENT_INSET)
		if not isLand(Strait.height(ax, z)) then
			return false, `abutment at x {math.round(ax)} would stand in the sea`
		end
	end
	local t = -endY + END_ALLOWANCE
	while t <= endY - END_ALLOWANCE do
		local under = roadZ(t) - depth
		for _, dz in { -16, 0, 16 } do
			local h = Strait.height(cx + t, z + dz)
			if h > under then
				return false,
					`ground at x {math.round(cx + t)} is {string.format("%.1f", h - under)} studs above the deck's underside`
			end
		end
		t += DECK_STEP
	end
	-- How deep each end sits in the ground (the abutment takes up to the deck's depth)
	local notes = {}
	for _, s in { -1, 1 } do
		local x = cx + s * (endY - ABUTMENT_INSET)
		local buried = Strait.height(x, z) - (roadZ(endY - ABUTMENT_INSET) - depth)
		local side = if s < 0 then "west end" else "east end"
		if buried > 0 then
			table.insert(notes, `{side} {string.format("%.1f", buried)} studs into the ground`)
		else
			table.insert(notes, `{side} {string.format("%.1f", -buried)} studs above the ground`)
		end
	end
	return true, table.concat(notes, ", ")
end

-- Finds the best crossing on one side (dir = -1 west, +1 east).
local function bestCrossing(name: string, dir: number): (Crossing?, string)
	local best: Crossing? = nil
	local bestScore = math.huge
	local tried, fitted = 0, 0
	local lastReason = "no line reached both shores"
	for z = SCAN_Z[1], SCAN_Z[2], SCAN_Z[3] do
		local island, coast = shores(z, dir)
		if island and coast then
			tried += 1
			local gap = math.abs(coast - island)
			local cx = (coast + island) / 2
			local ok, detail = check(cx, z)
			if ok then
				fitted += 1
				local score = math.abs(gap - TARGET_GAP) + 0.2 * math.abs(z - PREFERRED_Z)
				if score < bestScore then
					bestScore = score
					best = {
						name = name,
						cx = cx,
						z = z,
						gap = gap,
						report = `{name}: line z {z}, gap {math.round(gap)} (x {math.round(island)} to {math.round(
							coast
						)}), centre x {math.round(cx)}; {detail}`,
					}
				end
			else
				lastReason = `z {z}: {detail}`
			end
		end
	end
	if not best then
		return nil, `{name}: no crossing fits ({tried} lines reached both shores; last: {lastReason})`
	end
	return best, `{(best :: Crossing).report} [{fitted} of {tried} lines fit]`
end

function BridgeBuilder.plan(): string
	table.clear(planned)
	local lines = {}
	for _, side in { { "BridgeWest", -1 }, { "BridgeEast", 1 } } do
		local crossing, report = bestCrossing(side[1] :: string, side[2] :: number)
		if crossing then
			table.insert(planned, crossing)
		end
		table.insert(lines, report)
	end
	return table.concat(lines, "\n")
end

-- Lays the imported parts out as ServerStorage.BridgeTemplate: each where the manifest says, in the model's own
-- frame (origin at midspan on the water line, length along z). The import's scale comes from the deck's length.
function BridgeBuilder.template(kit: Instance): string
	local found: { [string]: MeshPart } = {}
	for _, d in kit:GetDescendants() do
		if d:IsA("MeshPart") then
			found[d.Name] = d
		end
	end
	local report = {}
	local missing = {}
	for _, entry in Manifest.parts do
		if not found[entry.name] then
			table.insert(missing, entry.name)
		end
	end
	if #missing > 0 then
		return `missing parts in the import: {table.concat(missing, ", ")}`
	end

	-- Scale: the deck's longest side against the manifest's length. A longest side that isn't z means the
	-- importer turned the axes.
	local deck = found.Deck
	local longest = math.max(deck.Size.X, deck.Size.Y, deck.Size.Z)
	local deckEntry
	for _, entry in Manifest.parts do
		if entry.name == "Deck" then
			deckEntry = entry
		end
	end
	local scale = deckEntry.size[3] * STUDS / longest
	table.insert(report, `import scale x{string.format("%.3f", scale)}`)
	local worst = 0
	local out = ServerStorage:FindFirstChild("BridgeTemplate")
	if out then
		out:Destroy()
	end
	local model = Instance.new("Model")
	model.Name = "BridgeTemplate"
	model.LevelOfDetail = Enum.ModelLevelOfDetail.StreamingMesh
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	for _, entry in Manifest.parts do
		local src = found[entry.name]
		local p = src:Clone()
		p:ClearAllChildren()
		p.Size = src.Size * scale
		p.CFrame = CFrame.new(v3(entry.centre) * STUDS) * src.CFrame.Rotation
		-- The part's world-aligned size should match the manifest's; if not, the axes were turned on import
		local r = p.CFrame
		local half = p.Size / 2
		local extent = Vector3.new(
			math.abs(r.RightVector.X) * half.X + math.abs(r.UpVector.X) * half.Y + math.abs(r.LookVector.X) * half.Z,
			math.abs(r.RightVector.Y) * half.X + math.abs(r.UpVector.Y) * half.Y + math.abs(r.LookVector.Y) * half.Z,
			math.abs(r.RightVector.Z) * half.X + math.abs(r.UpVector.Z) * half.Y + math.abs(r.LookVector.Z) * half.Z
		) * 2
		local want = v3(entry.size) * STUDS
		worst = math.max(worst, (extent - want).Magnitude / math.max(want.Magnitude, 1))
		p.Anchored = true
		p.TextureID = ""
		p.CanTouch = false
		p:SetAttribute("TextureSet", entry.set)
		p:SetAttribute("Kind", entry.kind)
		local look = if entry.kind == "Light" then LIGHT_LOOK else LOOKS[entry.set]
		p.Color = look.colour
		p.Material = look.material
		if SOLID[entry.name] then
			p.CanCollide = true
			p.CanQuery = true
			pcall(function()
				p.CollisionFidelity = Enum.CollisionFidelity.PreciseConvexDecomposition
			end)
		else
			p.CanCollide = false
			p.CanQuery = false
			pcall(function()
				p.CollisionFidelity = Enum.CollisionFidelity.Box
			end)
		end
		p.CastShadow = entry.kind ~= "Light"
		p.Parent = model
	end
	model.WorldPivot = CFrame.new()
	model.Parent = ServerStorage
	table.insert(report, `{#Manifest.parts} parts, {Manifest.triangles} triangles, {Manifest.length} m`)
	if worst > 0.02 then
		table.insert(
			report,
			`WARNING: part sizes differ from the manifest by up to {math.round(worst * 100)}%: the importer may have turned the axes (check Forward -Z / Up Y)`
		)
	else
		table.insert(report, "layout matches the manifest")
	end
	return "ServerStorage.BridgeTemplate: " .. table.concat(report, "; ")
end

-- Applies the PBR skin: maps = { [set] = { Color, Normal, Roughness, Metalness } } of uploaded image asset ids.
-- The bridge's UVs run past 0..1 (the textures tile), so the images repeat along the parts.
function BridgeBuilder.skin(maps: { [string]: { [string]: number } }): string
	local roots: { Instance } = {}
	local template = ServerStorage:FindFirstChild("BridgeTemplate")
	if template then
		table.insert(roots, template)
	end
	local map = workspace:FindFirstChild("Map")
	local bridges = map and map:FindFirstChild("Bridges")
	if bridges then
		for _, b in bridges:GetChildren() do
			table.insert(roots, b)
		end
	end
	if #roots == 0 then
		return "nothing to skin: run template() first"
	end
	local count = 0
	for _, root in roots do
		for _, p in root:GetDescendants() do
			if p:IsA("MeshPart") and p:GetAttribute("Kind") ~= "Light" then
				local set = p:GetAttribute("TextureSet") :: string?
				local m = set and maps[set]
				local old = p:FindFirstChildOfClass("SurfaceAppearance")
				if old then
					old:Destroy()
				end
				if m then
					local a = Instance.new("SurfaceAppearance")
					a.ColorMap = `rbxassetid://{m.Color}`
					a.NormalMap = `rbxassetid://{m.Normal}`
					a.RoughnessMap = `rbxassetid://{m.Roughness}`
					a.MetalnessMap = `rbxassetid://{m.Metalness}`
					a.Parent = p
					p.Color = Color3.new(1, 1, 1)
					count += 1
				end
			end
		end
	end
	return `skinned {count} parts in {#roots} model(s)`
end

-- Places BridgeWest and BridgeEast at the planned crossings (planning first if needed). Each turns 90 degrees
-- about y, so its length runs along world x, with its water line on the sea.
function BridgeBuilder.place(): string
	local template = ServerStorage:FindFirstChild("BridgeTemplate") :: Model?
	if not template then
		return "no ServerStorage.BridgeTemplate: run template() first"
	end
	local lines = {}
	if #planned == 0 then
		table.insert(lines, BridgeBuilder.plan())
	end
	local parent = folder(folder(workspace, "Map"), "Bridges")
	for _, c in planned do
		local existing = parent:FindFirstChild(c.name)
		if existing then
			existing:Destroy()
		end
		local m = (template :: Model):Clone()
		m.Name = c.name
		m:PivotTo(CFrame.new(c.cx, WATER, c.z) * CFrame.Angles(0, math.pi / 2, 0))
		m:SetAttribute("Gap", math.round(c.gap))
		m.Parent = parent
		table.insert(lines, `placed {c.name} at ({math.round(c.cx)}, {WATER}, {c.z})`)
	end
	if #planned == 0 then
		table.insert(lines, "nothing placed: no crossing fits")
	end
	return table.concat(lines, "\n")
end

function BridgeBuilder.clear(): string
	local map = workspace:FindFirstChild("Map")
	local bridges = map and map:FindFirstChild("Bridges")
	if bridges then
		bridges:Destroy()
	end
	return "bridges cleared"
end

return BridgeBuilder
