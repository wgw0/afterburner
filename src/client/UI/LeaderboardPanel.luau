--!strict
-- The leaderboards (LIV-05), on the Career screen beside the achievements: a button per board, then its top
-- entries (rank, pilot, score), yours lit, and your own score under them.
-- props: OnLeaderboard(boardId) -> ({ board, entries = { { rank, userId, name, score } }, mine }?, why?)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("React")) :: any
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Leaderboards = require(Shared.Leaderboards)

local C = require(script.Parent.Components)
local Theme = require(script.Parent.Theme)

local e = React.createElement
local ROW_H = 30
local MEDALS = { Color3.fromRGB(255, 201, 60), Color3.fromRGB(200, 210, 220), Color3.fromRGB(215, 140, 80) }

local function LeaderboardPanel(props: any)
	local boardId, setBoardId = React.useState(Leaderboards.BOARDS[1].id)
	local result, setResult = React.useState(nil :: any)
	local why, setWhy = React.useState(nil :: string?)

	React.useEffect(function()
		local current = true
		setResult(nil)
		setWhy(nil)
		task.spawn(function()
			local data, message = props.OnLeaderboard(boardId)
			if current then
				setResult(data)
				setWhy(if data then nil else message or "Couldn't load it just now.")
			end
		end)
		return function()
			current = false
		end
	end, { boardId })

	local board = Leaderboards.get(boardId) :: Leaderboards.Board
	local me = Players.LocalPlayer.UserId

	-- Three to a row, sharing the width (six fixed buttons in one row ran off narrower screens)
	local picker: { [string]: any } = {
		Grid = e("UIGridLayout", {
			CellSize = UDim2.new(1 / 3, -6, 0, 36),
			CellPadding = UDim2.fromOffset(8, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}
	for i, b in Leaderboards.BOARDS do
		picker[b.id] = e(C.Button, {
			Text = string.upper(b.name),
			Style = if b.id == boardId then "Primary" else "Ghost",
			TextSize = 13,
			LayoutOrder = i,
			OnClick = function()
				setBoardId(b.id)
			end,
		})
	end

	local rows: { [string]: any } = { Layout = C.List({ Gap = 2 }) }
	local inTop = false
	if result then
		for _, entry in result.entries do
			local isMe = entry.userId == me or (entry.squadronId ~= nil and entry.squadronId == result.squadronId)
			inTop = inTop or isMe
			local medal = MEDALS[entry.rank]
			rows[`R{entry.rank}`] = e("Frame", {
				Size = UDim2.new(1, 0, 0, ROW_H),
				BackgroundColor3 = if isMe then Theme.AccentDark else Theme.Background,
				BackgroundTransparency = if isMe then 0.2 else 0.5,
				BorderSizePixel = 0,
				LayoutOrder = entry.rank,
			}, {
				Corner = C.corner(6),
				Rank = e(C.Label, {
					Text = `#{entry.rank}`,
					Size = UDim2.new(0, 60, 1, 0),
					Position = UDim2.fromOffset(12, 0),
					Heavy = true,
					TextSize = 15,
					Color = medal or Theme.Dim,
				}),
				Name = e(C.Label, {
					Text = entry.name .. (if isMe then (if entry.squadronId then "  (yours)" else "  (you)") else ""),
					Size = UDim2.new(1, -260, 1, 0),
					Position = UDim2.fromOffset(76, 0),
					Bold = true,
					TextSize = 15,
					Color = if isMe then Theme.Text else medal or Theme.Text,
				}),
				Score = e(C.Label, {
					Text = `{C.number(entry.score)} {board.unit}`,
					Size = UDim2.new(0, 160, 1, 0),
					Position = UDim2.new(1, -172, 0, 0),
					Bold = true,
					TextSize = 15,
					Align = "Right",
				}),
			})
		end
	end

	local status
	if why then
		status = why
	elseif not result then
		status = "Loading…"
	elseif #result.entries == 0 then
		status = if boardId == "Season" and result.mine == 0
			then "No season is running right now."
			else "Nobody's on this board yet. Fly a match to be first."
	elseif inTop then
		status = `You're on the board with {C.number(result.mine)} {board.unit}.`
	else
		status = if result.mine > 0
			then `You: {C.number(result.mine)} {board.unit}. The top {Leaderboards.TOP} are shown.`
			else `Fly a match to get on the board. The top {Leaderboards.TOP} are shown.`
	end
	if boardId == "KillsWeek" or boardId == "WinsWeek" then
		status ..= "  New every Monday at 00:00 UTC."
	end

	return e("Frame", {
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = props.Order,
	}, {
		Layout = C.List({ Gap = 10 }),
		Picker = e("Frame", {
			Size = UDim2.new(1, 0, 0, math.ceil(#Leaderboards.BOARDS / 3) * 44 - 8),
			BackgroundTransparency = 1,
			LayoutOrder = 1,
		}, picker),
		Status = e(C.Label, {
			Text = status,
			Size = UDim2.new(1, 0, 0, 18),
			TextSize = 13,
			Color = Theme.Dim,
			LayoutOrder = 2,
		}),
		Rows = e("Frame", {
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			LayoutOrder = 3,
		}, rows),
	})
end

return LeaderboardPanel
