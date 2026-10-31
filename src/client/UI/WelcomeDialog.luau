--!strict
-- The first-visit welcome (TUT-04): a brand-new pilot in the lobby gets this over the menu, built like the
-- free-spin window, recommending training. GO TO TRAINING heads to a training server (lesson 1 starts by
-- itself); X stays in the lobby and the pilot counts as onboarded, so it doesn't come back (MenuController).
-- props: OnTraining(), OnClose()

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("React")) :: any

local C = require(script.Parent.Components)
local Theme = require(script.Parent.Theme)

local e = React.createElement

local BODY = "Welcome to Afterburner. Before your first dogfight we recommend Training: short lessons on flying, "
	.. "the gun, missiles and beating a missile fired at you, then a first fight against an AI pilot. You can "
	.. "come back to it any time from the hangar."

local function WelcomeDialog(props: { OnTraining: () -> (), OnClose: () -> () })
	return e("TextButton", { -- dims the menu behind and swallows clicks
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.35,
	}, {
		Panel = e(C.Panel, {
			Size = UDim2.fromOffset(640, 300),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Padding = 30,
			StrokeColor = Theme.Accent,
			StrokeThickness = 2,
		}, {
			Title = e(C.Label, {
				Text = "ATTENTION, CADET!",
				Size = UDim2.new(1, -50, 0, 34),
				Heavy = true,
				TextSize = 30,
				Color = Theme.Accent,
			}),
			Close = e(C.Button, {
				Text = "X",
				Style = "Ghost",
				Size = UDim2.fromOffset(34, 34),
				Position = UDim2.new(1, -34, 0, 0),
				TextSize = 16,
				OnClick = props.OnClose,
			}),
			Body = e(C.Label, {
				Text = BODY,
				Size = UDim2.new(1, 0, 0, 110),
				Position = UDim2.fromOffset(0, 54),
				TextSize = 17,
				Wrap = true,
			}),
			Training = e(C.Button, {
				Text = "GO TO TRAINING",
				Style = "Primary",
				Size = UDim2.fromOffset(260, 50),
				Position = UDim2.new(0.5, 0, 1, -50),
				AnchorPoint = Vector2.new(0.5, 0),
				TextSize = 18,
				OnClick = props.OnTraining,
			}),
		}),
	})
end

return WelcomeDialog
