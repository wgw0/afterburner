--!strict
-- Career (PRG-03, LIV-02). Top: your lifetime stats, and the level track: your level and XP, then every
-- milestone (Config/LevelRewards) in a row, the ones reached lit, the next one marked, later ones dimmed,
-- with your callsign (CMP-01) and title picker under it. Bottom: the achievements, earned ones lit with the date.
-- props: Data, OnSetTitle(titleId) -> (ok, err), OnSetCallsign(text) -> (ok, err).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local React = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("React")) :: any
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Achievements = require(Shared.Achievements)
local Callsign = require(Shared.Callsign)
local Economy = require(Shared.Config.Economy)
local LevelRewards = require(Shared.Config.LevelRewards)
local Mastery = require(Shared.Mastery)
local Passes = require(Shared.Config.Passes)

local C = require(script.Parent.Parent.Components)
local Theme = require(script.Parent.Parent.Theme)

local e = React.createElement
local CARD_W, CARD_H = 250, 96
local STEP_W, STEP_H = 168, 128
local TOP_H = 340

local function stat(label: string, value: string, order: number)
	return e("Frame", { Size = UDim2.new(1, 0, 0, 34), BackgroundTransparency = 1, LayoutOrder = order }, {
		Label = e(C.Label, { Text = label, Size = UDim2.fromScale(0.6, 1), TextSize = 15, Color = Theme.Dim }),
		Value = e(C.Label, {
			Text = value,
			Size = UDim2.fromScale(0.4, 1),
			Position = UDim2.fromScale(0.6, 0),
			TextSize = 18,
			Bold = true,
			Align = "Right",
		}),
	})
end

-- One level on the track: its rewards, and whether it's reached, next, or still to come.
local function step(group: any, level: number, isNext: boolean, order: number)
	local reached = level >= group.Level
	local lines: { [string]: any } = { Layout = C.List({ Gap = 2 }) }
	for i, milestone in group.Rewards do
		lines[`R{i}`] = e(C.Label, {
			Text = LevelRewards.describe(milestone),
			Size = UDim2.new(1, 0, 0, 30),
			TextSize = 12,
			Bold = milestone.Kind == "Skin",
			Wrap = true,
			Color = if reached then Theme.Text elseif milestone.Kind == "Skin" then Theme.Warn else Theme.Dim,
			LayoutOrder = i,
		})
	end
	return e(C.Panel, {
		Size = UDim2.fromOffset(STEP_W, STEP_H),
		Color = if reached then Theme.PanelLight else Theme.Background,
		Transparency = if reached or isNext then 0 else 0.3,
		StrokeColor = if reached then Theme.Accent elseif isNext then Theme.Warn else nil,
		StrokeThickness = if reached or isNext then 1.5 else nil,
		Padding = 10,
		LayoutOrder = order,
	}, {
		Level = e(C.Label, {
			Text = `LEVEL {group.Level}`,
			Size = UDim2.new(1, 0, 0, 18),
			Bold = true,
			TextSize = 14,
			Color = if reached then Theme.Accent elseif isNext then Theme.Warn else Theme.Dim,
		}),
		State = e(C.Label, {
			Text = if reached then "✓" elseif isNext then `{group.Level - level} TO GO` else "",
			Size = UDim2.new(1, 0, 0, 18),
			TextSize = 11,
			Bold = true,
			Align = "Right",
			Color = if reached then Theme.Good else Theme.Warn,
		}),
		Rewards = e("Frame", {
			Size = UDim2.new(1, 0, 1, -24),
			Position = UDim2.fromOffset(0, 24),
			BackgroundTransparency = 1,
		}, lines),
	})
end

-- Your callsign: what other pilots see instead of your username, checked by Roblox's filter when you set it.
-- Needs the Custom Callsign pass; without it the row offers the pass.
local function CallsignBox(props: { Data: any, OnSetCallsign: (string) -> (boolean, string?) })
	local saved = props.Data.Callsign or ""
	local passAttribute = Passes.attribute("CustomCallsign")
	local owned, setOwned = React.useState(Players.LocalPlayer:GetAttribute(passAttribute) == true)
	React.useEffect(function()
		local connection = Players.LocalPlayer:GetAttributeChangedSignal(passAttribute):Connect(function()
			setOwned(Players.LocalPlayer:GetAttribute(passAttribute) == true)
		end)
		return function()
			connection:Disconnect()
		end
	end, {})
	local text, setText = React.useState(saved)
	local pending, setPending = React.useState(false)
	local message, setMessage = React.useState(nil :: { text: string, bad: boolean }?)
	local function submit(value: string)
		setPending(true)
		task.spawn(function()
			local ok, err = props.OnSetCallsign(value)
			setPending(false)
			if ok then
				setText(value)
				setMessage({ text = if value == "" then "Using your username" else "Saved", bad = false })
			else
				setMessage({ text = err or "Couldn't save that", bad = true })
			end
		end)
	end
	local label = e(C.Label, {
		Text = "CALLSIGN",
		Size = UDim2.fromOffset(78, 30),
		Bold = true,
		TextSize = 12,
		Color = Theme.Accent,
		LayoutOrder = 0,
	})
	if not owned then
		local pass = Passes.LIST.CustomCallsign
		local passId = Passes.idFor("CustomCallsign")
		return e("Frame", {
			Size = UDim2.new(1, 0, 0, 30),
			Position = UDim2.new(0, 0, 1, -68),
			BackgroundTransparency = 1,
		}, {
			Layout = C.List({ Horizontal = true, Gap = 6, AlignY = "Center" }),
			Label = label,
			Get = if passId
				then e(C.Button, {
					Text = `GET {string.upper(pass.DisplayName)}  ·  R$ {pass.Price}`,
					Style = "Primary",
					Size = UDim2.fromOffset(250, 30),
					TextSize = 12,
					LayoutOrder = 1,
					OnClick = function()
						MarketplaceService:PromptGamePassPurchase(Players.LocalPlayer, passId)
					end,
				})
				else nil,
			Message = e(C.Label, {
				Text = if passId then pass.Description else "Custom callsigns come with a game pass, coming soon",
				Size = UDim2.fromOffset(420, 30),
				TextSize = 12,
				Color = Theme.Dim,
				LayoutOrder = 2,
			}),
		})
	end
	return e("Frame", {
		Size = UDim2.new(1, 0, 0, 30),
		Position = UDim2.new(0, 0, 1, -68),
		BackgroundTransparency = 1,
	}, {
		Layout = C.List({ Horizontal = true, Gap = 6, AlignY = "Center" }),
		Label = label,
		Box = e("TextBox", {
			Text = text,
			PlaceholderText = Players.LocalPlayer.Name,
			PlaceholderColor3 = Theme.Dim,
			ClearTextOnFocus = false,
			Font = Theme.FontBold,
			TextSize = 14,
			TextColor3 = Theme.Text,
			BackgroundColor3 = Theme.Background,
			Size = UDim2.fromOffset(180, 30),
			LayoutOrder = 1,
			[React.Change.Text] = function(box: TextBox)
				if #box.Text > Callsign.MAX then
					box.Text = string.sub(box.Text, 1, Callsign.MAX)
				end
				setText(box.Text)
			end,
			[React.Event.FocusLost] = function(_box: TextBox, enter: boolean)
				if enter and text ~= saved and text ~= "" then
					submit(text)
				end
			end,
		}, {
			Corner = C.corner(),
			Stroke = C.stroke(),
			Padding = e("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }),
		}),
		Set = e(C.Button, {
			Text = "SET",
			Style = "Primary",
			Size = UDim2.fromOffset(56, 30),
			TextSize = 12,
			Pending = pending,
			Disabled = text == saved or text == "",
			LayoutOrder = 2,
			OnClick = function()
				submit(text)
			end,
		}),
		Clear = if saved ~= ""
			then e(C.Button, {
				Text = "USE USERNAME",
				Style = "Ghost",
				Size = UDim2.fromOffset(120, 30),
				TextSize = 12,
				Pending = pending,
				LayoutOrder = 3,
				OnClick = function()
					submit("")
				end,
			})
			else nil,
		Message = e(C.Label, {
			Text = if message then message.text else "Shown to everyone instead of your username",
			Size = UDim2.fromOffset(300, 30),
			TextSize = 12,
			Color = if message and message.bad then Theme.Bad else Theme.Dim,
			LayoutOrder = 4,
		}),
	})
end

local function LevelTrack(props: any)
	local data = props.Data
	local level = data.PilotLevel or 1
	local allUnlocked = data.Flags and data.Flags.AllUnlocked == true
	local scroller = React.useRef(nil)
	local pending, setPending = React.useState(false)
	local groups = LevelRewards.byLevel()
	local nextIndex = #groups + 1
	for i, group in groups do
		if group.Level > level then
			nextIndex = i
			break
		end
	end

	-- Start the track with the last level reached in view, the next one beside it
	React.useEffect(function()
		local frame = scroller.current
		if frame then
			frame.CanvasPosition = Vector2.new(math.max(nextIndex - 2, 0) * (STEP_W + 10), 0)
		end
	end, {})

	local steps: { [string]: any } = {
		Layout = C.List({ Horizontal = true, Gap = 10 }),
		Padding = e("UIPadding", { PaddingTop = UDim.new(0, 2), PaddingLeft = UDim.new(0, 2) }),
	}
	for i, group in groups do
		steps[`L{group.Level}`] = step(group, level, i == nextIndex, i)
	end

	-- Titles you can show on the scoreboard
	local titles: { [string]: any } = { Layout = C.List({ Horizontal = true, Gap = 6, AlignY = "Center" }) }
	titles.Label = e(C.Label, {
		Text = "TITLE",
		Size = UDim2.fromOffset(46, 30),
		Bold = true,
		TextSize = 12,
		Color = Theme.Accent,
		LayoutOrder = 0,
	})
	local options = { { "", "None" } }
	for _, group in groups do
		for _, milestone in group.Rewards do
			if milestone.Kind == "Title" then
				table.insert(options, { milestone.Id :: string, LevelRewards.TITLES[milestone.Id :: string] })
			end
		end
	end
	-- Titles from elsewhere (the login streak, then 5-star mastery) only show once you have them
	for _, id in LevelRewards.OTHER_TITLES do
		if data.Titles and data.Titles[id] then
			table.insert(options, { id, LevelRewards.TITLES[id] })
		end
	end
	local mastery = {}
	for id in data.Titles or {} do
		local name = Mastery.titleName(id)
		if name then
			table.insert(mastery, { id, name })
		end
	end
	table.sort(mastery, function(a, b)
		return a[2] < b[2]
	end)
	for _, option in mastery do
		table.insert(options, option)
	end
	local locked = 0
	for i, option in options do
		local id, name = option[1], option[2]
		if LevelRewards.titleUnlocked(id, level, allUnlocked, data.Titles) then
			titles[`T{i}`] = e(C.Button, {
				Text = name,
				Style = if (data.Title or "") == id then "Primary" else "Ghost",
				Size = UDim2.fromOffset(math.max(70, #name * 8 + 20), 30),
				TextSize = 12,
				Pending = pending,
				LayoutOrder = i,
				OnClick = function()
					setPending(true)
					task.spawn(function()
						props.OnSetTitle(id)
						setPending(false)
					end)
				end,
			})
		else
			locked += 1
		end
	end
	titles.More = if locked > 0
		then e(C.Label, {
			Text = `{locked} more with level`,
			Size = UDim2.fromOffset(140, 30),
			TextSize = 12,
			Color = Theme.Dim,
			LayoutOrder = 99,
		})
		else nil

	local need = Economy.xpToNext(level)
	return e(C.Panel, {
		Size = UDim2.new(1, -360, 0, TOP_H),
		Position = UDim2.fromOffset(340, 20),
		Padding = 16,
	}, {
		Title = e(C.Label, {
			Text = `PILOT LEVEL {level}`,
			Size = UDim2.new(0.5, 0, 0, 24),
			Heavy = true,
			TextSize = 22,
			Color = Theme.Accent,
		}),
		Every = e(C.Label, {
			Text = `+{Economy.LEVEL_CREDITS} Credits every level`,
			Size = UDim2.new(0.5, 0, 0, 24),
			Position = UDim2.fromScale(0.5, 0),
			TextSize = 12,
			Color = Theme.Dim,
			Align = "Right",
		}),
		Xp = e(C.Bar, {
			Value = if level >= Economy.MAX_LEVEL then 1 else math.clamp((data.PilotXP or 0) / need, 0, 1),
			Size = UDim2.new(1, 0, 0, 16),
			Position = UDim2.fromOffset(0, 32),
			Color = Theme.Accent,
			Text = if level >= Economy.MAX_LEVEL
				then "MAX LEVEL"
				else `{C.number(data.PilotXP or 0)} / {C.number(need)} XP to level {level + 1}`,
		}),
		Track = e("ScrollingFrame", {
			Size = UDim2.new(1, 0, 0, STEP_H + 18),
			Position = UDim2.fromOffset(0, 62),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollBarThickness = 6,
			ScrollingDirection = Enum.ScrollingDirection.X,
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.X,
			ref = scroller,
		}, steps),
		Callsign = e(CallsignBox, { Data = data, OnSetCallsign = props.OnSetCallsign }),
		Titles = e("Frame", {
			Size = UDim2.new(1, 0, 0, 30),
			Position = UDim2.new(0, 0, 1, -32),
			BackgroundTransparency = 1,
		}, titles),
	})
end

-- An achievement: its border and name in its rarity's colour (faint until earned), the rarity in the corner.
local function card(def: any, earned: any, order: number)
	local lit = earned ~= nil
	local colour = Theme.Rarity[def.rarity] or Theme.Accent
	return e(C.Panel, {
		Size = UDim2.fromOffset(CARD_W, CARD_H),
		Color = if lit then Theme.PanelLight else Theme.Background,
		Transparency = if lit then 0 else 0.3,
		Padding = 12,
		LayoutOrder = order,
		StrokeColor = colour,
		StrokeThickness = if lit then 2 else 1,
		StrokeTransparency = if lit then 0 else 0.6,
	}, {
		Name = e(C.Label, {
			Text = def.name,
			Size = UDim2.new(1, 0, 0, 22),
			Bold = true,
			TextSize = 16,
			Color = if lit then colour else Theme.Dim,
		}),
		Text = e(C.Label, {
			Text = def.text,
			Size = UDim2.new(1, 0, 0, 34),
			Position = UDim2.fromOffset(0, 24),
			TextSize = 12,
			Wrap = true,
			Color = if lit then Theme.Text else Theme.Dim,
		}),
		When = e(C.Label, {
			Text = if lit then os.date("!Earned %d %b %Y", earned.At) :: string else "Not yet",
			Size = UDim2.new(0.6, 0, 0, 14),
			Position = UDim2.new(0, 0, 1, -14),
			TextSize = 11,
			Color = if lit then Theme.Good else Theme.Locked,
		}),
		Rarity = e(C.Label, {
			Text = if def.secret then `SECRET · {string.upper(def.rarity)}` else string.upper(def.rarity),
			Size = UDim2.new(0.6, 0, 0, 14),
			Position = UDim2.new(0.4, 0, 1, -14),
			TextSize = 10,
			Bold = true,
			Align = "Right",
			Color = colour,
			Transparency = if lit then 0 else 0.4,
		}),
	})
end

local function Career(props: any)
	local data = props.Data
	local stats = data.Stats or {}
	local earned = data.Achievements or {}
	local kills = (stats.Kills or 0) + (stats.AIKills or 0)
	local deaths = stats.Deaths or 0
	-- Secret achievements stay hidden until earned, and aren't in the total
	local count, total, secrets = 0, 0, 0
	for _, def in Achievements.LIST do
		if not def.secret then
			total += 1
			if earned[def.id] then
				count += 1
			end
		elseif earned[def.id] then
			secrets += 1
		end
	end
	local tally = `{count} / {total}{if secrets > 0 then ` + {secrets} secret` else ""}`

	local cards: { [string]: any } = {
		Grid = e("UIGridLayout", {
			CellSize = UDim2.fromOffset(CARD_W, CARD_H),
			CellPadding = UDim2.fromOffset(12, 12),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}
	-- In rarity order (Common first, Legendary last), then in list order within a rarity
	for i, def in Achievements.LIST do
		if not def.secret or earned[def.id] then
			local rank = table.find(Achievements.RARITIES, def.rarity) or #Achievements.RARITIES
			cards[def.id] = card(def, earned[def.id], rank * 100 + i)
		end
	end

	return e("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
	}, {
		Padding = e("UIPadding", { PaddingBottom = UDim.new(0, 20) }),
		Stats = e(C.Panel, {
			Size = UDim2.fromOffset(300, TOP_H),
			Position = UDim2.fromOffset(20, 20),
			Padding = 16,
		}, {
			Layout = C.List({ Gap = 4 }),
			Title = e(C.Label, { Text = "CAREER", Bold = true, Color = Theme.Accent, TextSize = 14, LayoutOrder = 0 }),
			Matches = stat("Matches", tostring(stats.Matches or 0), 2),
			Wins = stat("Wins", tostring(stats.Wins or 0), 3),
			Kills = stat("Kills", tostring(kills), 4),
			Players = stat("  of them players", tostring(stats.Kills or 0), 5),
			Deaths = stat("Times shot down", tostring(deaths), 6),
			Ratio = stat("Kills per death", string.format("%.2f", kills / math.max(deaths, 1)), 7),
			Achievements = stat("Achievements", `{count} / {total}`, 8),
		}),
		Level = e(LevelTrack, { Data = data, OnSetTitle = props.OnSetTitle, OnSetCallsign = props.OnSetCallsign }),
		-- Sized to its cards
		Achievements = e("Frame", {
			Size = UDim2.new(1, -40, 0, 0),
			Position = UDim2.fromOffset(20, TOP_H + 40),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = Theme.Panel,
			BackgroundTransparency = 0.05,
			BorderSizePixel = 0,
		}, {
			Corner = C.corner(),
			Stroke = C.stroke(),
			Padding = e("UIPadding", {
				PaddingTop = UDim.new(0, 16),
				PaddingBottom = UDim.new(0, 16),
				PaddingLeft = UDim.new(0, 16),
				PaddingRight = UDim.new(0, 16),
			}),
			Layout = C.List({ Gap = 12 }),
			Title = e(C.Label, {
				Text = `ACHIEVEMENTS  ·  {tally}`,
				Bold = true,
				Color = Theme.Accent,
				TextSize = 14,
				Size = UDim2.new(1, 0, 0, 20),
				LayoutOrder = 0,
			}),
			Cards = e("Frame", {
				Size = UDim2.fromScale(1, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				LayoutOrder = 1,
			}, cards),
		}),
	})
end

return Career
