--!strict
-- The screen shown while a teleport carries you to a match, a training server or a lobby (DEVELOPMENT.md
-- §25.4): navy, the logo in orange, and a line saying where you're going. Handed to
-- TeleportService:SetTeleportGui, which keeps it up through the teleport.

local Theme = require(script.Parent.Theme)

local LoadingScreen = {}

function LoadingScreen.build(text: string): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "AfterburnerLoading"
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 100

	local back = Instance.new("Frame")
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = Theme.Background
	back.BorderSizePixel = 0
	back.Parent = gui

	local logo = Instance.new("TextLabel")
	logo.Size = UDim2.new(1, 0, 0, 60)
	logo.Position = UDim2.fromScale(0.5, 0.44)
	logo.AnchorPoint = Vector2.new(0.5, 0.5)
	logo.BackgroundTransparency = 1
	logo.Font = Theme.FontHeavy
	logo.TextSize = 52
	logo.TextColor3 = Theme.Accent
	logo.Text = "AFTERBURNER"
	logo.Parent = back

	local line = Instance.new("TextLabel")
	line.Size = UDim2.new(1, 0, 0, 24)
	line.Position = UDim2.new(0.5, 0, 0.44, 52)
	line.AnchorPoint = Vector2.new(0.5, 0.5)
	line.BackgroundTransparency = 1
	line.Font = Theme.FontBold
	line.TextSize = 18
	line.TextColor3 = Theme.Text
	line.Text = text
	line.Parent = back

	local bar = Instance.new("Frame")
	bar.Size = UDim2.fromOffset(220, 3)
	bar.Position = UDim2.new(0.5, 0, 0.44, 84)
	bar.AnchorPoint = Vector2.new(0.5, 0.5)
	bar.BackgroundColor3 = Theme.Accent
	bar.BorderSizePixel = 0
	bar.Parent = back

	return gui
end

return LoadingScreen
