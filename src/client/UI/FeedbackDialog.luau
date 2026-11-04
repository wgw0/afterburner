--!strict
-- The report-a-bug window (Shared/Feedback): a type (Bug / Lag / Idea / Other), what happened, SEND. Device
-- info goes with it (MenuController gathers it). Shown in the menu's modal ScreenGui, over the menu.
-- props: Kind, Text, Pending, Message (the server's answer), Sent, OnKind(kind), OnText(text), OnSend(),
--   OnClose().

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("React")) :: any
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Feedback = require(Shared.Feedback)

local C = require(script.Parent.Components)
local Theme = require(script.Parent.Theme)

local e = React.createElement
local WIDTH, HEIGHT = 640, 480
local KIND_LABELS = { Bug = "BUG", Lag = "LAG", Idea = "IDEA", Other = "OTHER" }

local function FeedbackDialog(props: any)
	local text = props.Text or ""
	local length = utf8.len(text) or #text
	local tabs: { [string]: any } = { Layout = C.List({ Horizontal = true, Gap = 10 }) }
	for i, kind in Feedback.KINDS do
		tabs[kind] = e(C.Button, {
			Text = KIND_LABELS[kind],
			Style = if props.Kind == kind then "Primary" else "Ghost",
			Size = UDim2.new(0.25, -8, 1, 0),
			TextSize = 18,
			LayoutOrder = i,
			OnClick = function()
				props.OnKind(kind)
			end,
		})
	end

	return e("TextButton", { -- dims the menu behind and swallows clicks
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.35,
	}, {
		Panel = e(C.Panel, {
			Size = UDim2.fromOffset(WIDTH, HEIGHT),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Padding = 28,
			StrokeColor = Theme.Accent,
			StrokeThickness = 2,
		}, {
			Title = e(C.Label, {
				-- Follows the tab: it isn't always a bug
				Text = ({ Bug = "REPORT A BUG", Lag = "REPORT LAG", Idea = "SHARE AN IDEA", Other = "SEND FEEDBACK" })[props.Kind]
					or "SEND FEEDBACK",
				Size = UDim2.new(1, -50, 0, 36),
				Heavy = true,
				TextSize = 32,
				Color = Theme.Accent,
			}),
			Close = e(C.Button, {
				Text = "X",
				Style = "Ghost",
				Size = UDim2.fromOffset(40, 40),
				Position = UDim2.new(1, -40, 0, -2),
				TextSize = 18,
				OnClick = props.OnClose,
			}),
			Tabs = e("Frame", {
				Size = UDim2.new(1, 0, 0, 48),
				Position = UDim2.fromOffset(0, 54),
				BackgroundTransparency = 1,
			}, tabs),
			Box = e("Frame", {
				Size = UDim2.new(1, 0, 0, 180),
				Position = UDim2.fromOffset(0, 118),
				BackgroundColor3 = Theme.Background,
			}, {
				Corner = C.corner(10),
				Stroke = e("UIStroke", { Color = Theme.Dim, Thickness = 1, Transparency = 0.5 }),
				Input = e("TextBox", {
					Text = text,
					PlaceholderText = "What happened, and where? (a few words is fine)",
					PlaceholderColor3 = Theme.Dim,
					TextColor3 = Theme.Text,
					Font = Theme.Font,
					TextSize = 18,
					TextWrapped = true,
					MultiLine = true,
					ClearTextOnFocus = false,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextYAlignment = Enum.TextYAlignment.Top,
					BackgroundTransparency = 1,
					Size = UDim2.new(1, -28, 1, -40),
					Position = UDim2.fromOffset(14, 12),
					[React.Change.Text] = function(box: TextBox)
						-- Hold it to the limit as they type
						local typed = box.Text
						if (utf8.len(typed) or #typed) > Feedback.MAX_LENGTH then
							typed =
								string.sub(typed, 1, (utf8.offset(typed, Feedback.MAX_LENGTH + 1) or #typed + 1) - 1)
							box.Text = typed
						end
						props.OnText(typed)
					end,
				}),
				Count = e(C.Label, {
					Text = `{length}/{Feedback.MAX_LENGTH}`,
					Size = UDim2.fromOffset(100, 20),
					Position = UDim2.new(1, -14, 1, -10),
					AnchorPoint = Vector2.new(1, 1),
					TextSize = 15,
					Bold = true,
					Align = "Right",
					Color = Theme.Dim,
				}),
			}),
			Note = e(C.Label, {
				Text = props.Message or "Your device info (frame rate, memory, graphics) is sent with it.",
				Size = UDim2.new(1, 0, 0, 22),
				Position = UDim2.fromOffset(0, 310),
				TextSize = 15,
				Align = "Center",
				Bold = props.Message ~= nil,
				Color = if props.Sent then Theme.Good elseif props.Message then Theme.Warn else Theme.Dim,
			}),
			Send = e(C.Button, {
				Text = if props.Sent then "DONE" else "SEND",
				Style = "Primary",
				Size = UDim2.fromOffset(240, 52),
				Position = UDim2.new(0.5, 0, 1, -52),
				AnchorPoint = Vector2.new(0.5, 0),
				TextSize = 20,
				Pending = props.Pending,
				Disabled = not props.Sent and string.match(text, "%S") == nil, -- nothing written yet
				OnClick = if props.Sent then props.OnClose else props.OnSend,
			}),
		}),
	})
end

return FeedbackDialog
