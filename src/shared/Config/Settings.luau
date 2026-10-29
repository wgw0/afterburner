--!strict
-- Player settings (DEVELOPMENT.md §29, SET-01): the known settings, their defaults and allowed values.
-- Saved in the profile; the client changes them through SettingsUpdate and the server keeps only
-- known keys with valid values (sanitize), so a modified client can't store anything else.

local AircraftData = require(script.Parent.Parent.AircraftData)

export type Spec =
	{ kind: "enum", values: { string }, default: string }
	| { kind: "number", min: number, max: number, default: number }
	| { kind: "boolean", default: boolean }

local SPECS: { [string]: Spec } = {
	ControlScheme = { kind = "enum", values = { "MouseAim", "Direct" }, default = "MouseAim" },
	MouseSensitivity = { kind = "number", min = 0.2, max = 3, default = 1 },
	InvertPitch = { kind = "boolean", default = false },
	DefaultCamera = { kind = "enum", values = { "Cockpit", "Chase" }, default = "Cockpit" },
	FieldOfView = { kind = "number", min = 55, max = 90, default = 70 },
	Units = { kind = "enum", values = { "Imperial", "Metric" }, default = "Imperial" },
	MasterVolume = { kind = "number", min = 0, max = 1, default = 1 },
	CockpitVolume = { kind = "number", min = 0, max = 1, default = 1 },
	MusicVolume = { kind = "number", min = 0, max = 1, default = 0.6 }, -- AUD-05
	RadioVolume = { kind = "number", min = 0, max = 1, default = 1 }, -- radio calls (AUD-04)
	ReduceShake = { kind = "boolean", default = false },
	ReduceFlashing = { kind = "boolean", default = false },
	-- SET-03 accessibility
	Subtitles = { kind = "boolean", default = false }, -- voice lines and warning tones as text
	HUDColour = { kind = "enum", values = { "Green", "Cyan", "White" }, default = "Green" },
	MenuScale = { kind = "number", min = 0.8, max = 1.4, default = 1 }, -- menus, banner, scoreboard
	-- The jet picked in the hangar, so a match server launches you in it (it follows you between servers)
	SelectedJet = (function(): Spec
		local ids = {}
		for id in AircraftData.getAll() do
			table.insert(ids, id)
		end
		table.sort(ids)
		return { kind = "enum", values = ids, default = "F5E" }
	end)(),
	-- The mode PLAY queues for (MMK-03, UI-05)
	QueueMode = {
		kind = "enum",
		values = { "Any", "Dogfight", "TeamDeathmatch", "AirSuperiority" },
		default = "Any",
	},
}

local Settings = {}

Settings.SPECS = table.freeze(SPECS)

function Settings.defaults(): { [string]: any }
	local values = {}
	for key, spec in SPECS do
		values[key] = spec.default
	end
	return values
end

-- Whether one value is allowed for a setting.
function Settings.valid(key: string, value: any): boolean
	local spec = SPECS[key]
	if not spec then
		return false
	end
	if spec.kind == "enum" then
		return type(value) == "string" and table.find(spec.values, value) ~= nil
	elseif spec.kind == "number" then
		return type(value) == "number" and value == value and value >= spec.min and value <= spec.max
	else
		return type(value) == "boolean"
	end
end

-- A clean settings table: known keys only, invalid or missing values replaced by defaults.
function Settings.sanitize(input: any): { [string]: any }
	local clean = Settings.defaults()
	if type(input) == "table" then
		for key in SPECS do
			if Settings.valid(key, input[key]) then
				clean[key] = input[key]
			end
		end
	end
	return clean
end

return Settings
