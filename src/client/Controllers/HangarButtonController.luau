--!strict
-- Back to the hangar from a flight or a drive: a button in the top bar's row at the top right, in the menu's
-- navy and orange. Hold H, or press and hold the button, for HOLD seconds so a stray press mid-fight doesn't
-- end the sortie. Leaving straight after taking damage still credits the attacker (DamageModel.CRASH_WINDOW).

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)

local Theme = require(script.Parent.Parent.UI.Theme)
local DriveController = require(script.Parent.DriveController)
local FlightController = require(script.Parent.FlightController)

local HOLD = 0.6 -- seconds
local WIDTH, HEIGHT = 190, 44
local KEY = Enum.KeyCode.H

local HangarButtonController = {
	Priority = 91, -- after MenuController
}

local gui: ScreenGui
local button: TextButton
local fill: Frame
local keycap: Frame
local title: TextLabel
local subtitle: TextLabel
local stroke: UIStroke
local holdingKey = false
local holdingButton = false
local held = 0
local sent = false

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function text(parent: Instance, value: string, size: number, font: Enum.Font, colour: Color3): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Text = value
	l.TextSize = size
	l.Font = font
	l.TextColor3 = colour
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Parent = parent
	return l
end

-- Sits in the top bar's row, just left of Roblox's own buttons on the right.
local function place()
	local inset = GuiService.TopbarInset
	local right = if inset.Max.X > 0 then inset.Max.X else workspace.CurrentCamera.ViewportSize.X
	local rowHeight = math.max(inset.Height, HEIGHT + 12)
	button.Position = UDim2.fromOffset(right - 12, rowHeight / 2)
end

local function leave()
	sent = true
	if FlightController.jet then
		Net.Client.fire("ReturnToHangar")
	elseif DriveController.vehicle then
		task.spawn(function()
			DriveController:PutAway()
		end)
	end
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "HangarButton"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 5
	gui.Enabled = false

	button = Instance.new("TextButton")
	button.Name = "Hangar"
	button.Size = UDim2.fromOffset(WIDTH, HEIGHT)
	button.AnchorPoint = Vector2.new(1, 0.5)
	button.BackgroundColor3 = Theme.Panel
	button.BackgroundTransparency = 0.1
	button.AutoButtonColor = false
	button.Text = ""
	button.ClipsDescendants = true
	button.Parent = gui
	corner(button, Theme.Radius)
	stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Accent
	stroke.Thickness = 1.5
	stroke.Transparency = 0.25
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = button

	-- Fills left to right while held
	fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = Theme.Accent
	fill.BackgroundTransparency = 0.55
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(0, 1)
	fill.ZIndex = 1
	fill.Parent = button

	keycap = Instance.new("Frame")
	keycap.Name = "Key"
	keycap.Size = UDim2.fromOffset(28, 28)
	keycap.Position = UDim2.new(0, 9, 0.5, 0)
	keycap.AnchorPoint = Vector2.new(0, 0.5)
	keycap.BackgroundColor3 = Theme.PanelLight
	keycap.ZIndex = 2
	keycap.Parent = button
	corner(keycap, 6)
	local keyStroke = Instance.new("UIStroke")
	keyStroke.Color = Theme.Accent
	keyStroke.Thickness = 1
	keyStroke.Parent = keycap
	local keyLabel = text(keycap, "H", 15, Theme.FontHeavy, Theme.Accent)
	keyLabel.Size = UDim2.fromScale(1, 1)
	keyLabel.TextXAlignment = Enum.TextXAlignment.Center
	keyLabel.ZIndex = 3

	title = text(button, "HANGAR", 15, Theme.FontBold, Theme.Text)
	title.Name = "Title"
	title.Size = UDim2.new(1, -54, 0, 18)
	title.Position = UDim2.fromOffset(46, 5)
	title.ZIndex = 2
	subtitle = text(button, "hold to leave", 11, Theme.Font, Theme.Dim)
	subtitle.Name = "Subtitle"
	subtitle.Size = UDim2.new(1, -54, 0, 14)
	subtitle.Position = UDim2.fromOffset(46, 24)
	subtitle.ZIndex = 2

	button.MouseEnter:Connect(function()
		stroke.Transparency = 0
	end)
	button.MouseLeave:Connect(function()
		stroke.Transparency = 0.25
		holdingButton = false
	end)
	button.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			holdingButton = true
		end
	end)
	button.InputEnded:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			holdingButton = false
		end
	end)
end

function HangarButtonController:Init()
	build()
end

function HangarButtonController:Start()
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	place()
	GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(place)
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(place)

	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == KEY then
			holdingKey = true
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == KEY then
			holdingKey = false
		end
	end)

	RunService.RenderStepped:Connect(function(dt)
		local active = FlightController.jet ~= nil or DriveController.vehicle ~= nil
		if not active then
			sent, held, holdingKey, holdingButton = false, 0, false, false
		end
		gui.Enabled = active
		if not active then
			return
		end
		-- No keyboard (a phone): the key hint would mean nothing
		keycap.Visible = UserInputService.KeyboardEnabled
		local textX = if keycap.Visible then 46 else 14
		title.Position = UDim2.fromOffset(textX, 5)
		subtitle.Position = UDim2.fromOffset(textX, 24)
		if (holdingKey or holdingButton) and not sent then
			held = math.min(held + dt, HOLD)
			if held >= HOLD then
				leave()
			end
		else
			held = math.max(held - dt * 3, 0)
		end
		fill.Size = UDim2.fromScale(held / HOLD, 1)
		subtitle.Text = if sent then "leaving…" elseif held > 0 then "keep holding" else "hold to leave"
	end)
end

return HangarButtonController
