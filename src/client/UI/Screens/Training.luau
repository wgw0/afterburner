--!strict
-- The training server's home screen (DEVELOPMENT.md §28, TUT-03): any jet, the six lessons, and Vs AI.
-- Vs AI pays pilot XP only; lessons and free flight pay nothing. Shown in place of the Hangar on a training server (ServerRole).
-- props: Data, Selected, OnSelect(id), Status, CanPlay, OnPlay(id), Lessons ({ {id, name} }), OnLesson(id),
--   VsAIRunning (bool), ModeName (the running match's name), OnVsAI(modeId, difficulty, count), OnFreeFlight(),
--   OnMultiplayer() (back to a lobby: the button left of FLY, where TRAINING sits in the lobby),
--   FirstSession (a new pilot: show the welcome card, TUT-04), OnFinishOnboarding() (stay in training),
--   OnDetails(id) (the jet's details, right of FLY as in the Hangar).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("React")) :: any
local Shared = ReplicatedStorage:WaitForChild("Shared")
local AircraftData = require(Shared.AircraftData)
local Progression = require(Shared.Progression)
local LiveConfig = require(Shared.LiveConfig)
local MatchRules = require(Shared.MatchRules)
local Strike = require(Shared.Strike)

local UI = script.Parent.Parent
local C = require(UI.Components)
local JetPreview = require(UI.JetPreview)
local Theme = require(UI.Theme)

local e = React.createElement
local TIER_NAMES = { "I", "II", "III", "IV", "V", "VI", "VII", "VIII" }
-- Vs AI modes, colour-coded by kind (Will): one-on-one and co-op, kill modes, objective modes. A row of
-- two across the top, then two rows of three.
local KINDS = {
	Solo = Theme.Rarity.Legendary, -- one opponent, or the waves
	Kills = Theme.Rarity.Rare, -- shoot down the most
	Objective = Theme.Rarity.Epic, -- zones and bombers
}
local VS_DUEL = { { "DuelCasual", "1V1 DUEL", "Solo" }, { "Waves", "PVE WAVES", "Solo" } }
local VS_MODES = {
	{ "Dogfight", "DOGFIGHT", "Kills" },
	{ "TeamDeathmatch", "TEAMS", "Kills" },
	{ "GunsOnly", "GUNS ONLY", "Kills" },
}
local VS_MODES_2 =
	{ { "BVR", "BVR", "Kills" }, { "AirSuperiority", "ZONES", "Objective" }, { "StrikeEscort", "STRIKE", "Objective" } }
local DIFFICULTIES = {
	{ "Easy", "EASY", Theme.Good },
	{ "Normal", "NORMAL", Theme.Wings },
	{ "Hard", "HARD", Theme.Warn },
	{ "Ace", "ACE", Theme.Bad },
}
local MAX_AI = 11
local CLUSTER_W, CLUSTER_H = 880, 250 -- the bottom cluster's design size (MULTIPLAYER ... DETAILS)
local SIDE_PANELS = 2 * (20 + 300 + 16) -- the jets list on the left, the lessons and Vs AI on the right
local DARK_TEXT = Color3.fromRGB(14, 16, 22)

local function minutes(modeId: string): number
	return math.floor((MatchRules.MODES :: any)[modeId].TimeLimit / 60)
end

-- What each Vs AI mode is, shown under START VS AI
local ABOUT = {
	DuelCasual = "One AI pilot, best of five rounds. You start in opposite corners with one life a round: last one flying takes it.",
	Waves = `Defend your airbase from {Strike.WAVES} waves of AI fighters and bombers, each bigger than the last. It can take {Strike.BASE_HITS} bomber hits.`,
	Dogfight = `Free for all: every jet is an enemy. First to {MatchRules.MODES.Dogfight.ScoreLimit} kills, or the most after {minutes(
		"Dogfight"
	)} minutes.`,
	TeamDeathmatch = `Two teams with AI wingmen. First team to {MatchRules.MODES.TeamDeathmatch.ScoreLimit} kills, or the most after {minutes(
		"TeamDeathmatch"
	)} minutes.`,
	GunsOnly = `Free for all with no missiles: guns only, with {MatchRules.GUNS_ONLY_AMMO} times the ammo. Get in close.`,
	BVR = "Beyond visual range: two teams start far apart with radar missiles only. Needs a Tier IV+ jet with radar missiles.",
	AirSuperiority = "Two teams fight for three zones. Hold more zones than the other side and their tickets drain; losing jets costs tickets too.",
	StrikeEscort = `Escort your team's bombers to the enemy airbase and shoot down theirs. First to {Strike.STRIKE_LIMIT} strikes wins.`,
}

local function find(list: { any }, id: string): any
	for _, item in list do
		if item[1] == id then
			return item
		end
	end
	return nil
end

-- A row of choice buttons sharing the panel's width, each tinted by `colourOf(item)`: outlined in its colour,
-- filled when picked.
local function choices(list: { any }, value: string, order: number, onPick: (string) -> (), colourOf: (any) -> Color3)
	local buttons: { [string]: any } = { Layout = C.List({ Horizontal = true, Gap = 8 }) }
	local share = 1 / #list
	local trim = math.ceil(8 * (#list - 1) / #list)
	for i, item in list do
		local id, colour = item[1], colourOf(item)
		local picked = value == id
		buttons[id] = e(C.Button, {
			Text = item[2],
			Style = if picked then "Secondary" else "Ghost",
			Color = if picked then colour else nil,
			TextColor = if picked then DARK_TEXT else colour,
			StrokeColor = colour,
			Size = UDim2.new(share, -trim, 0, 38),
			TextSize = 12,
			LayoutOrder = i,
			OnClick = function()
				onPick(id)
			end,
		})
	end
	-- Clear of the scroll bar, with room for the outlines (drawn outside each button) on both sides
	buttons.Padding = e("UIPadding", { PaddingLeft = UDim.new(0, 2), PaddingRight = UDim.new(0, 8) })
	return e("Frame", { Size = UDim2.new(1, 0, 0, 40), BackgroundTransparency = 1, LayoutOrder = order }, buttons)
end

local function kindColour(item: any): Color3
	return KINDS[item[3]]
end

local function difficultyColour(item: any): Color3
	return item[3]
end

-- A small heading over a group of buttons
local function heading(text: string, order: number)
	return e(C.Label, {
		Text = text,
		Size = UDim2.new(1, 0, 0, 16),
		TextSize = 11,
		Bold = true,
		Color = Theme.Dim,
		LayoutOrder = order,
	})
end

-- Space between groups
local function gap(height: number, order: number)
	return e("Frame", { Size = UDim2.new(1, 0, 0, height), BackgroundTransparency = 1, LayoutOrder = order })
end

-- The first three lessons, as the welcome card walks a new pilot through them
local BASICS = { { "Flight", "Basic flight" }, { "Energy", "Energy" }, { "Guns", "Guns" } }

-- A new pilot's welcome (TUT-04): lessons 1–3 ticked off as they go, the next one, or skip to multiplayer.
local function Welcome(props: any)
	local done = props.Data.Lessons or {}
	local nextLesson = nil
	local rows: { [string]: any } = { Layout = C.List({ Gap = 4 }) }
	for i, lesson in BASICS do
		local finished = done[lesson[1]] == true
		if not finished and not nextLesson then
			nextLesson = lesson
		end
		rows[lesson[1]] = e(C.Label, {
			Text = `{if finished then "✓" else tostring(i) .. "."}  {lesson[2]}`,
			Size = UDim2.new(1, 0, 0, 22),
			TextSize = 15,
			Bold = nextLesson == lesson,
			Color = if finished then Theme.Good elseif nextLesson == lesson then Theme.Text else Theme.Dim,
			LayoutOrder = i,
		})
	end
	local complete = nextLesson == nil
	return e(C.Panel, {
		Size = UDim2.fromOffset(440, 262),
		Position = UDim2.fromScale(0.5, 0.36),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Padding = 20,
		StrokeColor = Theme.Accent,
		StrokeThickness = 2,
	}, {
		Title = e(C.Label, {
			Text = if complete then "TRAINING COMPLETE" else "WELCOME, PILOT",
			Size = UDim2.new(1, 0, 0, 28),
			Heavy = true,
			TextSize = 24,
			Color = Theme.Accent,
		}),
		Text = e(C.Label, {
			Text = if complete
				then "You've got the basics. Time for a real fight, or keep practising here."
				else "Three short lessons get you flying and fighting. You can skip them any time.",
			Size = UDim2.new(1, 0, 0, 36),
			Position = UDim2.fromOffset(0, 34),
			TextSize = 13,
			Wrap = true,
			Color = Theme.Dim,
		}),
		Lessons = e("Frame", {
			Size = UDim2.new(1, 0, 0, 74),
			Position = UDim2.fromOffset(0, 78),
			BackgroundTransparency = 1,
		}, rows),
		Primary = e(C.Button, {
			Text = if complete then "PLAY MULTIPLAYER" else `START: {string.upper((nextLesson :: any)[2])}`,
			Style = "Primary",
			Size = UDim2.new(0.56, -6, 0, 44),
			Position = UDim2.new(0, 0, 1, -44),
			TextSize = 15,
			OnClick = function()
				if complete then
					props.OnMultiplayer()
				else
					props.OnLesson((nextLesson :: any)[1])
				end
			end,
		}),
		Secondary = e(C.Button, {
			Text = if complete then "KEEP TRAINING" else "SKIP TO MULTIPLAYER",
			Style = "Ghost",
			Size = UDim2.new(0.44, -6, 0, 44),
			Position = UDim2.new(1, 0, 1, -44),
			AnchorPoint = Vector2.new(1, 0),
			TextSize = 12,
			OnClick = if complete then props.OnFinishOnboarding else props.OnMultiplayer,
		}),
	})
end

local function Training(props: any)
	local data = props.Data
	local selected = props.Selected
	local airframe = selected and AircraftData.get(selected) :: any
	local vsMode, setVsMode = React.useState("Dogfight")
	local difficulty, setDifficulty = React.useState("Normal")
	local count, setCount = React.useState(5)

	-- Every jet, by tier then BR: anything can be flown here
	local all = {}
	for id in AircraftData.getAll() do
		table.insert(all, id)
	end
	table.sort(all, function(a, b)
		local aa, bb = AircraftData.get(a) :: any, AircraftData.get(b) :: any
		if aa.Tier ~= bb.Tier then
			return aa.Tier < bb.Tier
		end
		return (LiveConfig.battleRating(a) or 0) < (LiveConfig.battleRating(b) or 0)
	end)
	local jets: { [string]: any } = { Layout = C.List({ Gap = 4 }) }
	jets.Title = e(C.Label, { Text = "ANY JET", Bold = true, Color = Theme.Accent, TextSize = 14, LayoutOrder = 0 })
	for i, id in all do
		local info = AircraftData.get(id) :: any
		local owned = data.Aircraft[id] and data.Aircraft[id].Owned
		jets[id] = e("TextButton", {
			Size = UDim2.new(1, -6, 0, 34),
			LayoutOrder = i,
			BackgroundColor3 = if id == selected then Theme.AccentDark else Theme.PanelLight,
			BackgroundTransparency = if id == selected then 0 else 0.4,
			AutoButtonColor = true,
			Text = "",
			[React.Event.Activated] = function()
				props.OnSelect(id)
			end,
		}, {
			Corner = C.corner(6),
			Name = e(C.Label, {
				Text = info.DisplayName,
				Size = UDim2.new(1, -70, 1, 0),
				Position = UDim2.fromOffset(10, 0),
				TextSize = 13,
				Bold = id == selected,
				Color = if owned then Theme.Text else Theme.Dim,
			}),
			Tier = e(C.Label, {
				Text = `{TIER_NAMES[info.Tier]} · {LiveConfig.battleRating(id)}`,
				Size = UDim2.fromOffset(60, 34),
				Position = UDim2.new(1, -66, 0, 0),
				TextSize = 12,
				Align = "Right",
				Color = Theme.Dim,
			}),
		})
	end

	-- Lessons and Vs AI
	local side: { [string]: any } = { Layout = C.List({ Gap = 8 }) }
	side.LessonsTitle =
		e(C.Label, { Text = "LESSONS", Bold = true, Color = Theme.Accent, TextSize = 14, LayoutOrder = 0 })
	for i, lesson in props.Lessons do
		side[lesson.id] = e(C.Button, {
			Text = `{i}. {lesson.name}`,
			Size = UDim2.new(1, 0, 0, 38),
			TextSize = 13,
			LayoutOrder = i,
			OnClick = function()
				props.OnLesson(lesson.id)
			end,
		})
	end
	side.VsGap = gap(6, 17)
	side.VsTitle = e(C.Label, { Text = "VS AI", Bold = true, Color = Theme.Accent, TextSize = 14, LayoutOrder = 18 })
	side.ModeHeading = heading("MODE", 19)
	side.ModeDuel = choices(VS_DUEL, vsMode, 20, setVsMode, kindColour)
	side.Mode = choices(VS_MODES, vsMode, 21, setVsMode, kindColour)
	side.Mode2 = choices(VS_MODES_2, vsMode, 22, setVsMode, kindColour)
	side.DifficultyGap = gap(4, 23)
	side.DifficultyHeading = heading("DIFFICULTY", 24)
	side.Difficulty = choices(DIFFICULTIES, difficulty, 25, setDifficulty, difficultyColour)
	local duel = vsMode == "DuelCasual" or vsMode == "Waves" -- one opponent, or the waves decide
	side.Count = if duel
		then nil
		else e("Frame", { Size = UDim2.new(1, 0, 0, 36), BackgroundTransparency = 1, LayoutOrder = 26 }, {
			Layout = C.List({ Horizontal = true, Gap = 8, AlignY = "Center" }),
			Label = e(C.Label, {
				Text = `{count} opponent{if count == 1 then "" else "s"}`,
				Size = UDim2.fromOffset(140, 36),
				TextSize = 14,
				LayoutOrder = 1,
			}),
			Down = e(C.Button, {
				Text = "−",
				Size = UDim2.fromOffset(44, 36),
				TextSize = 20,
				Disabled = count <= 1,
				LayoutOrder = 2,
				OnClick = function()
					setCount(math.max(count - 1, 1))
				end,
			}),
			Up = e(C.Button, {
				Text = "+",
				Size = UDim2.fromOffset(44, 36),
				TextSize = 20,
				Disabled = count >= MAX_AI,
				LayoutOrder = 3,
				OnClick = function()
					setCount(math.min(count + 1, MAX_AI))
				end,
			}),
		})
	side.Start = e(C.Button, {
		Text = if props.VsAIRunning then "RESTART VS AI" else "START VS AI",
		Style = "Primary",
		Size = UDim2.new(1, 0, 0, 40),
		TextSize = 14,
		LayoutOrder = 27,
		OnClick = function()
			props.OnVsAI(vsMode, difficulty, if duel then 1 else count)
		end,
	})
	-- What the picked mode is, in its kind's colour
	local picked = find(VS_DUEL, vsMode) or find(VS_MODES, vsMode) or find(VS_MODES_2, vsMode)
	side.About = e("Frame", {
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 28,
	}, {
		Layout = C.List({ Gap = 4 }),
		Name = e(C.Label, {
			Text = string.upper((MatchRules.MODES :: any)[vsMode].DisplayName),
			Size = UDim2.new(1, 0, 0, 20),
			TextSize = 16,
			Heavy = true,
			Color = if picked then kindColour(picked) else Theme.Accent,
			LayoutOrder = 1,
		}),
		Text = e(C.Label, {
			Text = ABOUT[vsMode] or "",
			TextSize = 15,
			Bold = true,
			Wrap = true,
			AutoHeight = true,
			Color = Theme.Text,
			LayoutOrder = 2,
		}),
	})
	side.Free = if props.VsAIRunning
		then e(C.Button, {
			Text = "BACK TO FREE FLIGHT",
			Size = UDim2.new(1, 0, 0, 40),
			TextSize = 13,
			LayoutOrder = 29,
			OnClick = props.OnFreeFlight,
		})
		else nil
	side.Note = e(C.Label, {
		Text = "Vs AI earns pilot XP (half a match's). Press MULTIPLAYER (next to FLY) to go back.",
		Color = Theme.Dim,
		TextSize = 12,
		Wrap = true,
		AutoHeight = true,
		LayoutOrder = 30,
	})

	return e("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, {
		Welcome = if props.FirstSession
			then e(Welcome, {
				Data = data,
				OnLesson = props.OnLesson,
				OnMultiplayer = props.OnMultiplayer,
				OnFinishOnboarding = props.OnFinishOnboarding,
			})
			else nil,
		-- The welcome card takes the turntable's place for a new pilot
		Preview = if airframe and not props.FirstSession
			then e(JetPreview, {
				AirframeId = selected,
				Skin = Progression.skinFor(data, selected),
				Size = UDim2.fromScale(0.45, 0.6),
				Position = UDim2.fromScale(0.5, 0.36),
				AnchorPoint = Vector2.new(0.5, 0.5),
			})
			else nil,
		Mode = e(C.Label, {
			Text = if props.VsAIRunning then string.upper(props.ModeName or "VS AI") else "FREE FLIGHT",
			Position = UDim2.fromScale(0.5, 0.02),
			AnchorPoint = Vector2.new(0.5, 0),
			Size = UDim2.fromOffset(500, 24),
			Align = "Center",
			Bold = true,
			Color = Theme.Accent,
			TextSize = 18,
		}),
		-- Name, FLY and the buttons round it: a CLUSTER_W design that shrinks to fit between the side panels
		Cluster = e(C.Fit, {
			Width = CLUSTER_W,
			Height = CLUSTER_H,
			Sides = SIDE_PANELS,
			Position = UDim2.fromScale(0.5, 1),
			AnchorPoint = Vector2.new(0.5, 1),
			ZIndex = 2,
		}, {
			JetName = e(C.Label, {
				Text = if airframe then airframe.DisplayName else "",
				Position = UDim2.new(0.5, 0, 1, -236),
				AnchorPoint = Vector2.new(0.5, 0),
				Size = UDim2.fromOffset(600, 40),
				Align = "Center",
				Heavy = true,
				TextSize = 34,
			}),
			JetInfo = e(C.Label, {
				Text = if airframe
					then `Tier {TIER_NAMES[airframe.Tier]}  ·  BR {LiveConfig.battleRating(selected)}  ·  {airframe.Branch}{if data.Aircraft[selected]
							and data.Aircraft[selected].Owned
						then ""
						else "  ·  not owned yet"}`
					else "",
				Position = UDim2.new(0.5, 0, 1, -194),
				AnchorPoint = Vector2.new(0.5, 0),
				Size = UDim2.fromOffset(600, 22),
				Align = "Center",
				Color = Theme.Dim,
				TextSize = 16,
			}),
			Multiplayer = e(C.Button, {
				Text = "MULTIPLAYER",
				Style = "Ghost",
				TextSize = 20,
				Size = UDim2.fromOffset(210, 70),
				Position = UDim2.new(0.5, -440, 1, -137),
				OnClick = props.OnMultiplayer,
			}),
			Details = e(C.Button, {
				Text = "DETAILS",
				Style = "Ghost",
				TextSize = 20,
				Size = UDim2.fromOffset(180, 70),
				Position = UDim2.new(0.5, 230, 1, -137),
				Disabled = selected == nil,
				OnClick = function()
					props.OnDetails(selected)
				end,
			}),
			Fly = e(C.Button, {
				Text = "FLY",
				Style = "Primary",
				TextSize = 40,
				Size = UDim2.fromOffset(420, 96),
				Position = UDim2.new(0.5, 0, 1, -150),
				AnchorPoint = Vector2.new(0.5, 0),
				Disabled = not (props.CanPlay and selected),
				OnClick = function()
					props.OnPlay(selected)
				end,
			}),
			Status = e(C.Label, {
				Text = props.Status or "",
				Position = UDim2.new(0.5, 0, 1, -50),
				AnchorPoint = Vector2.new(0.5, 0),
				Size = UDim2.fromOffset(440, 46),
				Align = "Center",
				AlignY = "Top",
				Wrap = true,
				Color = Theme.Warn,
				Bold = true,
				TextSize = 16,
			}),
		}),
		Jets = e(C.Panel, {
			Size = UDim2.new(0, 300, 1, -40),
			Position = UDim2.fromOffset(20, 20),
			Padding = 14,
		}, {
			List = e("ScrollingFrame", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ScrollBarThickness = 4,
				CanvasSize = UDim2.new(),
				AutomaticCanvasSize = Enum.AutomaticSize.Y,
			}, jets),
		}),
		Side = e(C.Panel, {
			Size = UDim2.new(0, 280, 1, -40),
			Position = UDim2.new(1, -20, 0, 20),
			AnchorPoint = Vector2.new(1, 0),
			Padding = 14,
		}, {
			List = e("ScrollingFrame", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ScrollBarThickness = 4,
				CanvasSize = UDim2.new(),
				AutomaticCanvasSize = Enum.AutomaticSize.Y,
			}, side),
		}),
	})
end

return Training
