--!strict
-- Right to Erasure (CMP-04; DEVELOPMENT.md §32.3): removes everything Afterburner stores under a UserId,
-- for admin erasure.run when Roblox's webhook passes on a request. Each step is tried even if another
-- fails, and the result lists what was done, so a step can be re-run. What goes:
--   the save: Player_<id> in every PlayerData_<env>_v1..vN store (older schema versions too)
--   reports against them (Reports u<id>, ReportCounts) and their id in other pilots' report records
--   their bug reports (Feedback day:<n> entries) and daily counts (n:<id>:<day>)
--   their leaderboard entries (every weekly store since leaderboards began, every season, all-time)
--   their squadron membership (Squadrons s:<id>; the squadron is disbanded if they were its last member)
-- MemoryStore entries expire by themselves; analytics are Roblox's.

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Environment = require(Shared.Config.Environment)
local Leaderboards = require(Shared.Leaderboards)
local PlayerData = require(Shared.PlayerData)
local Seasons = require(Shared.Config.Seasons)
local Squadron = require(Shared.Squadron)

local Erasure = {}

Erasure.LEADERBOARDS_SINCE = 1793577600 -- Monday 2 November 2026: no weekly board is older
Erasure.FEEDBACK_DAYS = 400 -- bug reports are looked for this many days back

local function each(store: DataStore, prefix: string, fn: (key: string) -> ())
	local ok, pages = pcall(store.ListKeysAsync, store, prefix, 100)
	if not ok then
		error(`couldn't list {prefix}: {pages}`)
	end
	while true do
		for _, item in (pages :: DataStoreKeyPages):GetCurrentPage() do
			fn(item.KeyName)
		end
		if (pages :: DataStoreKeyPages).IsFinished then
			break
		end
		pages:AdvanceToNextPageAsync()
	end
end

local function step(lines: { string }, name: string, fn: () -> string)
	local ok, result = pcall(fn)
	table.insert(lines, if ok then `{name}: {result}` else `{name}: FAILED ({result}) - run again`)
end

-- Erases a player's data. Returns a line per step.
function Erasure.run(userId: number): { string }
	local lines = {}
	local id = tostring(userId)
	local env = if Environment.isTest() then "Test" else "Prod"

	-- First, while the save still says which squadron they're in
	step(lines, "Squadron", function()
		local save = DataStoreService:GetDataStore(`PlayerData_{env}_v{PlayerData.VERSION}`):GetAsync(`Player_{id}`)
		local data = if type(save) == "table" and type(save.Data) == "table" then save.Data else save
		local squadronId = type(data) == "table" and type(data.Squadron) == "table" and data.Squadron.Id
		if type(squadronId) ~= "string" or squadronId == "" then
			return "not in one"
		end
		local squadrons = DataStoreService:GetDataStore("Squadrons")
		local emptied: Squadron.Record? = nil
		squadrons:UpdateAsync(`s:{squadronId}`, function(raw)
			local record = Squadron.clean(raw)
			if not record or not record.members[id] then
				return nil
			end
			if not Squadron.leave(record, userId) then
				emptied = record
			end
			return record
		end)
		if emptied then
			squadrons:RemoveAsync(`s:{squadronId}`)
			squadrons:RemoveAsync(`tag:{(emptied :: Squadron.Record).tag}`)
			return "removed (it was disbanded: they were the last member)"
		end
		return "removed"
	end)

	step(lines, "Save", function()
		local removed = 0
		for version = 1, PlayerData.VERSION do
			local store = DataStoreService:GetDataStore(`PlayerData_{env}_v{version}`)
			store:RemoveAsync(`Player_{id}`)
			removed += 1
		end
		return `removed from {removed} store version(s)`
	end)

	step(lines, "Reports against them", function()
		DataStoreService:GetDataStore("Reports"):RemoveAsync(`u{id}`)
		DataStoreService:GetOrderedDataStore("ReportCounts"):RemoveAsync(id)
		return "removed"
	end)

	step(lines, "Reports they made", function()
		local reports = DataStoreService:GetDataStore("Reports")
		local changed = 0
		each(reports, "u", function(key)
			reports:UpdateAsync(key, function(record)
				if type(record) ~= "table" or type(record.entries) ~= "table" then
					return nil
				end
				local kept, dropped = {}, false
				for _, entry in record.entries do
					if type(entry) == "table" and entry.reporter == userId then
						dropped = true
					else
						table.insert(kept, entry)
					end
				end
				if not dropped then
					return nil -- leave it as it is
				end
				changed += 1
				record.entries = kept
				return record
			end)
		end)
		return `removed from {changed} record(s)`
	end)

	step(lines, "Bug reports", function()
		local feedback = DataStoreService:GetDataStore("Feedback")
		local counts = 0
		each(feedback, `n:{id}:`, function(key)
			feedback:RemoveAsync(key)
			counts += 1
		end)
		local today = os.time() // 86400
		local changed = 0
		for day = today - Erasure.FEEDBACK_DAYS, today do
			local ok, list = pcall(feedback.GetAsync, feedback, `day:{day}`)
			if ok and type(list) == "table" then
				local mine = false
				for _, entry in list do
					if type(entry) == "table" and entry.user == userId then
						mine = true
					end
				end
				if mine then
					feedback:UpdateAsync(`day:{day}`, function(current)
						local kept = {}
						for _, entry in current or {} do
							if not (type(entry) == "table" and entry.user == userId) then
								table.insert(kept, entry)
							end
						end
						return kept
					end)
					changed += 1
				end
			end
		end
		return `{changed} day(s) of reports and {counts} daily count(s) cleaned`
	end)

	step(lines, "Leaderboards", function()
		local names = { "LB_KillsAll", "LB_DuelRating" }
		for _, season in Seasons.LIST do
			table.insert(names, `LB_Season_{season.Id}`)
		end
		local first, last = Leaderboards.week(Erasure.LEADERBOARDS_SINCE), Leaderboards.week(os.time())
		-- (SquadronWeek is keyed by squadron, not player: nothing of theirs there)
		for week = first, last do
			table.insert(names, `LB_KillsWeek_{week}`)
			table.insert(names, `LB_WinsWeek_{week}`)
		end
		for _, name in names do
			DataStoreService:GetOrderedDataStore(name):RemoveAsync(id)
		end
		return `removed from {#names} board(s)`
	end)

	return lines
end

return Erasure
