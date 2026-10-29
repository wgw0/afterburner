--!strict
-- Analytics wrapper (DEVELOPMENT.md §30, ANL-01). Every analytics call goes through here:
--   * pcall'd: analytics must never break gameplay
--   * tagged with the environment, so test traffic is easy to filter out
--   * kept in a small in-memory log for tests and the admin panel
-- AnalyticsService custom events need a player; server-wide events attach to the first player present.

local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Environment = require(ReplicatedStorage:WaitForChild("Shared").Config.Environment)

local Telemetry = {}

local RECENT_LIMIT = 200
Telemetry.recent = {} :: { { name: string, value: number?, fields: { [string]: any }, time: number } }

local function remember(name: string, value: number?, fields: { [string]: any })
	table.insert(Telemetry.recent, { name = name, value = value, fields = fields, time = os.time() })
	if #Telemetry.recent > RECENT_LIMIT then
		table.remove(Telemetry.recent, 1)
	end
end

local function anyPlayer(): Player?
	return Players:GetPlayers()[1]
end

-- A custom event. player optional (server-wide events attach to someone present). Roblox keeps two custom
-- fields per event (the third is the environment): `primary` names which fields go (in order); without it,
-- the first two keys alphabetically. Every field stays in the in-memory log.
function Telemetry.event(
	name: string,
	value: number?,
	fields: { [string]: any }?,
	player: Player?,
	primary: { string }?
)
	local data = table.clone(fields or {})
	data.env = Environment.get()
	remember(name, value, data)
	local who = player or anyPlayer()
	if not who then
		return
	end
	pcall(function()
		-- Custom fields are limited to three; send the most useful ones.
		local custom = {}
		local keys = {}
		if primary then
			keys = table.clone(primary)
		else
			for k in data do
				if k ~= "env" then
					table.insert(keys, k)
				end
			end
			table.sort(keys)
		end
		local slots = { Enum.AnalyticsCustomFieldKeys.CustomField01, Enum.AnalyticsCustomFieldKeys.CustomField02 }
		for i, k in keys do
			if slots[i] then
				custom[slots[i].Name] = `{k}={tostring(data[k])}`
			end
		end
		custom[Enum.AnalyticsCustomFieldKeys.CustomField03.Name] = `env={data.env}`
		AnalyticsService:LogCustomEvent(who, name, value or 1, custom)
	end)
end

-- One step of a recurring funnel (a session id groups one run of it).
function Telemetry.funnel(player: Player, funnel: string, step: number, stepName: string)
	remember(`funnel:{funnel}`, step, { step = stepName })
	pcall(function()
		AnalyticsService:LogFunnelStepEvent(player, funnel, nil, step, stepName)
	end)
end

-- A step of the one-time onboarding funnel (ANL-02). Log each step once per player (TelemetryService keeps
-- track in the save).
function Telemetry.onboarding(player: Player, step: number, stepName: string)
	remember("onboarding", step, { step = stepName })
	pcall(function()
		AnalyticsService:LogOnboardingFunnelStepEvent(player, step, stepName)
	end)
end

-- A progression milestone, e.g. the highest tier a player has reached.
function Telemetry.progression(player: Player, path: string, level: number, levelName: string?)
	remember(`progression:{path}`, level, { name = levelName })
	pcall(function()
		AnalyticsService:LogProgressionEvent(player, path, Enum.AnalyticsProgressionType.Complete, level, levelName)
	end)
end

function Telemetry.count(name: string): number
	local n = 0
	for _, e in Telemetry.recent do
		if e.name == name then
			n += 1
		end
	end
	return n
end

return Telemetry
