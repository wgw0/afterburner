--!strict
-- Choosing what PLAY queues for, in the lobby's Hangar (UI-05): one card above PLAY shows the chosen mode (its
-- kind's colour, team size, length and a one-line pitch); clicking it opens a picker of every mode as large
-- cards grouped by kind, with the main mode (Ranked Duel, Will) featured first with your rank. The mode under
-- the pointer is explained in full along the bottom; clicking a card picks it and closes the picker.
-- props: Value (the mode id), OnPick(id), Data (the save, for the duel rank), RecommendAny (few pilots online:
-- Any mode is marked RECOMMENDED, and the card's pitch says so while another mode is picked).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("React")) :: any
local ReactRoblox = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("ReactRoblox")) :: any
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Duel = require(Shared.Duel)

local C = require(script.Parent.Components)
local ModeInfo = require(script.Parent.ModeInfo)
local Theme = require(script.Parent.Theme)

local e = React.createElement

local KINDS, MODES = ModeInfo.KINDS, ModeInfo.MODES

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
	local recommended = id == "Any" and props.RecommendAny == true
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
			Color = if picked or recommended then kind.colour else Theme.Stroke,
			Thickness = if picked then 3 elseif recommended then 2 else 1,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
		Stripe = stripe(kind.colour),
		Body = e("Frame", {
			Size = UDim2.new(1, -36, 1, -28),
			Position = UDim2.fromOffset(22, 14),
			BackgroundTransparency = 1,
		}, {
			Kind = e(C.Label, {
				Text = if featured
					then `{kind.name}  ·  MAIN MODE`
					elseif recommended then `{kind.name}  ·  RECOMMENDED`
					else kind.name,
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
				RecommendAny = props.RecommendAny,
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
			-- Few pilots online and another mode picked: the tip instead of the pitch
			Pitch = e(C.Label, {
				Text = if props.RecommendAny and props.Value ~= "Any"
					then "Few pilots online: ANY MODE finds you a match fastest"
					else mode.pitch,
				Size = UDim2.new(1, -200, 0, 20),
				Position = UDim2.fromOffset(22, 38),
				TextSize = 15,
				Bold = props.RecommendAny and props.Value ~= "Any",
				Color = if props.RecommendAny and props.Value ~= "Any" then Theme.Accent else Theme.Text,
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
						RecommendAny = props.RecommendAny,
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
