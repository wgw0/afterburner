--!strict
-- How matchmaking picks your opponents (MMK-03), on the right of the lobby's Hangar between the challenges
-- and the free spin: the jet you click PLAY with sets your BR, and the range of BR you can meet.
-- props: AirframeId (the selected jet), or nil for none.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("React")) :: any
local Shared = ReplicatedStorage:WaitForChild("Shared")
local AircraftData = require(Shared.AircraftData)
local LiveConfig = require(Shared.LiveConfig)
local Queue = require(Shared.Queue)

local C = require(script.Parent.Components)
local Theme = require(script.Parent.Theme)

local e = React.createElement
local HEIGHT = 150

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

local function MatchmakingPanel(props: { AirframeId: string? })
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
			Text = `You're matched by the jet you click PLAY with, against jets near its level (after a long wait, up to {rating(
				Queue.SPREAD_MAX
			)} BR away). In the match you can fly it or a lower jet. Empty seats get AI pilots at that level.`,
			Size = UDim2.new(1, 0, 0, 60),
			Position = UDim2.fromOffset(0, 64),
			TextSize = 11,
			Wrap = true,
			Color = Theme.Dim,
		}),
	})
end

return MatchmakingPanel
