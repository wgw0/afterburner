--!strict
-- Choosing what PLAY queues for, in the lobby's Hangar (UI-05): one card above PLAY shows the chosen mode (its
-- kind's colour, team size, length and a one-line pitch); clicking it opens a picker of every mode as large
-- cards grouped by kind, with the main mode (Ranked Duel, Will) featured first with your rank. The mode under
-- the pointer is explained in full along the bottom; clicking a card picks it and closes the picker.
-- props: Value (the mode id), OnPick(id), Data (the save, for the duel rank).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("React")) :: any
local ReactRoblox = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("ReactRoblox")) :: any
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Duel = require(Shared.Duel)
local MatchRules = require(Shared.MatchRules)
local Strike = require(Shared.Strike)

local C = require(script.Parent.Components)
local Theme = require(script.Parent.Theme)

local e = React.createElement

-- Each kind of mode has its colour, on the card's stripe and tag
local KINDS = {
	Duels = { name = "DUELS", colour = Theme.Rarity.Legendary },
	Teams = { name = "TEAM BATTLE", colour = Theme.Rarity.Rare },
	FreeForAll = { name = "FREE FOR ALL", colour = Theme.Bad },
	Coop = { name = "CO-OP", colour = Theme.Good },
	Quick = { name = "QUICK PLAY", colour = Theme.Accent },
}

local function minutes(modeId: string): string
	return `{math.floor((MatchRules.MODES :: any)[modeId].TimeLimit / 60)} min`
end

type Mode = { name: string, kind: string, size: string, length: string, pitch: string, about: string }

local MODES: { [string]: Mode } = {
	Duel = {
		name = "Ranked Duel",
		kind = "Duels",
		size = "1v1",
		length = "Best of 5",
		pitch = "Climb the ranks, one pilot at a time.",
		about = `1v1 against a pilot near your rating, best of five rounds with one life each. You start in opposite corners; first to {Duel.ROUNDS_TO_WIN} round wins. Wins and losses move your duel rating.`,
	},
	DuelCasual = {
		name = "Casual Duel",
		kind = "Duels",
		size = "1v1",
		length = "Best of 5",
		pitch = "Duel practice. No rating on the line.",
		about = "The same 1v1 rounds as Ranked Duel, for practice: your rating doesn't move.",
	},
	Any = {
		name = "Any Mode",
		kind = "Quick",
		size = "3v3 or FFA",
		length = "Fastest",
		pitch = "Jump into whichever match is ready first.",
		about = "Whichever of the team and free-for-all modes finds you a match fastest.",
	},
	TeamDeathmatch = {
		name = "Teams",
		kind = "Teams",
		size = "3v3",
		length = minutes("TeamDeathmatch"),
		pitch = "Fly with your wingmen. Most kills wins.",
		about = `Two teams of three. First team to {MatchRules.MODES.TeamDeathmatch.ScoreLimit} kills, or the most after {minutes(
			"TeamDeathmatch"
		)}.`,
	},
	AirSuperiority = {
		name = "Zones",
		kind = "Teams",
		size = "3v3",
		length = minutes("AirSuperiority"),
		pitch = "Seize the sky. Hold zones, drain tickets.",
		about = "Two teams fight for three zones. Hold more zones than the enemy and their tickets drain; every jet lost costs tickets too.",
	},
	StrikeEscort = {
		name = "Strike Escort",
		kind = "Teams",
		size = "3v3",
		length = minutes("StrikeEscort"),
		pitch = "Escort your bombers. Stop theirs.",
		about = `Two teams escort AI bombers to the enemy airbase and hunt theirs. First to {Strike.STRIKE_LIMIT} bomber strikes wins.`,
	},
	BVR = {
		name = "BVR Battle",
		kind = "Teams",
		size = "3v3",
		length = minutes("BVR"),
		pitch = "Radar missiles from 20 km out.",
		about = "Beyond visual range: two teams start about 20 km apart with radar missiles only. Needs a Tier IV+ jet with radar missiles.",
	},
	Dogfight = {
		name = "Dogfight",
		kind = "FreeForAll",
		size = "6 pilots",
		length = minutes("Dogfight"),
		pitch = "Everyone's a target. Most kills wins.",
		about = `Free for all: every other jet is an enemy. First to {MatchRules.MODES.Dogfight.ScoreLimit} kills, or the most after {minutes(
			"Dogfight"
		)}.`,
	},
	GunsOnly = {
		name = "Guns Only",
		kind = "FreeForAll",
		size = "6 pilots",
		length = minutes("GunsOnly"),
		pitch = "No missiles. Just guns and nerve.",
		about = `Free for all with no missiles: guns only, with {MatchRules.GUNS_ONLY_AMMO} times the ammo. Close-in turning fights.`,
	},
	Waves = {
		name = "PvE Waves",
		kind = "Coop",
		size = "Co-op, up to 3",
		length = `{Strike.WAVES} waves`,
		pitch = "Team up against waves of AI raiders.",
		about = `Co-op for up to three: defend your airbase from {Strike.WAVES} waves of AI fighters and bombers, each bigger than the last.`,
	},
}

-- The picker's rows: { id, columns wide }. The main mode leads, wide.
local ROWS = {
	{ { "Duel", 2 }, { "DuelCasual", 1 }, { "Any", 1 } },
	{ { "TeamDeathmatch", 1 }, { "AirSuperiority", 1 }, { "StrikeEscort", 1 }, { "BVR", 1 } },
	{ { "Dogfight", 4 / 3 }, { "GunsOnly", 4 / 3 }, { "Waves", 4 / 3 } },
}
local ROW_HEIGHTS = { 150, 132, 132 }
local PANEL_W, PANEL_H = 1040, 660
local PAD, GAP = 24, 12
local COLUMN = (PANEL_W - 2 * PAD - 3 * GAP) / 4
local CARD_W = 640 -- the card above PLAY

-- "BRONZE · 1000" for the duel modes
local function rankText(data: any): string
	local rec = data and data.Duel or Duel.newRecord()
	local rating = rec.Rating or Duel.START_RATING
	return `{string.upper(Duel.rankFor(rating).name)} · {rating}`
end

local function stripe(colour: Color3)
	return e("Frame", {
		Size = UDim2.new(0, 6, 1, 0),
		BackgroundColor3 = colour,
		BorderSizePixel = 0,
	}, { Corner = C.corner(3) })
end

-- One mode in the picker
local function ModeTile(props: any)
	local id, mode = props.Id, MODES[props.Id]
	local kind = KINDS[mode.kind]
	local picked = props.Picked
	local featured = id == "Duel"
	return e("TextButton", {
		Size = UDim2.fromOffset(props.Width, props.Height),
		BackgroundColor3 = if picked then Theme.PanelLight else Theme.Panel,
		BackgroundTransparency = 0,
		AutoButtonColor = true,
		Text = "",
		LayoutOrder = props.Order,
		[React.Event.Activated] = function()
			props.OnPick(id)
		end,
		[React.Event.MouseEnter] = function()
			props.OnHover(id)
		end,
		[React.Event.SelectionGained] = function()
			props.OnHover(id)
		end,
	}, {
		Corner = C.corner(10),
		Stroke = e("UIStroke", {
			Color = if picked then kind.colour else Theme.Stroke,
			Thickness = if picked then 3 else 1,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
		Stripe = stripe(kind.colour),
		Body = e("Frame", {
			Size = UDim2.new(1, -36, 1, -28),
			Position = UDim2.fromOffset(22, 14),
			BackgroundTransparency = 1,
		}, {
			Kind = e(C.Label, {
				Text = if featured then `{kind.name}  ·  MAIN MODE` else kind.name,
				Size = UDim2.new(1, 0, 0, 14),
				TextSize = 12,
				Bold = true,
				Color = kind.colour,
			}),
			Picked = if picked
				then e(C.Label, {
					Text = "✓ SELECTED",
					Size = UDim2.new(1, 0, 0, 14),
					Align = "Right",
					TextSize = 12,
					Bold = true,
					Color = kind.colour,
				})
				else nil,
			Name = e(C.Label, {
				Text = string.upper(mode.name),
				Size = UDim2.new(1, 0, 0, if featured then 34 else 26),
				Position = UDim2.fromOffset(0, 20),
				TextSize = if featured then 30 else 22,
				Heavy = true,
			}),
			Facts = e(C.Label, {
				Text = `{mode.size}  ·  {mode.length}{if mode.kind == "Duels"
					then "  ·  " .. rankText(props.Data)
					else ""}`,
				Size = UDim2.new(1, 0, 0, 16),
				Position = UDim2.fromOffset(0, if featured then 58 else 50),
				TextSize = 14,
				Color = Theme.Dim,
			}),
			Pitch = e(C.Label, {
				Text = mode.pitch,
				Size = UDim2.new(1, 0, 0, 36),
				Position = UDim2.new(0, 0, 1, -36),
				TextSize = if featured then 17 else 15,
				Bold = true,
				Wrap = true,
				Color = Theme.Text,
			}),
		}),
	})
end

-- The full-screen picker
local function Picker(props: any)
	local hovered, setHovered = React.useState(props.Value)
	local fit, setFit = React.useState(1)
	local probe = React.useRef(nil)
	local rows: { [string]: any } = { Layout = C.List({ Gap = GAP }) }
	for r, row in ROWS do
		local tiles: { [string]: any } = { Layout = C.List({ Horizontal = true, Gap = GAP }) }
		for i, item in row do
			local columns = item[2]
			tiles[item[1]] = e(ModeTile, {
				Id = item[1],
				Width = math.floor(COLUMN * columns + GAP * (columns - 1)),
				Height = ROW_HEIGHTS[r],
				Order = i,
				Picked = item[1] == props.Value,
				Data = props.Data,
				OnPick = props.OnPick,
				OnHover = setHovered,
			})
		end
		rows["Row" .. r] = e("Frame", {
			Size = UDim2.new(1, 0, 0, ROW_HEIGHTS[r]),
			BackgroundTransparency = 1,
			LayoutOrder = r,
		}, tiles)
	end
	local shown = MODES[hovered] or MODES[props.Value]
	local shownKind = KINDS[shown.kind]
	-- The picker shrinks to fit a small screen (a probe of known size tells the menu's scale)
	local function measure(frame: Frame)
		local p = probe.current
		local scale = if p and p.AbsoluteSize.X > 0 then p.AbsoluteSize.X / 100 else 1
		local w, h = frame.AbsoluteSize.X / scale, frame.AbsoluteSize.Y / scale
		setFit(math.min(1, (w - 40) / PANEL_W, (h - 40) / PANEL_H))
	end
	return e("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.35,
		AutoButtonColor = false,
		Text = "",
		Selectable = false,
		[React.Change.AbsoluteSize] = measure,
		[React.Event.Activated] = props.OnClose, -- a click outside the panel
	}, {
		Probe = e("Frame", { Size = UDim2.fromOffset(100, 100), BackgroundTransparency = 1, ref = probe }),
		Panel = e("TextButton", {
			Size = UDim2.fromOffset(PANEL_W, PANEL_H),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = Theme.Background,
			AutoButtonColor = false,
			Text = "",
			Selectable = false,
		}, {
			Scale = e("UIScale", { Scale = fit }),
			Corner = C.corner(14),
			Stroke = e("UIStroke", { Color = Theme.Stroke, Thickness = 1.5 }),
			Padding = e("UIPadding", {
				PaddingTop = UDim.new(0, PAD),
				PaddingBottom = UDim.new(0, PAD),
				PaddingLeft = UDim.new(0, PAD),
				PaddingRight = UDim.new(0, PAD),
			}),
			Title = e(C.Label, {
				Text = "CHOOSE A MODE",
				Size = UDim2.new(1, -140, 0, 32),
				TextSize = 28,
				Heavy = true,
				Color = Theme.Accent,
			}),
			Close = e(C.Button, {
				Text = "CLOSE",
				Style = "Ghost",
				Size = UDim2.fromOffset(110, 36),
				Position = UDim2.new(1, 0, 0, -2),
				AnchorPoint = Vector2.new(1, 0),
				TextSize = 14,
				OnClick = props.OnClose,
			}),
			Rows = e("Frame", {
				Size = UDim2.new(1, 0, 0, ROW_HEIGHTS[1] + ROW_HEIGHTS[2] + ROW_HEIGHTS[3] + 2 * GAP),
				Position = UDim2.fromOffset(0, 50),
				BackgroundTransparency = 1,
			}, rows),
			-- The mode under the pointer, in full
			About = e("Frame", {
				Size = UDim2.new(1, 0, 0, 96),
				Position = UDim2.new(0, 0, 1, -96),
				BackgroundColor3 = Theme.Panel,
				BorderSizePixel = 0,
			}, {
				Corner = C.corner(10),
				Stripe = stripe(shownKind.colour),
				Name = e(C.Label, {
					Text = `{string.upper(shown.name)}   {shown.size}  ·  {shown.length}`,
					Size = UDim2.new(1, -40, 0, 22),
					Position = UDim2.fromOffset(22, 12),
					TextSize = 18,
					Heavy = true,
					Color = shownKind.colour,
				}),
				Text = e(C.Label, {
					Text = shown.about,
					Size = UDim2.new(1, -40, 0, 48),
					Position = UDim2.fromOffset(22, 38),
					TextSize = 16,
					Bold = true,
					Wrap = true,
				}),
			}),
		}),
	})
end

local function ModeSelect(props: any)
	local open, setOpen = React.useState(false)
	local mode = MODES[props.Value] or MODES.Any
	local kind = KINDS[mode.kind]
	return e("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 3,
	}, {
		-- The chosen mode, above PLAY: click to change
		Card = e("TextButton", {
			Size = UDim2.fromOffset(CARD_W, 66),
			Position = UDim2.new(0.5, 0, 1, -228),
			AnchorPoint = Vector2.new(0.5, 0),
			BackgroundColor3 = Theme.Panel,
			BackgroundTransparency = 0.1,
			AutoButtonColor = true,
			Text = "",
			[React.Event.Activated] = function()
				setOpen(true)
			end,
		}, {
			Corner = C.corner(10),
			Stroke = e(
				"UIStroke",
				{ Color = kind.colour, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }
			),
			Stripe = stripe(kind.colour),
			Name = e(C.Label, {
				Text = string.upper(mode.name),
				Size = UDim2.fromOffset(250, 26),
				Position = UDim2.fromOffset(22, 9),
				TextSize = 22,
				Heavy = true,
				Color = kind.colour,
			}),
			Facts = e(C.Label, {
				Text = `{mode.size}  ·  {mode.length}{if mode.kind == "Duels"
					then "  ·  " .. rankText(props.Data)
					else ""}`,
				Size = UDim2.fromOffset(330, 26),
				Position = UDim2.fromOffset(250, 9),
				TextSize = 14,
				Bold = true,
				Color = Theme.Dim,
			}),
			Pitch = e(C.Label, {
				Text = mode.pitch,
				Size = UDim2.new(1, -200, 0, 20),
				Position = UDim2.fromOffset(22, 38),
				TextSize = 15,
				Color = Theme.Text,
			}),
			Change = e("Frame", {
				Size = UDim2.fromOffset(150, 40),
				Position = UDim2.new(1, -12, 0.5, 0),
				AnchorPoint = Vector2.new(1, 0.5),
				BackgroundColor3 = kind.colour,
				BorderSizePixel = 0,
			}, {
				Corner = C.corner(8),
				Label = e(C.Label, {
					Text = "CHANGE MODE",
					Size = UDim2.fromScale(1, 1),
					Align = "Center",
					TextSize = 14,
					Bold = true,
					Color = Color3.fromRGB(14, 16, 22),
				}),
			}),
		}),
		-- Its own ScreenGui above the menu (which draws with Global ZIndex), like the spin window
		Picker = if open
			then ReactRoblox.createPortal({
				AfterburnerModePicker = e("ScreenGui", {
					DisplayOrder = 30,
					IgnoreGuiInset = true,
					ResetOnSpawn = false,
					ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
				}, {
					Picker = e(Picker, {
						Value = props.Value,
						Data = props.Data,
						OnPick = function(id: string)
							props.OnPick(id)
							setOpen(false)
						end,
						OnClose = function()
							setOpen(false)
						end,
					}),
				}),
			}, Players.LocalPlayer:WaitForChild("PlayerGui"))
			else nil,
	})
end

return ModeSelect
