--!strict
-- The menu root (UI-01): a top bar (pilot level, Credits, free RP, Wings, navigation) and the current screen.
-- MenuController owns the state and re-renders this with fresh props; screens only send intents back.
-- props: Data, Screen ("Hangar" | "TechTree" | "Settings" | "Detail" | "Results"), DetailId, Navigate(screen, id?),
--   plus everything the screens need (see MenuController).

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("React")) :: any
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Config.Economy)
local Perks = require(Shared.Perks)
local Season = require(Shared.Season)

local C = require(script.Parent.Components)
local Theme = require(script.Parent.Theme)
local Screens = script.Parent.Screens
local AircraftDetail = require(Screens.AircraftDetail)
local Career = require(Screens.Career)
local Hangar = require(Screens.Hangar)
local Results = require(Screens.Results)
local SeasonScreen = require(Screens.Season)
local ShopScreen = require(Screens.Shop)
local SettingsScreen = require(Screens.Settings)
local Training = require(Screens.Training)
local TechTree = require(Screens.TechTree)

local e = React.createElement

-- Where the free space starts to the right of Roblox's own top-left buttons (menu, chat, voice), which
-- draw over our full-screen menu. It changes with the buttons shown, so it's watched.
local function useTopbarLeft(): number
	local left, setLeft = React.useState(GuiService.TopbarInset.Min.X)
	React.useEffect(function()
		local connection = GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(function()
			setLeft(GuiService.TopbarInset.Min.X)
		end)
		return function()
			connection:Disconnect()
		end
	end, {})
	return left
end

-- While a booster runs: "2x CREDITS 54:10" (and/or RP) under the wallet, counting down.
local function BoosterChip(props: { Data: any })
	local now, setNow = React.useState(os.time())
	React.useEffect(function()
		local running = true
		task.spawn(function()
			while running do
				task.wait(1)
				setNow(os.time())
			end
		end)
		return function()
			running = false
		end
	end, {})
	local parts = {}
	for _, kind in { "Credits", "RP" } do
		local left = Perks.boosterLeft(props.Data, kind, now)
		if left > 0 then
			table.insert(parts, string.format("2x %s %d:%02d", string.upper(kind), left // 60, left % 60))
		end
	end
	if #parts == 0 then
		return nil
	end
	return e(C.Label, {
		Text = table.concat(parts, "   "),
		Size = UDim2.fromOffset(320, 16),
		Position = UDim2.new(1, -20, 1, -2),
		AnchorPoint = Vector2.new(1, 1),
		Bold = true,
		TextSize = 12,
		Align = "Right",
		Color = Theme.Good,
	})
end

-- What each currency is, what it's for and how to get more: the card under its chip on hover
local CURRENCY_INFO = {
	Credits = {
		Title = "CREDITS",
		Body = "The game's main money. Buy jets you've researched, upgrade modules and skins.\n\n"
			.. "Earn them in every match (kills, assists, wins, finishing), from challenges, levelling up, the "
			.. "daily reward and the free spin.",
	},
	FreeRP = {
		Title = "FREE RP",
		Body = "Research points you can put towards any jet in the tech tree.\n\n"
			.. "Every match pays RP into the jet you flew, and a tenth of it lands here too. Pilot levels 12 and "
			.. "30 pay a big chunk.",
	},
	Wings = {
		Title = "WINGS",
		Body = "The premium currency, for looks only: camos, skins, contrails, kill markers, HUD themes and wing "
			.. "art. Never power.\n\nGet them from Wings packs in the Shop (press +), and now and then from the "
			.. "free spin.",
	},
}
local TOOLTIP_Z = 50 -- the menu draws by absolute ZIndex: the card sits over every screen

-- A currency in the top bar: its own border, an "i" to say there's more, the info card on hover, and an
-- optional + (Wings: straight to the packs in the Shop).
local function CurrencyChip(props: {
	Text: string,
	Colour: Color3,
	Info: string,
	Width: number,
	Order: number,
	OnPlus: (() -> ())?,
})
	local hover, setHover = React.useState(false)
	local info = CURRENCY_INFO[props.Info]
	local right = if props.OnPlus then 62 else 30 -- room for the i (and the +)
	return e("Frame", {
		Size = UDim2.fromOffset(props.Width, 34),
		BackgroundColor3 = Theme.Panel,
		BackgroundTransparency = if hover then 0 else 0.35,
		LayoutOrder = props.Order,
		[React.Event.MouseEnter] = function()
			setHover(true)
		end,
		[React.Event.MouseLeave] = function()
			setHover(false)
		end,
	}, {
		Corner = C.corner(8),
		Stroke = e("UIStroke", {
			Color = props.Colour,
			Thickness = if hover then 2 else 1.25,
			Transparency = if hover then 0 else 0.3,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
		Amount = e(C.Label, {
			Text = props.Text,
			Size = UDim2.new(1, -(right + 10), 1, 0),
			Position = UDim2.fromOffset(10, 0),
			Bold = true,
			TextSize = 16,
			Color = props.Colour,
			Align = "Right",
		}),
		Hint = e(C.Label, {
			Text = "ⓘ",
			Size = UDim2.fromOffset(20, 34),
			Position = UDim2.new(1, -(right - 4), 0, 0),
			TextSize = 14,
			Align = "Center",
			Color = props.Colour,
			Transparency = if hover then 0 else 0.4,
		}),
		Plus = if props.OnPlus
			then e(C.Button, {
				Text = "+",
				Size = UDim2.fromOffset(26, 26),
				Position = UDim2.new(1, -30, 0.5, -13),
				TextSize = 20,
				Color = props.Colour,
				TextColor = Theme.Background,
				OnClick = props.OnPlus,
			})
			else nil,
		Info = if hover and info
			then e(C.Panel, {
				Size = UDim2.fromOffset(380, 210), -- fixed: wrapped text doesn't grow an auto-sized card
				Position = UDim2.new(1, 0, 1, 8),
				AnchorPoint = Vector2.new(1, 0),
				Padding = 14,
				Color = Theme.Background,
				Transparency = 0,
				StrokeColor = props.Colour,
				StrokeThickness = 1.5,
				ZIndex = TOOLTIP_Z,
			}, {
				Layout = C.List({ Gap = 6 }),
				Title = e(C.Label, {
					Text = info.Title,
					Bold = true,
					TextSize = 18,
					Color = props.Colour,
					LayoutOrder = 1,
					ZIndex = TOOLTIP_Z,
				}),
				Body = e(C.Label, {
					Text = info.Body,
					Size = UDim2.new(1, 0, 0, 146),
					Wrap = true,
					AlignY = "Top",
					TextSize = 16,
					Color = Theme.Text,
					LayoutOrder = 2,
					ZIndex = TOOLTIP_Z,
				}),
			})
			else nil,
	})
end

local function TopBar(props: any)
	local data = props.Data
	local need = Economy.xpToNext(data.PilotLevel)
	local logoLeft = useTopbarLeft() + 12
	local function tab(name: string, label: string, order: number)
		return e(C.Button, {
			Text = label,
			Style = if props.Screen == name then "Primary" else "Ghost",
			Size = UDim2.fromOffset(108, 40),
			TextSize = 14,
			LayoutOrder = order,
			OnClick = function()
				props.Navigate(name)
			end,
		})
	end
	return e("Frame", {
		Size = UDim2.new(1, 0, 0, Theme.TopBar),
		BackgroundColor3 = Theme.Background,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
	}, {
		Logo = e(C.Label, {
			Text = "AFTERBURNER",
			Size = UDim2.fromOffset(260, Theme.TopBar),
			Position = UDim2.fromOffset(math.max(logoLeft, 20), 0),
			Heavy = true,
			TextSize = 26,
			Color = Theme.Accent,
		}),
		Tabs = e("Frame", {
			Size = UDim2.fromOffset(6 * 108 + 5 * 10, 40),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
		}, {
			Layout = C.List({ Horizontal = true, Gap = 10, Align = "Center" }),
			Hangar = tab("Hangar", "HANGAR", 1),
			Tree = tab("TechTree", "TECH TREE", 2),
			Career = tab("Career", "CAREER", 3),
			-- A dot while season rewards are waiting to be claimed
			Season = tab("Season", if Season.claimable(data) > 0 then "SEASON  ●" else "SEASON", 4),
			Shop = tab("Shop", "SHOP", 5),
			Settings = tab("Settings", "SETTINGS", 6),
		}),
		Boosters = e(BoosterChip, { Data = data }),
		Wallet = e("Frame", {
			Size = UDim2.fromOffset(720, Theme.TopBar),
			Position = UDim2.new(1, -20, 0, 0),
			AnchorPoint = Vector2.new(1, 0),
			BackgroundTransparency = 1,
		}, {
			Layout = C.List({ Horizontal = true, Gap = 12, Align = "Right", AlignY = "Center" }),
			Level = e("Frame", { Size = UDim2.fromOffset(180, 40), BackgroundTransparency = 1, LayoutOrder = 1 }, {
				Label = e(C.Label, {
					Text = `PILOT LEVEL {data.PilotLevel}`,
					Bold = true,
					TextSize = 13,
					Size = UDim2.new(1, 0, 0, 16),
				}),
				Bar = e(C.Bar, {
					Value = data.PilotXP / need,
					Size = UDim2.new(1, 0, 0, 12),
					Position = UDim2.fromOffset(0, 22),
					Color = Theme.Accent,
					Text = `{data.PilotXP} / {need}`,
				}),
			}),
			Credits = e(CurrencyChip, {
				Text = `{C.number(data.Credits)} Cr`,
				Colour = Theme.Text,
				Info = "Credits",
				Width = 150,
				Order = 2,
			}),
			FreeRP = e(CurrencyChip, {
				Text = `{C.number(data.FreeRP)} free RP`,
				Colour = Theme.Good,
				Info = "FreeRP",
				Width = 160,
				Order = 3,
			}),
			-- Wings (the premium currency): the + opens the Shop at the Wings packs
			Wings = e(CurrencyChip, {
				Text = `{C.number(data.Wings or 0)} Wings`,
				Colour = Theme.Wings,
				Info = "Wings",
				Width = 160,
				Order = 4,
				OnPlus = function()
					props.Navigate("Shop", "Wings")
				end,
			}),
		}),
	})
end

-- The live event and message of the day (LiveConfig event / motd, OPS-01), at the top of the hangar.
local function NewsBanner(props: any)
	local event, motd = props.Event or "", props.Motd or ""
	if event ~= "" and props.EventEnds then
		-- A scheduled event says when it ends (a real date, not a countdown)
		event ..= `  ·  until {os.date("!%A %H:%M", props.EventEnds)} UTC`
	end
	if event == "" and motd == "" then
		return nil
	end
	local text = if event ~= "" and motd ~= ""
		then `{string.upper(event)}  ·  {motd}`
		elseif event ~= "" then string.upper(event)
		else motd
	return e(C.Panel, {
		Size = UDim2.fromOffset(math.min(80 + #text * 8, 900), 34),
		Position = UDim2.new(0.5, 0, 0, 14),
		AnchorPoint = Vector2.new(0.5, 0),
		StrokeColor = Theme.Accent,
		StrokeThickness = 1.5,
		Padding = 6,
	}, {
		Text = e(C.Label, {
			Text = text,
			Size = UDim2.fromScale(1, 1),
			Align = "Center",
			Bold = true,
			TextSize = 14,
			Color = if event ~= "" then Theme.Accent else Theme.Text,
		}),
	})
end

local function App(props: any)
	local data = props.Data
	if not data then
		return e(C.Label, {
			Text = "Loading your save…",
			Size = UDim2.fromScale(1, 1),
			Align = "Center",
			TextSize = 20,
			Color = Theme.Dim,
		})
	end
	local screen = props.Screen
	local body
	if screen == "Results" and props.Match then
		body = e(Results, {
			Match = props.Match,
			Rewards = props.Rewards,
			Data = data,
			OnReport = props.OnReport,
			OnShop = function()
				props.Navigate("Shop")
			end,
		})
	elseif screen == "Shop" then
		body = e(ShopScreen, {
			Data = data,
			Focus = props.ShopFocus,
			FocusKey = props.ShopFocusKey,
			OnBuyProduct = props.OnBuyProduct,
			OnBuyPass = props.OnBuyPass,
			OnBuyCosmetic = props.OnBuyCosmetic,
			OnEquipCosmetic = props.OnEquipCosmetic,
			OnChooseStarter = props.OnChooseStarter,
			OnBuyBundle = props.OnBuyBundle,
			OnTechTree = function()
				props.Navigate("TechTree")
			end,
			OnSeason = function()
				props.Navigate("Season")
			end,
		})
	elseif screen == "Season" then
		body = e(SeasonScreen, {
			Data = data,
			OnClaimSeason = props.OnClaimSeason,
			OnBuySeasonPass = props.OnBuySeasonPass,
			OnReroll = props.OnReroll,
		})
	elseif screen == "Career" then
		body = e(Career, { Data = data, OnSetTitle = props.OnSetTitle, OnSetCallsign = props.OnSetCallsign })
	elseif screen == "Settings" then
		body = e(SettingsScreen, {
			Values = props.Settings,
			OnSet = props.OnSetting,
			OnCapture = props.OnCapture,
			Level = data.PilotLevel,
			AllUnlocked = data.Flags and data.Flags.AllUnlocked == true,
			OnFeedback = props.OnFeedback,
		})
	elseif screen == "TechTree" then
		body = e(TechTree, {
			Data = data,
			OnResearch = props.OnResearch,
			OnBuy = props.OnBuy,
			OnChooseTierUnlock = props.OnChooseTierUnlock,
			OnDetails = function(id)
				props.Navigate("Detail", id)
			end,
		})
	elseif screen == "Detail" and props.DetailId then
		body = e(AircraftDetail, {
			Data = data,
			AirframeId = props.DetailId,
			OnBack = function()
				props.Navigate(props.BackTo or "Hangar")
			end,
			OnBuyModule = props.OnBuyModule,
			OnSetModuleFitted = props.OnSetModuleFitted,
			OnBuySkin = props.OnBuySkin,
			OnSetSkin = props.OnSetSkin,
			OnLineup = props.OnLineup,
		})
	elseif props.Role == "Training" then
		body = e(Training, {
			Data = data,
			OnMultiplayer = function()
				props.OnTravel("Lobby")
			end,
			FirstSession = props.FirstSession,
			OnFinishOnboarding = props.OnFinishOnboarding,
			Selected = props.Selected,
			OnSelect = props.OnSelect,
			Status = props.Status,
			CanPlay = props.CanPlay,
			OnPlay = props.OnPlay,
			Lessons = props.Lessons,
			OnLesson = props.OnLesson,
			VsAIRunning = props.VsAIRunning,
			ModeName = props.ModeName,
			OnVsAI = props.OnVsAI,
			OnFreeFlight = props.OnFreeFlight,
			OnDetails = function(id)
				props.Navigate("Detail", id)
			end,
		})
	else
		body = e(Hangar, {
			Data = data,
			Selected = props.Selected,
			OnSelect = props.OnSelect,
			Status = props.Status,
			CanPlay = props.CanPlay,
			OnPlay = props.OnPlay,
			-- Left of PLAY: TRAINING in a lobby, LEAVE MATCH on a match server (MatchmakingService)
			SideText = if props.Role == "Lobby" then "TRAINING" elseif props.Role == "Match" then "LEAVE MATCH" else nil,
			OnSide = function()
				props.OnTravel(if props.Role == "Lobby" then "Training" else "Lobby")
			end,
			-- On a match server: report a cheater (CMP-03)
			OnReport = if props.Role == "Match" then props.OnReport else nil,
			OnFeedback = props.OnFeedback,
			OnDetails = function(id)
				props.Navigate("Detail", id)
			end,
			OnLineup = props.OnLineup,
			PlayText = props.PlayText,
			OnReroll = props.OnReroll,
			OnSpin = props.OnSpin,
			QueueMode = props.QueueMode,
			OnQueueMode = props.OnQueueMode,
			Party = props.Party,
			PartyCandidates = props.PartyCandidates,
			OnPartyInvite = props.OnPartyInvite,
			OnPartyRespond = props.OnPartyRespond,
			OnPartyKick = props.OnPartyKick,
			OnPartyLeave = props.OnPartyLeave,
			OnInviteFriends = props.OnInviteFriends,
		})
	end
	-- Menu scale setting (SET-03): a UIScale grows everything; the frame shrinks by the same factor so the
	-- scaled menu still fills the screen exactly
	local scale = props.MenuScale or 1
	return e("Frame", {
		Size = UDim2.fromScale(1 / scale, 1 / scale),
		BackgroundColor3 = Theme.Background,
		-- The hangar lets the prerendered Strait behind it show through (MenuBackdrop); other screens keep it dim
		BackgroundTransparency = if screen == "Results" then 0.35 elseif screen == "Hangar" then 0.45 else 0.15,
		BorderSizePixel = 0,
	}, {
		Scale = e("UIScale", { Scale = scale }),
		Top = if screen ~= "Results"
			then e(TopBar, {
				Data = data,
				Screen = screen,
				Navigate = props.Navigate,
			})
			else nil,
		Body = e("Frame", {
			Size = UDim2.new(1, 0, 1, if screen == "Results" then 0 else -Theme.TopBar),
			Position = UDim2.fromOffset(0, if screen == "Results" then 0 else Theme.TopBar),
			BackgroundTransparency = 1,
		}, {
			Screen = body,
			News = if screen == "Hangar"
				then e(NewsBanner, { Event = props.Event, EventEnds = props.EventEnds, Motd = props.Motd })
				else nil,
		}),
	})
end

return App
