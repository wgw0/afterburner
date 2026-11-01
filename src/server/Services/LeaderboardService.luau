--!strict
-- Leaderboards (LIV-05, DAT-04; boards and scores in Shared/Leaderboards). Each board is an OrderedDataStore
-- keyed by user id. A player's scores are written after each scored match (ProgressionService.MatchRewarded)
-- and when they leave, only those that changed. GetLeaderboard reads a board's top entries, cached for
-- CACHE seconds per server, with display names, plus the asking player's own score. Admin
-- leaderboard.remove takes a player off every current board (a cheater).
-- Studio without API access to DataStores: the boards just show the players here.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserService = game:GetService("UserService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Leaderboards = require(Shared.Leaderboards)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)
local ProgressionService = require(script.Parent.ProgressionService)

local LeaderboardService = {
	Priority = 72, -- after ProgressionService
}

local CACHE = 60 -- seconds a board's top entries are kept before reading again

type Entry = { rank: number, userId: number, name: string, score: number }

local written: { [Player]: { [string]: number } } = {} -- store name → score last written for the player
local cache: { [string]: { at: number, entries: { Entry } } } = {} -- by store name
local names: { [number]: string } = {}

local function storeFor(name: string): OrderedDataStore?
	local ok, store = pcall(DataStoreService.GetOrderedDataStore, DataStoreService, name)
	return if ok then store else nil
end

-- Writes a player's scores that changed since last time (and aren't 0).
local function push(player: Player, data: { [string]: any }?)
	data = data or DataService:GetData(player)
	if not data then
		return
	end
	local now = os.time()
	local mine = written[player] or {}
	written[player] = mine
	for _, board in Leaderboards.BOARDS do
		local name = Leaderboards.storeName(board.id, now)
		local score = Leaderboards.score(data :: any, board.id, now)
		if name and score > 0 and mine[name] ~= score then
			local store = storeFor(name)
			local ok, err = pcall(function()
				(store :: OrderedDataStore):SetAsync(tostring(player.UserId), score)
			end)
			if ok then
				mine[name] = score
			else
				warn(`[Leaderboards] couldn't write {name} for {player.UserId}: {err}`)
			end
		end
	end
end

-- Display names for user ids, looked up in one request and remembered.
local function fillNames(userIds: { number })
	local missing = {}
	for _, userId in userIds do
		if not names[userId] then
			local player = Players:GetPlayerByUserId(userId)
			if player then
				names[userId] = player.DisplayName
			else
				table.insert(missing, userId)
			end
		end
	end
	if #missing > 0 then
		local ok, infos = pcall(UserService.GetUserInfosByUserIdsAsync, UserService, missing)
		if ok then
			for _, info in infos do
				names[info.Id] = info.DisplayName
			end
		end
	end
end

-- The players on this server, ranked (Studio without DataStore access).
local function localTop(boardId: string, now: number): { Entry }
	local list = {}
	for _, player in Players:GetPlayers() do
		local data = DataService:GetData(player)
		local score = if data then Leaderboards.score(data, boardId, now) else 0
		if score > 0 then
			table.insert(list, { rank = 0, userId = player.UserId, name = player.DisplayName, score = score })
		end
	end
	table.sort(list, function(a, b)
		return a.score > b.score
	end)
	for i, entry in list do
		entry.rank = i
	end
	return list
end

-- A board's top entries now (cached), or nil and why not.
function LeaderboardService:Top(boardId: string): ({ Entry }?, string?)
	if not Leaderboards.get(boardId) then
		return nil, "Unknown board"
	end
	local now = os.time()
	local name = Leaderboards.storeName(boardId, now)
	if not name then
		return {}, nil -- between seasons
	end
	local cached = cache[name]
	if cached and now - cached.at < CACHE then
		return cached.entries, nil
	end
	local store = storeFor(name)
	local ok, pages = pcall(function()
		return (store :: OrderedDataStore):GetSortedAsync(false, Leaderboards.TOP)
	end)
	if not ok then
		return localTop(boardId, now), nil
	end
	local entries: { Entry } = {}
	local ids = {}
	for i, item in (pages :: DataStorePages):GetCurrentPage() do
		local userId = tonumber(item.key)
		if userId then
			table.insert(entries, { rank = i, userId = userId, name = "", score = item.value })
			table.insert(ids, userId)
		end
	end
	fillNames(ids)
	for _, entry in entries do
		entry.name = names[entry.userId] or `Pilot {entry.userId}`
	end
	cache[name] = { at = now, entries = entries }
	return entries, nil
end

-- Takes a player off every current board. Returns how many boards they were removed from.
function LeaderboardService:Remove(userId: number): number
	local now = os.time()
	local removed = 0
	for _, board in Leaderboards.BOARDS do
		local name = Leaderboards.storeName(board.id, now)
		if name then
			local store = storeFor(name)
			if store and pcall(store.RemoveAsync, store, tostring(userId)) then
				removed += 1
			end
			cache[name] = nil
		end
	end
	local player = Players:GetPlayerByUserId(userId)
	if player then
		written[player] = {}
	end
	return removed
end

function LeaderboardService:Init()
	Net.Server.handle("GetLeaderboard", function(player: Player, boardId: string)
		local entries, why = self:Top(boardId)
		if not entries then
			return nil, why
		end
		local data = DataService:GetData(player)
		return {
			board = boardId,
			entries = entries,
			mine = if data then Leaderboards.score(data, boardId, os.time()) else 0,
		},
			nil
	end)
	ProgressionService.MatchRewarded:Connect(function(player: Player, data: { [string]: any })
		task.spawn(push, player, data)
	end)
end

function LeaderboardService:Start()
	Players.PlayerRemoving:Connect(function(player)
		push(player)
		written[player] = nil
	end)
end

return LeaderboardService
