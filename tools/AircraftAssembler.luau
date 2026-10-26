--!strict
-- Turns an imported jet into a game-ready model (docs/art/AIRCRAFT_PIPELINE.md §4). In Studio, Edit mode:
--   1. File → Import 3D → tools/blender/out/<Id>_base.fbx, imported as one Model into the workspace
--   2. print(require(game.ServerStorage.Tools.AircraftAssembler).install("F5E", workspace.F5E_base))
--   3. Read the report, play-test, save the place
-- The manifest (tools/Manifests/<Id>.luau, written by the Blender generator) says where every part
-- belongs. The imported MeshParts are matched to it by name, so whatever scale, axes or pivots the
-- importer produced, the result is exact: parts are placed by their manifest bounds, control surfaces
-- and gear hinge on Motor6Ds at the manifest's hinge points, and Root, Hull, hitboxes and attachments
-- come from the manifest too. The imported Model is left untouched.
-- install() never deletes: a model it replaces moves to ServerStorage.ReplacedModels.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Contract = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AircraftModelContract"))

local STUDS = 1 / 0.28

-- Untextured look per texture set, until the PBR skins exist
local SET_LOOK: { [string]: { color: Color3, material: Enum.Material, transparency: number?, reflectance: number? } } =
	{
		Body = { color = Color3.fromRGB(140, 150, 160), material = Enum.Material.SmoothPlastic },
		Wings = { color = Color3.fromRGB(134, 144, 154), material = Enum.Material.SmoothPlastic },
		Details = { color = Color3.fromRGB(70, 70, 75), material = Enum.Material.Metal },
		-- Not Roblox's Glass material: it draws opaque over water
		Glass = {
			color = Color3.fromRGB(40, 55, 70),
			material = Enum.Material.SmoothPlastic,
			transparency = 0.6,
			reflectance = 0.15,
		},
	}
local HIDDEN_KINDS = { Gear = true, GearWheel = true, GearDoor = true } -- gear stays up in flight

local AircraftAssembler = {}

local function v3(t: { number }): Vector3
	return Vector3.new(t[1], t[2], t[3])
end

local function loadManifest(id: string): any
	local module = script.Parent:FindFirstChild("Manifests") and script.Parent.Manifests:FindFirstChild(id)
	assert(module and module:IsA("ModuleScript"), `No manifest tools/Manifests/{id}.luau`)
	return require(module:Clone() :: any) -- a fresh copy, so a regenerated manifest is picked up
end

-- Imported MeshParts by manifest name. The importer names parts after the FBX objects; some versions
-- wrap each in a Model of that name instead.
local function findParts(source: Instance, manifest: any): ({ [string]: MeshPart }, { string })
	local wanted: { [string]: boolean } = {}
	for _, entry in manifest.parts do
		wanted[entry.name] = true
	end
	local found: { [string]: MeshPart } = {}
	local notes = {}
	local candidates = source:GetDescendants()
	table.insert(candidates, source)
	for _, d in candidates do
		if d:IsA("MeshPart") then
			local name = if wanted[d.Name]
				then d.Name
				elseif d.Parent and wanted[d.Parent.Name] then d.Parent.Name
				else nil
			if name and found[name] then
				table.insert(notes, `duplicate imported part {name}; using the first`)
			elseif name then
				found[name] = d
			end
		end
	end
	return found, notes
end

-- An orthonormal frame from a forward and a right vector (nose along -Z, as the game expects)
local function frame(forward: Vector3, right: Vector3): CFrame
	local f = forward.Unit
	local r = (right - f * right:Dot(f)).Unit
	local u = (-f):Cross(r)
	return CFrame.fromMatrix(Vector3.zero, r, u)
end

type Fit = { rotation: CFrame, scale: number, offset: Vector3, residual: number }

-- The rotation, scale and offset that take the imported layout onto the manifest's (in studs)
local function fitLayout(parts: { [string]: MeshPart }, manifest: any): Fit
	local expected: { [string]: Vector3 } = {}
	for _, entry in manifest.parts do
		expected[entry.name] = v3(entry.bounds.centre) * STUDS
	end
	local function mid(a: string, b: string, t: { [string]: Vector3 }): Vector3
		return (t[a] + t[b]) / 2
	end
	local imported: { [string]: Vector3 } = {}
	for name, part in parts do
		imported[name] = part.Position
	end
	local fe = expected.Pitot - mid("NozzleL", "NozzleR", expected)
	local re = expected.WingR - expected.WingL
	local fi = imported.Pitot - mid("NozzleL", "NozzleR", imported)
	local ri = imported.WingR - imported.WingL
	local rotation = frame(fe, re) * frame(fi, ri):Inverse()
	local scale = (fe.Magnitude / fi.Magnitude + re.Magnitude / ri.Magnitude) / 2

	local sum, count = Vector3.zero, 0
	for name, c in imported do
		sum += expected[name] - rotation * (c * scale)
		count += 1
	end
	local offset = sum / count
	local residual = 0
	for name, c in imported do
		residual = math.max(residual, (rotation * (c * scale) + offset - expected[name]).Magnitude)
	end
	return { rotation = rotation, scale = scale, offset = offset, residual = residual }
end

local function invisibleBox(name: string, size: Vector3, at: Vector3, parent: Instance, root: BasePart): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = CFrame.new(at)
	p.Transparency = 1
	p.Massless = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Parent = parent
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = p
	weld.Parent = p
	return p
end

-- Builds the game model (not parented). Returns it with a report, or nil and the problems.
function AircraftAssembler.build(id: string, source: Instance): (Model?, { string })
	local manifest = loadManifest(id)
	local parts, report = findParts(source, manifest)
	local missing = {}
	for _, entry in manifest.parts do
		if not parts[entry.name] then
			table.insert(missing, entry.name)
		end
	end
	for _, needed in { "Pitot", "NozzleL", "NozzleR", "WingL", "WingR" } do
		if not parts[needed] then
			return nil, { `the import has no {needed} part, which is needed to line the model up` }
		end
	end
	if #missing > 0 then
		return nil, { `the import is missing {#missing} parts: {table.concat(missing, ", ")}` }
	end

	local fit = fitLayout(parts, manifest)
	local turned = fit.rotation.LookVector:Dot(Vector3.new(0, 0, -1)) < 0.999
		or fit.rotation.UpVector:Dot(Vector3.yAxis) < 0.999
	table.insert(report, `scale x{string.format("%.3f", fit.scale)}{if turned then ", axes corrected" else ""}`)
	table.insert(report, `layout fit within {string.format("%.2f", fit.residual)} studs`)
	if fit.residual > 0.5 then
		table.insert(report, "WARNING: parts don't match the manifest layout well; check the import")
	end

	local model = Instance.new("Model")
	model.Name = id
	model:SetAttribute("Assembled", true)
	model:SetAttribute("Triangles", manifest.triangles)

	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(1, 1, 1)
	root.CFrame = CFrame.new()
	root.Transparency = 1
	root.CanCollide = false
	root.CanTouch = false
	root.CanQuery = false
	root.Parent = model
	model.PrimaryPart = root

	for _, entry in manifest.parts do
		local src = parts[entry.name]
		local part = src:Clone()
		part:ClearAllChildren() -- importer extras (materials, textures)
		part.Size = src.Size * fit.scale
		part.CFrame = CFrame.new(v3(entry.bounds.centre) * STUDS) * fit.rotation * src.CFrame.Rotation
		part.Anchored = false
		part.Massless = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.TextureID = ""
		pcall(function()
			part.CollisionFidelity = Enum.CollisionFidelity.Box
			part.RenderFidelity = Enum.RenderFidelity.Automatic
		end)
		local look = SET_LOOK[entry.set] or SET_LOOK.Body
		part.Color = look.color
		part.Material = look.material
		part.Transparency = look.transparency or 0
		part.Reflectance = look.reflectance or 0
		if HIDDEN_KINDS[entry.kind] then
			part.Transparency = 1
		end
		part:SetAttribute("TextureSet", entry.set)
		part:SetAttribute("Kind", entry.kind)
		part.Parent = model

		if entry.hinge then
			local pivot = CFrame.new(v3(entry.pivot) * STUDS)
			local motor = Instance.new("Motor6D")
			motor.Name = "Hinge"
			motor.Part0 = root
			motor.Part1 = part
			motor.C0 = pivot
			motor.C1 = part.CFrame:Inverse() * pivot
			motor.Parent = part
			part:SetAttribute("Control", entry.hinge.control)
			part:SetAttribute("HingeAxis", v3(entry.hinge.axis).Unit)
			part:SetAttribute("HingeMin", entry.hinge.min)
			part:SetAttribute("HingeMax", entry.hinge.max)
		else
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = part
			weld.Parent = part
		end
	end

	local hull = invisibleBox("Hull", v3(manifest.hull.size) * STUDS, v3(manifest.hull.at) * STUDS, model, root)
	hull.CanCollide = true
	hull.CanTouch = true

	local hitboxes = Instance.new("Folder")
	hitboxes.Name = "Hitboxes"
	hitboxes.Parent = model
	for name, box in manifest.hitboxes do
		local p = invisibleBox(name, v3(box.size) * STUDS, v3(box.at) * STUDS, hitboxes, root)
		p.CanQuery = true
	end

	for name, at in manifest.attachments do
		local a = Instance.new("Attachment")
		a.Name = name
		a.Position = v3(at) * STUDS
		a.Parent = root
	end

	table.insert(report, `{#manifest.parts} parts, {manifest.triangles} triangles`)
	return model, report
end

-- Builds the model and puts it in ReplicatedStorage.Assets.Aircraft.<id>. Returns a report.
function AircraftAssembler.install(id: string, source: Instance): string
	local model, report = AircraftAssembler.build(id, source)
	if not model then
		return `{id}: FAILED\n  - {table.concat(report, "\n  - ")}`
	end
	local problems = Contract.validate(model)
	if #problems > 0 then
		model:Destroy()
		return `{id}: FAILED the model contract\n  - {table.concat(problems, "\n  - ")}`
	end

	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local folder = assets and assets:FindFirstChild("Aircraft")
	assert(folder, "ReplicatedStorage.Assets.Aircraft is missing")
	local existing = folder:FindFirstChild(id)
	if existing then
		local backups = ServerStorage:FindFirstChild("ReplacedModels")
		if not backups then
			backups = Instance.new("Folder")
			backups.Name = "ReplacedModels"
			backups.Parent = ServerStorage
		end
		existing.Name = `{id}_{os.date("!%Y%m%d_%H%M%S")}`
		existing.Parent = backups
		table.insert(report, `the previous model moved to ServerStorage.ReplacedModels.{existing.Name}`)
	end
	model.Parent = folder
	return `{id}: installed\n  - {table.concat(report, "\n  - ")}`
end

return AircraftAssembler
