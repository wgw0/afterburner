--!strict
-- Kill markers (PRG-07): a row of stencilled stars under the canopy, one per mastery star, on jets with
-- Mastery.MARKERS_FROM stars or more. A kill-marker style (SHP-07, Config/Cosmetics "Marker") paints a
-- different mark or colour. Shared: the server marks spawned jets (everyone sees them) and the client marks
-- its menu previews. Laid on the skin by HullDecal (call once the model is in the world).

local Catalogue = require(script.Parent.Config.Cosmetics)
local HullDecal = require(script.Parent.HullDecal)
local Mastery = require(script.Parent.Mastery)

local KillMarkers = {}

local NAME = "KillMarkers"
local STAR = 0.34 -- studs per mark
local BELOW_EYE = 0.85 -- studs under the pilot's eye
local AFT_OF_EYE = 0.9 -- studs behind it
local PAINT = Color3.fromRGB(235, 235, 225)

-- Marks a jet for its mastery stars (removing old marks); nothing under MARKERS_FROM. style: a Marker
-- cosmetic's id, or nil for the plain stars.
function KillMarkers.apply(model: Model, stars: number, style: string?)
	HullDecal.clear(model, NAME)
	local eye = HullDecal.eye(model)
	if stars < Mastery.MARKERS_FROM or not eye then
		return
	end
	local item = style and Catalogue.get(style)
	local glyph = if item and item.Kind == "Marker" then item.Glyph or "★" else "★"
	local colour = if item and item.Kind == "Marker" then item.Colour or PAINT else PAINT
	local spot = (eye * CFrame.new(0, -BELOW_EYE, AFT_OF_EYE)).Position
	for _, side in { 1, -1 } do
		HullDecal.place(model, NAME, spot, side, Vector2.new(STAR * stars, STAR), function(gui)
			local label = Instance.new("TextLabel")
			label.Size = UDim2.fromScale(1, 1)
			label.BackgroundTransparency = 1
			label.Text = string.rep(glyph, stars)
			label.TextScaled = true
			label.Font = Enum.Font.GothamBold
			label.TextColor3 = colour
			label.TextTransparency = 0.1
			label.Parent = gui
		end)
	end
end

return KillMarkers
