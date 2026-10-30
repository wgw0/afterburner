--!strict
-- Nose art (SHP-07, Config/Cosmetics "NoseArt"): a decal on each side of the nose, between the cockpit and
-- the radome, sized to the jet's nose. Shared like KillMarkers: the server paints spawned jets and the client
-- its menu previews. Laid on the skin by HullDecal (call once the model is in the world).

local Catalogue = require(script.Parent.Config.Cosmetics)
local HullDecal = require(script.Parent.HullDecal)

local NoseArt = {}

local NAME = "NoseArt"
local ALONG = 0.6 -- of the way from the pilot's eye to the nose tip
local BELOW = 0.16 -- of that distance, under the eye line
local HEIGHT = 0.22 -- the decal's height, of that distance (it's twice as wide as high)

-- How far ahead of the eye the nose tip is, in studs, or nil: rays back along the centreline from ahead, at
-- heights from just under the eye down to the root (the radome sits below the eye line), the furthest hit.
local function noseLength(model: Model, root: BasePart, eye: CFrame, world: WorldRoot): number?
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
	local look = eye.LookVector
	local drop = math.max((eye.Position - root.Position):Dot(eye.UpVector), 0.3)
	local best: number? = nil
	for k = 0, 4 do
		local from = eye.Position + look * 80 - eye.UpVector * (0.15 + drop * k / 4)
		local hit = world:Raycast(from, look * -80, params)
		local ahead = hit and (hit.Position - eye.Position):Dot(look)
		if ahead and (best == nil or ahead > best) then
			best = ahead
		end
	end
	for part, canQuery in before do
		part.CanQuery = canQuery
	end
	return best
end

-- Paints a jet's nose art (removing any old), or just clears it for nil / an unknown id.
function NoseArt.apply(model: Model, id: string?)
	HullDecal.clear(model, NAME)
	local item = id and Catalogue.get(id)
	local eye = HullDecal.eye(model)
	local world = model:FindFirstAncestorWhichIsA("WorldRoot")
	if not (item and item.Kind == "NoseArt" and item.Images and eye and world) then
		return
	end
	local length = noseLength(model, model.PrimaryPart :: BasePart, eye, world)
	if not length or length < 0.5 then
		return
	end
	local spot = (eye * CFrame.new(0, -length * BELOW, -length * ALONG)).Position
	local h = length * HEIGHT
	local images = item.Images
	for i, side in { 1, -1 } do
		HullDecal.place(model, NAME, spot, side, Vector2.new(h * 2, h), function(gui)
			local image = Instance.new("ImageLabel")
			image.Size = UDim2.fromScale(1, 1)
			image.BackgroundTransparency = 1
			image.Image = images[i]
			image.Parent = gui
		end)
	end
end

return NoseArt
