--!strict
-- Paint on a jet's side: a thin invisible plate laid flat on the visible skin, holding a SurfaceGui. Every
-- jet's fuselage is a different shape, so the spot is found by casting a ray in from each side onto the skin
-- at a point given relative to the pilot's eye (the root's CockpitEye). Used by KillMarkers and NoseArt.
-- Call once the model is in a world that's in the game (Workspace, or a WorldModel already parented): rays
-- don't work in a detached one.

local HullDecal = {}

-- Where a ray from this side (1 right, -1 left) lands on the visible skin at `spot`, or nil. The model's
-- visible parts don't take queries (rays hit the hitboxes), so they take them just for this cast.
local function skinHit(model: Model, root: BasePart, world: WorldRoot, spot: Vector3, side: number): RaycastResult?
	local visible, before = {}, {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 0.5 and not d:FindFirstChildOfClass("SurfaceGui") then
			table.insert(visible, d)
			before[d] = d.CanQuery
			d.CanQuery = true
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = visible
	local origin = spot + root.CFrame.RightVector * side * 20
	local hit = world:Raycast(origin, root.CFrame.RightVector * -side * 40, params)
	for part, canQuery in before do
		part.CanQuery = canQuery
	end
	return hit
end

-- The pilot's eye in world space, or nil if the jet has none.
function HullDecal.eye(model: Model): CFrame?
	local root = model.PrimaryPart
	local eye = root and root:FindFirstChild("CockpitEye") :: Attachment?
	return eye and eye.WorldCFrame
end

-- Removes a decal's plates.
function HullDecal.clear(model: Model, name: string)
	for _, old in model:GetChildren() do
		if old.Name == name then
			old:Destroy()
		end
	end
end

-- Lays a plate `size` studs (width, height) on the skin at `spot` on one side; fill(gui, side) puts the
-- paint in its SurfaceGui. Returns the plate, or nil if there's no side wall there.
function HullDecal.place(
	model: Model,
	name: string,
	spot: Vector3,
	side: number,
	size: Vector2,
	fill: (gui: SurfaceGui, side: number) -> ()
): Part?
	local root = model.PrimaryPart
	local world = model:FindFirstAncestorWhichIsA("WorldRoot")
	if not (root and world) then
		return nil
	end
	local hit = skinHit(model, root, world, spot, side)
	if not hit then
		return nil
	end
	-- Face out from the skin, kept upright with the jet (paint on a curved side still reads level)
	local up = root.CFrame.UpVector
	local out = hit.Normal - up * hit.Normal:Dot(up)
	if out.Magnitude < 0.2 then
		return nil -- not a side wall here
	end
	out = out.Unit
	local part = Instance.new("Part")
	part.Name = name
	part.Size = Vector3.new(size.X, size.Y, 0.02)
	part.Transparency = 1
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.Anchored = root.Anchored
	part.CFrame = CFrame.lookAt(hit.Position + out * 0.03, hit.Position + out, up)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 120
	gui.LightInfluence = 1
	gui.Parent = part
	fill(gui, side)
	if not root.Anchored then
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = part
		weld.Parent = part
	end
	part.Parent = model
	return part
end

return HullDecal
