--!strict
-- Matchmaking across servers (DEVELOPMENT.md §25, MMK-02/03/04/06).
--   Roles: a public server is a Lobby (hangar and queue). A reserved server reads the record the lobby
--   wrote for it under its PrivateServerId and becomes a Match (one match for the players sent, then
--   everyone goes back to a lobby) or Training (one player: lessons, Vs AI, any jet). Teleport data is
--   never trusted: the record lives in MemoryStore.
--   Queue: PLAY in a lobby adds the player to a MemoryStore sorted map (lineup BR, mode, join time, which
--   lobby server). Entries expire unless their lobby keeps refreshing them, so a crashed lobby leaves no
--   ghosts. One lobby server at a time holds the matchmaker lease and every POLL seconds forms matches
--   (Queue.form), reserves a battle server for each, writes its record, and tells each lobby server which of
--   its players to send. Lobbies poll for that and teleport them, with retries; anyone who still can't get
--   there goes back to the front of the queue.
--   First session (TUT-04): a brand-new pilot (never onboarded, no matches, no lessons) joining a lobby goes
--   straight to a training server, where lesson 1 starts. Going back to a lobby (MULTIPLAYER, or SKIP TO
--   MULTIPLAYER on the welcome card) marks them onboarded, so it only happens once.
--   Studio can't reserve servers or teleport, so there the queue is local and a formed match (or Travel)
--   switches this server's role in place instead.

local MemoryStoreService = game:GetService("MemoryStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local TeleportService = game:GetService("TeleportService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MatchRules = require(Shared.MatchRules)
local Matchmaking = require(Shared.Matchmaking)
local MatchmakingStats = require(Shared.MatchmakingStats)
local Net = require(Shared.Net)
local Places = require(Shared.Config.Places)
local Queue = require(Shared.Queue)
local ServerRole = require(Shared.ServerRole)

local Telemetry = require(ServerScriptService.Server.Lib.Telemetry)
local AircraftService = require(script.Parent.AircraftService)
local DataService = require(script.Parent.DataService)
local MatchService = require(script.Parent.MatchService)
local TelemetryService = require(script.Parent.TelemetryService)

local STATS_KEPT = 500 -- recent waits and matches kept for matchmaking.stats (MMK-06)
local POLL = 2 -- seconds between matchmaker passes, and between a lobby's checks for players to send
local REFRESH = 15 -- a queued player's entry is re-written this often...
local ENTRY_TTL = 60 -- ...and expires after this, if its lobby server has gone
local LEASE_TTL = 8
local RECORD_TTL = 3600
local ASSIGN_TTL = 120
local RECORD_TRIES = 8 -- a reserved server reads its record this many times, 1.5 s apart
local TELEPORT_TRIES = 3
local STUDIO_FILL_AFTER = 4 -- a solo test in Studio shouldn't wait 30 s

local MatchmakingService = {
	Priority = 51, -- after MatchService
}

type Store = {
	queueSet: (key: string, value: any) -> (),
	queueRefresh: (key: string, value: any) -> boolean, -- only if still queued; false if it's gone
	queueRemove: (key: string) -> (),
	queueAll: () -> { any },
	update: (key: string, transform: (any) -> any, ttl: number) -> any,
	get: (key: string) -> any,
	set: (key: string, value: any, ttl: number) -> (),
}

local function memoryStore(): Store
	local queue = MemoryStoreService:GetSortedMap("MatchQueue")
	local map = MemoryStoreService:GetHashMap("Matchmaking")
	return {
		queueSet = function(key, value)
			queue:SetAsync(key, value, ENTRY_TTL)
		end,
		queueRefresh = function(key, value)
			return queue:UpdateAsync(key, function(old)
				return if old == nil then nil else value
			end, ENTRY_TTL) ~= nil
		end,
		queueRemove = function(key)
			queue:RemoveAsync(key)
		end,
		queueAll = function()
			local out = {}
			local lower = nil
			for _ = 1, 10 do -- 200 a page
				local page = queue:GetRangeAsync(Enum.SortDirection.Ascending, 200, lower)
				for _, item in page do
					table.insert(out, item.value)
				end
				if #page < 200 then
					break
				end
				lower = { key = page[#page].key }
			end
			return out
		end,
		update = function(key, transform, ttl)
			return map:UpdateAsync(key, transform, ttl)
		end,
		get = function(key)
			return map:GetAsync(key)
		end,
		set = function(key, value, ttl)
			map:SetAsync(key, value, ttl)
		end,
	}
end

-- Studio: one server, so plain tables behave the same
local function localStore(): Store
	local queue, map = {}, {}
	return {
		queueSet = function(key, value)
			queue[key] = value
		end,
		queueRefresh = function(key, value)
			if queue[key] == nil then
				return false
			end
			queue[key] = value
			return true
		end,
		queueRemove = function(key)
			queue[key] = nil
		end,
		queueAll = function()
			local out = {}
			for _, value in queue do
				table.insert(out, value)
			end
			return out
		end,
		update = function(key, transform)
			local new = transform(map[key])
			if new ~= nil then
				map[key] = new
			end
			return new
		end,
		get = function(key)
			return map[key]
		end,
		set = function(key, value)
			map[key] = value
		end,
	}
end

local studio = RunService:IsStudio()
local store: Store = if studio then localStore() else memoryStore()

type Queued = { mode: string, joinedAt: number, missingSince: number?, airframe: string? }
local queued: { [Player]: Queued } = {}
local leaving: { [Player]: boolean } = {} -- a teleport is under way
local teleportFails: { [Player]: number } = {}
local modeTurn = 0
-- What this lobby saw lately (MMK-06): waits of players matched and of players who gave up, and the matches
-- formed while this server held the matchmaker lease
local stats = { matched = {} :: { number }, gaveUp = {} :: { number }, formed = {} :: { any } }

local function now(): number
	return DateTime.now().UnixTimestampMillis / 1000
end

local function keyOf(userId: number): string
	return tostring(userId)
end

local function sendState(player: Player, payload: { [string]: any })
	Net.Server.fire("QueueState", player, payload)
end

local function despawnAll(player: Player?)
	for _, jet in AircraftService:GetJets() do
		if player == nil or jet.pilot == player then
			AircraftService:Despawn(jet, "Despawn")
		end
	end
end

local function entryFor(player: Player, q: Queued): Queue.Entry
	local data = DataService:GetData(player)
	-- The jet you clicked PLAY with, if it's in your lineup; else the lineup's best (Matchmaking.queueBR)
	local br = data and Matchmaking.queueBR(data.Lineup, q.airframe) or Matchmaking.DEFAULT_BR
	return { userId = player.UserId, br = br, mode = q.mode, joinedAt = q.joinedAt, jobId = game.JobId }
end

------------------------------------------------------------------------------------------------ roles

local function becomeLobby()
	ReplicatedStorage:SetAttribute("ServerRole", "Lobby")
	MatchService:Idle("Lobby")
end

local function becomeTraining()
	ReplicatedStorage:SetAttribute("ServerRole", "Training")
	MatchService:SetMode("FreeFlight")
end

local function becomeMatch(record: any)
	ReplicatedStorage:SetAttribute("ServerRole", "Match")
	MatchService:StartFromRecord(record)
end

-- A reserved server: read the record the lobby wrote for it. No record means a training server (the
-- record write may have failed; training is the harmless guess).
local function resolveRole()
	local reserved = game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0
	if not reserved then
		becomeLobby()
		return
	end
	ReplicatedStorage:SetAttribute("ServerRole", "Pending")
	MatchService:Idle("Pending")
	task.spawn(function()
		local record = nil
		for _ = 1, RECORD_TRIES do
			local ok, value = pcall(store.get, `match:{game.PrivateServerId}`)
			if ok and value then
				record = value
				break
			end
			task.wait(1.5)
		end
		if record and record.role == "Match" and (MatchRules.MODES :: any)[record.mode] then
			becomeMatch(record)
		else
			becomeTraining()
		end
	end)
end

-- A new pilot has made their choice (multiplayer, or staying in training): no more first-session flow.
local function markOnboarded(player: Player, how: string)
	local fresh = false
	DataService:Update(player, function(data)
		if not data.Flags.Onboarded then
			data.Flags.Onboarded = true
			fresh = true
		end
	end)
	if fresh then
		local data = DataService:GetData(player)
		local lessons = 0
		for _ in (data and data.Lessons or {}) do
			lessons += 1
		end
		Telemetry.event("Onboarded", lessons, { how = how }, player)
		TelemetryService:Onboarding(player, "Onboarded")
	end
end
function MatchmakingService:MarkOnboarded(player: Player, how: string)
	markOnboarded(player, how)
end

------------------------------------------------------------------------------------------------ teleports

-- Starts a teleport, retrying if it can't start. Failures after it starts come back on TeleportInitFailed.
local function teleport(placeId: number, players: { Player }, options: TeleportOptions?): boolean
	for attempt = 1, TELEPORT_TRIES do
		local ok, err = pcall(function()
			TeleportService:TeleportAsync(placeId, players, options)
		end)
		if ok then
			return true
		end
		warn(`[Matchmaking] teleport attempt {attempt} failed: {err}`)
		task.wait(attempt * 2)
	end
	Telemetry.event("TeleportFailed", #players, { stage = "start", target = ServerRole.get() }, players[1])
	return false
end

-- Back to a lobby: after a match, or LEAVE / MULTIPLAYER.
local function sendToLobby(players: { Player })
	if studio then
		despawnAll(nil)
		becomeLobby()
		return
	end
	for _, player in players do
		leaving[player] = true
	end
	if not teleport(Places.lobby(), players, nil) then
		for _, player in players do
			leaving[player] = nil
			Net.Server.fire("SpawnRefused", player, "Couldn't reach a lobby just now. Try again in a moment.")
		end
	end
end

local function sendToTraining(player: Player)
	if studio then
		despawnAll(nil)
		becomeTraining()
		return
	end
	local ok, err = pcall(function()
		local code, serverId = TeleportService:ReserveServer(Places.battle())
		store.set(`match:{serverId}`, { role = "Training", players = { player.UserId } }, RECORD_TTL)
		local options = Instance.new("TeleportOptions")
		options.ReservedServerAccessCode = code
		leaving[player] = true
		if not teleport(Places.battle(), { player }, options) then
			error("teleport didn't start")
		end
	end)
	if not ok then
		leaving[player] = nil
		warn(`[Matchmaking] training for {player.Name} failed: {err}`)
		Net.Server.fire("SpawnRefused", player, "Couldn't get there just now. Try again in a moment.")
	end
end

------------------------------------------------------------------------------------------------ queue

local function join(player: Player, mode: string, airframe: string?)
	if not ServerRole.isLobby() or not Queue.validMode(mode) or leaving[player] then
		return
	end
	local q = queued[player]
	if q then
		q.mode = mode
		q.airframe = airframe or q.airframe
	else
		q = { mode = mode, joinedAt = now(), airframe = airframe }
		queued[player] = q
		Telemetry.event("QueueJoined", 1, { mode = mode }, player)
	end
	local ok, err = pcall(store.queueSet, keyOf(player.UserId), entryFor(player, q))
	if not ok then
		queued[player] = nil
		warn(`[Matchmaking] queue join failed: {err}`)
		sendState(player, { state = "Idle", message = "Matchmaking is busy. Try again in a moment." })
		return
	end
	sendState(player, { state = "Searching", mode = mode, waited = now() - q.joinedAt })
end

local function leave(player: Player, quiet: boolean?)
	local q = queued[player]
	if not q then
		return
	end
	queued[player] = nil
	pcall(store.queueRemove, keyOf(player.UserId))
	Telemetry.event("QueueLeft", now() - q.joinedAt, { mode = q.mode }, player)
	MatchmakingStats.push(stats.gaveUp, now() - q.joinedAt, STATS_KEPT)
	if not quiet then
		sendState(player, { state = "Idle" })
	end
end

-- Keep this lobby's entries alive. One that's gone was taken into a match (its assignment is on the way)
-- or expired; if no assignment turns up soon, queue it again.
local function refreshEntries()
	for player, q in queued do
		local ok, present = pcall(store.queueRefresh, keyOf(player.UserId), entryFor(player, q))
		if ok and present then
			q.missingSince = nil
		elseif ok then
			q.missingSince = q.missingSince or now()
			if now() - q.missingSince > REFRESH then
				q.missingSince = nil
				pcall(store.queueSet, keyOf(player.UserId), entryFor(player, q))
			end
		end
	end
end

-- An assignment from the matchmaker: send these players (the ones still here and queued) to their match.
local function sendGroup(assignment: any)
	local entries: { [number]: any } = {}
	for _, entry in assignment.entries do
		entries[entry.userId] = entry
	end
	local players = {}
	for userId in entries do
		local player = Players:GetPlayerByUserId(userId)
		if player and queued[player] then
			table.insert(players, player)
		end
	end
	if #players == 0 then
		return
	end
	for _, player in players do
		local q = queued[player]
		queued[player] = nil
		leaving[player] = true
		sendState(player, { state = "Found", mode = assignment.mode })
		Telemetry.event("QueueMatched", now() - q.joinedAt, { mode = assignment.mode }, player)
		MatchmakingStats.push(stats.matched, now() - q.joinedAt, STATS_KEPT)
	end
	local options = Instance.new("TeleportOptions")
	options.ReservedServerAccessCode = assignment.code
	if not teleport(assignment.place, players, options) then
		-- Back to the front of the queue (their original join time)
		for _, player in players do
			leaving[player] = nil
			if player.Parent then
				local entry = entries[player.UserId]
				queued[player] = { mode = entry.mode, joinedAt = entry.joinedAt }
				pcall(store.queueSet, keyOf(player.UserId), entryFor(player, queued[player]))
				sendState(player, {
					state = "Searching",
					mode = entry.mode,
					waited = now() - entry.joinedAt,
					message = "Couldn't join that match. Still searching…",
				})
			end
		end
	end
end

local function pollAssignments()
	if next(queued) == nil then
		return -- nobody here is waiting (also saves requests)
	end
	local taken = nil
	local ok = pcall(store.update, `lobby:{game.JobId}`, function(old)
		taken = old
		return if old == nil or #old == 0 then nil else {}
	end, ASSIGN_TTL)
	if ok and taken then
		for _, assignment in taken do
			task.spawn(sendGroup, assignment)
		end
	end
end

------------------------------------------------------------------------------------------------ matchmaker

local function holdLease(): boolean
	local ok, value = pcall(store.update, "lease", function(old)
		local t = now()
		if old == nil or old.owner == game.JobId or old.expires < t then
			return { owner = game.JobId, expires = t + LEASE_TTL }
		end
		return nil
	end, LEASE_TTL)
	return ok and value ~= nil and value.owner == game.JobId
end

local function pickMode(): string
	modeTurn += 1
	return Queue.MODES[(modeTurn - 1) % #Queue.MODES + 1]
end

local function makeMatch(match: Queue.Match)
	local users = {}
	for _, entry in match.entries do
		table.insert(users, entry.userId)
		pcall(store.queueRemove, keyOf(entry.userId))
	end
	local record = { role = "Match", mode = match.mode, players = users, band = match.band, formed = now() }
	-- Value: the longest wait in it (s). Sent: the mode and the BR spread; AI seats in the log (MMK-06)
	local spread = math.round(match.spread * 10) / 10
	Telemetry.event(
		"MatchFormed",
		match.longestWait,
		{ mode = match.mode, players = #users, ai = Queue.MATCH_SIZE - #users, spread = spread },
		nil,
		{ "mode", "spread" }
	)
	MatchmakingStats.push(
		stats.formed,
		{ mode = match.mode, players = #users, spread = spread, longestWait = match.longestWait },
		STATS_KEPT
	)

	if studio then
		-- No reserved servers in Studio: this server becomes the match
		for _, userId in users do
			local player = Players:GetPlayerByUserId(userId)
			if player then
				queued[player] = nil
				sendState(player, { state = "Found", mode = match.mode })
			end
		end
		becomeMatch(record)
		return
	end

	local ok, code, serverId = pcall(function()
		return TeleportService:ReserveServer(Places.battle())
	end)
	if not ok then
		warn(`[Matchmaking] couldn't reserve a server: {code}`)
		for _, entry in match.entries do
			pcall(store.queueSet, keyOf(entry.userId), entry) -- back in, same join time
		end
		return
	end
	pcall(store.set, `match:{serverId}`, record, RECORD_TTL)
	local byJob: { [string]: { any } } = {}
	for _, entry in match.entries do
		byJob[entry.jobId] = byJob[entry.jobId] or {}
		table.insert(byJob[entry.jobId], entry)
	end
	for jobId, entries in byJob do
		pcall(store.update, `lobby:{jobId}`, function(old)
			local list = old or {}
			table.insert(list, { code = code, place = Places.battle(), mode = match.mode, entries = entries })
			return list
		end, ASSIGN_TTL)
	end
end

local function runMatchmaker()
	if not holdLease() then
		return
	end
	local ok, entries = pcall(store.queueAll)
	if not ok then
		warn(`[Matchmaking] couldn't read the queue: {entries}`)
		return
	end
	local matches = Queue.form(entries, {
		now = now(),
		fillAfter = if studio then STUDIO_FILL_AFTER else nil,
		pickMode = pickMode,
	})
	for _, match in matches do
		makeMatch(match)
	end
end

------------------------------------------------------------------------------------------------ lifecycle

-- What this lobby saw lately, for the admin command matchmaking.stats (MMK-06): wait times of matched
-- players and of those who gave up, still queued here, and the matches formed while it ran the matchmaker.
function MatchmakingService:Stats(): any
	local queuedHere, modes = 0, {}
	for _, q in queued do
		queuedHere += 1
		modes[q.mode] = (modes[q.mode] or 0) + 1
	end
	local formed = { count = #stats.formed, players = 0, aiSeats = 0, spread = 0, byMode = {} }
	for _, match in stats.formed do
		formed.players += match.players
		formed.aiSeats += Queue.MATCH_SIZE - match.players
		formed.spread += match.spread
		formed.byMode[match.mode] = (formed.byMode[match.mode] or 0) + 1
	end
	if formed.count > 0 then
		formed.players = math.round(formed.players / formed.count * 10) / 10
		formed.spread = math.round(formed.spread / formed.count * 100) / 100
	end
	return {
		role = ServerRole.get(),
		queuedNow = queuedHere,
		queuedModes = modes,
		matchedWaits = MatchmakingStats.waits(stats.matched),
		gaveUpWaits = MatchmakingStats.waits(stats.gaveUp),
		matchesFormed = formed, -- players and spread are averages; aiSeats a total
	}
end

-- Testing (admin onboarding.restart): send a player into the first-session flow now.
function MatchmakingService:StartFirstSession(player: Player)
	leave(player, true)
	sendToTraining(player)
end

function MatchmakingService:Init()
	resolveRole()

	Net.Server.on("QueueJoin", join)
	Net.Server.on("QueueLeave", function(player: Player)
		leave(player)
	end)
	Net.Server.on("Travel", function(player: Player, target: string)
		if target == "Training" and ServerRole.isLobby() and not leaving[player] then
			local data = DataService:GetData(player)
			if data and not data.Flags.Onboarded then
				Telemetry.event("FirstSessionTraining", 1, {}, player)
			end
			leave(player, true)
			sendToTraining(player)
		elseif target == "Lobby" and not ServerRole.isLobby() and not leaving[player] then
			markOnboarded(player, "Multiplayer")
			sendToLobby({ player })
		end
	end)
	-- A brand-new pilot in a lobby gets the welcome window (MenuController): GO TO TRAINING is a Travel, and
	-- closing it is SkipOnboarding
	Net.Server.on("SkipOnboarding", function(player: Player)
		if ServerRole.isLobby() then
			markOnboarded(player, "Skipped")
		end
	end)
	DataService.ProfileLoaded:Connect(function(player, data)
		if not data.Flags.Onboarded and (data.Stats.Matches > 0 or next(data.Lessons) ~= nil) then
			-- Played before the first-session flow existed: they know their way round
			DataService:Update(player, function(d)
				d.Flags.Onboarded = true
				d.Onboarding.Onboarded = true -- reached, not logged: their funnel ran before this step existed
			end)
		end
	end)
	-- After a match's results, everyone goes back to a lobby
	MatchService.MatchOver:Connect(function()
		sendToLobby(Players:GetPlayers())
	end)

	TeleportService.TeleportInitFailed:Connect(
		function(player: Player, result: Enum.TeleportResult, message: string, placeId: number, options: any)
			local fails = (teleportFails[player] or 0) + 1
			teleportFails[player] = fails
			warn(`[Matchmaking] teleport failed for {player.Name} ({result.Name}): {message}`)
			if fails < TELEPORT_TRIES and result ~= Enum.TeleportResult.Unauthorized then
				task.wait(fails * 2)
				pcall(function()
					TeleportService:TeleportAsync(placeId, { player }, options)
				end)
				return
			end
			teleportFails[player] = nil
			leaving[player] = nil
			Telemetry.event("TeleportFailed", 1, { stage = "init", result = result.Name }, player)
			sendState(player, { state = "Idle", message = "Couldn't join. Press PLAY to try again." })
		end
	)

	Players.PlayerRemoving:Connect(function(player)
		leave(player, true)
		leaving[player] = nil
		teleportFails[player] = nil
	end)
end

function MatchmakingService:Start()
	task.spawn(function()
		local sinceRefresh = 0
		while true do
			task.wait(POLL)
			if ServerRole.isLobby() then
				sinceRefresh += POLL
				if sinceRefresh >= REFRESH then
					sinceRefresh = 0
					refreshEntries()
				end
				runMatchmaker()
				pollAssignments()
			end
		end
	end)
end

return MatchmakingService
