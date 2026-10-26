--!strict
-- The menu root (UI-01): a top bar (pilot level, Credits, free RP, navigation) and the current screen.
-- MenuController owns the state and re-renders this with fresh props; screens only send intents back.
-- props: Data, Screen ("Hangar" | "TechTree" | "Detail" | "Results"), DetailId, Navigate(screen, id?),
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
local Hangar = require(Screens.Hangar)
local Results = require(Screens.Results)
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
			Size = UDim2.fromOffset(300, 40),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
		}, {
			Layout = C.List({ Horizontal = true, Gap = 12, Align = "Center" }),
			Hangar = tab("Hangar", "HANGAR", 1),
			Tree = tab("TechTree", "TECH TREE", 2),
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
	else
		body = e(Hangar, {
			Data = data,
			Selected = props.Selected,
			OnSelect = props.OnSelect,
			Status = props.Status,
			CanPlay = props.CanPlay,
			OnPlay = props.OnPlay,
			OnDetails = function(id)
				props.Navigate("Detail", id)
			end,
			OnLineup = props.OnLineup,
			OnLesson = props.OnLesson,
			Lessons = props.Lessons,
			TrainingNote = props.TrainingNote,
		})
	end
	return e("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Background,
		BackgroundTransparency = if screen == "Results" then 0.35 else 0.15,
		BorderSizePixel = 0,
	}, {
		Top = if screen ~= "Results"
			then e(TopBar, { Data = data, Screen = screen, Navigate = props.Navigate })
			else nil,
		Body = e("Frame", {
			Size = UDim2.new(1, 0, 1, if screen == "Results" then 0 else -Theme.TopBar),
			Position = UDim2.fromOffset(0, if screen == "Results" then 0 else Theme.TopBar),
			BackgroundTransparency = 1,
		}, { Screen = body }),
	})
end

return App
