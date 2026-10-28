--!strict
-- Builds the Ground Roamer's template (DEVELOPMENT.md §36) from its imported FBX, for GroundRoamerService:
-- ServerStorage.Vehicles.GroundRoamer. Run in Studio Edit mode after importing
-- tools/blender/out/GroundRoamer.fbx (and uploading its textures):
--   local B = require(game.ServerStorage.Tools.GroundRoamerBuilder)
--   B.template(workspace.GroundRoamer, maps)   -- maps optional; see below
-- The import is matched to the manifest (tools/Manifests/Vehicles/GroundRoamer.luau) by the four wheels, which
-- undoes any scale or axis change the importer made, then each part is placed where the manifest says.
--
-- The template: an invisible Root (the collision box; its pivot on the ground midway between the axles) and a
-- Ballast below it that holds the centre of mass 0.6 m up (as Shared/GroundVehicle's tests assume); the visible
-- parts welded on, massless and without collision; each wheel on a Motor6D named Wheel<FL|FR|RL|RR> that
-- DriveController turns and spins; two headlamp SpotLights; and Skins/<skin>/<set> SurfaceAppearances.
--
-- maps: { [skin]: { [set]: { Color: number, Normal: number, Roughness: number, Metalness: number } } } with
-- sets Body, Canvas and Details per skin, plus maps.Decals = { Color = ..., ... } shared by every skin.

local ServerStorage = game:GetService("ServerStorage")

local manifest = require(script.Parent.Manifests.Vehicles.GroundRoamer) :: any

local GroundRoamerBuilder = {}

local ROOT_SIZE = Vector3.new(1.6, 0.7, 3.5)
local ROOT_CENTRE = Vector3.new(0, 0.85, -0.03) -- body box from 0.5 m to 1.2 m up
local BALLAST_SIZE = Vector3.new(1.0, 0.2, 2.0)
local BALLAST_CENTRE = Vector3.new(0, 0.35, 0)
local ROOT_DENSITY, BALLAST_DENSITY = 1, 9.8 -- puts the centre of mass at 0.6 m

local LOOK: { [string]: { colour: Color3, material: Enum.Material, transparency: number? } } = {
	Body = { colour = Color3.fromRGB(70, 80, 62), material = Enum.Material.SmoothPlastic },
	Canvas = { colour = Color3.fromRGB(96, 98, 76), material = Enum.Material.Fabric },
	Details = { colour = Color3.fromRGB(40, 40, 40), material = Enum.Material.SmoothPlastic },
	Glass = { colour = Color3.fromRGB(40, 54, 62), material = Enum.Material.SmoothPlastic, transparency = 0.55 },
	Decals = { colour = Color3.fromRGB(230, 230, 224), material = Enum.Material.SmoothPlastic },
}

local function v3(t: { number }): Vector3
	return Vector3.new(t[1], t[2], t[3])
end

-- Orthonormal frame from a forward and a right direction (x right, y up, z back)
local function frame(forward: Vector3, right: Vector3): CFrame
	local look = forward.Unit
	local r = (right - look * right:Dot(look)).Unit
	return CFrame.fromMatrix(Vector3.zero, r, r:Cross(look))
end

local function centreOf(centres: { [string]: Vector3 }, a: string, b: string): Vector3
	return (centres[a] + centres[b]) / 2
end

function GroundRoamerBuilder.template(kit: Instance, maps: any?): string
	local entries: { [string]: any } = {}
	for _, entry in manifest.parts do
		entries[entry.name] = entry
	end
	local parts: { [string]: MeshPart } = {}
	for _, d in kit:GetDescendants() do
		if d:IsA("MeshPart") and entries[d.Name] then
			parts[d.Name] = d
		end
	end
	for _, name in { "WheelFL", "WheelFR", "WheelRL", "WheelRR", "Body" } do
		if not parts[name] then
			return `missing {name} in the import`
		end
	end

	-- Fit the import to the manifest by the wheels: rotation, scale and offset
	local expected, imported = {}, {}
	for name, part in parts do
		expected[name] = v3(entries[name].bounds.centre)
		imported[name] = part.Position
	end
	local fe = centreOf(expected, "WheelFL", "WheelFR") - centreOf(expected, "WheelRL", "WheelRR")
	local re = centreOf(expected, "WheelFR", "WheelRR") - centreOf(expected, "WheelFL", "WheelRL")
	local fi = centreOf(imported, "WheelFL", "WheelFR") - centreOf(imported, "WheelRL", "WheelRR")
	local ri = centreOf(imported, "WheelFR", "WheelRR") - centreOf(imported, "WheelFL", "WheelRL")
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

	local model = Instance.new("Model")
	model.Name = manifest.airframe
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = ROOT_SIZE
	root.CFrame = CFrame.new(ROOT_CENTRE)
	root.Transparency = 1
	root.CanCollide = true
	root.CustomPhysicalProperties = PhysicalProperties.new(ROOT_DENSITY, 0.3, 0.2)
	root.PivotOffset = CFrame.new(-ROOT_CENTRE) -- the model's pivot: on the ground between the axles
	root.Parent = model
	model.PrimaryPart = root
	local ballast = Instance.new("Part")
	ballast.Name = "Ballast"
	ballast.Size = BALLAST_SIZE
	ballast.CFrame = CFrame.new(BALLAST_CENTRE)
	ballast.Transparency = 1
	ballast.CanCollide = false
	ballast.CanQuery = false
	ballast.CanTouch = false
	ballast.CustomPhysicalProperties = PhysicalProperties.new(BALLAST_DENSITY, 0.3, 0.2)
	ballast.Parent = model
	local weld = Instance.new("WeldConstraint")
	weld.Part0, weld.Part1 = root, ballast
	weld.Parent = ballast

	for name, src in parts do
		local entry = entries[name]
		local part = src:Clone()
		part:ClearAllChildren()
		part.Size = src.Size * scale
		part.CFrame = CFrame.new(rotation * (src.Position * scale) + offset) * rotation * src.CFrame.Rotation
		part.Anchored = false
		part.Massless = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.TextureID = ""
		local look = LOOK[entry.set] or LOOK.Details
		part.Color = look.colour
		part.Material = look.material
		part.Transparency = look.transparency or 0
		part:SetAttribute("TextureSet", entry.set)
		part.Parent = model
		if entry.kind == "Wheel" then
			local hub = CFrame.new(v3(entry.pivot))
			local motor = Instance.new("Motor6D")
			motor.Name = name
			motor.Part0, motor.Part1 = root, part
			motor.C0 = root.CFrame:Inverse() * hub
			motor.C1 = part.CFrame:Inverse() * hub
			motor.Parent = root
		else
			local w = Instance.new("WeldConstraint")
			w.Part0, w.Part1 = root, part
			w.Parent = part
		end
	end

	-- Headlamps (L switches them, in DriveController)
	for _, side in { "HeadlampL", "HeadlampR" } do
		local at = manifest.attachments[side]
		if at then
			local attachment = Instance.new("Attachment")
			attachment.Name = side
			attachment.CFrame = root.CFrame:Inverse() * CFrame.new(v3(at))
			attachment.Parent = root
			local lamp = Instance.new("SpotLight")
			lamp.Name = "Beam"
			lamp.Face = Enum.NormalId.Front
			lamp.Angle = 55
			lamp.Range = 45
			lamp.Brightness = 3
			lamp.Color = Color3.fromRGB(255, 240, 210)
			lamp.Enabled = false
			lamp.Parent = attachment
		end
	end

	-- Skins: one SurfaceAppearance per texture set
	local skins = Instance.new("Folder")
	skins.Name = "Skins"
	skins.Parent = model
	local skinCount = 0
	if maps then
		for skin, sets in maps do
			if skin ~= "Decals" then
				local folder = Instance.new("Folder")
				folder.Name = skin
				folder.Parent = skins
				local all = table.clone(sets)
				all.Decals = maps.Decals
				for set, ids in all do
					local appearance = Instance.new("SurfaceAppearance")
					appearance.Name = set
					appearance.ColorMap = `rbxassetid://{ids.Color}`
					appearance.NormalMap = `rbxassetid://{ids.Normal}`
					appearance.RoughnessMap = `rbxassetid://{ids.Roughness}`
					appearance.MetalnessMap = `rbxassetid://{ids.Metalness}`
					appearance.Parent = folder
				end
				skinCount += 1
			end
		end
	end

	local store = ServerStorage:FindFirstChild("Vehicles")
	if not store then
		store = Instance.new("Folder")
		store.Name = "Vehicles"
		store.Parent = ServerStorage
	end
	local old = (store :: Instance):FindFirstChild(model.Name)
	if old then
		old:Destroy()
	end
	model.Parent = store
	return string.format(
		"built ServerStorage.Vehicles.%s: %d parts, scale x%.3f, layout fit within %.3f m, %d skins%s",
		model.Name,
		count,
		scale,
		residual,
		skinCount,
		if residual > 0.05 then " (WARNING: parts don't match the manifest well; check the import)" else ""
	)
end

return GroundRoamerBuilder
