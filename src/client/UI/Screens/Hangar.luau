--!strict
-- Hangar, the home screen (UI-02): the selected jet on a turntable, your lineup, your other jets, the
-- Play button with the match status, and training.
-- props: Data, Selected, OnSelect(id), Status (string), CanPlay, OnPlay(id), OnDetails(id),
--   OnLineup(ids) -> (ok, err), OnLesson(lessonId), Lessons ({ {id, name} }), TrainingNote.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("React")) :: any
local Shared = ReplicatedStorage:WaitForChild("Shared")
local AircraftData = require(Shared.AircraftData)
local Economy = require(Shared.Config.Economy)
local Progression = require(Shared.Progression)

local UI = script.Parent.Parent
local C = require(UI.Components)
local JetPreview = require(UI.JetPreview)
local Theme = require(UI.Theme)

local e = React.createElement
local TIER_NAMES = { "I", "II", "III", "IV", "V", "VI", "VII", "VIII" }

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
			Text = `Tier {TIER_NAMES[airframe.Tier]}  ·  BR {airframe.BattleRating}  ·  {props.RP} RP`,
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
	local selected = props.Selected
	local airframe = selected and AircraftData.get(selected) :: any
	local slots = Progression.lineupSlots(data.PilotLevel)

	-- Lineup column
	local lineupChildren: { [string]: any } = { Layout = C.List({ Gap = 8 }) }
	lineupChildren.Title =
		e(C.Label, { Text = "LINEUP", Bold = true, Color = Theme.Accent, TextSize = 14, LayoutOrder = 0 })
	for i = 1, 3 do
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
		return (aa and aa.BattleRating or 0) < (bb and bb.BattleRating or 0)
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
				Text = `{info and info.DisplayName or id}  ·  BR {info and info.BattleRating or "?"}`,
				Size = UDim2.new(1, -96, 1, 0),
				TextSize = 14,
				Color = if index then Theme.Text else Theme.Dim,
			}),
			Toggle = e(C.Button, {
				Text = if index then "Remove" elseif full then "Swap" else "Add",
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

	-- Training column
	local trainingChildren: { [string]: any } = { Layout = C.List({ Gap = 8 }) }
	trainingChildren.Title =
		e(C.Label, { Text = "TRAINING", Bold = true, Color = Theme.Accent, TextSize = 14, LayoutOrder = 0 })
	for i, lesson in props.Lessons do
		trainingChildren[lesson.id] = e(C.Button, {
			Text = `{i}. {lesson.name}`,
			LayoutOrder = i,
			TextSize = 14,
			OnClick = function()
				props.OnLesson(lesson.id)
			end,
		})
	end
	trainingChildren.Note = e(C.Label, {
		Text = props.TrainingNote or "",
		Color = Theme.Dim,
		TextSize = 12,
		Wrap = true,
		AutoHeight = true,
		LayoutOrder = 99,
	})

	return e("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, {
		Preview = if airframe
			then e(JetPreview, {
				AirframeId = selected,
				Size = UDim2.fromScale(0.5, 0.62),
				Position = UDim2.fromScale(0.5, 0.36),
				AnchorPoint = Vector2.new(0.5, 0.5),
			})
			else nil,
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
				then `Tier {TIER_NAMES[airframe.Tier]}  ·  BR {airframe.BattleRating}  ·  {airframe.Branch}`
				else "",
			Position = UDim2.new(0.5, 0, 0.68, 42),
			AnchorPoint = Vector2.new(0.5, 0),
			Size = UDim2.fromOffset(600, 22),
			Align = "Center",
			Color = Theme.Dim,
			TextSize = 16,
		}),
		Play = e(C.Button, {
			Text = "PLAY",
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
		Details = e(C.Button, {
			Text = "DETAILS",
			Style = "Ghost",
			TextSize = 14,
			Size = UDim2.fromOffset(110, 44),
			Position = UDim2.new(0.5, 150, 1, -102),
			Disabled = selected == nil,
			OnClick = function()
				props.OnDetails(selected)
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
		Lineup = e(C.Panel, {
			Size = UDim2.new(0, 300, 1, -40),
			Position = UDim2.fromOffset(20, 20),
			Padding = 14,
		}, {
			Layout = C.List({ Gap = 14 }),
			Lineup = e("Frame", {
				Size = UDim2.new(1, 0, 0, 240),
				BackgroundTransparency = 1,
				LayoutOrder = 1,
			}, lineupChildren),
			Owned = e("ScrollingFrame", {
				Size = UDim2.new(1, 0, 1, -260),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ScrollBarThickness = 4,
				CanvasSize = UDim2.new(),
				AutomaticCanvasSize = Enum.AutomaticSize.Y,
				LayoutOrder = 2,
			}, ownedChildren),
		}),
		Training = e(C.Panel, {
			Size = UDim2.fromOffset(240, 250),
			Position = UDim2.new(1, -20, 0, 20),
			AnchorPoint = Vector2.new(1, 0),
			Padding = 14,
		}, trainingChildren),
	})
end

return Hangar
