--!strict
-- The report-a-cheater window (CMP-03): pick the pilot (if not picked already) and a reason, then SEND. The
-- report goes to ReportService with the pilot's anti-cheat data. Shown in the menu's modal ScreenGui
-- (MenuController), over the menu.
-- props: Targets ({ { userId, name } }), Target (userId or nil), Reason (Reports reason id or nil), Pending,
--   Message (the server's answer), Sent (true once it went through), OnTarget(userId), OnReason(id), OnSend(),
--   OnClose().

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("React")) :: any
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Reports = require(Shared.Reports)

local C = require(script.Parent.Components)
local Theme = require(script.Parent.Theme)

local e = React.createElement
local WIDTH, HEIGHT = 560, 470

local function choices(items: { any }, selected: any, onPick: (any) -> ()): { [string]: any }
	local children: { [string]: any } = { Layout = C.List({ Gap = 6 }) }
	for i, item in items do
		children[`C{i}`] = e(C.Button, {
			Text = item.label,
			Style = "Ghost",
			Selected = item.id == selected,
			Size = UDim2.new(1, 0, 0, 36),
			TextSize = 14,
			LayoutOrder = i,
			OnClick = function()
				onPick(item.id)
			end,
		})
	end
	return children
end

local function ReportDialog(props: any)
	local targets = {}
	for _, target in props.Targets or {} do
		table.insert(targets, { id = target.userId, label = target.name })
	end
	table.sort(targets, function(a, b)
		return a.label:lower() < b.label:lower()
	end)

	local body: { [string]: any } = {
		Title = e(C.Label, {
			Text = "REPORT A CHEATER",
			Size = UDim2.new(1, 0, 0, 28),
			Heavy = true,
			TextSize = 24,
			Color = Theme.Accent,
		}),
		Intro = e(C.Label, {
			Text = "Reports are checked against this server's anti-cheat data. " .. Reports.ROBLOX_HINT,
			Size = UDim2.new(1, 0, 0, 34),
			Position = UDim2.fromOffset(0, 32),
			TextSize = 12,
			Wrap = true,
			Color = Theme.Dim,
		}),
	}
	if #targets == 0 then
		body.Empty = e(C.Label, {
			Text = "There's nobody else on this server to report.",
			Size = UDim2.new(1, 0, 0, 24),
			Position = UDim2.fromOffset(0, 90),
			TextSize = 14,
		})
	else
		body.PilotHead = e(C.Label, {
			Text = "PILOT",
			Size = UDim2.new(0.5, -8, 0, 18),
			Position = UDim2.fromOffset(0, 76),
			Bold = true,
			TextSize = 12,
			Color = Theme.Accent,
		})
		body.Pilots = e("ScrollingFrame", {
			Size = UDim2.new(0.5, -8, 1, -170),
			Position = UDim2.fromOffset(0, 98),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollBarThickness = 4,
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			CanvasSize = UDim2.new(),
		}, choices(targets, props.Target, props.OnTarget))
		body.ReasonHead = e(C.Label, {
			Text = "REASON",
			Size = UDim2.new(0.5, -8, 0, 18),
			Position = UDim2.new(0.5, 8, 0, 76),
			Bold = true,
			TextSize = 12,
			Color = Theme.Accent,
		})
		body.Reasons = e("Frame", {
			Size = UDim2.new(0.5, -8, 1, -170),
			Position = UDim2.new(0.5, 8, 0, 98),
			BackgroundTransparency = 1,
		}, choices(Reports.REASONS, props.Reason, props.OnReason))
	end
	body.Message = e(C.Label, {
		Text = props.Message or "",
		Size = UDim2.new(1, -330, 0, 44),
		Position = UDim2.new(0, 0, 1, -44),
		TextSize = 13,
		Bold = true,
		Wrap = true,
		Color = if props.Sent then Theme.Good else Theme.Warn,
	})
	body.Close = e(C.Button, {
		Text = if props.Sent then "DONE" else "CANCEL",
		Style = "Ghost",
		Size = UDim2.fromOffset(140, 44),
		Position = UDim2.new(1, if props.Sent then -140 else -310, 1, -44),
		TextSize = 14,
		OnClick = props.OnClose,
	})
	if not props.Sent then
		body.Send = e(C.Button, {
			Text = "SEND REPORT",
			Style = "Primary",
			Size = UDim2.fromOffset(160, 44),
			Position = UDim2.new(1, -160, 1, -44),
			TextSize = 14,
			Pending = props.Pending,
			Disabled = not (props.Target and props.Reason),
			OnClick = props.OnSend,
		})
	end

	return e("TextButton", { -- dims the menu behind and swallows clicks
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		AutoButtonColor = false,
		Text = "",
	}, {
		Card = e(C.Panel, {
			Size = UDim2.fromOffset(WIDTH, HEIGHT),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Padding = 24,
			StrokeColor = Theme.Accent,
			StrokeThickness = 2,
		}, body),
	})
end

return ReportDialog
