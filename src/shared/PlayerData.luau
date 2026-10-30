--!strict
-- Player save data (DESIGN §9.3, DEVELOPMENT.md §22.2): schema v1, migrations, the replica sent to the
-- owning client, and deltas. Pure, so DataService and the tests share it.
--   Version / Migrations: MIGRATIONS[n](data) upgrades version n-1 to n; run on every load.
--   Aircraft[id]: { Owned, Researched, RP, Modules = { [moduleId] = fitted (true) or owned but off (false) },
--     Mastery, Camo (skin in use), Skins = { [skinId] = true } (bought; the default is always owned) }
--   Flags.AllUnlocked: full access (the game's owner and admins, Progression.unlockEverything)
--   PilotXP is XP into the current level (TotalXP keeps the lifetime sum).
--   Challenges: today's and this week's challenges and their progress (Challenges.luau); Achievements:
--     { [id] = { At, Badge } } (Achievements.luau). Stats are lifetime counts (Progression.applyRewards).
--   ProcessedReceipts is bounded (most recent RECEIPT_HISTORY ids), enough to stop double grants.

local Challenges = require(script.Parent.Challenges)
local Spin = require(script.Parent.Spin)
local Streak = require(script.Parent.Streak)
local Economy = require(script.Parent.Config.Economy)
local Settings = require(script.Parent.Config.Settings)

local PlayerData = {}

PlayerData.VERSION = 1
PlayerData.RECEIPT_HISTORY = 100

-- Fields the client may see (its own data only). Everything else stays on the server.
PlayerData.REPLICATED = table.freeze({
	"PilotXP",
	"PilotLevel",
	"TotalXP",
	"Credits",
	"Wings",
	"FreeRP",
	"Aircraft",
	"Lineup",
	"Settings",
	"Stats",
	"Flags",
	"Challenges",
	"Achievements",
	"Title",
	"Callsign",
	"Passes",
	"Boosters",
	"Cosmetics",
	"Lessons",
	"Streak",
	"Titles",
})

local function deepCopy<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in value :: any do
		copy[k] = deepCopy(v)
	end
	return copy :: any
end
PlayerData.deepCopy = deepCopy

function PlayerData.newAircraft(owned: boolean): { [string]: any }
	return { Owned = owned, Researched = owned, RP = 0, Modules = {}, Mastery = 0, Camo = "Default", Skins = {} }
end

-- A fresh account.
function PlayerData.template(): { [string]: any }
	local aircraft = {}
	for _, id in Economy.STARTERS do
		aircraft[id] = PlayerData.newAircraft(true)
	end
	return {
		Version = PlayerData.VERSION,
		PilotXP = 0,
		PilotLevel = 1,
		TotalXP = 0,
		Credits = Economy.STARTING_CREDITS,
		Wings = 0,
		FreeRP = 0,
		Aircraft = aircraft,
		Lineup = { Economy.STARTERS[1] },
		Cosmetics = { Owned = {}, Equipped = {} }, -- Wings cosmetics (Shared/Cosmetics): [id] = true; [kind] = id
		Passes = {}, -- [passKey] = true while owned: PassService mirrors Roblox's answer on every join and purchase
		Boosters = { Credits = 0, RP = 0 }, -- unix time each booster runs out (Shared/Perks)
		ProcessedReceipts = {},
		Settings = Settings.defaults(),
		Stats = { Kills = 0, AIKills = 0, Deaths = 0, Matches = 0, Wins = 0 },
		Challenges = Challenges.newState(),
		Achievements = {},
		Title = "", -- the title shown on the scoreboard (Config/LevelRewards), "" for none
		PendingTierUnlock = false, -- { Tier, Jets } chosen before a Tier Unlock purchase (Shop), false for none
		Callsign = "", -- your custom callsign as typed and cleaned (CMP-01), "" for your username; re-filtered on join
		LevelRewardsClaimed = 0, -- the level whose Credits / Free RP milestones have been paid up to
		Lessons = {}, -- [lessonId] = true once finished (TelemetryService)
		Streak = Streak.newState(), -- the daily login streak (LIV-03)
		Spin = Spin.newState(), -- free spins: banked and play-time toward the next (SpinService)
		Titles = {}, -- titles unlocked other than by level, e.g. the streak's [titleId] = true
		Onboarding = {}, -- onboarding funnel steps already logged (ANL-02)
		TopTier = 0, -- highest tier owned, for the progression event
		Season = { Id = 1, XP = 0, Premium = false, Claimed = {} },
		Flags = {},
		LastWinDay = 0, -- os.time() // 86400 of the last win (first win of the day bonus)
	}
end

-- MIGRATIONS[n](data) turns a version n-1 save into version n. None yet: v1 is the first schema.
PlayerData.MIGRATIONS = table.freeze({}) :: { [number]: (data: { [string]: any }) -> () }

-- Brings a loaded save up to date: runs migrations in order, then fills any missing fields from the
-- template (new fields added later get their defaults). Returns the data and the versions applied.
function PlayerData.migrate(
	data: { [string]: any },
	migrations: { [number]: (data: { [string]: any }) -> () }?,
	targetVersion: number?
): ({ [string]: any }, { number })
	local steps = migrations or PlayerData.MIGRATIONS
	local target = targetVersion or PlayerData.VERSION
	local applied = {}
	local version = if type(data.Version) == "number" then data.Version else 0
	while version < target do
		version += 1
		local step = steps[version]
		if step then
			step(data)
		end
		data.Version = version
		table.insert(applied, version)
	end
	PlayerData.reconcile(data)
	return data, applied
end

-- Adds missing fields (recursively for plain tables) from the template. Never removes anything.
function PlayerData.reconcile(data: { [string]: any })
	local function fill(target: { [any]: any }, defaults: { [any]: any })
		for k, v in defaults do
			if target[k] == nil then
				target[k] = deepCopy(v)
			elseif type(v) == "table" and type(target[k]) == "table" and k ~= "Lineup" and k ~= "Aircraft" then
				fill(target[k], v)
			end
		end
	end
	fill(data, PlayerData.template())
	for _, id in Economy.STARTERS do
		if not data.Aircraft[id] then
			data.Aircraft[id] = PlayerData.newAircraft(true)
		end
	end
	data.Settings = Settings.sanitize(data.Settings)
end

-- Remembers a processed purchase id; keeps only the most recent RECEIPT_HISTORY.
function PlayerData.rememberReceipt(data: { [string]: any }, purchaseId: string)
	table.insert(data.ProcessedReceipts, purchaseId)
	while #data.ProcessedReceipts > PlayerData.RECEIPT_HISTORY do
		table.remove(data.ProcessedReceipts, 1)
	end
end

local function deepEqual(a: any, b: any): boolean
	if type(a) ~= type(b) then
		return false
	end
	if type(a) ~= "table" then
		return a == b
	end
	for k, v in a do
		if not deepEqual(v, b[k]) then
			return false
		end
	end
	for k in b do
		if a[k] == nil then
			return false
		end
	end
	return true
end
PlayerData.deepEqual = deepEqual

-- The client's view of a save: copies of the replicated fields.
function PlayerData.replica(data: { [string]: any }): { [string]: any }
	local view = {}
	for _, key in PlayerData.REPLICATED do
		view[key] = deepCopy(data[key])
	end
	return view
end

-- Top-level replicated fields that differ between two replicas (only those are sent).
function PlayerData.delta(before: { [string]: any }, after: { [string]: any }): { [string]: any }?
	local changes = {}
	local any = false
	for _, key in PlayerData.REPLICATED do
		if not deepEqual(before[key], after[key]) then
			changes[key] = deepCopy(after[key])
			any = true
		end
	end
	return if any then changes else nil
end

return PlayerData
