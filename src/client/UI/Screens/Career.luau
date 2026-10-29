--!strict
-- Career (LIV-02): your lifetime stats and the achievements, earned ones lit with the date, the rest dimmed
-- with what they ask for. props: Data.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("React")) :: any
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Achievements = require(Shared.Achievements)

local C = require(script.Parent.Parent.Components)
local Theme = require(script.Parent.Parent.Theme)

local e = React.createElement
local CARD_W, CARD_H = 250, 96

local function stat(label: string, value: string, order: number)
	return e("Frame", { Size = UDim2.new(1, 0, 0, 34), BackgroundTransparency = 1, LayoutOrder = order }, {
		Label = e(C.Label, { Text = label, Size = UDim2.fromScale(0.6, 1), TextSize = 15, Color = Theme.Dim }),
		Value = e(C.Label, {
			Text = value,
			Size = UDim2.fromScale(0.4, 1),
			Position = UDim2.fromScale(0.6, 0),
			TextSize = 18,
			Bold = true,
			Align = "Right",
		}),
	})
end

local function card(def: any, earned: any, order: number)
	local lit = earned ~= nil
	return e(C.Panel, {
		Size = UDim2.fromOffset(CARD_W, CARD_H),
		Color = if lit then Theme.PanelLight else Theme.Background,
		Transparency = if lit then 0 else 0.3,
		Padding = 12,
		LayoutOrder = order,
		StrokeColor = if lit then Theme.Accent else nil,
		StrokeThickness = if lit then 1.5 else nil,
	}, {
		Name = e(C.Label, {
			Text = def.name,
			Size = UDim2.new(1, 0, 0, 22),
			Bold = true,
			TextSize = 16,
			Color = if lit then Theme.Accent else Theme.Dim,
		}),
		Text = e(C.Label, {
			Text = def.text,
			Size = UDim2.new(1, 0, 0, 34),
			Position = UDim2.fromOffset(0, 24),
			TextSize = 12,
			Wrap = true,
			Color = if lit then Theme.Text else Theme.Dim,
		}),
		When = e(C.Label, {
			Text = if lit then os.date("!Earned %d %b %Y", earned.At) :: string else "Not yet",
			Size = UDim2.new(1, 0, 0, 14),
			Position = UDim2.new(0, 0, 1, -14),
			TextSize = 11,
			Color = if lit then Theme.Good else Theme.Locked,
		}),
	})
end

local function Career(props: any)
	local data = props.Data
	local stats = data.Stats or {}
	local earned = data.Achievements or {}
	local kills = (stats.Kills or 0) + (stats.AIKills or 0)
	local deaths = stats.Deaths or 0
	local count = 0
	for _ in earned do
		count += 1
	end

	local cards: { [string]: any } = {
		Grid = e("UIGridLayout", {
			CellSize = UDim2.fromOffset(CARD_W, CARD_H),
			CellPadding = UDim2.fromOffset(12, 12),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}
	for i, def in Achievements.LIST do
		cards[def.id] = card(def, earned[def.id], i)
	end

	return e("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, {
		Stats = e(C.Panel, {
			Size = UDim2.fromOffset(300, 330),
			Position = UDim2.fromOffset(20, 20),
			Padding = 16,
		}, {
			Layout = C.List({ Gap = 4 }),
			Title = e(C.Label, { Text = "CAREER", Bold = true, Color = Theme.Accent, TextSize = 14, LayoutOrder = 0 }),
			Level = stat("Pilot level", tostring(data.PilotLevel or 1), 1),
			Matches = stat("Matches", tostring(stats.Matches or 0), 2),
			Wins = stat("Wins", tostring(stats.Wins or 0), 3),
			Kills = stat("Kills", tostring(kills), 4),
			Players = stat("  of them players", tostring(stats.Kills or 0), 5),
			Deaths = stat("Times shot down", tostring(deaths), 6),
			Ratio = stat("Kills per death", string.format("%.2f", kills / math.max(deaths, 1)), 7),
		}),
		Achievements = e(C.Panel, {
			Size = UDim2.new(1, -380, 1, -40),
			Position = UDim2.fromOffset(340, 20),
			Padding = 16,
		}, {
			Title = e(C.Label, {
				Text = `ACHIEVEMENTS  ·  {count} / {#Achievements.LIST}`,
				Bold = true,
				Color = Theme.Accent,
				TextSize = 14,
				Size = UDim2.new(1, 0, 0, 20),
			}),
			Cards = e("ScrollingFrame", {
				Size = UDim2.new(1, 0, 1, -32),
				Position = UDim2.fromOffset(0, 32),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ScrollBarThickness = 4,
				CanvasSize = UDim2.new(),
				AutomaticCanvasSize = Enum.AutomaticSize.Y,
			}, cards),
		}),
	})
end

return Career
