--!strict
-- G effects on the pilot's view (DEVELOPMENT.md §8.5).
--   Grey-out: colour drains and the edges close in as G stress builds (from 0.6).
--   G-LOC: at full stress the screen goes black for a few seconds (FlightController holds the jet level).
--   Red-out: strong negative G tints the view red.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Spring = require(Shared.Util.Spring)

local FlightController = require(script.Parent.FlightController)

local GEffectsController = {
	Priority = 65,
}

local colour: ColorCorrectionEffect
local blackout: Frame
local edges: { Frame } = {}
local greySpring = Spring.new(0, 6, 1)
local redSpring = Spring.new(0, 6, 1)
local blackSpring = Spring.new(0, 5, 1)

local function edge(gui: ScreenGui, rotation: number): Frame
	-- A gradient strip that fades from black at the screen edge to clear toward the centre.
	local f = Instance.new("Frame")
	f.BackgroundColor3 = Color3.new(0, 0, 0)
	f.BorderSizePixel = 0
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(0.5, 0.5)
	f.Size = UDim2.fromScale(2, 2)
	f.Rotation = rotation
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 0
	gradient.Parent = f
	f.Parent = gui
	return f
end

local function build()
	colour = Instance.new("ColorCorrectionEffect")
	colour.Name = "AfterburnerGEffects"
	colour.Parent = Lighting

	local gui = Instance.new("ScreenGui")
	gui.Name = "AfterburnerGEffects"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 10
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	for _, rotation in { 0, 90, 180, 270 } do
		table.insert(edges, edge(gui, rotation))
	end

	blackout = Instance.new("Frame")
	blackout.BackgroundColor3 = Color3.new(0, 0, 0)
	blackout.BorderSizePixel = 0
	blackout.Size = UDim2.fromScale(1, 1)
	blackout.BackgroundTransparency = 1
	blackout.Parent = gui
end

local function update(dt: number)
	local state = FlightController.state
	local grey = 0
	local red = 0
	local black = 0
	if state then
		grey = math.clamp((state.gStress - 0.6) / 0.4, 0, 1)
		red = math.clamp(state.redStress, 0, 1)
		black = if FlightController:IsUnconscious() then 1 else 0
	end
	grey = greySpring:Update(dt, grey)
	red = redSpring:Update(dt, red)
	black = blackSpring:Update(dt, black)

	colour.Saturation = -grey
	colour.Brightness = -0.15 * grey
	colour.TintColor = Color3.new(1, 1 - 0.7 * red, 1 - 0.7 * red)

	-- Tunnel vision: each edge strip's gradient closes further in as grey-out deepens.
	local reach = 0.02 + 0.45 * grey
	for _, f in edges do
		local gradient = f:FindFirstChildOfClass("UIGradient") :: UIGradient
		gradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(math.clamp(0.75 - reach, 0.01, 0.98), 1),
			NumberSequenceKeypoint.new(0.75, math.clamp(1 - grey, 0, 1)),
			NumberSequenceKeypoint.new(1, math.clamp(1 - grey, 0, 1)),
		})
		f.Visible = grey > 0.01
	end
	blackout.BackgroundTransparency = 1 - math.clamp(black, 0, 1)
end

function GEffectsController:Start()
	build()
	RunService.RenderStepped:Connect(update)
end

return GEffectsController
