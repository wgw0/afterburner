--!strict
-- Today's and this week's challenges (LIV-01), on the right of the Hangar: each with its progress bar and
-- reward, a tick when done, and REROLL on unfinished daily ones while a reroll is left. Shows the time to the
-- next reset. props: Data (player data), OnReroll(index) -> (ok, err).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("React")) :: any
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Challenges = require(Shared.Challenges)
local Perks = require(Shared.Perks)

local C = require(script.Parent.Components)
local Theme = require(script.Parent.Theme)

local e = React.createElement
local WIDTH = 300
local ROW_H = 62

local function duration(seconds: number): string
	local hours = seconds // 3600
	if hours >= 24 then
		return `{hours // 24}d {hours % 24}h`
	end
	return `{hours}h {(seconds % 3600) // 60}m`
end

local function row(props: any)
	local def = Challenges.get(props.Entry.Id)
	if not def then
		return nil
	end
	local entry = props.Entry
	return e("Frame", {
		Size = UDim2.new(1, 0, 0, ROW_H),
		BackgroundTransparency = 1,
		LayoutOrder = props.Order,
	}, {
		Text = e(C.Label, {
			Text = def.text,
			Size = UDim2.new(1, if props.CanReroll then -72 else 0, 0, 34),
			TextSize = 13,
			Bold = true,
			Wrap = true,
			Color = if entry.Done then Theme.Dim else Theme.Text,
		}),
		Reroll = if props.CanReroll
			then e(C.Button, {
				Text = "REROLL",
				Style = "Ghost",
				Size = UDim2.fromOffset(66, 24),
				Position = UDim2.new(1, -66, 0, 2),
				TextSize = 10,
				Pending = props.Pending,
				OnClick = props.OnReroll,
			})
			else nil,
		Bar = e(C.Bar, {
			Value = entry.Progress / def.target,
			Size = UDim2.new(1, -128, 0, 8),
			Position = UDim2.fromOffset(0, 40),
			Color = if entry.Done then Theme.Good else Theme.Accent,
		}),
		Count = e(C.Label, {
			Text = if entry.Done then "✓ DONE" else `{entry.Progress}/{def.target}`,
			Size = UDim2.fromOffset(50, 16),
			Position = UDim2.new(1, -122, 0, 36),
			TextSize = 11,
			Bold = true,
			Align = "Right",
			Color = if entry.Done then Theme.Good else Theme.Dim,
		}),
		Reward = e(C.Label, {
			Text = `+{C.number(def.credits)} Cr`,
			Size = UDim2.fromOffset(66, 16),
			Position = UDim2.new(1, -66, 0, 36),
			TextSize = 11,
			Align = "Right",
			Color = Theme.Warn,
		}),
	})
end

local function ChallengesPanel(props: any)
	local pending, setPending = React.useState(nil :: number?)
	local err, setErr = React.useState(nil :: string?)
	local state = props.Data.Challenges
	if not state then
		return nil
	end
	local untilDay, untilWeek = Challenges.untilReset(os.time())
	local allowance = Perks.rerolls(props.Data, Challenges.REROLLS_PER_DAY) -- VIP gets one more
	local rerollLeft = (state.Rerolls or 0) < allowance and state.Day == Challenges.day(os.time())

	local children: { [string]: any } = {
		Layout = C.List({ Gap = 4 }),
		Daily = e("Frame", { Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1, LayoutOrder = 0 }, {
			Title = e(C.Label, {
				Text = "DAILY CHALLENGES",
				Size = UDim2.fromScale(0.6, 1),
				Bold = true,
				Color = Theme.Accent,
				TextSize = 13,
			}),
			Reset = e(C.Label, {
				Text = `new in {duration(untilDay)}`,
				Size = UDim2.fromScale(0.4, 1),
				Position = UDim2.fromScale(0.6, 0),
				TextSize = 11,
				Color = Theme.Dim,
				Align = "Right",
			}),
		}),
	}
	for i, entry in state.Daily or {} do
		children[`Daily{i}`] = e(row, {
			Entry = entry,
			Order = i,
			CanReroll = rerollLeft and not entry.Done,
			Pending = pending == i,
			OnReroll = function()
				setPending(i)
				task.spawn(function()
					local ok, why = props.OnReroll(i)
					setPending(nil)
					setErr(if ok then nil else why)
				end)
			end,
		})
	end
	children.Weekly = e("Frame", { Size = UDim2.new(1, 0, 0, 26), BackgroundTransparency = 1, LayoutOrder = 10 }, {
		Title = e(C.Label, {
			Text = "WEEKLY",
			Size = UDim2.new(0.6, 0, 0, 18),
			Position = UDim2.fromOffset(0, 8),
			Bold = true,
			Color = Theme.Accent,
			TextSize = 13,
		}),
		Reset = e(C.Label, {
			Text = `new in {duration(untilWeek)}`,
			Size = UDim2.new(0.4, 0, 0, 18),
			Position = UDim2.new(0.6, 0, 0, 8),
			TextSize = 11,
			Color = Theme.Dim,
			Align = "Right",
		}),
	})
	for i, entry in state.Weekly or {} do
		children[`Weekly{i}`] = e(row, { Entry = entry, Order = 10 + i })
	end
	children.Error = if err
		then e(
			C.Label,
			{ Text = err, Color = Theme.Bad, TextSize = 12, LayoutOrder = 99, Size = UDim2.new(1, 0, 0, 16) }
		)
		else nil

	local rows = #(state.Daily or {}) + #(state.Weekly or {})
	return e(C.Panel, {
		Size = UDim2.fromOffset(WIDTH, 18 + 26 + rows * (ROW_H + 4) + (if err then 20 else 0) + 34),
		Position = UDim2.new(1, -20, 0, 20),
		AnchorPoint = Vector2.new(1, 0),
		Padding = 14,
	}, children)
end

return ChallengesPanel
