--!strict
-- The pilot's damage diagram (DEVELOPMENT.md §12.3, DMG-05): a small top-down outline of the jet on the HUD,
-- each component coloured by its health (DamageModel.condition): faint in the HUD colour when fine, amber
-- when damaged, red when critical, a red outline once lost, and FIRE beside it while the engine burns.
-- Built from plain instances like the rest of the HUD (HUDController owns it and places it).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DamageModel = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("DamageModel"))

local DamageDiagram = {}

local AMBER = Color3.fromRGB(255, 190, 80)
local RED = Color3.fromRGB(255, 85, 70)
local WIDTH, HEIGHT = 64, 84

-- Each component's box in the outline (nose up): x, y, width, height, drawing order
local SHAPES: { [string]: { number } } = {
	WingL = { 2, 32, 25, 16, 1 },
	WingR = { 37, 32, 25, 16, 1 },
	Tail = { 17, 68, 30, 10, 1 },
	Fuselage = { 26, 6, 12, 66, 2 },
	Engine = { 27, 54, 10, 16, 3 },
	Cockpit = { 28, 12, 8, 12, 3 },
}

export type Diagram = { frame: Frame, parts: { [string]: { fill: Frame, stroke: UIStroke } }, fire: TextLabel }

function DamageDiagram.create(parent: Instance): Diagram
	local frame = Instance.new("Frame")
	frame.Name = "DamageDiagram"
	frame.AnchorPoint = Vector2.new(0, 1)
	frame.Size = UDim2.fromOffset(WIDTH, HEIGHT)
	frame.BackgroundTransparency = 1
	frame.Visible = false
	frame.Parent = parent
	local scale = Instance.new("UIScale")
	scale.Scale = 1.4 -- legible at a glance without crowding the corner
	scale.Parent = frame
	local parts = {}
	for component, shape in SHAPES do
		local fill = Instance.new("Frame")
		fill.Name = component
		fill.Position = UDim2.fromOffset(shape[1], shape[2])
		fill.Size = UDim2.fromOffset(shape[3], shape[4])
		fill.ZIndex = shape[5]
		fill.BorderSizePixel = 0
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 2)
		corner.Parent = fill
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 1
		stroke.Parent = fill
		fill.Parent = frame
		parts[component] = { fill = fill, stroke = stroke }
	end
	local fire = Instance.new("TextLabel")
	fire.Name = "Fire"
	fire.BackgroundTransparency = 1
	fire.Font = Enum.Font.Code
	fire.TextSize = 14
	fire.TextColor3 = RED
	fire.Text = "FIRE"
	fire.TextXAlignment = Enum.TextXAlignment.Left
	fire.Position = UDim2.fromOffset(WIDTH + 6, HEIGHT - 28)
	fire.Size = UDim2.fromOffset(40, 16)
	fire.Visible = false
	fire.Parent = frame
	return { frame = frame, parts = parts, fire = fire }
end

-- Colours the diagram for the latest health fractions. Shown once anything is damaged (or burning).
function DamageDiagram.update(diagram: Diagram, fractions: { [string]: number }?, onFire: boolean, hud: Color3)
	local damaged = onFire
	for component, part in diagram.parts do
		local condition = DamageModel.condition(if fractions then fractions[component] or 1 else 1)
		damaged = damaged or condition ~= "Ok"
		local colour = if condition == "Ok" then hud elseif condition == "Damaged" then AMBER else RED
		part.fill.BackgroundColor3 = colour
		part.fill.BackgroundTransparency = if condition == "Ok" then 0.8 elseif condition == "Lost" then 1 else 0.25
		part.stroke.Color = colour
		part.stroke.Transparency = if condition == "Ok" then 0.4 else 0
		part.stroke.Thickness = if condition == "Lost" then 2 else 1
	end
	diagram.fire.Visible = onFire
	diagram.frame.Visible = damaged
end

return DamageDiagram
