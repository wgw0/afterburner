--!strict
-- The daily login reward window (LIV-03): this week of your streak as 7 tiles (claimed ones ticked, today's
-- lit, the rest to come, day 7 the big one), CLAIM, then what you got. Shown over the menu once a day, in
-- its own ScreenGui above the menu's (MenuController).
-- props: Streak (data.Streak), Today (UTC day), Result (after claiming: { count, credits, freeRP, title? }),
--   Pending, OnClaim(), OnClose().

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("React")) :: any
local Shared = ReplicatedStorage:WaitForChild("Shared")
local LevelRewards = require(Shared.Config.LevelRewards)
local Streak = require(Shared.Streak)

local C = require(script.Parent.Components)
local Theme = require(script.Parent.Theme)

local e = React.createElement
local TILE_W, TILE_H = 92, 112

local function tile(count: number, best: number, state: string, order: number)
	local reward = Streak.reward(count, best)
	local big = Streak.weekDay(count) == #Streak.WEEK
	local lines = { `{C.number(reward.credits)} Cr` }
	if reward.freeRP > 0 then
		table.insert(lines, `{C.number(reward.freeRP)} RP`)
	end
	if reward.title then
		table.insert(lines, `"{LevelRewards.TITLES[reward.title] or reward.title}"`)
	end
	local today = state == "Today"
	return e(C.Panel, {
		Size = UDim2.fromOffset(TILE_W, TILE_H),
		Color = if today then Theme.AccentDark elseif state == "Done" then Theme.PanelLight else Theme.Background,
		Transparency = if state == "Later" then 0.3 else 0,
		StrokeColor = if today then Theme.Accent elseif big then Theme.Rarity.Legendary else nil,
		StrokeThickness = if today or big then 2 else nil,
		Padding = 8,
		LayoutOrder = order,
	}, {
		Day = e(C.Label, {
			Text = `DAY {count}`,
			Size = UDim2.new(1, 0, 0, 16),
			Bold = true,
			TextSize = 12,
			Align = "Center",
			Color = if today then Theme.Text elseif big then Theme.Rarity.Legendary else Theme.Dim,
		}),
		Reward = e(C.Label, {
			Text = table.concat(lines, "\n"),
			Size = UDim2.new(1, 0, 1, -40),
			Position = UDim2.fromOffset(0, 20),
			TextSize = 12,
			Bold = today or big,
			Wrap = true,
			Align = "Center",
			Color = if state == "Later" then Theme.Dim else Theme.Text,
		}),
		Tick = e(C.Label, {
			Text = if state == "Done" then "✓" elseif today then "TODAY" else "",
			Size = UDim2.new(1, 0, 0, 16),
			Position = UDim2.new(0, 0, 1, -16),
			TextSize = 11,
			Bold = true,
			Align = "Center",
			Color = if state == "Done" then Theme.Good else Theme.Text,
		}),
	})
end

local function DailyReward(props: any)
	local state = props.Streak
	local result = props.Result
	-- The week shown: the one today's claim lands in (or landed in)
	local current = if result then result.count else Streak.nextCount(state, props.Today)
	local weekStart = current - Streak.weekDay(current) + 1
	local best = if result then state.Best - (if result.title then current else 0) else state.Best
	local tiles: { [string]: any } = { Layout = C.List({ Horizontal = true, Gap = 8, Align = "Center" }) }
	for i = 1, #Streak.WEEK do
		local count = weekStart + i - 1
		local tileState = if count < current then "Done" elseif count == current then "Today" else "Later"
		if result and count == current then
			tileState = "Done"
		end
		tiles[`D{i}`] = tile(count, best, tileState, i)
	end

	local got = nil
	if result then
		local parts = { `+{C.number(result.credits)} Credits` }
		if result.freeRP > 0 then
			table.insert(parts, `+{C.number(result.freeRP)} Free RP`)
		end
		if result.title then
			table.insert(parts, `title "{LevelRewards.TITLES[result.title] or result.title}" (pick it in Career)`)
		end
		got = table.concat(parts, "  ·  ")
	end

	return e("TextButton", { -- dims the menu behind and swallows clicks
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		AutoButtonColor = false,
		Text = "",
	}, {
		Card = e(C.Panel, {
			Size = UDim2.fromOffset(7 * TILE_W + 6 * 8 + 48, 310),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Padding = 24,
			StrokeColor = Theme.Accent,
			StrokeThickness = 2,
		}, {
			Title = e(C.Label, {
				Text = "DAILY REWARD",
				Size = UDim2.new(1, 0, 0, 28),
				Heavy = true,
				TextSize = 24,
				Color = Theme.Accent,
			}),
			Streak = e(C.Label, {
				Text = if result then `Day {result.count} of your streak` else `Day {current} of your streak`,
				Size = UDim2.new(1, 0, 0, 20),
				Position = UDim2.fromOffset(0, 32),
				TextSize = 14,
				Bold = true,
			}),
			Tiles = e("Frame", {
				Size = UDim2.new(1, 0, 0, TILE_H),
				Position = UDim2.fromOffset(0, 62),
				BackgroundTransparency = 1,
			}, tiles),
			Note = e(C.Label, {
				Text = got
					or "Come back each day. Miss a day and your streak waits; miss more and you go back to the start of the week.",
				Size = UDim2.new(1, -200, 0, 36),
				Position = UDim2.new(0, 0, 1, -40),
				TextSize = if got then 14 else 12,
				Bold = got ~= nil,
				Wrap = true,
				Color = if got then Theme.Good else Theme.Dim,
			}),
			Action = e(C.Button, {
				Text = if result then "NICE" else "CLAIM",
				Style = "Primary",
				Size = UDim2.fromOffset(180, 44),
				Position = UDim2.new(1, 0, 1, -44),
				AnchorPoint = Vector2.new(1, 0),
				TextSize = 16,
				Pending = props.Pending,
				OnClick = if result then props.OnClose else props.OnClaim,
			}),
		}),
	})
end

return DailyReward
