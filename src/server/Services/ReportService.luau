--!strict
-- Reporting a cheater (DEVELOPMENT.md §32, CMP-03). A pilot reports another pilot from this server with a
-- reason; the report is stored with the target's recent anti-cheat data (AntiCheatService) for review, in
-- the "Reports" DataStore (one record per reported pilot), and an OrderedDataStore keeps how often each
-- pilot has been reported so the most-reported can be listed (admin commands reports.top / reports.show).
-- Only UserIds are stored (§32 privacy); names appear in the server log only.
-- Nothing happens to the reported pilot automatically.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Reports = require(Shared.Reports)
local ServerRole = require(Shared.ServerRole)

local Telemetry = require(ServerScriptService.Server.Lib.Telemetry)
local AntiCheatService = require(script.Parent.AntiCheatService)

local ReportService = {
	Priority = 50,
}

local STORE = "Reports"
local COUNTS = "ReportCounts"

local lastReport: { [Player]: number } = {}
local reported: { [Player]: { [number]: boolean } } = {}
local seen: { [number]: string } = {} -- everyone who has been on this server: UserId -> name

local function key(userId: number): string
	return `u{userId}`
end

local function store(): DataStore?
	local ok, result = pcall(DataStoreService.GetDataStore, DataStoreService, STORE)
	return if ok then result else nil
end

local function counts(): OrderedDataStore?
	local ok, result = pcall(DataStoreService.GetOrderedDataStore, DataStoreService, COUNTS)
	return if ok then result else nil
end

local function save(targetUserId: number, entry: any): boolean
	local reports = store()
	if not reports then
		return false
	end
	local total = 0
	local ok, err = pcall(function()
		reports:UpdateAsync(key(targetUserId), function(record)
			record = Reports.add(record, entry)
			total = record.count
			return record
		end)
	end)
	if not ok then
		warn(`[Reports] Couldn't save a report on {targetUserId}: {err}`)
		return false
	end
	local ordered = counts()
	if ordered then
		pcall(ordered.SetAsync, ordered, tostring(targetUserId), total)
	end
	return true
end

-- Files a report. Returns (ok, message for the reporter).
function ReportService:Report(reporter: Player, targetUserId: number, reason: string): (boolean, string)
	local now = os.time()
	local mine = reported[reporter] or {}
	reported[reporter] = mine
	local ok, err = Reports.validate(reporter.UserId, targetUserId, reason, now, lastReport[reporter], mine)
	if not ok then
		return false, err :: string
	end
	local targetName = seen[targetUserId]
	if not targetName then
		return false, "That pilot hasn't been on this server."
	end
	lastReport[reporter] = now
	mine[targetUserId] = true

	local target = Players:GetPlayerByUserId(targetUserId)
	local entry = {
		at = now,
		reporter = reporter.UserId,
		reason = reason,
		role = ServerRole.get(),
		placeId = game.PlaceId,
		jobId = game.JobId,
		targetPresent = target ~= nil,
		antiCheat = AntiCheatService:Snapshot(targetUserId, Reports.RECENT_STRIKES),
	}
	local strikes = if entry.antiCheat then entry.antiCheat.violations else 0
	-- flagged: whether the target has any anti-cheat strikes here (a number would split the funnel)
	Telemetry.event("PlayerReported", strikes, { reason = reason, flagged = strikes > 0 }, reporter)
	warn(
		`[Reports] {reporter.Name} reported {targetName} ({targetUserId}) for {reason}; {strikes} anti-cheat strikes here`
	)
	task.spawn(save, targetUserId, entry)
	return true, "Thanks, your report has been logged for review."
end

-- The most-reported pilots: { { userId, count } }, most first.
function ReportService:Top(count: number): { any }
	local ordered = counts()
	if not ordered then
		return {}
	end
	local ok, pages = pcall(ordered.GetSortedAsync, ordered, false, count)
	if not ok then
		return {}
	end
	local list = {}
	for _, item in (pages :: any):GetCurrentPage() do
		table.insert(list, { userId = tonumber(item.key), count = item.value })
	end
	return list
end

-- A pilot's stored report record (count, reporters, the newest entries), or nil.
function ReportService:Get(userId: number): any
	local reports = store()
	if not reports then
		return nil
	end
	local ok, record = pcall(reports.GetAsync, reports, key(userId))
	return if ok then record else nil
end

function ReportService:Init()
	Net.Server.handle("ReportPlayer", function(player: Player, targetUserId: number, reason: string)
		return self:Report(player, targetUserId, reason)
	end)
	local function arrived(player: Player)
		seen[player.UserId] = player.Name
	end
	Players.PlayerAdded:Connect(arrived)
	for _, player in Players:GetPlayers() do
		arrived(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		lastReport[player] = nil
		reported[player] = nil
	end)
end

return ReportService
