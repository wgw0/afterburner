--!strict
-- Match results (UI-06): who won, your reward lines counting up, your pilot level bar filling, and the
-- top of the scoreboard, with REPORT on other human pilots (CMP-03). Without VIP (and no Credits booster
-- running, which VIP wouldn't add to), a line says what VIP would have added this match, with a way to the
-- Shop (DEVELOPMENT.md §27.9). The group and friends bonuses (Shared/Social) are reward lines when earned, and a
-- small dim line each saying how to get them when not. props: Match (MatchState), Rewards (MatchRewards payload or nil), Data,
-- OnReport(userId), OnShop().

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local React = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("React")) :: any
local Shared = ReplicatedStorage:WaitForChild("Shared")
local AircraftData = require(Shared.AircraftData)
local Duel = require(Shared.Duel)
local Economy = require(Shared.Config.Economy)
local LevelRewards = require(Shared.Config.LevelRewards)
local Mastery = require(Shared.Mastery)
local Passes = require(Shared.Config.Passes)
local Perks = require(Shared.Perks)
local Social = require(Shared.Social)
local SocialConfig = require(Shared.Config.Social)

local UI = script.Parent.Parent
local C = require(UI.Components)
local Theme = require(UI.Theme)

local e = React.createElement
local COL_W = 64 -- a number column (rewards and scoreboard)
local REPORT_W = 76 -- room for a scoreboard row's REPORT button
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
		elseif match.reason == "Rounds" then "duel won on rounds"
		elseif match.reason == "Forfeit" then "the other pilot left"
		elseif match.reason == "Draw" then "level on rounds"
		elseif match.reason == "Strikes" then "strike limit reached"
		elseif match.reason == "Waves" then (if match.winner == "Base held"
			then "every wave beaten"
			else "the base fell")
		else "time's up"
	local children: { [string]: any } = {
		Title = e(C.Label, {
			Text = if match.winner == "Draw"
				then "DRAW"
				elseif match.mission and match.mission.kind == "Waves" then string.upper(match.winner or "")
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

	-- Duels (MCH-09): the round score, and your rating change with your rank
	local duel = match.duel
	if duel then
		local parts = {}
		for _, seat in duel.seats do
			table.insert(parts, `{seat.name} {seat.wins}`)
		end
		local mine = duel.ratings and duel.ratings[tostring(Players.LocalPlayer.UserId)]
		local line = table.concat(parts, "  –  ")
		local colour = Theme.Text
		if mine and mine.ranked then
			local rank = Duel.rankFor(mine.rating)
			line ..= `  ·  {if mine.change >= 0 then "+" else ""}{mine.change} rating  ·  {rank.name} {mine.rating}`
			local promoted = mine.promoted or {}
			if #promoted > 0 then
				line ..= `  ·  NEW RANK: {promoted[#promoted]}!`
			end
			colour = if mine.change > 0 then Theme.Good elseif mine.change < 0 then Theme.Warn else Theme.Text
		elseif duel.ranked then
			line ..= "  ·  unranked: an AI opponent"
		end
		-- In place of the reason line: the round score says how it was won
		children.Sub = e(C.Label, {
			Text = `{line}  ·  {if match.expected then "back to the lobby" else "next match"} in {match.timeLeft or 0}s`,
			Size = UDim2.new(1, 0, 0, 18),
			Position = UDim2.fromOffset(0, 58),
			Align = "Center",
			Bold = true,
			Color = colour,
			TextSize = 14,
		})
	end

	-- Your rewards: XP, RP and Credits in three right-aligned columns under their headings
	local function columns(values: { string }, props: { [string]: any }): { [string]: any }
		local cells: { [string]: any } = {}
		for c, text in values do
			cells[`C{c}`] = e(C.Label, {
				Text = text,
				Size = UDim2.fromOffset(COL_W, props.Height or 20),
				Position = UDim2.new(1, -COL_W * (#values - c + 1), 0, 0),
				Align = "Right",
				TextSize = props.TextSize or 14,
				Bold = props.Bold,
				Color = props.Color,
			})
		end
		return cells
	end
	local rewardChildren: { [string]: any } = { Layout = C.List({ Gap = 6 }) }
	rewardChildren.Head = e("Frame", { Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1, LayoutOrder = 0 }, {
		A = e(
			C.Label,
			{ Text = "YOUR REWARDS", Bold = true, Color = Theme.Accent, TextSize = 13, Size = UDim2.fromScale(0.5, 1) }
		),
		Columns = e(
			"Frame",
			{ Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 },
			columns({ "XP", "RP", "CREDITS" }, { TextSize = 12, Color = Theme.Dim, Height = 18 })
		),
	})
	if rewards then
		for i, line in rewards.Lines do
			-- Each line starts counting a little after the one above it
			local local_t = math.clamp(t * (#rewards.Lines + 1) - (i - 1), 0, 1)
			rewardChildren[`L{i}`] = e(
				"Frame",
				{ Size = UDim2.new(1, 0, 0, 20), BackgroundTransparency = 1, LayoutOrder = i },
				{
					Label = e(C.Label, {
						Text = line.Label,
						TextSize = 14,
						Size = UDim2.new(1, -3 * COL_W, 1, 0),
						-- The group and friends bonuses in green
						Color = if line.Label == Social.GROUP_LABEL or line.Label == Social.FRIENDS_LABEL
							then Theme.Good
							else nil,
					}),
					Values = e(
						"Frame",
						{ Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 },
						columns({
							C.number(line.XP * local_t),
							C.number(line.RP * local_t),
							C.number(line.Credits * local_t),
						}, { Color = Theme.Good })
					),
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
				Values = e(
					"Frame",
					{ Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 },
					columns({
						`+{C.number(rewards.XP * t)}`,
						`+{C.number(totalRP * t)}`,
						`+{C.number(rewards.Credits * t)}`,
					}, { TextSize = 16, Bold = true, Color = Theme.Good, Height = 26 })
				),
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
				)} Cr{if gain.Title
					then `  ·  title "{LevelRewards.titleName(gain.Title)}"`
					elseif Mastery.unlockText(gain.Stars) then `  ·  {Mastery.unlockText(gain.Stars)}`
					else ""}`,
				TextSize = 13,
				Bold = true,
				Color = Theme.Rarity.Legendary,
				LayoutOrder = 102 + i,
			})
		end
		-- The group and friends bonuses not earned this match: how to get them (earned ones are lines above)
		if not rewards.Training then
			local earned = {}
			for _, line in rewards.Lines do
				earned[line.Label] = true
			end
			local hints = {}
			if Social.groupOn() and not earned[Social.GROUP_LABEL] then
				table.insert(hints, `Join the Afterburner group: {Social.percent(SocialConfig.GROUP)} Credits & XP`)
			end
			if not earned[Social.FRIENDS_LABEL] then
				table.insert(
					hints,
					`Fly with a friend or your party: {Social.percent(SocialConfig.FRIENDS)} Credits & XP`
				)
			end
			for i, hint in hints do
				rewardChildren[`S{i}`] = e(C.Label, {
					Text = hint,
					TextSize = 12,
					Color = Theme.Dim,
					LayoutOrder = 105 + i,
				})
			end
		end
		-- What VIP would have added: its +25% on this match's Credits (a running Credits booster already
		-- reaches the ×2 cap, so then it adds nothing and the line isn't shown)
		local vip = Players.LocalPlayer:GetAttribute(Passes.attribute("VIP")) == true
		local extra = math.floor(rewards.Credits * (Perks.VIP_CREDITS - 1))
		if
			not vip
			and extra > 0
			and Passes.idFor("VIP")
			and Perks.boosterLeft(data, "Credits", os.time()) == 0
			and props.OnShop
		then
			rewardChildren.Vip = e("Frame", {
				Size = UDim2.new(1, 0, 0, 34),
				BackgroundTransparency = 1,
				LayoutOrder = 108,
			}, {
				Label = e(C.Label, {
					Text = `★ VIP Pilot would have added +{C.number(extra)} Cr this match`,
					Size = UDim2.new(1, -110, 1, 0),
					TextSize = 13,
					Bold = true,
					Color = Color3.fromRGB(255, 201, 60),
				}),
				Button = e(C.Button, {
					Text = "SEE VIP",
					Style = "Primary",
					Color = Color3.fromRGB(255, 201, 60),
					Size = UDim2.fromOffset(100, 30),
					Position = UDim2.fromScale(1, 0.5),
					AnchorPoint = Vector2.new(1, 0.5),
					TextSize = 13,
					OnClick = props.OnShop,
				}),
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
	board.Head = e("Frame", { Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1, LayoutOrder = 0 }, {
		Title = e(C.Label, { Text = "SCOREBOARD", Bold = true, Color = Theme.Accent, TextSize = 13 }),
		Columns = e("Frame", {
			Size = UDim2.new(1, -REPORT_W, 1, 0),
			BackgroundTransparency = 1,
		}, columns({ "K", "D", "SCORE" }, { TextSize = 12, Color = Theme.Dim, Height = 18 })),
	})
	local me = Players.LocalPlayer.UserId
	local ranking = match.ranking or {}
	local myPlace = nil
	for i, score in ranking do
		if not score.isAI and score.userId == me then
			myPlace = i
		end
	end
	for i, score in ranking do
		-- The top 8, and you wherever you finished (in the 8th row's place if you're further down)
		local mine = i == myPlace
		if i > 8 and not mine then
			continue
		elseif i == 8 and myPlace and myPlace > 8 then
			continue
		end
		local reportable = props.OnReport
			and not score.isAI
			and (score.userId or 0) > 0
			and score.userId ~= Players.LocalPlayer.UserId
		board[`R{i}`] = e("Frame", {
			Size = UDim2.new(1, 0, 0, 24),
			BackgroundColor3 = Theme.AccentDark,
			BackgroundTransparency = if mine then 0.3 else 1,
			BorderSizePixel = 0,
			LayoutOrder = i,
		}, {
			Corner = C.corner(4),
			Name = e(C.Label, {
				Text = `{i}. {score.name}{if mine then "  (you)" else ""}`,
				Size = UDim2.new(1, -REPORT_W - 3 * COL_W, 1, 0),
				Position = UDim2.fromOffset(4, 0),
				TextSize = 14,
				Bold = mine,
				Color = if score.isAI then Theme.Dim else Theme.Text,
			}),
			Numbers = e(
				"Frame",
				{
					Size = UDim2.new(1, -REPORT_W, 1, 0),
					BackgroundTransparency = 1,
				},
				columns(
					{ tostring(score.kills), tostring(score.deaths), C.number(score.score) },
					{ Height = 24, Bold = mine }
				)
			),
			Report = if reportable
				then e(C.Button, {
					Text = "REPORT",
					Style = "Ghost",
					TextSize = 11,
					Size = UDim2.fromOffset(REPORT_W - 6, 22),
					Position = UDim2.new(1, -(REPORT_W - 6), 0, 1),
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
