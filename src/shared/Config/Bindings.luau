--!strict
-- Key and button bindings (DEVELOPMENT.md §7.1, INP-05). Every rebindable action, with its keyboard (or mouse
-- button) and gamepad defaults. Players' changes are saved in the Bindings setting as overrides only:
--   { [actionId] = { keyboard = "Space"?, gamepad = "ButtonX"? } }  ("None" unbinds)
-- so a default changed here still reaches everyone who hasn't changed that action. Names are Enum.KeyCode
-- names, or MouseButton1/2/3 for the keyboard column. Sticks, triggers, mouse movement and the arrow-key
-- alternates aren't rebindable (they're axes, not buttons). Pure: the server validates saved bindings with it.

export type Action = {
	id: string,
	label: string,
	group: string,
	keyboard: string?, -- default
	gamepad: string?, -- default (nil: the gamepad uses an axis for it, or has nothing)
	padAxis: string?, -- the gamepad does it with a stick or trigger instead (not rebindable): shown as this
}

local ACTIONS: { Action } = {
	-- Flight
	{ id = "ThrottleUp", label = "Throttle up", group = "FLIGHT", keyboard = "W", padAxis = "RT" },
	{ id = "ThrottleDown", label = "Throttle down", group = "FLIGHT", keyboard = "S", padAxis = "LT" },
	{ id = "RollLeft", label = "Roll left", group = "FLIGHT", keyboard = "Q", padAxis = "Left stick" },
	{ id = "RollRight", label = "Roll right", group = "FLIGHT", keyboard = "E", padAxis = "Left stick" },
	{ id = "YawLeft", label = "Rudder left", group = "FLIGHT", keyboard = "A", gamepad = "ButtonL1" },
	{ id = "YawRight", label = "Rudder right", group = "FLIGHT", keyboard = "D", gamepad = "ButtonR1" },
	{
		id = "Override",
		label = "Limiter override (hold)",
		group = "FLIGHT",
		keyboard = "LeftShift",
		gamepad = "ButtonL3",
	},
	{ id = "SwitchScheme", label = "Mouse aim / direct", group = "FLIGHT", keyboard = "M" },
	-- Weapons
	{ id = "FireGun", label = "Fire guns", group = "WEAPONS", keyboard = "MouseButton1", gamepad = "ButtonA" },
	{ id = "FireMissile", label = "Fire missile", group = "WEAPONS", keyboard = "Space", gamepad = "ButtonX" },
	{ id = "NextWeapon", label = "Next missile", group = "WEAPONS", keyboard = "R", gamepad = "DPadUp" },
	{ id = "RadarLock", label = "Radar lock / unlock", group = "WEAPONS", keyboard = "T", gamepad = "ButtonY" },
	{ id = "Flares", label = "Flares", group = "WEAPONS", keyboard = "F", gamepad = "ButtonB" },
	{ id = "Chaff", label = "Chaff", group = "WEAPONS", keyboard = "C", gamepad = "DPadDown" },
	-- View
	{ id = "Camera", label = "Cockpit / chase view", group = "VIEW", keyboard = "V", gamepad = "ButtonSelect" },
	{ id = "Padlock", label = "Padlock target (hold)", group = "VIEW", keyboard = "X", gamepad = "ButtonR3" },
	{ id = "Zoom", label = "Zoom (hold)", group = "VIEW", keyboard = "Z" },
	-- Other
	{ id = "Scoreboard", label = "Scoreboard (hold)", group = "OTHER", keyboard = "Tab", gamepad = "ButtonStart" },
	{ id = "Hangar", label = "Back to hangar (hold)", group = "OTHER", keyboard = "H", gamepad = "DPadLeft" },
	{ id = "FlyAgain", label = "Fly again (in the menu)", group = "OTHER", keyboard = "R", gamepad = "ButtonX" },
}

local BY_ID: { [string]: Action } = {}
for _, action in ACTIONS do
	BY_ID[action.id] = action
end

-- Gamepad buttons a binding may use (the sticks and triggers drive axes).
local GAMEPAD_BUTTONS = {
	"ButtonA",
	"ButtonB",
	"ButtonX",
	"ButtonY",
	"ButtonL1",
	"ButtonR1",
	"ButtonL3",
	"ButtonR3",
	"ButtonSelect",
	"ButtonStart",
	"DPadUp",
	"DPadDown",
	"DPadLeft",
	"DPadRight",
}
local MOUSE_BUTTONS = { "MouseButton1", "MouseButton2", "MouseButton3" }
-- Keys kept for the game itself: Escape opens Roblox's menu, the arrows are the fixed flight / snap-view
-- alternates, 1–3 fly a lineup slot from the menu, P is the test tuning panel.
local RESERVED = { "Escape", "Up", "Down", "Left", "Right", "LeftAlt", "One", "Two", "Three", "P", "Unknown" }

local Bindings = {}

Bindings.ACTIONS = ACTIONS
Bindings.GROUPS = { "FLIGHT", "WEAPONS", "VIEW", "OTHER" }

function Bindings.get(id: string): Action?
	return BY_ID[id]
end

local function isGamepadButton(name: string): boolean
	return table.find(GAMEPAD_BUTTONS, name) ~= nil
end

-- Whether `name` may go in a keyboard binding: a keyboard key (not a gamepad one, not reserved) or a mouse
-- button. "None" unbinds.
function Bindings.validKeyboard(name: any): boolean
	if type(name) ~= "string" then
		return false
	end
	if name == "None" or table.find(MOUSE_BUTTONS, name) then
		return true
	end
	if table.find(RESERVED, name) or isGamepadButton(name) or name:match("^Button") or name:match("^Thumbstick") then
		return false
	end
	local ok, code = pcall(function()
		return (Enum.KeyCode :: any)[name]
	end)
	return ok and code ~= nil
end

function Bindings.validGamepad(name: any): boolean
	return type(name) == "string" and (name == "None" or isGamepadButton(name))
end

-- Whether a saved Bindings value is allowed: known actions only, each with valid names.
function Bindings.valid(value: any): boolean
	if type(value) ~= "table" then
		return false
	end
	local count = 0
	for id, binding in value do
		count += 1
		if type(id) ~= "string" or not BY_ID[id] or type(binding) ~= "table" then
			return false
		end
		for field, name in binding do
			if field == "keyboard" then
				if not Bindings.validKeyboard(name) then
					return false
				end
			elseif field == "gamepad" then
				if not Bindings.validGamepad(name) then
					return false
				end
			else
				return false
			end
		end
	end
	return count <= #ACTIONS
end

-- The name bound to an action for a device ("keyboard" or "gamepad"), overrides first; nil if unbound.
function Bindings.resolve(overrides: any, id: string, device: string): string?
	local action = BY_ID[id]
	if not action then
		return nil
	end
	local override = type(overrides) == "table" and overrides[id]
	local name = if type(override) == "table" and override[device] ~= nil
		then override[device]
		else (action :: any)[device]
	return if name == "None" then nil else name
end

-- New overrides with `id` bound to `name` on `device`. Another action already using that key or button
-- gets this action's old one (a swap), so nothing is ever bound twice. Returns (overrides, swappedId?).
-- "FlyAgain" works in the menu, not in flight, so it may share a key with a flight action.
function Bindings.assign(overrides: any, id: string, device: string, name: string): ({ [string]: any }, string?)
	local result: { [string]: any } = {}
	for key, binding in (if type(overrides) == "table" then overrides else {}) do
		result[key] = table.clone(binding)
	end
	local old = Bindings.resolve(result, id, device)
	local swapped = nil
	for _, other in ACTIONS do
		local menuOnly = other.id == "FlyAgain" or id == "FlyAgain"
		if other.id ~= id and not menuOnly and Bindings.resolve(result, other.id, device) == name then
			result[other.id] = result[other.id] or {}
			result[other.id][device] = old or "None"
			swapped = other.id
		end
	end
	result[id] = result[id] or {}
	result[id][device] = name
	-- Drop overrides that now match the default
	for key, binding in result do
		local action = BY_ID[key]
		for field, value in binding do
			if value == (action :: any)[field] or (value == "None" and (action :: any)[field] == nil) then
				binding[field] = nil
			end
		end
		if next(binding) == nil then
			result[key] = nil
		end
	end
	return result, swapped
end

-- How a key or button shows on screen.
local LABELS = {
	MouseButton1 = "LMB",
	MouseButton2 = "RMB",
	MouseButton3 = "MMB",
	LeftShift = "L-Shift",
	RightShift = "R-Shift",
	LeftControl = "L-Ctrl",
	RightControl = "R-Ctrl",
	Space = "Space",
	Return = "Enter",
	ButtonA = "A",
	ButtonB = "B",
	ButtonX = "X",
	ButtonY = "Y",
	ButtonL1 = "LB",
	ButtonR1 = "RB",
	ButtonL3 = "L3",
	ButtonR3 = "R3",
	ButtonSelect = "View",
	ButtonStart = "Menu",
	DPadUp = "D-pad up",
	DPadDown = "D-pad down",
	DPadLeft = "D-pad left",
	DPadRight = "D-pad right",
}

function Bindings.label(name: string?): string
	if name == nil then
		return "—"
	end
	return LABELS[name] or name
end

return Bindings
