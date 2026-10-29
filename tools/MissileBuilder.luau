--!strict
-- Builds the missile models (ReplicatedStorage.Assets.Missiles.<Family>) that MissileViewController draws in
-- flight, from tools/blender/out/Missiles.fbx (tools/blender/missiles_generate.py). In Studio, Edit mode:
--   1. File → Import 3D → tools/blender/out/Missiles.fbx, as one Model (Merge Meshes off, Anchored on)
--   2. print(require(game.ServerStorage.Tools.MissileBuilder).install(workspace.Missiles))
-- The import is matched to the manifest (tools/Manifests/Missiles.luau) by where the six families' bodies sit
-- on their layout grid, which undoes any scale or axis change the importer made, as the Ground Roamer's
-- builder does with its wheels. The imported Model is left untouched.
--
-- Each family becomes a Model: Body (the PrimaryPart, anchored; the model's pivot is the missile's lengthwise
-- centre with the nose along -Z), Trim welded to it, a Tail attachment at the nozzle exit and a Length
-- attribute (metres) that the game scales against each missile's own WeaponData Length.
-- install() never deletes: a model it replaces moves to ServerStorage.ReplacedModels.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local WeaponData = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("WeaponData"))

local LOOK: { [string]: { colour: Color3, material: Enum.Material } } = {
	Body = { colour = Color3.fromRGB(225, 225, 220), material = Enum.Material.SmoothPlastic },
	Trim = { colour = Color3.fromRGB(62, 64, 68), material = Enum.Material.SmoothPlastic },
}

local MissileBuilder = {}

local function v3(t: { number }): Vector3
	return Vector3.new(t[1], t[2], t[3])
end

-- Orthonormal frame from a forward and a right direction (x right, y up, z back)
local function frame(forward: Vector3, right: Vector3): CFrame
	local look = forward.Unit
	local r = (right - look * right:Dot(look)).Unit
	return CFrame.fromMatrix(Vector3.zero, r, r:Cross(look))
end

local function mean(points: { Vector3 }): Vector3
	local sum = Vector3.zero
	for _, p in points do
		sum += p
	end
	return sum / #points
end

-- Imported MeshParts by manifest name. The importer names parts after the FBX objects; some versions wrap
-- each in a Model of that name instead.
local function findParts(source: Instance, entries: { [string]: any }): { [string]: MeshPart }
	local parts: { [string]: MeshPart } = {}
	for _, d in source:GetDescendants() do
		if d:IsA("MeshPart") then
			local name = if entries[d.Name]
				then d.Name
				elseif d.Parent and entries[d.Parent.Name] then d.Parent.Name
				else nil
			if name then
				parts[name] = d
			end
		end
	end
	return parts
end

-- Puts a model in a folder; one it replaces moves to ServerStorage.ReplacedModels (nothing is deleted).
local function replace(folder: Instance, model: Model)
	local existing = folder:FindFirstChild(model.Name)
	if existing then
		local backups = ServerStorage:FindFirstChild("ReplacedModels")
		if not backups then
			backups = Instance.new("Folder")
			backups.Name = "ReplacedModels"
			backups.Parent = ServerStorage
		end
		existing.Name = `{model.Name}_Missiles_{os.date("!%Y%m%d_%H%M%S")}`
		existing.Parent = backups
	end
	model.Parent = folder
end

local function folderIn(parent: Instance, name: string): Instance
	local folder = parent:FindFirstChild(name)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = name
		folder.Parent = parent
	end
	return folder :: Instance
end

function MissileBuilder.install(source: Instance): string
	local manifestModule = script.Parent.Manifests:FindFirstChild("Missiles")
	if not manifestModule then
		return "no manifest tools/Manifests/Missiles.luau"
	end
	local manifest = require(manifestModule:Clone() :: any) :: any -- a fresh copy, so a regenerated one is picked up
	local entries: { [string]: any } = {}
	for _, entry in manifest.parts do
		entries[entry.name] = entry
	end
	local parts = findParts(source, entries)
	for _, family in WeaponData.MISSILE_MODELS do
		for _, role in { "Body", "Trim" } do
			if not parts[`{family}_{role}`] then
				return `missing {family}_{role} in the import`
			end
		end
	end

	-- Fit the import to the manifest by the bodies' layout: the second row of families lies ahead of the
	-- first (forward), and each row runs left to right (right).
	local rows: { [number]: { expected: { Vector3 }, imported: { Vector3 } } } = {}
	local cols: { [number]: { expected: { Vector3 }, imported: { Vector3 } } } = {}
	for _, family in WeaponData.MISSILE_MODELS do
		local name = `{family}_Body`
		local pivot = v3(entries[name].pivot)
		local e, i = v3(entries[name].bounds.centre), parts[name].Position
		local row, col = math.round(-pivot.Z), math.round(pivot.X)
		rows[row] = rows[row] or { expected = {}, imported = {} }
		cols[col] = cols[col] or { expected = {}, imported = {} }
		table.insert(rows[row].expected, e)
		table.insert(rows[row].imported, i)
		table.insert(cols[col].expected, e)
		table.insert(cols[col].imported, i)
	end
	local function spread(groups: { [number]: any }, key: string): Vector3
		local lo, hi = math.huge, -math.huge
		for k in groups do
			lo, hi = math.min(lo, k), math.max(hi, k)
		end
		return mean(groups[hi][key]) - mean(groups[lo][key])
	end
	local fe, fi = spread(rows, "expected"), spread(rows, "imported")
	local re, ri = spread(cols, "expected"), spread(cols, "imported")
	local rotation = frame(fe, re) * frame(fi, ri):Inverse()
	local scale = (fe.Magnitude / fi.Magnitude + re.Magnitude / ri.Magnitude) / 2
	local sum, count = Vector3.zero, 0
	for name, part in parts do
		sum += v3(entries[name].bounds.centre) - rotation * (part.Position * scale)
		count += 1
	end
	local offset = sum / count
	local residual = 0
	for name, part in parts do
		residual = math.max(
			residual,
			(rotation * (part.Position * scale) + offset - v3(entries[name].bounds.centre)).Magnitude
		)
	end

	local assets = folderIn(ReplicatedStorage, "Assets")
	local store = folderIn(assets, "Missiles")
	local built = {}
	for _, family in WeaponData.MISSILE_MODELS do
		local body = entries[`{family}_Body`]
		local origin = v3(body.pivot) -- the family's lengthwise centre in the layout
		local model = Instance.new("Model")
		model.Name = family
		model:SetAttribute("Length", body.length)
		local placed: { [string]: MeshPart } = {}
		for _, role in { "Body", "Trim" } do
			local src = parts[`{family}_{role}`]
			local part = src:Clone()
			part:ClearAllChildren()
			part.Name = role
			part.Size = src.Size * scale
			part.CFrame = CFrame.new(rotation * (src.Position * scale) + offset - origin)
				* rotation
				* src.CFrame.Rotation
			part.Anchored = role == "Body"
			part.Massless = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.TextureID = ""
			part.Color = LOOK[role].colour
			part.Material = LOOK[role].material
			part.Parent = model
			placed[role] = part
		end
		local weld = Instance.new("WeldConstraint")
		weld.Part0, weld.Part1 = placed.Body, placed.Trim
		weld.Parent = placed.Trim
		placed.Body.PivotOffset = placed.Body.CFrame:Inverse() -- pivot at the missile's centre, nose -Z
		model.PrimaryPart = placed.Body
		local tail = Instance.new("Attachment")
		tail.Name = "Tail"
		tail.CFrame = placed.Body.CFrame:Inverse() * CFrame.new(v3(manifest.attachments[`{family}_Tail`]) - origin)
		tail.Parent = placed.Body
		replace(store, model)
		table.insert(built, family)
	end

	return string.format(
		"built ReplicatedStorage.Assets.Missiles: %s; scale x%.3f, layout fit within %.3f m%s",
		table.concat(built, ", "),
		scale,
		residual,
		if residual > 0.05 then " (WARNING: parts don't match the manifest well; check the import)" else ""
	)
end

return MissileBuilder
