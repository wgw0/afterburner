--!strict
-- Live config (DEVELOPMENT.md §31.1, OPS-01): values admins can change on live servers without publishing an
-- update. ConfigService (server) loads the overrides from a DataStore and puts each on ReplicatedStorage as
-- an attribute (LC_<key>), so the server and every client read them here with get(). Without an override
-- (and in tests) a key has its default.
--   br.<AirframeId>   a jet's battle rating (1–15; default its AircraftData value)
--   economy.xp / economy.credits / economy.rp   match reward multipliers (0.5–3), e.g. a double XP weekend
--   event             an event name shown in the menu ("" = none), e.g. "Double XP weekend"
--   motd              a message of the day shown in the menu ("" = none)
-- validate() is the only gate for what can be set (the admin commands use it).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AircraftData = require(script.Parent.AircraftData)

export type Spec =
	{ kind: "number", min: number, max: number, default: number }
	| { kind: "string", max: number, default: string }

local LiveConfig = {}

LiveConfig.SPECS = table.freeze({
	["economy.xp"] = { kind = "number", min = 0.5, max = 3, default = 1 },
	["economy.credits"] = { kind = "number", min = 0.5, max = 3, default = 1 },
	["economy.rp"] = { kind = "number", min = 0.5, max = 3, default = 1 },
	event = { kind = "string", max = 60, default = "" },
	motd = { kind = "string", max = 160, default = "" },
} :: { [string]: Spec })

LiveConfig.BR_MIN, LiveConfig.BR_MAX = 1, 15

-- The spec for a key, including the per-jet BR keys.
function LiveConfig.spec(key: string): Spec?
	local direct = LiveConfig.SPECS[key]
	if direct then
		return direct
	end
	local airframeId = key:match("^br%.([%w_]+)$")
	local airframe = airframeId and AircraftData.get(airframeId) :: any
	if airframe then
		return { kind = "number", min = LiveConfig.BR_MIN, max = LiveConfig.BR_MAX, default = airframe.BattleRating }
	end
	return nil
end

-- Checks a value for a key. Returns (true, the value as it'll be stored) or (false, why not).
function LiveConfig.validate(key: string, value: any): (boolean, any)
	local spec = LiveConfig.spec(key)
	if not spec then
		return false, `Unknown key {key}`
	end
	if spec.kind == "number" then
		local n = tonumber(value)
		if not n or n ~= n then
			return false, `{key} needs a number`
		end
		if n < spec.min or n > spec.max then
			return false, `{key} must be between {spec.min} and {spec.max}`
		end
		return true, math.round(n * 100) / 100
	end
	if type(value) ~= "string" then
		return false, `{key} needs text`
	end
	if #value > spec.max then
		return false, `{key} is limited to {spec.max} characters`
	end
	return true, value
end

-- The attribute a key lives in on ReplicatedStorage.
function LiveConfig.attributeName(key: string): string
	return "LC_" .. key:gsub("%.", "_")
end

-- A key's current value: the override if one is set, else the default.
function LiveConfig.get(key: string): any
	local spec = LiveConfig.spec(key)
	local value = ReplicatedStorage:GetAttribute(LiveConfig.attributeName(key))
	if value ~= nil and spec and LiveConfig.validate(key, value) then
		return value
	end
	return spec and spec.default
end

-- A jet's battle rating, live override included. Use this, not AircraftData's BattleRating, everywhere.
function LiveConfig.battleRating(airframeId: string): number?
	local airframe = AircraftData.get(airframeId) :: any
	if not airframe then
		return nil
	end
	return LiveConfig.get(`br.{airframeId}`)
end

return LiveConfig
