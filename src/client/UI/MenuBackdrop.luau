--!strict
-- The menu's backdrop: a picture of the Strait prerendered in Studio, behind the menus in place of the live
-- map (whose terrain near the camera often hadn't streamed in, so the hangar sat over a dark smear). Two
-- halves side by side (Roblox shrinks an image over 1024 px), sized to cover the screen and drifting slowly
-- so it doesn't look frozen. MenuController shows it whenever the menu is up.

local TweenService = game:GetService("TweenService")

local MenuBackdrop = {}

local LEFT = "rbxassetid://81464146315946"
local RIGHT = "rbxassetid://119903499658927"
local WIDTH, HEIGHT = 1920, 1006 -- the picture, in pixels
local OVERSCAN = 1.08 -- a little bigger than the screen, room to drift
local DRIFT_SECONDS = 45

-- A ScreenGui (disabled) holding the picture; parent it to PlayerGui.
function MenuBackdrop.build(displayOrder: number): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "AfterburnerMenuBackdrop"
	gui.DisplayOrder = displayOrder
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.Enabled = false

	local pan = Instance.new("Frame")
	pan.Name = "Pan"
	pan.AnchorPoint = Vector2.new(0.5, 0.5)
	pan.BackgroundColor3 = Color3.fromRGB(13, 26, 51)
	pan.BorderSizePixel = 0
	pan.Parent = gui
	for i, image in { LEFT, RIGHT } do
		local half = Instance.new("ImageLabel")
		half.Name = if i == 1 then "Left" else "Right"
		half.Size = UDim2.fromScale(0.5, 1)
		half.Position = UDim2.fromScale((i - 1) * 0.5, 0)
		half.BackgroundTransparency = 1
		half.Image = image
		half.Parent = pan
	end

	-- Cover the screen at the picture's own shape, then drift side to side across the spare width
	local tween: Tween? = nil
	local function fit()
		local view = (workspace.CurrentCamera :: Camera).ViewportSize
		local scale = math.max(view.X / WIDTH, view.Y / HEIGHT) * OVERSCAN
		local w, h = WIDTH * scale, HEIGHT * scale
		local spare = (w - view.X) / 2
		pan.Size = UDim2.fromOffset(w, h)
		pan.Position = UDim2.new(0.5, -spare, 0.5, 0)
		if tween then
			tween:Cancel()
		end
		local info = TweenInfo.new(DRIFT_SECONDS, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
		tween = TweenService:Create(pan, info, { Position = UDim2.new(0.5, spare, 0.5, 0) });
		(tween :: Tween):Play()
	end
	fit();
	(workspace.CurrentCamera :: Camera):GetPropertyChangedSignal("ViewportSize"):Connect(fit)
	return gui
end

return MenuBackdrop
