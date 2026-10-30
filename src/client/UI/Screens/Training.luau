--!strict
-- The training server's home screen (DEVELOPMENT.md §28, TUT-03): any jet, the six lessons, and Vs AI.
-- Nothing here earns rewards. Shown in place of the Hangar on a training server (ServerRole).
-- props: Data, Selected, OnSelect(id), Status, CanPlay, OnPlay(id), Lessons ({ {id, name} }), OnLesson(id),
--   VsAIRunning (bool), ModeName (the running match's name), OnVsAI(modeId, difficulty, count), OnFreeFlight(),
--   OnMultiplayer() (back to a lobby: the button left of FLY, where TRAINING sits in the lobby),
--   FirstSession (a new pilot: show the welcome card, TUT-04), OnFinishOnboarding() (stay in training).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("React")) :: any
local Shared = ReplicatedStorage:WaitForChild("Shared")
local AircraftData = require(Shared.AircraftData)
local Progression = require(Shared.Progression)
local LiveConfig = require(Shared.LiveConfig)

local UI = script.Parent.Parent
local C = require(UI.Components)
local JetPreview = require(UI.JetPreview)
local Theme = require(UI.Theme)

local e = React.createElement
local TIER_NAMES = { "I", "II", "III", "IV", "V", "VI", "VII", "VIII" }
-- Two rows of two: four buttons in one row are too narrow for their names
local VS_MODES = { { "Dogfight", "FREE-FOR-ALL" }, { "TeamDeathmatch", "TEAMS" } }
local VS_MODES_2 = { { "AirSuperiority", "ZONES" }, { "GunsOnly", "GUNS ONLY" } }
local DIFFICULTIES = { "Easy", "Normal", "Hard", "Ace" }
local MAX_AI = 11

-- A row of choice buttons sharing `width` pixels.
local function choices(list: { any }, value: string, width: number, order: number, onPick: (string) -> ())
	local buttons: { [string]: any } = { Layout = C.List({ Horizontal = true, Gap = 6 }) }
	local each = math.floor((width - 6 * (#list - 1)) / #list)
	for i, item in list do
		local id = if type(item) == "table" then item[1] else item
		local label = if type(item) == "table" then item[2] else string.upper(item)
		buttons[id] = e(C.Button, {
			Text = label,
			Style = if value == id then "Primary" else "Ghost",
			Size = UDim2.fromOffset(each, 36),
			TextSize = 11,
			LayoutOrder = i,
			OnClick = function()
				onPick(id)
			end,
		})
	end
	return e("Frame", { Size = UDim2.new(1, 0, 0, 36), BackgroundTransparency = 1, LayoutOrder = order }, buttons)
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
	side.VsTitle = e(C.Label, { Text = "VS AI", Bold = true, Color = Theme.Accent, TextSize = 14, LayoutOrder = 19 })
	side.Mode = choices(VS_MODES, vsMode, 252, 20, setVsMode)
	side.Mode2 = choices(VS_MODES_2, vsMode, 252, 21, setVsMode)
	side.Difficulty = choices(DIFFICULTIES, difficulty, 252, 22, setDifficulty)
	side.Count = e("Frame", { Size = UDim2.new(1, 0, 0, 36), BackgroundTransparency = 1, LayoutOrder = 23 }, {
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
		LayoutOrder = 24,
		OnClick = function()
			props.OnVsAI(vsMode, difficulty, count)
		end,
	})
	side.Free = if props.VsAIRunning
		then e(C.Button, {
			Text = "BACK TO FREE FLIGHT",
			Size = UDim2.new(1, 0, 0, 40),
			TextSize = 13,
			LayoutOrder = 25,
			OnClick = props.OnFreeFlight,
		})
		else nil
	side.Note = e(C.Label, {
		Text = "Training earns no rewards. Press MULTIPLAYER (next to FLY) to go back.",
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
		JetName = e(C.Label, {
			Text = if airframe then airframe.DisplayName else "",
			Position = UDim2.fromScale(0.5, 0.68),
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
			Position = UDim2.new(0.5, 0, 0.68, 42),
			AnchorPoint = Vector2.new(0.5, 0),
			Size = UDim2.fromOffset(600, 22),
			Align = "Center",
			Color = Theme.Dim,
			TextSize = 16,
		}),
		Multiplayer = e(C.Button, {
			Text = "MULTIPLAYER",
			Style = "Ghost",
			TextSize = 14,
			Size = UDim2.fromOffset(130, 44),
			Position = UDim2.new(0.5, -280, 1, -102),
			OnClick = props.OnMultiplayer,
		}),
		Fly = e(C.Button, {
			Text = "FLY",
			Style = "Primary",
			TextSize = 26,
			Size = UDim2.fromOffset(260, 60),
			Position = UDim2.new(0.5, 0, 1, -110),
			AnchorPoint = Vector2.new(0.5, 0),
			Disabled = not (props.CanPlay and selected),
			OnClick = function()
				props.OnPlay(selected)
			end,
		}),
		Status = e(C.Label, {
			Text = props.Status or "",
			Position = UDim2.new(0.5, 0, 1, -40),
			AnchorPoint = Vector2.new(0.5, 0),
			Size = UDim2.fromOffset(700, 22),
			Align = "Center",
			Color = Theme.Warn,
			Bold = true,
			TextSize = 16,
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
