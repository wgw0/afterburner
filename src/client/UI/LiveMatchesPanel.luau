--!strict
-- LIVE NOW, across the top of the lobby's Hangar (Will: show ongoing games and let people join them easily):
-- up to three matches in progress with a free seat (Shared/LiveMatches), each with its mode (in its kind's
-- colour), map, pilots and time left, and JOIN, which takes a seat in it (an AI pilot's). Hidden when there
-- are none.
-- props: Matches ({ { id, mode, map, humans, seats, state, timeLeft } }), Online (pilots online), OnJoin(id).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("React")) :: any
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Maps = require(Shared.Config.Maps)

local C = require(script.Parent.Components)
local ModeInfo = require(script.Parent.ModeInfo)
local Theme = require(script.Parent.Theme)

local e = React.createElement
local CARD_W, CARD_H, GAP = 256, 84, 12
local WIDTH = 3 * CARD_W + 2 * GAP
local SIDE_PANELS = 2 * (20 + 300 + 16) -- the lineup on the left, the 300-wide column on the right, gaps

local function timeText(match: any): string
	if match.state == "Countdown" then
		return "starting now"
	elseif match.timeLeft >= 3600 then
		return "no time limit"
	end
	return `{match.timeLeft // 60}:{string.format("%02d", match.timeLeft % 60)} left`
end

local function Card(props: { Match: any, Order: number, OnJoin: (string) -> () })
	local match = props.Match
	local mode = ModeInfo.MODES[match.mode]
	local kind = mode and ModeInfo.KINDS[mode.kind]
	local colour = if kind then kind.colour else Theme.Accent
	local map = Maps.get(match.map)
	return e(C.Panel, {
		Size = UDim2.fromOffset(CARD_W, CARD_H),
		LayoutOrder = props.Order,
		StrokeColor = colour,
		StrokeThickness = 1.5,
	}, {
		Stripe = e("Frame", {
			Size = UDim2.new(0, 5, 1, 0),
			BackgroundColor3 = colour,
			BorderSizePixel = 0,
		}, { Corner = C.corner(3) }),
		Name = e(C.Label, {
			Text = string.upper(if mode then mode.name else match.mode),
			Size = UDim2.new(1, -118, 0, 22), -- clear of JOIN (86 wide, 12 in)
			Position = UDim2.fromOffset(16, 10),
			TextSize = 17,
			Heavy = true,
			Color = colour,
		}),
		Where = e(C.Label, {
			Text = if map then map.DisplayName else "",
			Size = UDim2.new(1, -118, 0, 18), -- clear of JOIN (86 wide, 12 in)
			Position = UDim2.fromOffset(16, 33),
			TextSize = 13,
			Color = Theme.Dim,
		}),
		Pilots = e(C.Label, {
			Text = `{match.humans}/{match.seats} pilots  ·  {timeText(match)}`,
			Size = UDim2.new(1, -118, 0, 18), -- clear of JOIN (86 wide, 12 in)
			Position = UDim2.fromOffset(16, 54),
			TextSize = 13,
			Bold = true,
		}),
		Join = e(C.Button, {
			Text = "JOIN",
			Style = "Primary",
			Size = UDim2.fromOffset(86, 44),
			Position = UDim2.new(1, -12, 0.5, 0),
			AnchorPoint = Vector2.new(1, 0.5),
			TextSize = 17,
			OnClick = function()
				props.OnJoin(match.id)
			end,
		}),
	})
end

local function LiveMatchesPanel(props: any)
	local matches = props.Matches or {}
	if #matches == 0 then
		return nil
	end
	local cards: { [string]: any } = { Layout = C.List({ Horizontal = true, Gap = GAP, Align = "Center" }) }
	for i, match in matches do
		cards[`M{i}`] = e(Card, { Match = match, Order = i, OnJoin = props.OnJoin })
	end
	return e(C.Fit, {
		Width = WIDTH,
		Height = CARD_H + 26,
		Sides = SIDE_PANELS,
		Position = UDim2.new(0.5, 0, 0, 92), -- under the news banner and the friends-bonus chip (56 to 84)
		AnchorPoint = Vector2.new(0.5, 0),
		ZIndex = 3,
	}, {
		Title = e(C.Label, {
			Text = `LIVE NOW  ·  join a match in progress{if (props.Online or 0) > 0
				then `  ·  {props.Online} pilot{if props.Online == 1 then "" else "s"} online`
				else ""}`,
			Size = UDim2.new(1, 0, 0, 20),
			Align = "Center",
			TextSize = 14,
			Bold = true,
			Color = Theme.Accent,
		}),
		Cards = e("Frame", {
			Size = UDim2.new(1, 0, 0, CARD_H),
			Position = UDim2.fromOffset(0, 26),
			BackgroundTransparency = 1,
		}, cards),
	})
end

return LiveMatchesPanel
