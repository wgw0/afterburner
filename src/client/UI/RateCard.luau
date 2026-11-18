--!strict
-- After a 👍 on a check-in (PulseCard): asks the pilot, with nothing offered in return (Roblox's rules forbid
-- rewarding votes), to rate the game and favourite it. Each button opens Roblox's own prompt (MenuController).
-- Shown once per visit, in the same place as the check-in. props: OnRate(), OnFavourite(), OnClose().

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("React")) :: any
local ReactRoblox = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("ReactRoblox")) :: any

local C = require(script.Parent.Components)
local Theme = require(script.Parent.Theme)

local e = React.createElement
local WIDTH = 340

local function RateCard(props: { OnRate: () -> (), OnFavourite: () -> (), OnClose: () -> () })
	local panel = e(C.Panel, {
		Size = UDim2.fromOffset(WIDTH, 136),
		Position = UDim2.fromScale(0.5, 0.6),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Padding = 14,
		StrokeColor = Theme.Accent,
		StrokeThickness = 2,
	}, {
		Title = e(C.Label, {
			Text = "Thanks, pilot!",
			Size = UDim2.new(1, -40, 0, 22),
			TextSize = 16,
			Heavy = true,
			Color = Theme.Accent,
		}),
		Close = e(C.Button, {
			Text = "X", -- the menu font has no ✕
			Style = "Ghost",
			Size = UDim2.fromOffset(32, 32),
			Position = UDim2.new(1, 0, 0, -6),
			AnchorPoint = Vector2.new(1, 0),
			TextSize = 14,
			OnClick = props.OnClose,
		}),
		Ask = e(C.Label, {
			Text = "A thumbs up on the game helps other pilots find Afterburner.",
			Size = UDim2.new(1, 0, 0, 34),
			Position = UDim2.fromOffset(0, 26),
			TextSize = 13,
			Color = Theme.Dim,
			Wrap = true,
		}),
		Rate = e(C.Button, {
			Text = "👍  RATE IT",
			Style = "Primary",
			Size = UDim2.new(0.5, -5, 0, 44),
			Position = UDim2.new(0, 0, 1, -44),
			TextSize = 15,
			OnClick = props.OnRate,
		}),
		Favourite = e(C.Button, {
			Text = "★  FAVOURITE",
			Size = UDim2.new(0.5, -5, 0, 44),
			Position = UDim2.new(1, 0, 1, -44),
			AnchorPoint = Vector2.new(1, 0),
			TextSize = 15,
			OnClick = props.OnFavourite,
		}),
	})
	return ReactRoblox.createPortal({
		AfterburnerRate = e("ScreenGui", {
			DisplayOrder = 25,
			IgnoreGuiInset = true,
			ResetOnSpawn = false,
			ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		}, { Card = panel }),
	}, Players.LocalPlayer:WaitForChild("PlayerGui"))
end

return RateCard
