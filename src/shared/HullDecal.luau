--!strict
-- Paint on a jet's side: a thin invisible plate laid flat on the visible skin, holding a SurfaceGui. Every
-- jet's fuselage is a different shape, so the spot is found by casting a ray in from the side (1 right, -1
-- left) onto the skin. `fits` checks a plate's corners all lie on the skin too, so paint isn't left hanging
-- off a curved or tapering surface. Used by KillMarkers and WingArt. Call once the model is in a world that's in
-- the game (Workspace, or a WorldModel already parented): rays don't work in a detached one.

local HullDecal = {}

export type Caster = {
	model: Model,
	root: BasePart,
	world: WorldRoot,
	cast: (origin: Vector3, direction: Vector3) -> RaycastResult?,
	done: () -> (),
}

-- Rays against the model's visible skin. Its visible parts don't take queries (rays hit the hitboxes), so
-- they take them until done().
function HullDecal.caster(model: Model): Caster?
	local root = model.PrimaryPart
	local world = model:FindFirstAncestorWhichIsA("WorldRoot")
	if not (root and world) then
		return nil
	end
	local visible, before = {}, {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 0.5 then
			table.insert(visible, d)
			before[d] = d.CanQuery
			d.CanQuery = true
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = visible
	return {
		model = model,
		root = root,
		world = world,
		cast = function(origin: Vector3, direction: Vector3): RaycastResult?
			return world:Raycast(origin, direction, params)
		end,
		done = function()
			for part, canQuery in before do
				if part.Parent then
					part.CanQuery = canQuery
				end
			end
		end,
	}
end

-- The plate's frame on the skin at `spot` from this side (facing out, kept upright with the jet), or nil if
-- there's no side wall there.
function HullDecal.surface(c: Caster, spot: Vector3, side: number): CFrame?
	local right = c.root.CFrame.RightVector
	local hit = c.cast(spot + right * side * 20, right * -side * 40)
	if not hit then
		return nil
	end
	local up = c.root.CFrame.UpVector
	local out = hit.Normal - up * hit.Normal:Dot(up)
	if out.Magnitude < 0.2 then
		return nil
	end
	out = out.Unit
	return CFrame.lookAt(hit.Position + out * 0.03, hit.Position + out, up)
end

-- Whether a plate of `size` at `frame` lies on the skin: rays in at its corners and edge midpoints all land
-- within `tolerance` studs of its plane.
function HullDecal.fits(c: Caster, frame: CFrame, size: Vector2, tolerance: number): boolean
	local out = frame.LookVector
	for _, f in
		{ { -0.5, -0.5 }, { 0.5, -0.5 }, { -0.5, 0.5 }, { 0.5, 0.5 }, { 0, -0.5 }, { 0, 0.5 }, { -0.5, 0 }, { 0.5, 0 } }
	do
		local point = (frame * CFrame.new(f[1] * size.X, f[2] * size.Y, 0)).Position
		local hit = c.cast(point + out * 3, out * -6)
		if not hit or math.abs((hit.Position - point):Dot(out)) > tolerance then
			return false
		end
	end
	return true
end

-- Removes a decal's plates.
function HullDecal.clear(model: Model, name: string)
	for _, old in model:GetChildren() do
		if old.Name == name then
			old:Destroy()
		end
	end
end

-- The pilot's eye in world space, or nil if the jet has none.
function HullDecal.eye(model: Model): CFrame?
	local root = model.PrimaryPart
	local eye = root and root:FindFirstChild("CockpitEye") :: Attachment?
	return eye and eye.WorldCFrame
end

-- Makes the plate at `frame`; fill(gui) puts the paint in its SurfaceGui.
function HullDecal.plate(model: Model, name: string, frame: CFrame, size: Vector2, fill: (gui: SurfaceGui) -> ()): Part
	local root = model.PrimaryPart :: BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Size = Vector3.new(size.X, size.Y, 0.02)
	part.Transparency = 1
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.Anchored = root.Anchored
	part.CFrame = frame
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 120
	gui.LightInfluence = 1
	gui.Parent = part
	fill(gui)
	if not root.Anchored then
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = part
		weld.Parent = part
	end
	part.Parent = model
	return part
end

-- Lays a plate on the skin at `spot` on one side (no fit check). Returns it, or nil if there's no side wall.
function HullDecal.place(
	model: Model,
	name: string,
	spot: Vector3,
	side: number,
	size: Vector2,
	fill: (gui: SurfaceGui, side: number) -> ()
): Part?
	local c = HullDecal.caster(model)
	if not c then
		return nil
	end
	local frame = HullDecal.surface(c, spot, side)
	c.done()
	if not frame then
		return nil
	end
	return HullDecal.plate(model, name, frame, size, function(gui)
		fill(gui, side)
	end)
end

return HullDecal
