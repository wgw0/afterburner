--!strict
-- Match results (UI-06): who won, your reward lines counting up, your pilot level bar filling, and the
-- top of the scoreboard, with REPORT on other human pilots (CMP-03). props: Match (MatchState), Rewards
-- (MatchRewards payload or nil), Data, OnReport(userId).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local React = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("React")) :: any
local Shared = ReplicatedStorage:WaitForChild("Shared")
local AircraftData = require(Shared.AircraftData)
local Economy = require(Shared.Config.Economy)
local LevelRewards = require(Shared.Config.LevelRewards)
local Mastery = require(Shared.Mastery)

local UI = script.Parent.Parent
local C = require(UI.Components)
local Theme = require(UI.Theme)

local e = React.createElement
local COUNT_SECONDS = 1.8

local function Results(props: any)
	local match, rewards, data = props.Match, props.Rewards, props.Data
	local t, setT = React.useState(0)

	-- Count up once per new rewards payload
	React.useEffect(function()
		setT(0)
		local started = os.clock()
		local connection
		connection = RunService.RenderStepped:Connect(function()
			local progress = math.clamp((os.clock() - started) / COUNT_SECONDS, 0, 1)
			setT(progress)
			if progress >= 1 then
				connection:Disconnect()
			end
		end)
		return function()
			connection:Disconnect()
		end
	end, { rewards })

	local reason = if match.reason == "ScoreLimit"
		then "kill limit reached"
		elseif match.reason == "Tickets" then "out of tickets"
		else "time's up"
	local children: { [string]: any } = {
		Title = e(C.Label, {
			Text = if match.teams and match.winner == "Draw"
				then "DRAW"
				elseif match.teams then `{string.upper(match.winner or "Nobody")} TEAM WINS`
				else `{match.winner or "Nobody"} WINS`,
			Size = UDim2.new(1, 0, 0, 40),
			Position = UDim2.fromOffset(0, 16),
			Align = "Center",
			Heavy = true,
			TextSize = 32,
			Color = Theme.Accent,
		}),
		Sub = e(C.Label, {
			Text = `{reason}  ·  {if match.expected then "back to the lobby" else "next match"} in {match.timeLeft or 0}s`,
			Size = UDim2.new(1, 0, 0, 18),
			Position = UDim2.fromOffset(0, 58),
			Align = "Center",
			Color = Theme.Dim,
			TextSize = 14,
		}),
	}

	-- Your rewards
	local rewardChildren: { [string]: any } = { Layout = C.List({ Gap = 6 }) }
	rewardChildren.Head = e("Frame", { Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1, LayoutOrder = 0 }, {
		A = e(
			C.Label,
			{ Text = "YOUR REWARDS", Bold = true, Color = Theme.Accent, TextSize = 13, Size = UDim2.fromScale(0.5, 1) }
		),
		B = e(C.Label, {
			Text = "XP      RP      CREDITS",
			Color = Theme.Dim,
			TextSize = 12,
			Size = UDim2.fromScale(0.5, 1),
			Position = UDim2.fromScale(0.5, 0),
			Align = "Right",
		}),
	})
	if rewards then
		for i, line in rewards.Lines do
			-- Each line starts counting a little after the one above it
			local local_t = math.clamp(t * (#rewards.Lines + 1) - (i - 1), 0, 1)
			rewardChildren[`L{i}`] = e(
				"Frame",
				{ Size = UDim2.new(1, 0, 0, 20), BackgroundTransparency = 1, LayoutOrder = i },
				{
					Label = e(C.Label, { Text = line.Label, TextSize = 14, Size = UDim2.fromScale(0.5, 1) }),
					Values = e(C.Label, {
						Text = string.format(
							"%d    %d    %d",
							line.XP * local_t,
							line.RP * local_t,
							line.Credits * local_t
						),
						Mono = true,
						TextSize = 14,
						Size = UDim2.fromScale(0.5, 1),
						Position = UDim2.fromScale(0.5, 0),
						Align = "Right",
						Color = Theme.Good,
					}),
				}
			)
		end
		local totalRP = 0
		for _, rp in rewards.RP do
			totalRP += rp
		end
		rewardChildren.Total = e(
			"Frame",
			{ Size = UDim2.new(1, 0, 0, 26), BackgroundTransparency = 1, LayoutOrder = 100 },
			{
				Label = e(C.Label, { Text = "TOTAL", Bold = true, TextSize = 16, Size = UDim2.fromScale(0.5, 1) }),
				Values = e(C.Label, {
					Text = string.format("+%d XP   +%d RP   +%d Cr", rewards.XP * t, totalRP * t, rewards.Credits * t),
					Bold = true,
					TextSize = 16,
					Size = UDim2.fromScale(0.5, 1),
					Position = UDim2.fromScale(0.5, 0),
					Align = "Right",
					Color = Theme.Good,
				}),
			}
		)
		local need = Economy.xpToNext(data.PilotLevel)
		rewardChildren.Level = e(
			"Frame",
			{ Size = UDim2.new(1, 0, 0, 40), BackgroundTransparency = 1, LayoutOrder = 101 },
			{
				Label = e(C.Label, {
					Text = if (rewards.LevelsGained or 0) > 0 and t >= 1
						then `LEVEL UP!  Pilot level {data.PilotLevel}`
						else `Pilot level {data.PilotLevel}`,
					Bold = true,
					TextSize = 14,
					Color = if (rewards.LevelsGained or 0) > 0 and t >= 1 then Theme.Accent else Theme.Text,
					Size = UDim2.new(1, 0, 0, 18),
				}),
				Bar = e(C.Bar, {
					Value = (data.PilotXP / need) * t,
					Size = UDim2.new(1, 0, 0, 12),
					Position = UDim2.fromOffset(0, 24),
					Color = Theme.Accent,
					Text = `{data.PilotXP} / {need} XP`,
				}),
			}
		)
		-- Mastery stars reached this match (PRG-07), paid on top of the total
		for i, gain in rewards.Mastery or {} do
			local airframe = AircraftData.get(gain.Airframe) :: any
			rewardChildren[`M{i}`] = e(C.Label, {
				Text = `{Mastery.starText(gain.Stars)}  {airframe and airframe.DisplayName or gain.Airframe} mastery  +{C.number(
					gain.Credits
				)} Cr{if gain.Title then `  ·  title "{LevelRewards.titleName(gain.Title)}"` else ""}`,
				TextSize = 13,
				Bold = true,
				Color = Theme.Rarity.Legendary,
				LayoutOrder = 102 + i,
			})
		end
		if rewards.Afk then
			rewardChildren.Afk = e(C.Label, {
				Text = "No survival or win bonus: no controls touched for a minute.",
				Color = Theme.Warn,
				TextSize = 12,
				Wrap = true,
				LayoutOrder = 110,
			})
		end
	else
		rewardChildren.None = e(C.Label, {
			Text = "No rewards this match: you didn't fly.",
			Color = Theme.Dim,
			TextSize = 14,
			LayoutOrder = 1,
		})
	end
	children.Rewards = e(C.Panel, {
		Size = UDim2.new(0.5, -24, 1, -100),
		Position = UDim2.fromOffset(16, 88),
		Color = Theme.Background,
		Padding = 12,
	}, rewardChildren)

	-- Top of the scoreboard
	local board: { [string]: any } = { Layout = C.List({ Gap = 4 }) }
	board.Head = e(C.Label, { Text = "SCOREBOARD", Bold = true, Color = Theme.Accent, TextSize = 13, LayoutOrder = 0 })
	for i, score in match.ranking or {} do
		if i > 8 then
			break
		end
		local reportable = props.OnReport
			and not score.isAI
			and (score.userId or 0) > 0
			and score.userId ~= Players.LocalPlayer.UserId
		board[`R{i}`] = e("Frame", { Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1, LayoutOrder = i }, {
			Line = e(C.Label, {
				Text = string.format("%d. %s   %d K  %d D  %d", i, score.name, score.kills, score.deaths, score.score),
				Size = UDim2.new(1, if reportable then -76 else 0, 1, 0),
				TextSize = 14,
				Color = if score.isAI then Theme.Dim else Theme.Text,
			}),
			Report = if reportable
				then e(C.Button, {
					Text = "REPORT",
					Style = "Ghost",
					TextSize = 11,
					Size = UDim2.fromOffset(70, 22),
					Position = UDim2.new(1, -70, 0, 1),
					OnClick = function()
						props.OnReport(score.userId)
					end,
				})
				else nil,
		})
	end
	children.Board = e(C.Panel, {
		Size = UDim2.new(0.5, -24, 1, -100),
		Position = UDim2.new(0.5, 8, 0, 88),
		Color = Theme.Background,
		Padding = 12,
	}, board)

	return e(C.Panel, {
		Size = UDim2.fromOffset(820, 470),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		StrokeColor = Theme.Accent,
		StrokeThickness = 1.5,
	}, children)
end

return Results
