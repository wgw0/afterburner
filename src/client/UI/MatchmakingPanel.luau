--!strict
-- How matchmaking picks your opponents (MMK-03), on the right of the lobby's Hangar between the challenges
-- and the free spin: the jet you click PLAY with sets your BR, and the range of BR you can meet. For a duel
-- (MCH-09), your duel rank and rating, and how a duel goes.
-- props: AirframeId (the selected jet), or nil for none; Mode (the mode PLAY queues for); Data (the save).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("React")) :: any
local Shared = ReplicatedStorage:WaitForChild("Shared")
local AircraftData = require(Shared.AircraftData)
local Duel = require(Shared.Duel)
local LiveConfig = require(Shared.LiveConfig)
local Queue = require(Shared.Queue)

local C = require(script.Parent.Components)
local Theme = require(script.Parent.Theme)

local e = React.createElement
local HEIGHT = 176

local function rating(br: number): string
	return string.format("%.1f", math.max(br, 0))
end

-- The lowest and highest BR of any jet (the range shown stops there)
local function extremes(): (number, number)
	local low, high = math.huge, -math.huge
	for id in AircraftData.getAll() do
		local br = LiveConfig.battleRating(id) :: number
		low, high = math.min(low, br), math.max(high, br)
	end
	return low, high
end

-- Duels: your rank and rating (and the next rank), and how a duel goes
local function DuelPanel(props: { Mode: string, Data: any })
	local rec = props.Data and props.Data.Duel or Duel.newRecord()
	local rating = rec.Rating or Duel.START_RATING
	local rank = Duel.rankFor(rating)
	local nextRank = Duel.nextRank(rating)
	local ranked = props.Mode == "Duel"
	local record =
		`{rec.Won or 0} won · {rec.Lost or 0} lost{if (rec.Drawn or 0) > 0 then ` · {rec.Drawn} drawn` else ""}`
	return e(C.Panel, {
		Size = UDim2.fromOffset(300, HEIGHT),
		Position = UDim2.new(1, -20, 1, -116),
		AnchorPoint = Vector2.new(1, 1),
		Padding = 14,
	}, {
		Title = e(C.Label, {
			Text = if ranked then "RANKED DUEL" else "CASUAL DUEL",
			Size = UDim2.new(1, 0, 0, 18),
			Bold = true,
			TextSize = 13,
			Color = Theme.Accent,
		}),
		Rank = e(C.Label, {
			Text = `{string.upper(rank.name)}  ·  {rating}`,
			Size = UDim2.new(1, 0, 0, 22),
			Position = UDim2.fromOffset(0, 22),
			Bold = true,
			TextSize = 18,
			Color = rank.colour,
		}),
		Next = e(C.Label, {
			Text = if nextRank then `{nextRank.name} at {nextRank.min}  ·  {record}` else `Top rank  ·  {record}`,
			Size = UDim2.new(1, 0, 0, 16),
			Position = UDim2.fromOffset(0, 46),
			TextSize = 12,
			Color = Theme.Dim,
		}),
		How = e(C.Label, {
			Text = `1v1, best of five rounds. Each round you both start head-on with one life; first to {Duel.ROUNDS_TO_WIN} round wins. {if ranked
				then "Wins and losses move your rating, against pilots rated near you."
				else "Practice: your rating doesn't move."} Nobody about after {Duel.AI_AFTER} s? An AI pilot takes them on (unranked).`,
			Size = UDim2.new(1, 0, 0, 90),
			Position = UDim2.fromOffset(0, 66),
			TextSize = 12,
			Wrap = true,
			Color = Theme.Text,
		}),
	})
end

local function MatchmakingPanel(props: { AirframeId: string?, Mode: string?, Data: any })
	if props.Mode == "Duel" or props.Mode == "DuelCasual" then
		return DuelPanel({ Mode = props.Mode :: string, Data = props.Data })
	end
	local airframe = props.AirframeId and AircraftData.get(props.AirframeId) :: any
	local br = airframe and LiveConfig.battleRating(props.AirframeId :: string)
	local you, range
	if airframe and br then
		you = `{airframe.DisplayName} · BR {rating(br)}`
		local low, high = extremes()
		range = `Opponents: BR {rating(math.max(br - Queue.SPREAD_MIN, low))} – {rating(
			math.min(br + Queue.SPREAD_MIN, high)
		)}`
	else
		you = "Pick a jet in your lineup"
		range = `Opponents: within {rating(Queue.SPREAD_MIN)} BR of it`
	end
	return e(C.Panel, {
		Size = UDim2.fromOffset(300, HEIGHT),
		Position = UDim2.new(1, -20, 1, -116),
		AnchorPoint = Vector2.new(1, 1),
		Padding = 14,
	}, {
		Title = e(C.Label, {
			Text = "MATCHMAKING",
			Size = UDim2.new(1, 0, 0, 18),
			Bold = true,
			TextSize = 13,
			Color = Theme.Accent,
		}),
		Jet = e(C.Label, {
			Text = you,
			Size = UDim2.new(1, 0, 0, 18),
			Position = UDim2.fromOffset(0, 24),
			Bold = true,
			TextSize = 14,
		}),
		Range = e(C.Label, {
			Text = range,
			Size = UDim2.new(1, 0, 0, 16),
			Position = UDim2.fromOffset(0, 44),
			TextSize = 13,
		}),
		How = e(C.Label, {
			Text = `You're matched by the jet you click PLAY with, against jets near its level. The longer you wait, the wider the search: up to {rating(
				Queue.SPREAD_MAX
			)} BR away, and any mode after {Queue.ANY_MODE_AFTER // 60} minutes. Empty seats get AI pilots.`,
			Size = UDim2.new(1, 0, 0, 86),
			Position = UDim2.fromOffset(0, 64),
			TextSize = 13,
			Wrap = true,
			Color = Theme.Dim,
		}),
	})
end

return MatchmakingPanel
