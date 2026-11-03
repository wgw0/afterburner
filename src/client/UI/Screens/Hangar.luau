--!strict
-- Hangar, the home screen (UI-02): the selected jet on a turntable, your lineup, your other jets and the
-- Play button with the match status. Training is on its own servers (TRAINING in the top bar).
-- props: Data, Selected, OnSelect(id), Status (string), CanPlay, OnPlay(id), SideText and OnSide() (the button left of
--   PLAY: TRAINING in a lobby, LEAVE MATCH on a match server), OnDetails(id),
--   OnReport(userId?) (on a match server: the report-a-cheater window), OnFeedback() (the report-a-bug window), OnLineup(ids) -> (ok, err), PlayText (PLAY / CANCEL / JOINING…), QueueMode and OnQueueMode(mode) (in a
--   lobby: the mode picker over PLAY), OnReroll(index) (the challenges panel on the right),
--   OnSpin() -> (prize?, err) (the free-spin button bottom right and its window).

local Players = game:GetService("Players")
local TextService = game:GetService("TextService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("React")) :: any
local ReactRoblox = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("ReactRoblox")) :: any
local Shared = ReplicatedStorage:WaitForChild("Shared")
local AircraftData = require(Shared.AircraftData)
local Economy = require(Shared.Config.Economy)
local Cosmetics = require(Shared.Cosmetics)
local Progression = require(Shared.Progression)
local Mastery = require(Shared.Mastery)
local LiveConfig = require(Shared.LiveConfig)
local MatchRules = require(Shared.MatchRules)
local Duel = require(Shared.Duel)
local Strike = require(Shared.Strike)

local UI = script.Parent.Parent
local ChallengesPanel = require(UI.ChallengesPanel)
local C = require(UI.Components)
local JetPreview = require(UI.JetPreview)
local MatchmakingPanel = require(UI.MatchmakingPanel)
local PartyPanel = require(UI.PartyPanel)
local SpinButton = require(UI.SpinButton)
local SpinDialog = require(UI.SpinDialog)
local Theme = require(UI.Theme)

local e = React.createElement
local TIER_NAMES = { "I", "II", "III", "IV", "V", "VI", "VII", "VIII" }
-- The mode PLAY queues for: a duel first (Will: the main mode), then the team and free-for-all modes, then Any
-- (the fastest of those). { id, label, width }
local QUEUE_MODES = {
	{ "Duel", "RANKED DUEL", 140 },
	{ "DuelCasual", "CASUAL DUEL", 130 },
	{ "Dogfight", "DOGFIGHT", 104 },
	{ "TeamDeathmatch", "TEAMS", 84 },
	{ "AirSuperiority", "ZONES", 84 },
	{ "StrikeEscort", "STRIKE", 88 },
	{ "BVR", "BVR", 68 },
	{ "GunsOnly", "GUNS ONLY", 104 },
	{ "Waves", "PVE", 68 },
	{ "Any", "ANY", 64 },
}
local SWAP_BLUE = Color3.fromRGB(110, 170, 255) -- the Swap button's border in the jets list
local PICKER_WIDTH = 1010 -- the mode buttons and the gaps between them
local SIDE_PANELS = 2 * (20 + 300 + 16) -- the lineup on the left, challenges on the right, and a gap

local function minutes(modeId: string): number
	return math.floor((MatchRules.MODES :: any)[modeId].TimeLimit / 60)
end

-- What each mode is like, shown while the pointer is over its button
local MODE_ABOUT = {
	Duel = `1v1 against a pilot near your rating, best of five rounds with one life each. You start in opposite corners; first to {Duel.ROUNDS_TO_WIN} round wins. Wins and losses move your duel rating.`,
	DuelCasual = "The same 1v1 rounds as Ranked, for practice: your rating doesn't move.",
	Dogfight = `Free for all: every other jet is an enemy. First to {MatchRules.MODES.Dogfight.ScoreLimit} kills, or the most after {minutes(
		"Dogfight"
	)} minutes.`,
	TeamDeathmatch = `Two teams of three. First team to {MatchRules.MODES.TeamDeathmatch.ScoreLimit} kills, or the most after {minutes(
		"TeamDeathmatch"
	)} minutes.`,
	AirSuperiority = "Two teams fight for three zones. Hold more zones than the enemy and their tickets drain; every jet lost costs tickets too.",
	StrikeEscort = `Two teams escort AI bombers to the enemy airbase and hunt theirs. First to {Strike.STRIKE_LIMIT} bomber strikes wins.`,
	BVR = "Beyond visual range: two teams start about 20 km apart with radar missiles only. Needs a Tier IV+ jet with radar missiles.",
	GunsOnly = `Free for all with no missiles: guns only, with {MatchRules.GUNS_ONLY_AMMO} times the ammo. Close-in turning fights.`,
	Waves = `Co-op for up to three: defend your airbase from {Strike.WAVES} waves of AI fighters and bombers, each bigger than the last.`,
	Any = "Whichever of the team and free-for-all modes finds you a match fastest.",
}

local function modePicker(props: any)
	-- Shrinks to fit between the side panels on a narrow screen (or a large Menu scale) rather than run under
	-- them. The frame's height is a fixed 50, so its width over its height gives the room in the menu's units.
	local room, setRoom = React.useState(PICKER_WIDTH)
	local hovered, setHovered = React.useState(nil :: string?)
	local fit = math.clamp(room / PICKER_WIDTH, 0.4, 1)
	local buttons: { [string]: any } = { Layout = C.List({ Horizontal = true, Gap = 8, Align = "Center" }) }
	for i, item in QUEUE_MODES do
		local id, label, width = item[1], item[2], item[3]
		buttons[id] = e("Frame", {
			Size = UDim2.fromOffset(width, 50),
			BackgroundTransparency = 1,
			LayoutOrder = i,
			[React.Event.MouseEnter] = function()
				setHovered(id)
			end,
			[React.Event.MouseLeave] = function()
				setHovered(function(current)
					return if current == id then nil else current
				end)
			end,
		}, {
			Button = e(C.Button, {
				Text = label,
				Style = if props.Value == id then "Primary" else "Ghost",
				Size = UDim2.fromScale(1, 1),
				TextSize = 15,
				OnClick = function()
					props.OnPick(id)
				end,
			}),
		})
	end
	local about = hovered and MODE_ABOUT[hovered]
	-- Measured, as wrapped text doesn't grow a box that sizes itself
	local aboutHeight = if about
		then TextService:GetTextSize(about, 15, Theme.FontBold, Vector2.new(436, 1000)).Y
		else 0
	return e("Frame", {
		Size = UDim2.new(1, -SIDE_PANELS, 0, 50),
		Position = UDim2.new(0.5, 0, 1, -224),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		ZIndex = 3, -- the explanation sits over the jet's name
		[React.Change.AbsoluteSize] = function(frame: Frame)
			if frame.AbsoluteSize.Y > 0 then
				setRoom(frame.AbsoluteSize.X / frame.AbsoluteSize.Y * 50)
			end
		end,
	}, {
		Row = e("Frame", {
			Size = UDim2.fromOffset(PICKER_WIDTH, 50),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
		}, {
			Scale = e("UIScale", { Scale = fit }),
			Buttons = e("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, buttons),
		}),
		-- The hovered mode, explained just above the row
		About = if about
			then e(C.Panel, {
				Size = UDim2.fromOffset(460, 12 + 20 + 4 + aboutHeight + 12),
				Position = UDim2.new(0.5, 0, 0, -10),
				AnchorPoint = Vector2.new(0.5, 1),
				Padding = 12,
				StrokeColor = Theme.Accent,
				ZIndex = 5,
			}, {
				Layout = C.List({ Gap = 4 }),
				Name = e(C.Label, {
					Text = string.upper(
						if hovered == "Any" then "Any mode" else (MatchRules.MODES :: any)[hovered].DisplayName
					),
					Size = UDim2.new(1, 0, 0, 20),
					TextSize = 16,
					Heavy = true,
					Color = Theme.Accent,
					LayoutOrder = 1,
					ZIndex = 5,
				}),
				Text = e(C.Label, {
					Text = about,
					Size = UDim2.new(1, 0, 0, aboutHeight),
					TextSize = 15,
					Bold = true,
					Wrap = true,
					LayoutOrder = 2,
					ZIndex = 5,
				}),
			})
			else nil,
	})
end

local function slotCard(props: any)
	local airframe = props.Id and AircraftData.get(props.Id) :: any
	local selected = props.Id ~= nil and props.Id == props.Selected
	if not airframe then
		return e(C.Panel, {
			Size = UDim2.new(1, 0, 0, 64),
			LayoutOrder = props.Order,
			Color = Theme.Background,
			Transparency = 0.3,
		}, {
			Label = e(C.Label, {
				Text = props.LockedText or "Empty slot",
				Size = UDim2.fromScale(1, 1),
				Align = "Center",
				Color = Theme.Dim,
				TextSize = 14,
			}),
		})
	end
	return e("TextButton", {
		Size = UDim2.new(1, 0, 0, 64),
		LayoutOrder = props.Order,
		BackgroundColor3 = if selected then Theme.AccentDark else Theme.PanelLight,
		AutoButtonColor = true,
		Text = "",
		[React.Event.Activated] = function()
			props.OnSelect(props.Id)
		end,
	}, {
		Corner = C.corner(),
		Stroke = if selected then C.stroke(Theme.Accent, 1.5) else nil,
		Key = e(C.Label, {
			Text = `[{props.Order}]`,
			Size = UDim2.fromOffset(34, 64),
			Position = UDim2.fromOffset(8, 0),
			Color = Theme.Dim,
			Bold = true,
			TextSize = 14,
		}),
		Name = e(C.Label, {
			Text = airframe.DisplayName,
			Size = UDim2.new(1, -50, 0, 22),
			Position = UDim2.fromOffset(42, 10),
			Bold = true,
			TextSize = 17,
		}),
		Info = e(C.Label, {
			Text = `Tier {TIER_NAMES[airframe.Tier]}  ·  BR {LiveConfig.battleRating(props.Id)}  ·  {props.RP} RP`,
			Size = UDim2.new(1, -50, 0, 18),
			Position = UDim2.fromOffset(42, 34),
			Color = Theme.Dim,
			TextSize = 13,
		}),
	})
end

local function Hangar(props: any)
	local data = props.Data
	local lineupError, setLineupError = React.useState(nil :: string?)
	local pending, setPending = React.useState(false)
	local spinOpen, setSpinOpen = React.useState(false)
	local selected = props.Selected
	local airframe = selected and AircraftData.get(selected) :: any
	local slots = Progression.slotsFor(data)

	-- Lineup column
	local lineupChildren: { [string]: any } = { Layout = C.List({ Gap = 8 }) }
	lineupChildren.Title =
		e(C.Label, { Text = "LINEUP", Bold = true, Color = Theme.Accent, TextSize = 14, LayoutOrder = 0 })
	-- Every slot you have (the Extra Lineup Slot pass makes a fourth), and at least the three levels unlock
	local lineupRows = math.max(3, slots)
	local lineupHeight = 26 + lineupRows * 72 -- the title, then each slot card (64) and its gap
	for i = 1, lineupRows do
		local id = data.Lineup[i]
		local lockedText = nil
		if i > slots then
			for _, step in Economy.LINEUP_SLOTS do
				if step.slots == i then
					lockedText = `Slot unlocks at pilot level {step.level}`
				end
			end
		end
		lineupChildren[`Slot{i}`] = e(slotCard, {
			Id = if i <= slots then id else nil,
			Order = i,
			Selected = selected,
			OnSelect = props.OnSelect,
			RP = id and data.Aircraft[id] and data.Aircraft[id].RP or 0,
			LockedText = lockedText,
		})
	end

	-- Your other jets: add to / remove from the lineup
	local owned = {}
	for id, entry in data.Aircraft do
		if entry.Owned then
			table.insert(owned, id)
		end
	end
	table.sort(owned, function(a, b)
		local aa, bb = AircraftData.get(a) :: any, AircraftData.get(b) :: any
		return (aa and LiveConfig.battleRating(a) or 0) < (bb and LiveConfig.battleRating(b) or 0)
	end)
	local function setLineup(ids)
		setPending(true)
		task.spawn(function()
			local ok, err = props.OnLineup(ids)
			setPending(false)
			setLineupError(if ok then nil else err)
		end)
	end
	-- With every slot full (a new pilot has only one), adding a jet swaps it in for the selected lineup jet,
	-- or the last slot; otherwise a one-slot pilot could never change jets.
	local full = #data.Lineup >= slots
	local swapIndex = (selected and table.find(data.Lineup, selected)) or math.min(slots, #data.Lineup)
	local ownedChildren: { [string]: any } = { Layout = C.List({ Gap = 6 }) }
	ownedChildren.Title =
		e(C.Label, { Text = "YOUR JETS", Bold = true, Color = Theme.Accent, TextSize = 14, LayoutOrder = 0 })
	for i, id in owned do
		local info = AircraftData.get(id) :: any
		local index = table.find(data.Lineup, id)
		ownedChildren[id] = e("Frame", {
			Size = UDim2.new(1, 0, 0, 44),
			BackgroundTransparency = 1,
			LayoutOrder = i,
		}, {
			Name = e(C.Label, {
				Text = `{info and info.DisplayName or id}  ·  BR {info and LiveConfig.battleRating(id) or "?"}`,
				Size = UDim2.new(1, -96, 1, 0),
				TextSize = 14,
				Color = if index then Theme.Text else Theme.Dim,
			}),
			Toggle = e(C.Button, {
				Text = if index then "Remove" elseif full then "Swap" else "Add",
				-- What it does at a glance: red takes a jet out, blue swaps it in, green adds it
				StrokeColor = if index then Theme.Bad elseif full then SWAP_BLUE else Theme.Good,
				Size = UDim2.fromOffset(88, 36),
				Position = UDim2.new(1, -88, 0.5, -18),
				TextSize = 13,
				Pending = pending,
				Disabled = index ~= nil and #data.Lineup <= 1, -- always keep one jet
				OnClick = function()
					local ids = table.clone(data.Lineup)
					if index then
						table.remove(ids, index)
					elseif full then
						ids[swapIndex] = id
					else
						table.insert(ids, id)
					end
					setLineup(ids)
					if not index then
						props.OnSelect(id)
					end
				end,
			}),
		})
	end
	ownedChildren.Error = if lineupError
		then e(C.Label, { Text = lineupError, Color = Theme.Bad, TextSize = 13, LayoutOrder = 999, Wrap = true })
		else nil

	return e("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, {
		Preview = if airframe
			then e(JetPreview, {
				AirframeId = selected,
				Skin = Progression.skinFor(data, selected),
				Marker = Cosmetics.equipped(data, "Marker"),
				WingArt = Cosmetics.equipped(data, "WingArt"),
				Mastery = Mastery.displayStars(data, selected),
				Size = UDim2.fromScale(0.5, 0.62),
				Position = UDim2.fromScale(0.5, 0.36),
				AnchorPoint = Vector2.new(0.5, 0.5),
			})
			else nil,
		-- The jet's name and line sit just above the mode buttons (not a share of the height, which put them over
		-- the buttons on a short screen)
		JetName = e(C.Label, {
			Text = if airframe then airframe.DisplayName else "",
			Position = UDim2.new(0.5, 0, 1, -300),
			AnchorPoint = Vector2.new(0.5, 0),
			Size = UDim2.fromOffset(600, 40),
			Align = "Center",
			Heavy = true,
			TextSize = 34,
		}),
		JetInfo = e(C.Label, {
			Text = if airframe
				then `Tier {TIER_NAMES[airframe.Tier]}  ·  BR {LiveConfig.battleRating(selected)}  ·  {airframe.Branch}  ·  {Mastery.starText(
					Mastery.stars(data.Aircraft[selected] and data.Aircraft[selected].Mastery or 0)
				)}`
				else "",
			Position = UDim2.new(0.5, 0, 1, -258),
			AnchorPoint = Vector2.new(0.5, 0),
			Size = UDim2.fromOffset(600, 22),
			Align = "Center",
			Color = Theme.Dim,
			TextSize = 16,
		}),
		Modes = if props.QueueMode then e(modePicker, { Value = props.QueueMode, OnPick = props.OnQueueMode }) else nil,
		Play = e(C.Button, {
			Text = props.PlayText or "PLAY",
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
		Side = if props.SideText
			then e(C.Button, {
				Text = props.SideText,
				Style = "Ghost",
				TextSize = 20,
				Size = UDim2.fromOffset(210, 70),
				Position = UDim2.new(0.5, -440, 1, -137),
				OnClick = props.OnSide,
			})
			else nil,
		Report = if props.OnReport
			then e(C.Button, {
				Text = "REPORT",
				Style = "Ghost",
				TextSize = 15,
				Size = UDim2.fromOffset(210, 40),
				Position = UDim2.new(0.5, -440, 1, -58),
				OnClick = function()
					props.OnReport(nil)
				end,
			})
			else nil,
		-- Report a bug (Shared/Feedback), under DETAILS
		Feedback = if props.OnFeedback
			then e(C.Button, {
				Text = "REPORT BUG",
				Style = "Ghost",
				TextSize = 15,
				Size = UDim2.fromOffset(180, 40),
				Position = UDim2.new(0.5, 230, 1, -58),
				StrokeColor = Theme.Warn,
				OnClick = props.OnFeedback,
			})
			else nil,
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
		Status = e(C.Label, {
			Text = props.Status or "",
			Position = UDim2.new(0.5, 0, 1, -44),
			AnchorPoint = Vector2.new(0.5, 0),
			Size = UDim2.fromOffset(420, 22),
			Align = "Center",
			Color = Theme.Warn,
			Bold = true,
			TextSize = 18,
		}),
		Challenges = e(ChallengesPanel, { Data = data, OnReroll = props.OnReroll }),
		-- In a lobby (where PLAY queues): how the jet you pick decides who you meet
		Matchmaking = if props.QueueMode
			then e(MatchmakingPanel, { AirframeId = selected, Mode = props.QueueMode, Data = data })
			else nil,
		-- In a lobby: your party (MMK-05)
		Party = if props.QueueMode and props.Party
			then e(PartyPanel, {
				Party = props.Party,
				Candidates = props.PartyCandidates,
				OnInvite = props.OnPartyInvite,
				OnRespond = props.OnPartyRespond,
				OnKick = props.OnPartyKick,
				OnLeave = props.OnPartyLeave,
				OnInviteFriends = props.OnInviteFriends,
			})
			else nil,
		SpinButton = if props.OnSpin
			then e(SpinButton, {
				OnOpen = function()
					setSpinOpen(true)
				end,
			})
			else nil,
		-- Its own ScreenGui above the menu: the menu draws with Global ZIndex, which put the window's backdrop
		-- over its own buttons
		SpinDialog = if spinOpen and props.OnSpin
			then ReactRoblox.createPortal({
				AfterburnerSpin = e("ScreenGui", {
					DisplayOrder = 30,
					IgnoreGuiInset = true,
					ResetOnSpawn = false,
					ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
				}, {
					Dialog = e(SpinDialog, {
						OnSpin = props.OnSpin,
						OnClose = function()
							setSpinOpen(false)
						end,
					}),
				}),
			}, Players.LocalPlayer:WaitForChild("PlayerGui"))
			else nil,
		Lineup = e(C.Panel, {
			Size = UDim2.new(0, 300, 1, -40),
			Position = UDim2.fromOffset(20, 20),
			Padding = 14,
		}, {
			Layout = C.List({ Gap = 14 }),
			Lineup = e("Frame", {
				Size = UDim2.new(1, 0, 0, lineupHeight),
				BackgroundTransparency = 1,
				LayoutOrder = 1,
			}, lineupChildren),
			Owned = e("ScrollingFrame", {
				Size = UDim2.new(1, 0, 1, -(lineupHeight + 20)),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ScrollBarThickness = 4,
				CanvasSize = UDim2.new(),
				AutomaticCanvasSize = Enum.AutomaticSize.Y,
				LayoutOrder = 2,
			}, ownedChildren),
		}),
	})
end

return Hangar
