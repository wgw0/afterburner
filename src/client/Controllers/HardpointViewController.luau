--!strict
-- Shows the missiles each jet carries on its Hardpoint attachments, on this client only. The loadout's slots
-- (AircraftData Missiles, after modules) take the hardpoints in order, so the first slot (usually the
-- heat-seekers) gets Hardpoint1, 2..., and each missile hangs centred on its hardpoint at its real Length
-- (in flight they're drawn bigger, see MissileViewController). A hardpoint whose missile would overlap one
-- already hung is skipped, so a jet may show fewer than it carries. A slot shows as many missiles as it has left
-- (the jet's Msl_<id> attribute, set by MissileService), so a type disappears when the last one is fired.
-- Which rail a missile leaves from is chosen by the server, so the one hidden is not always the one that
-- left: close enough at a glance.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Progression = require(Shared.Progression)
local WeaponData = require(Shared.WeaponData)

local HARDPOINT_SCALE = 1 -- times the missile's real Length
local CLEARANCE = 1.6

type Mounted = { model: Model, parts: { BasePart } }
type Placed = { at: Vector3, radius: number, half: number }
type Rack = {
	folder: Folder,
	connections: { RBXScriptConnection },
}

local HardpointViewController = {
	Priority = 61,
}

local folder: Folder
local racks: { [Model]: Rack } = {}

local function template(family: string): Model?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local models = assets and assets:FindFirstChild("Missiles")
	local found = models and models:FindFirstChild(family)
	if found and found:IsA("Model") and found.PrimaryPart and found:GetAttribute("Length") then
		return found
	end
	return nil
end

local function hardpoints(root: BasePart): { Attachment }
	local list = {}
	for i = 1, 12 do
		local a = root:FindFirstChild(`Hardpoint{i}`)
		if a and a:IsA("Attachment") then
			table.insert(list, a)
		end
	end
	return list
end

-- A copy of the family's model at the missile's length, welded to the jet's root on the hardpoint
local function mount(source: Model, spec: WeaponData.Missile, root: BasePart, at: Attachment, parent: Instance): Mounted
	local model = source:Clone()
	model:ScaleTo(spec.Length * HARDPOINT_SCALE / (source:GetAttribute("Length") :: number))
	model:PivotTo(root.CFrame * at.CFrame)
	local parts = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.Massless = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			table.insert(parts, d)
		end
	end
	local weld = Instance.new("WeldConstraint")
	weld.Part0, weld.Part1 = root, model.PrimaryPart
	weld.Parent = model.PrimaryPart
	model.Parent = parent
	return { model = model, parts = parts }
end

-- Whether a missile centred at `at` (root space, nose -Z) clears the ones already hung. Fins at 45° can
-- interleave a little, so bodies only need CLEARANCE times their radii apart side to side.
local function fits(placed: { Placed }, at: Vector3, body: { radius: number, half: number }): boolean
	for _, other in placed do
		local side = Vector2.new(at.X - other.at.X, at.Y - other.at.Y).Magnitude
		local alongside = math.abs(at.Z - other.at.Z) < body.half + other.half
		if alongside and side < (body.radius + other.radius) * CLEARANCE then
			return false
		end
	end
	return true
end

local function setVisible(mounted: Mounted, visible: boolean)
	for _, part in mounted.parts do
		part.Transparency = if visible then 0 else 1
	end
end

local function clear(jet: Model)
	local rack = racks[jet]
	if rack then
		racks[jet] = nil
		for _, c in rack.connections do
			c:Disconnect()
		end
		rack.folder:Destroy()
	end
end

local function build(jet: Model)
	clear(jet)
	local root = jet.PrimaryPart
	local airframe = Progression.airframeForModel(jet)
	if not (root and airframe and jet.Parent) then
		return
	end
	local rack: Rack = { folder = Instance.new("Folder"), connections = {} }
	rack.folder.Name = jet.Name
	local free = hardpoints(root)
	local used: { [Attachment]: boolean } = {}
	local placed: { Placed } = {}
	for _, slot in airframe.Missiles or {} do
		local spec = WeaponData.getMissile(slot.Weapon)
		local source = spec and template(spec.Model)
		if not (spec and source) then
			continue
		end
		local scale = spec.Length * HARDPOINT_SCALE / (source:GetAttribute("Length") :: number)
		local trim = source:FindFirstChild("Trim") -- nose to nozzle: its smallest side is the body's diameter
		local body = {
			radius = (if trim and trim:IsA("BasePart") then math.min(trim.Size.X, trim.Size.Y, trim.Size.Z) else 0.2)
				* scale
				/ 2,
			half = spec.Length * HARDPOINT_SCALE / 2,
		}
		local mounted: { Mounted } = {}
		for _ = 1, slot.Count do
			local at
			for _, candidate in free do
				if not used[candidate] and fits(placed, candidate.Position, body) then
					at = candidate
					break
				end
			end
			if not at then
				break
			end
			used[at] = true
			table.insert(placed, { at = at.Position, radius = body.radius, half = body.half })
			table.insert(mounted, mount(source, spec, root, at, rack.folder))
		end
		local attribute = `Msl_{slot.Weapon}`
		local function refresh()
			local left = jet:GetAttribute(attribute)
			local count = if type(left) == "number" then left else slot.Count
			for i, m in mounted do
				setVisible(m, i <= count)
			end
		end
		refresh()
		table.insert(rack.connections, jet:GetAttributeChangedSignal(attribute):Connect(refresh))
	end
	-- A new loadout (modules) or a rebuilt model: start again
	table.insert(
		rack.connections,
		jet:GetAttributeChangedSignal("Modules"):Connect(function()
			build(jet)
		end)
	)
	rack.folder.Parent = folder
	racks[jet] = rack
end

function HardpointViewController:Init()
	folder = Instance.new("Folder")
	folder.Name = "AfterburnerHardpoints"
	folder.Parent = workspace
end

function HardpointViewController:Start()
	local jets = workspace:WaitForChild("Jets")
	jets.ChildAdded:Connect(function(child)
		if child:IsA("Model") then
			task.delay(0.5, build, child) -- let the whole model replicate first
		end
	end)
	jets.ChildRemoved:Connect(function(child)
		if child:IsA("Model") then
			clear(child)
		end
	end)
	for _, child in jets:GetChildren() do
		if child:IsA("Model") then
			build(child)
		end
	end
end

return HardpointViewController
