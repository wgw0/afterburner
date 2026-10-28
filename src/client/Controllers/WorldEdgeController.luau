--!strict
-- The world past the map's edges (MAP-03), all client-side and never collidable or queryable.
--   Outside plain: flat slabs from the terrain's edge out to FAR, land where the coasts run on and sea
--     elsewhere (WorldEdge), so looking outward you see the world carry on into the haze instead of the
--     terrain ending in the void. A part can't be bigger than 2,048 studs, but a SpecialMesh can scale its
--     look far past that, so eight static parts stand in for an endless world.
--   Underlay: the same land and sea colours drawn under the terrain, below the sea floor, in bands that
--     follow the coasts. Terrain that hasn't streamed in yet shows as flat country instead of the void.
--   Border: red diagonal stripes drifting across the edge of the play area and the ceiling, like
--     Minecraft's world border. Only a patch around the point nearest you is drawn, fading out toward its
--     rim, and the whole patch fades in from SHOW_RANGE away. It doesn't stop you: the HUD's RETURN TO
--     BATTLE AREA countdown (and the server, after 10 s) does that.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Scale = require(Shared.Config.Scale)
local WorldEdge = require(Shared.WorldEdge)

local TILE = 2048 -- the largest a part can be
local FAR = 42000 -- how far the plain runs out (studs from the centre)
local LAND = Color3.fromRGB(98, 122, 56)
local SEA = Color3.fromRGB(34, 92, 104)
local LAND_DEPTH = 11.2 -- land reaches below sea level, so a coast shows a bank, not a gap
local UNDERLAY = -11.2 -- top of the underlay: below the sea floor and the terrain shell, so it never shows through
local UNDERLAY_BAND = 288 -- z-depth of each underlay band (the coasts are straight within one)

local LIMIT = Scale.MAP_HALF_EXTENT
local CEILING = Scale.CEILING
local FLOOR = -8.4
local SHOW_RANGE = 840 -- the border starts to show this far away
local OPACITY = 0.9 -- at the border itself, in the middle of the patch
local STRIPES = "rbxassetid://72392086444235" -- tools/blender/out/textures/Border_Stripes.png
local BORDER_TILE = 112 -- border tile size, and one repeat of the stripe texture, so tiles join up
local WALL_TILES = 6 -- border tiles each way from the point nearest the camera
local PATCH_RADIUS = BORDER_TILE * WALL_TILES -- the patch fades out by here
local DRIFT = 11.2 -- studs per second the stripes slide along

local WorldEdgeController = {
	Priority = 40,
	connection = nil :: RBXScriptConnection?, -- kept so an Edit-mode preview can be switched off
}

local folder: Folder

local function part(name: string): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = folder
	return p
end

-- Outside plain ---------------------------------------------------------------------------------------

-- One flat slab, drawn at any size: the part stays small and its mesh is scaled up.
local function slab(x0: number, x1: number, z0: number, z1: number, land: boolean, underlay: boolean?)
	if x1 - x0 < 1 or z1 - z0 < 1 then
		return
	end
	local top = if underlay then UNDERLAY elseif land then WorldEdge.PLAIN_HEIGHT else WorldEdge.WATER - 0.1
	local depth = if land and not underlay then LAND_DEPTH else 2
	local p = part("Plain")
	p.Size = Vector3.new(TILE, depth, TILE)
	p.Position = Vector3.new((x0 + x1) / 2, top - depth / 2, (z0 + z1) / 2)
	p.Color = if land then LAND else SEA
	-- Matte: SmoothPlastic's highlight lit each slab differently, so the seams between them showed
	p.Material = if land then Enum.Material.Fabric else Enum.Material.SmoothPlastic
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Brick
	mesh.Scale = Vector3.new((x1 - x0) / TILE, 1, (z1 - z0) / TILE)
	mesh.Parent = p
end

-- A band of the outside world from x0 to x1, split where the coasts run through it.
local function band(x0: number, x1: number, z0: number, z1: number, coastZ: number)
	local west, east = WorldEdge.outsideCoastX(coastZ)
	slab(x0, math.min(x1, west), z0, z1, true)
	slab(math.max(x0, west), math.min(x1, east), z0, z1, false)
	slab(math.max(x0, east), x1, z0, z1, true)
end

local function buildUnderlay()
	local half = WorldEdge.TERRAIN_HALF
	for z0 = -half, half - 1, UNDERLAY_BAND do
		local z1 = z0 + UNDERLAY_BAND
		local west, east = WorldEdge.coastX((z0 + z1) / 2)
		west, east = math.clamp(west, -half, half), math.clamp(east, -half, half)
		slab(-half, west, z0, z1, true, true)
		slab(west, east, z0, z1, false, true)
		slab(east, half, z0, z1, true, true)
	end
end

local function buildPlain()
	local half = WorldEdge.TERRAIN_HALF
	band(-FAR, FAR, -FAR, -half, -half) -- north, with the channel running on
	band(-FAR, FAR, half, FAR, half) -- south: open sea between the receding coasts
	band(-FAR, -half, -half, half, 0) -- west and east beside the terrain
	band(half, FAR, -half, half, 0)
end

-- Border -------------------------------------------------------------------------------------------------

-- One side of the play area: a plane at `offset` along `normal`, spanning [lo, hi] in two directions.
type Wall = {
	normal: Vector3, -- points out of the play area
	offset: number,
	u: Vector3,
	v: Vector3,
	uRange: { number },
	vRange: { number },
	tiles: { Part },
	textures: { { Texture } }, -- each tile's two faces, so the stripes show from either side
	cell: Vector2?,
}

local walls: { Wall } = {}

local function wall(normal: Vector3, u: Vector3, v: Vector3, offset: number, vRange: { number }): Wall
	local w: Wall = {
		normal = normal,
		offset = offset,
		u = u,
		v = v,
		uRange = { -LIMIT, LIMIT },
		vRange = vRange,
		tiles = {},
		textures = {},
		cell = nil,
	}
	for _ = 1, (2 * WALL_TILES + 1) ^ 2 do
		local p = part("Border")
		p.Transparency = 1
		local faces = {}
		for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
			local t = Instance.new("Texture")
			t.Texture = STRIPES
			t.Face = face
			t.StudsPerTileU = BORDER_TILE
			t.StudsPerTileV = BORDER_TILE
			t.Transparency = 1
			t.Parent = p
			table.insert(faces, t)
		end
		table.insert(w.tiles, p)
		table.insert(w.textures, faces)
	end
	table.insert(walls, w)
	return w
end

-- Places a wall's tiles on the grid around the point nearest the camera, clipped to the wall's extent.
local function layWall(w: Wall, cu: number, cv: number)
	local n = 0
	for a = cu - WALL_TILES, cu + WALL_TILES do
		for b = cv - WALL_TILES, cv + WALL_TILES do
			n += 1
			local p = w.tiles[n]
			local u0 = math.max(w.uRange[1] + a * BORDER_TILE, w.uRange[1])
			local u1 = math.min(w.uRange[1] + (a + 1) * BORDER_TILE, w.uRange[2])
			local v0 = math.max(w.vRange[1] + b * BORDER_TILE, w.vRange[1])
			local v1 = math.min(w.vRange[1] + (b + 1) * BORDER_TILE, w.vRange[2])
			if u1 - u0 < 1 or v1 - v0 < 1 then
				p:SetAttribute("Off", true)
				continue
			end
			p:SetAttribute("Off", nil)
			local centre = w.normal * w.offset + w.u * ((u0 + u1) / 2) + w.v * ((v0 + v1) / 2)
			p.CFrame = CFrame.fromMatrix(centre, w.u, w.v)
			p.Size = Vector3.new(u1 - u0, v1 - v0, 1)
		end
	end
end

local function updateWalls(camera: Vector3, clock: number)
	local drift = (clock * DRIFT) % BORDER_TILE
	for _, w in walls do
		local distance = math.abs(w.offset - camera:Dot(w.normal))
		local alpha = math.clamp(1 - distance / SHOW_RANGE, 0, 1)
		if alpha <= 0 then
			if w.cell then
				w.cell = nil
				for n, faces in w.textures do
					faces[1].Transparency, faces[2].Transparency = 1, 1
					w.tiles[n].Transparency = 1
				end
			end
			continue
		end
		local cu = math.floor((camera:Dot(w.u) - w.uRange[1]) / BORDER_TILE)
		local cv = math.floor((camera:Dot(w.v) - w.vRange[1]) / BORDER_TILE)
		local cell = Vector2.new(cu, cv)
		if w.cell ~= cell then
			w.cell = cell
			layWall(w, cu, cv)
		end
		-- Fade each tile by how far it is from the point on the wall nearest the camera
		local nearest = camera - w.normal * (camera:Dot(w.normal) - w.offset)
		for n, p in w.tiles do
			local faces = w.textures[n]
			local fade = if p:GetAttribute("Off")
				then 0
				else math.clamp(1 - (p.Position - nearest).Magnitude / PATCH_RADIUS, 0, 1)
			local transparency = 1 - OPACITY * alpha * fade * fade * (3 - 2 * fade)
			for _, t in faces do
				t.Transparency = transparency
				t.OffsetStudsU = drift
			end
			-- A fully transparent part doesn't draw its textures, so a shown tile is all but invisible
			-- instead; a hidden one goes fully transparent and isn't drawn at all
			p.Transparency = if transparency < 0.999 then 0.99 else 1
		end
	end
end

function WorldEdgeController:Start()
	folder = Instance.new("Folder")
	folder.Name = "WorldEdge"
	folder.Parent = workspace

	buildPlain()
	buildUnderlay()

	local x, y, z = Vector3.xAxis, Vector3.yAxis, Vector3.zAxis
	local height = { FLOOR, CEILING }
	wall(x, z, y, LIMIT, height)
	wall(-x, z, y, LIMIT, height)
	wall(z, x, y, LIMIT, height)
	wall(-z, x, y, LIMIT, height)
	wall(y, x, z, CEILING, { -LIMIT, LIMIT })

	WorldEdgeController.connection = RunService.RenderStepped:Connect(function()
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end
		updateWalls(camera.CFrame.Position, os.clock())
	end)
end

return WorldEdgeController
