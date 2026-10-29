--!strict
-- Settings screen (DEVELOPMENT.md §29, SET-02). Every row changes one setting at once through
-- SettingsController (applied straight away and saved to your profile).
-- props: Values (the current settings), OnSet(key, value), OnCapture(device, callback) (waits for the next key or
-- button: BindingsController:Capture).
-- Numbers use − / + buttons around a bar rather than a drag slider, so they work the same with a mouse,
-- touch and a gamepad.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("React")) :: any
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Bindings = require(Shared.Config.Bindings)
local Environment = require(Shared.Config.Environment)
local LevelRewards = require(Shared.Config.LevelRewards)
local Settings = require(Shared.Config.Settings)
local Version = require(Shared.Version)

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
				hint = "All but green stay clear of the red and amber warnings. More unlock with level.",
				choices = {
					{ "Green", "GREEN" },
					{ "Cyan", "CYAN" },
					{ "White", "WHITE" },
					{ "Pink", "PINK" },
					{ "Blue", "BLUE" },
					{ "Violet", "VIOLET" },
				},
			},
		},
	},
	{
		title = "GRAPHICS",
		rows = {
			{
				key = "EffectsQuality",
				label = "Effects quality",
				hint = "Smoke, sparks, lights and flares. Auto suits your device; lower helps phones.",
				choices = { { "Auto", "AUTO" }, { "Low", "LOW" }, { "Medium", "MEDIUM" }, { "High", "HIGH" } },
			},
			{ key = "Contrails", label = "Contrails", hint = "White trails from the wingtips at high altitude." },
			{ key = "Vapour", label = "Wingtip vapour", hint = "Short trails from the wingtips in hard turns." },
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
			-- Choices that unlock with pilot level (HUD colours, Config/LevelRewards) show the level until then
			local needed = row.key == "HUDColour" and LevelRewards.HUD_COLOURS[choice[1]]
			local locked = needed and not props.AllUnlocked and (props.Level or 1) < needed
			buttons[choice[1]] = e(C.Button, {
				Text = if locked then `LV {needed}` else choice[2],
				Style = if value == choice[1] then "Primary" else "Ghost",
				Size = UDim2.fromOffset(width, 44),
				TextSize = if #row.choices > 4 then 11 else 13,
				Disabled = locked,
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

-- Key bindings (INP-05): each action's key and gamepad button. Click one, then press the new key or button
-- (Esc cancels); one already used by another action swaps with it.
local BIND_ROW_H = 40

local function KeyBindings(props: any)
	local capturing, setCapturing = React.useState(nil :: string?) -- "<action>:<device>"
	local note, setNote = React.useState(nil :: string?)
	local overrides = props.Values.Bindings or {}

	local function startCapture(id: string, device: string)
		local started = props.OnCapture(device, function(name: string?)
			setCapturing(nil)
			if not name then
				setNote(nil)
				return
			end
			local result, swapped = Bindings.assign(overrides, id, device, name)
			local other = swapped and Bindings.get(swapped)
			setNote(
				if other then `Swapped: {other.label} is now on the key {(Bindings.get(id) :: any).label} had.` else nil
			)
			props.OnSet("Bindings", result)
		end)
		if started then
			setCapturing(`{id}:{device}`)
			setNote(
				if device == "keyboard"
					then "Press a key or mouse button (Esc cancels)."
					else "Press a gamepad button (Esc cancels)."
			)
		end
	end

	local function cell(action: any, device: string, order: number)
		local fixed = device == "gamepad" and action.padAxis
		local waiting = capturing == `{action.id}:{device}`
		local name = Bindings.resolve(overrides, action.id, device)
		return e(C.Button, {
			Text = if waiting then "…" elseif fixed then fixed else Bindings.label(name),
			Style = if waiting then "Primary" else "Ghost",
			Disabled = fixed ~= nil and fixed ~= false,
			Size = UDim2.fromOffset(150, 34),
			TextSize = 13,
			LayoutOrder = order,
			OnClick = function()
				startCapture(action.id, device)
			end,
		})
	end

	local rows: { [string]: any } = {
		Layout = C.List({ Gap = 2 }),
		Title = e(
			C.Label,
			{ Text = "KEY BINDINGS", Bold = true, Color = Theme.Accent, TextSize = 14, LayoutOrder = 0 }
		),
		Head = e("Frame", { Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1, LayoutOrder = 1 }, {
			Keyboard = e(C.Label, {
				Text = "KEYBOARD / MOUSE",
				Size = UDim2.fromOffset(150, 22),
				Position = UDim2.new(1, -310, 0, 0),
				TextSize = 11,
				Color = Theme.Dim,
				Align = "Center",
			}),
			Gamepad = e(C.Label, {
				Text = "GAMEPAD",
				Size = UDim2.fromOffset(150, 22),
				Position = UDim2.new(1, -150, 0, 0),
				TextSize = 11,
				Color = Theme.Dim,
				Align = "Center",
			}),
		}),
	}
	local order = 2
	local count = 0
	for _, group in Bindings.GROUPS do
		rows[`Group{group}`] = e(C.Label, {
			Text = group,
			Size = UDim2.new(1, 0, 0, 20),
			TextSize = 11,
			Bold = true,
			Color = Theme.Dim,
			LayoutOrder = order,
		})
		order += 1
		for _, action in Bindings.ACTIONS do
			if action.group == group then
				count += 1
				rows[action.id] = e("Frame", {
					Size = UDim2.new(1, 0, 0, BIND_ROW_H),
					BackgroundTransparency = 1,
					LayoutOrder = order,
				}, {
					Label = e(C.Label, {
						Text = action.label,
						Size = UDim2.new(1, -330, 1, 0),
						Bold = true,
						TextSize = 15,
					}),
					Cells = e("Frame", {
						Size = UDim2.fromOffset(310, 34),
						Position = UDim2.fromScale(1, 0.5),
						AnchorPoint = Vector2.new(1, 0.5),
						BackgroundTransparency = 1,
					}, {
						Layout = C.List({ Horizontal = true, Gap = 10, Align = "Right" }),
						Keyboard = cell(action, "keyboard", 1),
						Gamepad = cell(action, "gamepad", 2),
					}),
				})
				order += 1
			end
		end
	end
	rows.Footer = e("Frame", { Size = UDim2.new(1, 0, 0, 44), BackgroundTransparency = 1, LayoutOrder = order }, {
		Note = e(C.Label, {
			Text = note or "Sticks, triggers, the mouse and the arrow keys stay as they are.",
			Size = UDim2.new(1, -200, 1, 0),
			TextSize = 12,
			Color = if note then Theme.Warn else Theme.Dim,
			Wrap = true,
		}),
		Reset = e(C.Button, {
			Text = "RESET TO DEFAULTS",
			Style = "Ghost",
			Size = UDim2.fromOffset(180, 34),
			Position = UDim2.fromScale(1, 0.5),
			AnchorPoint = Vector2.new(1, 0.5),
			TextSize = 12,
			Disabled = next(overrides) == nil,
			OnClick = function()
				setNote(nil)
				props.OnSet("Bindings", {})
			end,
		}),
	})
	local height = 24 + 24 + #Bindings.GROUPS * 22 + count * (BIND_ROW_H + 2) + 50 + 28
	return e(C.Panel, {
		Size = UDim2.fromOffset(760, height),
		Padding = 14,
		LayoutOrder = props.Order,
	}, rows)
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
			rows[row.key] = e(Row, {
				Row = row,
				Values = props.Values,
				OnSet = props.OnSet,
				Order = j,
				Level = props.Level,
				AllUnlocked = props.AllUnlocked,
			})
		end
		local height = 24 + #section.rows * (ROW_H + 4) + 28
		sections[section.title] = e(C.Panel, {
			Size = UDim2.fromOffset(760, height),
			Padding = 14,
			LayoutOrder = i * 10,
		}, rows)
	end
	sections.KeyBindings = e(KeyBindings, {
		Values = props.Values,
		OnSet = props.OnSet,
		OnCapture = props.OnCapture,
		Order = 15, -- right after CONTROLS
	})
	sections.Note = e(C.Label, {
		Text = "Changes apply straight away and are saved with your pilot.",
		Size = UDim2.fromOffset(760, 20),
		TextSize = 13,
		Color = Theme.Dim,
		Align = "Center",
		LayoutOrder = #SECTIONS * 10 + 10,
	})
	-- The game's version (REL-03) and the server's place version, for bug reports and rollbacks (REL-04)
	sections.Version = e(C.Label, {
		Text = `Afterburner {Version.label(Environment.get())}`
			.. (if game.PlaceVersion > 0 then `  ·  build {game.PlaceVersion}` else ""),
		Size = UDim2.fromOffset(760, 18),
		TextSize = 12,
		Color = Theme.Dim,
		Align = "Center",
		LayoutOrder = #SECTIONS * 10 + 11,
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
