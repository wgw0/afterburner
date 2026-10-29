--!strict
-- Settings screen (DEVELOPMENT.md §29, SET-02). Every row changes one setting at once through
-- SettingsController (applied straight away and saved to your profile).
-- props: Values (the current settings), OnSet(key, value).
-- Numbers use − / + buttons around a bar rather than a drag slider, so they work the same with a mouse,
-- touch and a gamepad.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("React")) :: any
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Settings = require(Shared.Config.Settings)

local C = require(script.Parent.Parent.Components)
local Theme = require(script.Parent.Parent.Theme)

local e = React.createElement

local ROW_H = 52

-- What each row shows. Choices map a setting's values to labels; numbers have a step and a format.
local SECTIONS = {
	{
		title = "CONTROLS",
		rows = {
			{
				key = "ControlScheme",
				label = "Control scheme",
				hint = "Mouse aim: point and the jet follows. Direct: the mouse is the stick.",
				choices = { { "MouseAim", "MOUSE AIM" }, { "Direct", "DIRECT" } },
			},
			{ key = "MouseSensitivity", label = "Mouse sensitivity", step = 0.1, format = "%.1f×" },
			{ key = "InvertPitch", label = "Invert pitch", hint = "Flips the mouse's up and down." },
		},
	},
	{
		title = "CAMERA",
		rows = {
			{
				key = "DefaultCamera",
				label = "Default view",
				hint = "The view you start each flight in (V switches in flight).",
				choices = { { "Cockpit", "COCKPIT" }, { "Chase", "CHASE" } },
			},
			{ key = "FieldOfView", label = "Field of view", step = 1, format = "%d°" },
		},
	},
	{
		title = "HUD",
		rows = {
			{
				key = "Units",
				label = "Units",
				hint = "Speed, altitude and climb on the HUD.",
				choices = { { "Imperial", "KNOTS · FEET" }, { "Metric", "KM/H · METRES" } },
			},
			{
				key = "HUDColour",
				label = "HUD colour",
				hint = "Cyan and white stay clear of the red and amber warnings.",
				choices = { { "Green", "GREEN" }, { "Cyan", "CYAN" }, { "White", "WHITE" } },
			},
		},
	},
	{
		title = "AUDIO",
		rows = {
			{ key = "MasterVolume", label = "Master volume", step = 0.05, format = "%d%%", percent = true },
			{
				key = "CockpitVolume",
				label = "Cockpit volume",
				hint = "Warnings, seeker and radar tones.",
				step = 0.05,
				format = "%d%%",
				percent = true,
			},
			{ key = "MusicVolume", label = "Music volume", step = 0.05, format = "%d%%", percent = true },
			{
				key = "RadioVolume",
				label = "Radio volume",
				hint = 'Callouts like "Fox two" and "Splash one".',
				step = 0.05,
				format = "%d%%",
				percent = true,
			},
		},
	},
	{
		title = "ACCESSIBILITY",
		rows = {
			{
				key = "ReduceFlashing",
				label = "Reduce flashing",
				hint = "Dimmer explosions; warnings stay lit instead of blinking.",
			},
			{
				key = "Subtitles",
				label = "Subtitles",
				hint = "Voice warnings and radar warning tones as text.",
			},
			{
				key = "MenuScale",
				label = "Menu size",
				hint = "Menus, banner and scoreboard.",
				step = 0.1,
				format = "%d%%",
				percent = true,
			},
		},
	},
}

local function Row(props: any)
	local row = props.Row
	local spec = (Settings.SPECS :: any)[row.key]
	local value = props.Values[row.key]
	local control
	if spec.kind == "boolean" then
		control = e("Frame", { Size = UDim2.fromOffset(320, 44), BackgroundTransparency = 1 }, {
			Layout = C.List({ Horizontal = true, Gap = 8, Align = "Right" }),
			Off = e(C.Button, {
				Text = "OFF",
				Style = if value then "Ghost" else "Primary",
				Size = UDim2.fromOffset(150, 44),
				TextSize = 14,
				LayoutOrder = 1,
				OnClick = function()
					props.OnSet(row.key, false)
				end,
			}),
			On = e(C.Button, {
				Text = "ON",
				Style = if value then "Primary" else "Ghost",
				Size = UDim2.fromOffset(150, 44),
				TextSize = 14,
				LayoutOrder = 2,
				OnClick = function()
					props.OnSet(row.key, true)
				end,
			}),
		})
	elseif spec.kind == "enum" then
		local buttons: { [string]: any } = { Layout = C.List({ Horizontal = true, Gap = 8, Align = "Right" }) }
		-- Two choices are 150 wide; more share the same 320 px
		local width = math.min(150, math.floor((320 - 8 * (#row.choices - 1)) / #row.choices))
		for i, choice in row.choices do
			buttons[choice[1]] = e(C.Button, {
				Text = choice[2],
				Style = if value == choice[1] then "Primary" else "Ghost",
				Size = UDim2.fromOffset(width, 44),
				TextSize = 13,
				LayoutOrder = i,
				OnClick = function()
					props.OnSet(row.key, choice[1])
				end,
			})
		end
		control = e("Frame", { Size = UDim2.fromOffset(320, 44), BackgroundTransparency = 1 }, buttons)
	else
		local function nudge(direction: number)
			local stepped = math.round((value + direction * row.step) / row.step) * row.step
			props.OnSet(row.key, math.clamp(stepped, spec.min, spec.max))
		end
		local shown = if row.percent then math.round(value * 100) else value
		control = e("Frame", { Size = UDim2.fromOffset(320, 44), BackgroundTransparency = 1 }, {
			Layout = C.List({ Horizontal = true, Gap = 8, Align = "Right", AlignY = "Center" }),
			Down = e(C.Button, {
				Text = "−",
				Size = UDim2.fromOffset(44, 44),
				TextSize = 22,
				Disabled = value <= spec.min + 1e-6,
				LayoutOrder = 1,
				OnClick = function()
					nudge(-1)
				end,
			}),
			Bar = e(C.Bar, {
				Value = (value - spec.min) / (spec.max - spec.min),
				Size = UDim2.fromOffset(150, 14),
				Color = Theme.Accent,
				LayoutOrder = 2,
			}),
			Up = e(C.Button, {
				Text = "+",
				Size = UDim2.fromOffset(44, 44),
				TextSize = 22,
				Disabled = value >= spec.max - 1e-6,
				LayoutOrder = 3,
				OnClick = function()
					nudge(1)
				end,
			}),
			Value = e(C.Label, {
				Text = string.format(row.format, shown),
				Size = UDim2.fromOffset(52, 44),
				Bold = true,
				TextSize = 15,
				Align = "Right",
				LayoutOrder = 4,
			}),
		})
	end
	return e("Frame", {
		Size = UDim2.new(1, 0, 0, ROW_H),
		BackgroundTransparency = 1,
		LayoutOrder = props.Order,
	}, {
		Label = e(C.Label, {
			Text = row.label,
			Size = UDim2.new(1, -340, 0, 22),
			Position = UDim2.fromOffset(0, if row.hint then 4 else 15),
			Bold = true,
			TextSize = 16,
		}),
		Hint = if row.hint
			then e(C.Label, {
				Text = row.hint,
				Size = UDim2.new(1, -340, 0, 18),
				Position = UDim2.fromOffset(0, 28),
				TextSize = 12,
				Color = Theme.Dim,
			})
			else nil,
		Control = e("Frame", {
			Size = UDim2.fromOffset(320, 44),
			Position = UDim2.fromScale(1, 0.5),
			AnchorPoint = Vector2.new(1, 0.5),
			BackgroundTransparency = 1,
		}, { Control = control }),
	})
end

local function SettingsScreen(props: any)
	local sections: { [string]: any } = {
		Layout = C.List({ Gap = 14, Align = "Center" }),
		Padding = e("UIPadding", { PaddingTop = UDim.new(0, 20), PaddingBottom = UDim.new(0, 24) }),
	}
	for i, section in SECTIONS do
		local rows: { [string]: any } = {
			Layout = C.List({ Gap = 4 }),
			Title = e(C.Label, {
				Text = section.title,
				Bold = true,
				Color = Theme.Accent,
				TextSize = 14,
				LayoutOrder = 0,
			}),
		}
		for j, row in section.rows do
			rows[row.key] = e(Row, { Row = row, Values = props.Values, OnSet = props.OnSet, Order = j })
		end
		local height = 24 + #section.rows * (ROW_H + 4) + 28
		sections[section.title] = e(C.Panel, {
			Size = UDim2.fromOffset(760, height),
			Padding = 14,
			LayoutOrder = i,
		}, rows)
	end
	sections.Note = e(C.Label, {
		Text = "Changes apply straight away and are saved with your pilot.",
		Size = UDim2.fromOffset(760, 20),
		TextSize = 13,
		Color = Theme.Dim,
		Align = "Center",
		LayoutOrder = #SECTIONS + 1,
	})
	return e("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
	}, sections)
end

return SettingsScreen
