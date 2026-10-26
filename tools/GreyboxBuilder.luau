--!strict
-- Builds the Phase 1 greybox jets so they follow the model contract (DEVELOPMENT.md §5.3).
-- Run once in Studio (Edit mode), then save the place:
--   require(game.ServerStorage.Tools.GreyboxBuilder).install()
-- Only replaces models marked Greybox = true, so it never overwrites final art.
-- Dimensions are in metres at the visual scale (1 stud = 0.28 m); the nose points along -Z.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local STUDS = 1 / 0.28
local RAD = math.pi / 180

type PartSpec = {
	name: string,
	size: Vector3, -- metres
	at: Vector3, -- metres, relative to the centre of mass
	rot: Vector3?, -- degrees (X, Y, Z)
	color: Color3?,
	material: Enum.Material?,
	cylinder: boolean?, -- axis along Z
	glass: boolean?,
}

type JetSpec = {
	color: Color3,
	parts: { PartSpec },
	hull: { size: Vector3, at: Vector3 },
	hitboxes: { [string]: { size: Vector3, at: Vector3 } },
	attachments: { [string]: Vector3 },
}

local DARK_METAL = Color3.fromRGB(70, 70, 75)
local GLASS = Color3.fromRGB(40, 55, 70)

local SPECS: { [string]: JetSpec } = {
	F5E = {
		color = Color3.fromRGB(140, 150, 160),
		parts = {
			{ name = "NoseTip", size = Vector3.new(0.35, 0.35, 1.2), at = Vector3.new(0, 0, -7.0) },
			{ name = "Nose", size = Vector3.new(0.8, 0.75, 2.2), at = Vector3.new(0, 0, -5.3) },
			{ name = "FuselageFront", size = Vector3.new(1.35, 1.3, 4.0), at = Vector3.new(0, 0, -2.2) },
			{ name = "FuselageRear", size = Vector3.new(1.5, 1.25, 6.4), at = Vector3.new(0, 0, 2.9) },
			{ name = "Canopy", size = Vector3.new(0.75, 0.6, 2.2), at = Vector3.new(0, 0.92, -2.6), glass = true },
			{ name = "IntakeL", size = Vector3.new(0.45, 0.8, 2.0), at = Vector3.new(-0.85, -0.1, -0.6) },
			{ name = "IntakeR", size = Vector3.new(0.45, 0.8, 2.0), at = Vector3.new(0.85, -0.1, -0.6) },
			{
				name = "WingL",
				size = Vector3.new(3.4, 0.15, 2.2),
				at = Vector3.new(-2.4, -0.1, 1.0),
				rot = Vector3.new(0, 24, 0),
			},
			{
				name = "WingR",
				size = Vector3.new(3.4, 0.15, 2.2),
				at = Vector3.new(2.4, -0.1, 1.0),
				rot = Vector3.new(0, -24, 0),
			},
			{
				name = "HStabL",
				size = Vector3.new(1.6, 0.1, 1.0),
				at = Vector3.new(-1.4, 0, 5.6),
				rot = Vector3.new(0, 30, 0),
			},
			{
				name = "HStabR",
				size = Vector3.new(1.6, 0.1, 1.0),
				at = Vector3.new(1.4, 0, 5.6),
				rot = Vector3.new(0, -30, 0),
			},
			{
				name = "VFin",
				size = Vector3.new(0.12, 2.2, 2.0),
				at = Vector3.new(0, 1.6, 5.0),
				rot = Vector3.new(35, 0, 0),
			},
			{
				name = "NozzleL",
				size = Vector3.new(0.55, 0.55, 0.6),
				at = Vector3.new(-0.35, 0, 6.4),
				cylinder = true,
				color = DARK_METAL,
				material = Enum.Material.Metal,
			},
			{
				name = "NozzleR",
				size = Vector3.new(0.55, 0.55, 0.6),
				at = Vector3.new(0.35, 0, 6.4),
				cylinder = true,
				color = DARK_METAL,
				material = Enum.Material.Metal,
			},
		},
		hull = { size = Vector3.new(1.4, 1.4, 13), at = Vector3.new(0, 0, -0.3) },
		hitboxes = {
			Cockpit = { size = Vector3.new(1.2, 1.2, 2.0), at = Vector3.new(0, 0.4, -2.6) },
			Fuselage = { size = Vector3.new(1.5, 1.4, 6.0), at = Vector3.new(0, 0, -0.5) },
			Engine = { size = Vector3.new(1.5, 1.3, 3.5), at = Vector3.new(0, 0, 4.5) },
			WingL = { size = Vector3.new(3.3, 0.5, 2.4), at = Vector3.new(-2.4, 0, 1.0) },
			WingR = { size = Vector3.new(3.3, 0.5, 2.4), at = Vector3.new(2.4, 0, 1.0) },
			Tail = { size = Vector3.new(3.4, 2.4, 2.0), at = Vector3.new(0, 0.8, 5.5) },
		},
		attachments = {
			CockpitEye = Vector3.new(0, 1.25, -2.9),
			GunMuzzle = Vector3.new(0, 0.2, -6.2),
			Hardpoint1 = Vector3.new(-4.0, 0, 1.3),
			Hardpoint2 = Vector3.new(4.0, 0, 1.3),
			Hardpoint3 = Vector3.new(0, -0.8, 0),
			Nozzle1 = Vector3.new(-0.35, 0, 6.75),
			Nozzle2 = Vector3.new(0.35, 0, 6.75),
			WingtipL = Vector3.new(-4.07, -0.1, 1.7),
			WingtipR = Vector3.new(4.07, -0.1, 1.7),
			FlareDispenser = Vector3.new(0, -0.6, 5.0),
			ChaffDispenser = Vector3.new(0, -0.6, 4.6),
			ChaseCam = Vector3.new(0, 3.5, 22),
		},
	},

	MiG21bis = {
		color = Color3.fromRGB(175, 180, 185),
		parts = {
			{ name = "Probe", size = Vector3.new(0.1, 0.1, 1.6), at = Vector3.new(0, 0.3, -8.6), color = DARK_METAL },
			{
				name = "InletCone",
				size = Vector3.new(0.6, 0.6, 0.8),
				at = Vector3.new(0, 0, -7.6),
				cylinder = true,
				color = Color3.fromRGB(70, 80, 60),
			},
			{ name = "Fuselage", size = Vector3.new(1.25, 1.25, 11.5), at = Vector3.new(0, 0, -1.6), cylinder = true },
			{ name = "Rear", size = Vector3.new(1.15, 1.15, 2.6), at = Vector3.new(0, 0, 5.3), cylinder = true },
			{ name = "Canopy", size = Vector3.new(0.65, 0.6, 1.8), at = Vector3.new(0, 0.82, -3.6), glass = true },
			{ name = "Spine", size = Vector3.new(0.4, 0.35, 6.0), at = Vector3.new(0, 0.6, 0) },
			{ name = "WingInnerL", size = Vector3.new(1.3, 0.12, 4.6), at = Vector3.new(-1.25, -0.1, 1.6) },
			{ name = "WingInnerR", size = Vector3.new(1.3, 0.12, 4.6), at = Vector3.new(1.25, -0.1, 1.6) },
			{
				name = "WingOuterL",
				size = Vector3.new(1.6, 0.1, 2.4),
				at = Vector3.new(-2.7, -0.1, 2.5),
				rot = Vector3.new(0, 30, 0),
			},
			{
				name = "WingOuterR",
				size = Vector3.new(1.6, 0.1, 2.4),
				at = Vector3.new(2.7, -0.1, 2.5),
				rot = Vector3.new(0, -30, 0),
			},
			{
				name = "HStabL",
				size = Vector3.new(1.3, 0.1, 1.1),
				at = Vector3.new(-1.3, 0, 5.5),
				rot = Vector3.new(0, 45, 0),
			},
			{
				name = "HStabR",
				size = Vector3.new(1.3, 0.1, 1.1),
				at = Vector3.new(1.3, 0, 5.5),
				rot = Vector3.new(0, -45, 0),
			},
			{
				name = "VFin",
				size = Vector3.new(0.12, 2.4, 2.8),
				at = Vector3.new(0, 1.7, 4.6),
				rot = Vector3.new(50, 0, 0),
			},
			{ name = "VentralFin", size = Vector3.new(0.08, 0.6, 1.4), at = Vector3.new(0, -0.85, 5.2) },
			{
				name = "Nozzle",
				size = Vector3.new(0.95, 0.95, 0.6),
				at = Vector3.new(0, 0, 6.8),
				cylinder = true,
				color = DARK_METAL,
				material = Enum.Material.Metal,
			},
		},
		hull = { size = Vector3.new(1.3, 1.3, 14), at = Vector3.new(0, 0, -0.8) },
		hitboxes = {
			Cockpit = { size = Vector3.new(1.0, 1.0, 1.8), at = Vector3.new(0, 0.4, -3.6) },
			Fuselage = { size = Vector3.new(1.3, 1.3, 7.0), at = Vector3.new(0, 0, -2.0) },
			Engine = { size = Vector3.new(1.3, 1.3, 4.0), at = Vector3.new(0, 0, 4.0) },
			WingL = { size = Vector3.new(3.2, 0.5, 4.0), at = Vector3.new(-2.0, 0, 2.0) },
			WingR = { size = Vector3.new(3.2, 0.5, 4.0), at = Vector3.new(2.0, 0, 2.0) },
			Tail = { size = Vector3.new(2.8, 2.6, 2.5), at = Vector3.new(0, 0.9, 5.3) },
		},
		attachments = {
			CockpitEye = Vector3.new(0, 1.2, -3.8),
			GunMuzzle = Vector3.new(0, -0.7, -1.5),
			Hardpoint1 = Vector3.new(-1.8, -0.3, 1.8),
			Hardpoint2 = Vector3.new(1.8, -0.3, 1.8),
			Hardpoint3 = Vector3.new(-2.8, -0.3, 2.6),
			Hardpoint4 = Vector3.new(2.8, -0.3, 2.6),
			Hardpoint5 = Vector3.new(0, -0.8, 0.5),
			Nozzle1 = Vector3.new(0, 0, 7.1),
			WingtipL = Vector3.new(-3.57, -0.1, 3.6),
			WingtipR = Vector3.new(3.57, -0.1, 3.6),
			FlareDispenser = Vector3.new(0, -0.6, 5.5),
			ChaffDispenser = Vector3.new(0, -0.6, 5.0),
			ChaseCam = Vector3.new(0, 3.5, 22),
		},
	},
}

local GreyboxBuilder = {}

local function weld(root: BasePart, part: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0 = root
	w.Part1 = part
	w.Parent = part
end

local function cframeFor(at: Vector3, rot: Vector3?, cylinder: boolean?): CFrame
	local cf = CFrame.new(at * STUDS)
	if rot then
		cf *= CFrame.Angles(rot.X * RAD, rot.Y * RAD, rot.Z * RAD)
	end
	if cylinder then
		cf *= CFrame.Angles(0, math.pi / 2, 0) -- cylinder axis is X; turn it to lie along Z
	end
	return cf
end

function GreyboxBuilder.build(id: string): Model
	local spec = SPECS[id]
	assert(spec, `No greybox spec for {id}`)

	local model = Instance.new("Model")
	model.Name = id
	model:SetAttribute("Greybox", true)

	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(1, 1, 1)
	root.Transparency = 1
	root.CanCollide = false
	root.CanTouch = false
	root.CanQuery = false
	root.Parent = model
	model.PrimaryPart = root

	local function makePart(name: string, size: Vector3, cf: CFrame, parent: Instance): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = cf
		p.Massless = true
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = parent
		weld(root, p)
		return p
	end

	for _, ps in spec.parts do
		local size = if ps.cylinder then Vector3.new(ps.size.Z, ps.size.X, ps.size.Y) else ps.size
		local p = makePart(ps.name, size * STUDS, cframeFor(ps.at, ps.rot, ps.cylinder), model)
		if ps.cylinder then
			p.Shape = Enum.PartType.Cylinder
		end
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
		if ps.glass then
			p.Color = GLASS
			p.Material = Enum.Material.Glass
			p.Transparency = 0.35
		else
			p.Color = ps.color or spec.color
			p.Material = ps.material or Enum.Material.SmoothPlastic
		end
	end

	local hull = makePart("Hull", spec.hull.size * STUDS, CFrame.new(spec.hull.at * STUDS), model)
	hull.Transparency = 1
	hull.CanCollide = true
	hull.CanTouch = true
	hull.CanQuery = false

	local hitboxes = Instance.new("Folder")
	hitboxes.Name = "Hitboxes"
	hitboxes.Parent = model
	for name, hb in spec.hitboxes do
		local box = makePart(name, hb.size * STUDS, CFrame.new(hb.at * STUDS), hitboxes)
		box.Transparency = 1
		box.CanCollide = false
		box.CanTouch = false
		box.CanQuery = true
	end

	for name, at in spec.attachments do
		local a = Instance.new("Attachment")
		a.Name = name
		a.Position = at * STUDS
		a.Parent = root
	end

	return model
end

-- Builds every greybox jet into ReplicatedStorage.Assets.Aircraft. Returns a summary.
function GreyboxBuilder.install(): string
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if not assets then
		assets = Instance.new("Folder")
		assets.Name = "Assets"
		assets.Parent = ReplicatedStorage
	end
	local aircraft = assets:FindFirstChild("Aircraft")
	if not aircraft then
		aircraft = Instance.new("Folder")
		aircraft.Name = "Aircraft"
		aircraft.Parent = assets
	end

	local results = {}
	for id in SPECS do
		local existing = aircraft:FindFirstChild(id)
		if existing and existing:GetAttribute("Greybox") ~= true then
			table.insert(results, `{id}: skipped (final art present)`)
			continue
		end
		if existing then
			existing:Destroy()
		end
		local model = GreyboxBuilder.build(id)
		model.Parent = aircraft
		table.insert(results, `{id}: built ({#model:GetDescendants()} instances)`)
	end
	table.sort(results)
	return table.concat(results, "\n")
end

return GreyboxBuilder
