--!strict
-- Live config on the server (DEVELOPMENT.md §31.1, OPS-01). The overrides live in the LiveConfig DataStore
-- (key "current": { overrides = { [key] = value }, audit = { { at, by, key, old, new } } }), so they apply to
-- every server of this experience (the test and live experiences have separate stores). Each override is
-- put on ReplicatedStorage as an attribute (LiveConfig.attributeName) for the server and clients to read.
--   Loaded as the server starts (a second or so after boot), again every RELOAD seconds, and at once when another server changes one (the
--   LiveConfigChanged MessagingService topic).
--   Set / Clear (admin commands config.set / config.clear) validate with LiveConfig.validate and record who
--   changed what and when (the last AUDIT_KEEP changes).

local DataStoreService = game:GetService("DataStoreService")
local MessagingService = game:GetService("MessagingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local LiveConfig = require(Shared.LiveConfig)

local Telemetry = require(ServerScriptService.Server.Lib.Telemetry)

local STORE_KEY = "current"
local TOPIC = "LiveConfigChanged"
local RELOAD = 300 -- seconds
local AUDIT_KEEP = 50

local ConfigService = {
	Priority = 3, -- before everything that reads live config
}

type Record = { overrides: { [string]: any }, audit: { { [string]: any } } }

local store: DataStore? = nil
local current: Record = { overrides = {}, audit = {} }
local applied: { [string]: boolean } = {} -- attributes set from overrides

-- Puts the overrides on ReplicatedStorage (and takes away ones no longer set). Skips anything invalid.
local function apply(record: Record)
	current = record
	local seen: { [string]: boolean } = {}
	for key, value in record.overrides do
		local ok, clean = LiveConfig.validate(key, value)
		if ok then
			local name = LiveConfig.attributeName(key)
			ReplicatedStorage:SetAttribute(name, clean)
			seen[name] = true
		end
	end
	for name in applied do
		if not seen[name] then
			ReplicatedStorage:SetAttribute(name, nil)
		end
	end
	applied = seen
end

local function sanitize(raw: any): Record
	local record: Record = { overrides = {}, audit = {} }
	if type(raw) == "table" then
		if type(raw.overrides) == "table" then
			record.overrides = raw.overrides
		end
		if type(raw.audit) == "table" then
			record.audit = raw.audit
		end
	end
	return record
end

local function load()
	if not store then
		return
	end
	local ok, raw = pcall(function()
		return (store :: DataStore):GetAsync(STORE_KEY)
	end)
	if ok then
		apply(sanitize(raw))
	else
		warn(`[Config] couldn't load live config: {raw}`)
	end
end

-- Changes one override (value nil clears it). Returns (ok, message).
local function change(admin: Player, key: string, value: any): (boolean, string)
	local clean = nil
	if value ~= nil then
		local ok, result = LiveConfig.validate(key, value)
		if not ok then
			return false, result
		end
		clean = result
	elseif not LiveConfig.spec(key) then
		return false, `Unknown key {key}`
	end
	if not store then
		return false, "Live config store unavailable"
	end
	local saved: Record? = nil
	local ok, err = pcall(function()
		(store :: DataStore):UpdateAsync(STORE_KEY, function(raw)
			local record = sanitize(raw)
			local old = record.overrides[key]
			record.overrides[key] = clean
			table.insert(record.audit, {
				at = os.time(),
				by = admin.UserId,
				name = admin.Name,
				key = key,
				old = old,
				new = clean,
			})
			while #record.audit > AUDIT_KEEP do
				table.remove(record.audit, 1)
			end
			saved = record
			return record
		end)
	end)
	if not ok or not saved then
		return false, `Couldn't save: {err}`
	end
	apply(saved :: Record)
	pcall(function()
		MessagingService:PublishAsync(TOPIC, key)
	end)
	Telemetry.event("LiveConfigChanged", 1, { key = key }, admin)
	return true, if clean == nil then `Cleared {key}` else `{key} = {clean}`
end

function ConfigService:Set(admin: Player, key: string, value: any): (boolean, string)
	return change(admin, key, value)
end

function ConfigService:Clear(admin: Player, key: string): (boolean, string)
	return change(admin, key, nil)
end

function ConfigService:Overrides(): { [string]: any }
	return table.clone(current.overrides)
end

function ConfigService:Audit(count: number): { { [string]: any } }
	local audit = current.audit
	return { table.unpack(audit, math.max(#audit - count + 1, 1), #audit) }
end

function ConfigService:Init()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore("LiveConfig")
	end)
	if ok then
		store = result
	else
		warn(`[Config] no DataStore: {result}`)
	end
end

function ConfigService:Start()
	-- First load here (Init mustn't yield); defaults apply for the moment until it arrives
	task.spawn(load)
	pcall(function()
		MessagingService:SubscribeAsync(TOPIC, function()
			task.defer(load)
		end)
	end)
	task.spawn(function()
		while true do
			task.wait(RELOAD)
			load()
		end
	end)
end

return ConfigService
