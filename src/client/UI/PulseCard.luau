--!strict
-- A quick check-in (Shared/Pulse), in the open sky between the Hangar's jet and its name: "How's Afterburner so far?" with
-- 👍 / 👎, then an optional line and SEND. ✕ dismisses it for good. In its own ScreenGui above the menu (which
-- draws with Global ZIndex). props: Moment, OnAnswer(answer: "up" | "down" | "skip", text: string?).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("React")) :: any
local ReactRoblox = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("ReactRoblox")) :: any
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Pulse = require(Shared.Pulse)

local C = require(script.Parent.Components)
local Theme = require(script.Parent.Theme)

local e = React.createElement
local WIDTH = 340

local QUESTIONS = {
	Sortie = "You won your first dogfight! How was it?",
	Match1 = "How's Afterburner so far?",
	Match3 = "Enjoying Afterburner?",
}

local function PulseCard(props: { Moment: string, OnAnswer: (string, string?) -> () })
	local picked, setPicked = React.useState(nil :: string?)
	local text, setText = React.useState("")
	local height = if picked then 178 else 112
	local panel = e(C.Panel, {
		Size = UDim2.fromOffset(WIDTH, height),
		Position = UDim2.fromScale(0.5, 0.6),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Padding = 14,
		StrokeColor = Theme.Accent,
		StrokeThickness = 2,
	}, {
		Question = e(C.Label, {
			Text = QUESTIONS[props.Moment] or QUESTIONS.Match1,
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
			OnClick = function()
				-- Dismissed: a thumb already picked still counts
				props.OnAnswer(picked or "skip", nil)
			end,
		}),
		Up = if picked == nil
			then e(C.Button, {
				Text = "👍  GOOD",
				Size = UDim2.new(0.5, -5, 0, 52),
				Position = UDim2.fromOffset(0, 32),
				TextSize = 16,
				Color = Theme.Good,
				TextColor = Color3.fromRGB(14, 16, 22),
				OnClick = function()
					setPicked("up")
				end,
			})
			else nil,
		Down = if picked == nil
			then e(C.Button, {
				Text = "👎  NOT GREAT",
				Size = UDim2.new(0.5, -5, 0, 52),
				Position = UDim2.new(1, 0, 0, 32),
				AnchorPoint = Vector2.new(1, 0),
				TextSize = 16,
				Color = Theme.Bad,
				TextColor = Color3.fromRGB(14, 16, 22),
				OnClick = function()
					setPicked("down")
				end,
			})
			else nil,
		Prompt = if picked
			then e(C.Label, {
				Text = if picked == "up"
					then "Great! What would make it even better? (optional)"
					else "Sorry! What would make it better? (optional)",
				Size = UDim2.new(1, 0, 0, 18),
				Position = UDim2.fromOffset(0, 30),
				TextSize = 13,
				Color = Theme.Dim,
			})
			else nil,
		Box = if picked
			then e("TextBox", {
				Text = text,
				PlaceholderText = "A few words is plenty…",
				Size = UDim2.new(1, 0, 0, 40),
				Position = UDim2.fromOffset(0, 52),
				BackgroundColor3 = Theme.Background,
				BorderSizePixel = 0,
				ClearTextOnFocus = false,
				Font = Theme.Font,
				TextSize = 14,
				TextColor3 = Theme.Text,
				PlaceholderColor3 = Theme.Dim,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextWrapped = true,
				[React.Change.Text] = function(box: TextBox)
					local value = string.sub(box.Text, 1, Pulse.MAX_TEXT)
					if value ~= box.Text then
						box.Text = value
					end
					setText(value)
				end,
			}, {
				Corner = C.corner(6),
				Padding = e("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }),
			})
			else nil,
		Send = if picked
			then e(C.Button, {
				Text = if string.match(text, "%S") then "SEND" else "DONE",
				Style = "Primary",
				Size = UDim2.new(1, 0, 0, 40),
				Position = UDim2.new(0, 0, 1, -40),
				TextSize = 15,
				OnClick = function()
					props.OnAnswer(picked :: string, if string.match(text, "%S") then text else nil)
				end,
			})
			else nil,
	})
	return ReactRoblox.createPortal({
		AfterburnerPulse = e("ScreenGui", {
			DisplayOrder = 25,
			IgnoreGuiInset = true,
			ResetOnSpawn = false,
			ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		}, { Card = panel }),
	}, Players.LocalPlayer:WaitForChild("PlayerGui"))
end

return PulseCard
