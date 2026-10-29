--!strict
-- The menu root (UI-01): a top bar (pilot level, Credits, free RP, navigation) and the current screen.
-- MenuController owns the state and re-renders this with fresh props; screens only send intents back.
-- props: Data, Screen ("Hangar" | "TechTree" | "Settings" | "Detail" | "Results"), DetailId, Navigate(screen, id?),
--   plus everything the screens need (see MenuController).

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("React")) :: any
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared.Config.Economy)

local C = require(script.Parent.Components)
local Theme = require(script.Parent.Theme)
local Screens = script.Parent.Screens
local AircraftDetail = require(Screens.AircraftDetail)
local Career = require(Screens.Career)
local Hangar = require(Screens.Hangar)
local Results = require(Screens.Results)
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

local function TopBar(props: any)
	local data = props.Data
	local need = Economy.xpToNext(data.PilotLevel)
	local logoLeft = useTopbarLeft() + 12
	local function tab(name: string, label: string, order: number)
		return e(C.Button, {
			Text = label,
			Style = if props.Screen == name then "Primary" else "Ghost",
			Size = UDim2.fromOffset(140, 40),
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
			Size = UDim2.fromOffset(620, 40),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
		}, {
			Layout = C.List({ Horizontal = true, Gap = 12, Align = "Center" }),
			Hangar = tab("Hangar", "HANGAR", 1),
			Tree = tab("TechTree", "TECH TREE", 2),
			Career = tab("Career", "CAREER", 3),
			Settings = tab("Settings", "SETTINGS", 4),
		}),
		Wallet = e("Frame", {
			Size = UDim2.fromOffset(520, Theme.TopBar),
			Position = UDim2.new(1, -20, 0, 0),
			AnchorPoint = Vector2.new(1, 0),
			BackgroundTransparency = 1,
		}, {
			Layout = C.List({ Horizontal = true, Gap = 22, Align = "Right", AlignY = "Center" }),
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
			Credits = e(C.Label, {
				Text = `{C.number(data.Credits)} Cr`,
				Size = UDim2.fromOffset(130, 40),
				Bold = true,
				TextSize = 18,
				Align = "Right",
				LayoutOrder = 2,
			}),
			FreeRP = e(C.Label, {
				Text = `{C.number(data.FreeRP)} free RP`,
				Size = UDim2.fromOffset(130, 40),
				TextSize = 14,
				Color = Theme.Good,
				Align = "Right",
				LayoutOrder = 3,
			}),
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
		body = e(Results, { Match = props.Match, Rewards = props.Rewards, Data = data })
	elseif screen == "Career" then
		body = e(Career, { Data = data, OnSetTitle = props.OnSetTitle })
	elseif screen == "Settings" then
		body = e(SettingsScreen, {
			Values = props.Settings,
			OnSet = props.OnSetting,
			OnCapture = props.OnCapture,
			Level = data.PilotLevel,
			AllUnlocked = data.Flags and data.Flags.AllUnlocked == true,
		})
	elseif screen == "TechTree" then
		body = e(TechTree, {
			Data = data,
			OnResearch = props.OnResearch,
			OnBuy = props.OnBuy,
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
			OnDetails = function(id)
				props.Navigate("Detail", id)
			end,
			OnLineup = props.OnLineup,
			PlayText = props.PlayText,
			OnReroll = props.OnReroll,
			QueueMode = props.QueueMode,
			OnQueueMode = props.OnQueueMode,
		})
	end
	-- Menu scale setting (SET-03): a UIScale grows everything; the frame shrinks by the same factor so the
	-- scaled menu still fills the screen exactly
	local scale = props.MenuScale or 1
	return e("Frame", {
		Size = UDim2.fromScale(1 / scale, 1 / scale),
		BackgroundColor3 = Theme.Background,
		BackgroundTransparency = if screen == "Results" then 0.35 else 0.15,
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
		}, { Screen = body }),
	})
end

return App
