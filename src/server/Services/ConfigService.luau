--!strict
-- Live config on the server (DEVELOPMENT.md §31.1, OPS-01). The overrides live in the LiveConfig DataStore
-- (key "current": { overrides = { [key] = value }, audit = { { at, by, key, old, new } } }), so they apply to
-- every server of this experience (the test and live experiences have separate stores). Each override is
-- put on ReplicatedStorage as an attribute (LiveConfig.attributeName) for the server and clients to read.
--   Loaded as the server starts (a second or so after boot), again every RELOAD seconds, and at once when another server changes one (the
--   LiveConfigChanged MessagingService topic).
--   Set / Clear (admin commands config.set / config.clear) validate with LiveConfig.validate and record who
--   changed what and when (the last AUDIT_KEEP changes).
--   Scheduled events (OPS-03, Shared/Events) live in the same record ({ events = { ... } }) and are shared as
--   the LiveEvents attribute (JSON); admin event.add / event.remove change them.
--   Announcements (OPS-04): Announce sends a message to every player on every server (the Announce topic),
--   shown as a toast.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local MessagingService = game:GetService("MessagingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Events = require(Shared.Events)
local LiveConfig = require(Shared.LiveConfig)
local Net = require(Shared.Net)

local Telemetry = require(ServerScriptService.Server.Lib.Telemetry)

local STORE_KEY = "current"
local TOPIC = "LiveConfigChanged"
local ANNOUNCE_TOPIC = "Announce"
local RELOAD = 300 -- seconds
local AUDIT_KEEP = 50

local ConfigService = {
	Priority = 3, -- before everything that reads live config
}

type Record = { overrides: { [string]: any }, audit: { { [string]: any } }, events: { Events.Event } }

local store: DataStore? = nil
local current: Record = { overrides = {}, audit = {}, events = {} }
local announced: { [string]: boolean } = {} -- announcement ids already shown here
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
	ReplicatedStorage:SetAttribute(LiveConfig.EVENTS_ATTRIBUTE, HttpService:JSONEncode(record.events))
end

local function sanitize(raw: any): Record
	local record: Record = { overrides = {}, audit = {}, events = {} }
	if type(raw) == "table" then
		if type(raw.overrides) == "table" then
			record.overrides = raw.overrides
		end
		if type(raw.audit) == "table" then
			record.audit = raw.audit
		end
		record.events = Events.clean(raw.events)
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

-- Writes the record with `edit` applied, records the change in the audit and tells the other servers. edit
-- returns (true, nil, old, new) for the audit, or (false, why) to give up. Returns (ok, why not).
local function save(admin: Player, key: string, edit: (Record) -> (boolean, string?, any, any)): (boolean, string?)
	if not store then
		return false, "Live config store unavailable"
	end
	local saved: Record? = nil
	local why: string? = nil
	local ok, err = pcall(function()
		(store :: DataStore):UpdateAsync(STORE_KEY, function(raw)
			local record = sanitize(raw)
			local fine, problem, old, new = edit(record)
			if not fine then
				why = problem
				return nil
			end
			table.insert(
				record.audit,
				{ at = os.time(), by = admin.UserId, name = admin.Name, key = key, old = old, new = new }
			)
			while #record.audit > AUDIT_KEEP do
				table.remove(record.audit, 1)
			end
			saved = record
			return record
		end)
	end)
	if why then
		return false, why
	end
	if not ok or not saved then
		return false, `Couldn't save: {err}`
	end
	apply(saved :: Record)
	pcall(function()
		MessagingService:PublishAsync(TOPIC, key)
	end)
	Telemetry.event("LiveConfigChanged", 1, { key = key }, admin)
	return true, nil
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
	local ok, why = save(admin, key, function(record)
		local old = record.overrides[key]
		record.overrides[key] = clean
		return true, nil, old, clean
	end)
	if not ok then
		return false, why or "Couldn't save"
	end
	return true, if clean == nil then `Cleared {key}` else `{key} = {clean}`
end

function ConfigService:Set(admin: Player, key: string, value: any): (boolean, string)
	return change(admin, key, value)
end

function ConfigService:Clear(admin: Player, key: string): (boolean, string)
	return change(admin, key, nil)
end

-- Schedules an event (OPS-03; args as Events.make). Returns (ok, message).
function ConfigService:AddEvent(admin: Player, args: { [string]: any }): (boolean, string)
	local made: Events.Event? = nil
	local id = string.sub(HttpService:GenerateGUID(false), 1, 8)
	local ok, why = save(admin, "event.add", function(record)
		local event, problem = Events.make(args, record.events, os.time(), id)
		if not event then
			return false, problem
		end
		made = event
		table.insert(record.events, event)
		record.events = Events.trim(Events.clean(record.events), os.time())
		return true, nil, nil, event.name
	end)
	if not ok or not made then
		return false, why or "Couldn't schedule it"
	end
	local event = made :: Events.Event
	return true,
		`Scheduled "{event.name}" ({event.id}): {os.date("!%a %d %b %H:%M", event.start)} to {os.date(
			"!%a %d %b %H:%M",
			event.finish
		)} UTC, xp x{event.xp}, credits x{event.credits}, rp x{event.rp}`
end

-- Takes an event off the schedule (ending it now if it's running). Returns (ok, message).
function ConfigService:RemoveEvent(admin: Player, id: string): (boolean, string)
	local name = nil
	local ok, why = save(admin, "event.remove", function(record)
		for i, event in record.events do
			if event.id == id then
				name = event.name
				table.remove(record.events, i)
				return true, nil, event.name, nil
			end
		end
		return false, `No event {id}`
	end)
	return ok, if ok then `Removed "{name}"` else why or "Couldn't remove it"
end

function ConfigService:Events(): { Events.Event }
	return table.clone(current.events)
end

local function showAnnouncement(message: { [string]: any })
	if type(message) ~= "table" or type(message.id) ~= "string" or announced[message.id] then
		return
	end
	announced[message.id] = true
	Net.Server.fireAll("Announcement", { text = message.text, seconds = message.seconds })
end

-- Sends a message to every player on every server (OPS-04), shown for `seconds`. Returns (ok, message).
ConfigService.ANNOUNCE_MAX = 100
function ConfigService:Announce(admin: Player, text: any, seconds: any): (boolean, string)
	if type(text) ~= "string" or not string.match(text, "%S") then
		return false, "Usage: announce { text, seconds? }"
	elseif #text > ConfigService.ANNOUNCE_MAX then
		return false, `Announcements are limited to {ConfigService.ANNOUNCE_MAX} characters`
	end
	local message = {
		id = HttpService:GenerateGUID(false),
		text = text,
		seconds = math.clamp(tonumber(seconds) or 10, 5, 60),
	}
	showAnnouncement(message) -- here at once (and in Studio, where MessagingService doesn't reach)
	pcall(function()
		MessagingService:PublishAsync(ANNOUNCE_TOPIC, message)
	end)
	Telemetry.event("Announcement", 1, {}, admin)
	return true, `Announced to every server: {text}`
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
	pcall(function()
		MessagingService:SubscribeAsync(ANNOUNCE_TOPIC, function(message)
			showAnnouncement(message.Data)
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
