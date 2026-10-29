--!strict
-- Kill markers (PRG-07): a row of stencilled stars under the canopy, one per mastery star, on jets with
-- Mastery.MARKERS_FROM stars or more. Shared: the server marks spawned jets (everyone sees them) and the
-- client marks its menu previews. Every jet's fuselage is a different shape, so the spot is found by casting
-- a ray in from each side onto the visible skin below the cockpit (CockpitEye), and a thin invisible plate
-- holding the stars is laid flat on it. Call once the model is in a world that's in the game (Workspace, or a
-- WorldModel already parented): rays don't work in a detached one.

local Mastery = require(script.Parent.Mastery)

local KillMarkers = {}

local NAME = "KillMarkers"
local STAR = 0.34 -- studs per star
local BELOW_EYE = 0.85 -- studs under the pilot's eye
local AFT_OF_EYE = 0.9 -- studs behind it
local PAINT = Color3.fromRGB(235, 235, 225)

-- Where a ray from this side lands on the visible skin, or nil. The model's visible parts don't take
-- queries (rays hit the hitboxes), so they take them just for this cast.
local function skinHit(model: Model, root: BasePart, world: WorldRoot, side: number): RaycastResult?
	local eye = root:FindFirstChild("CockpitEye") :: Attachment?
	if not eye then
		return nil
	end
	local visible, before = {}, {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 0.5 and d.Name ~= NAME then
			table.insert(visible, d)
			before[d] = d.CanQuery
			d.CanQuery = true
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = visible
	local spot = eye.WorldCFrame * CFrame.new(0, -BELOW_EYE, AFT_OF_EYE)
	local origin = spot.Position + root.CFrame.RightVector * side * 20
	local hit = world:Raycast(origin, root.CFrame.RightVector * -side * 40, params)
	for part, canQuery in before do
		part.CanQuery = canQuery
	end
	return hit
end

local function plate(model: Model, root: BasePart, world: WorldRoot, side: number, stars: number)
	local hit = skinHit(model, root, world, side)
	if not hit then
		return
	end
	-- Face out from the skin, kept upright with the jet (paint on a curved side still reads level)
	local up = root.CFrame.UpVector
	local out = hit.Normal - up * hit.Normal:Dot(up)
	if out.Magnitude < 0.2 then
		return -- not a side wall here
	end
	out = out.Unit
	local part = Instance.new("Part")
	part.Name = NAME
	part.Size = Vector3.new(STAR * stars, STAR, 0.02)
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
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = string.rep("★", stars)
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = PAINT
	label.TextTransparency = 0.1
	label.Parent = gui
	if not root.Anchored then
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = part
		weld.Parent = part
	end
	part.Parent = model
end

-- Marks a jet for its mastery stars (removing old marks); nothing under MARKERS_FROM.
function KillMarkers.apply(model: Model, stars: number)
	for _, old in model:GetChildren() do
		if old.Name == NAME then
			old:Destroy()
		end
	end
	local root = model.PrimaryPart
	local world = model:FindFirstAncestorWhichIsA("WorldRoot")
	if stars < Mastery.MARKERS_FROM or not (root and world) then
		return
	end
	for _, side in { 1, -1 } do
		plate(model, root, world, side, stars)
	end
end

return KillMarkers
