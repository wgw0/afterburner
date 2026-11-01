--!strict
-- Parties (MMK-05; rules in Shared/Party, DEVELOPMENT.md §25.3): up to 3 pilots on one lobby server who
-- queue as one entry and fly on the same team. Each lobby server keeps its own parties.
--   Invites: to anyone on this server (PartyInvite), answered with PartyRespond. INVITE FRIENDS on the client
--   opens Roblox's invite window with launch data "party:<inviter>"; a friend who joins with it is moved to
--   the inviter's server if they landed elsewhere, then joins the party (friends only: the launch and
--   teleport data are only a hint).
--   After a match, MatchmakingService sends each party home together with { party = { leader, members } } in
--   its teleport data, and the party is put back together once its members arrive.
--   Every change goes to the members as PartyState; Changed lets MatchmakingService cancel a search whose
--   party changed.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Callsign = require(Shared.Callsign)
local Net = require(Shared.Net)
local Party = require(Shared.Party)
local ServerRole = require(Shared.ServerRole)
local Signal = require(Shared.Util.Signal)

local PartyService = {
	Priority = 50, -- before MatchmakingService
	Changed = Signal.new(), -- ({ userId }): these players' party changed
}

local RESTORE_WAIT = 30 -- seconds to wait for a party's members to arrive back from a match

local state = Party.new()
local restoring: { [number]: { members: { number }, deadline: number } } = {} -- by leader

local function now(): number
	return os.time()
end

local function nameOf(userId: number): string
	local player = Players:GetPlayerByUserId(userId)
	return if player then Callsign.nameOf(player) else tostring(userId)
end

-- What a player sees: their party (leader first) and the invites waiting for them.
local function view(userId: number): { [string]: any }
	local members = {}
	for _, id in Party.membersOf(state, userId) do
		table.insert(members, { userId = id, name = nameOf(id) })
	end
	local invites = {}
	for _, from in Party.invitesFor(state, userId, now()) do
		table.insert(invites, { userId = from, name = nameOf(from) })
	end
	return {
		leader = Party.leaderOf(state, userId),
		members = members,
		invites = invites,
		max = Party.MAX,
	}
end

local function push(userIds: { number })
	local seen = {}
	for _, userId in userIds do
		if not seen[userId] then
			seen[userId] = true
			local player = Players:GetPlayerByUserId(userId)
			if player then
				Net.Server.fire("PartyState", player, view(userId))
			end
		end
	end
end

local function changed(userIds: { number })
	push(userIds)
	PartyService.Changed:Fire(userIds)
end

-- The player's party, leader first ({ userId } on their own).
function PartyService:MembersOf(player: Player): { number }
	return Party.membersOf(state, player.UserId)
end

-- The leader of the player's party, or nil on their own.
function PartyService:LeaderOf(player: Player): number?
	return Party.leaderOf(state, player.UserId)
end

local function lobbyOnly(): (boolean, string?)
	if not ServerRole.isLobby() then
		return false, "Parties are made in the hangar"
	end
	return true, nil
end

function PartyService:Invite(player: Player, userId: number): (boolean, string?)
	local ok, why = lobbyOnly()
	if not ok then
		return false, why
	end
	local target = Players:GetPlayerByUserId(userId)
	if not target then
		return false, "They're not on this server"
	end
	ok, why = Party.invite(state, player.UserId, userId, now())
	if ok then
		push({ userId })
	end
	return ok, why
end

local function accept(player: Player, from: number): (boolean, string?)
	local before = Party.membersOf(state, from)
	local leader, why = Party.accept(state, player.UserId, from, now())
	if not leader then
		push({ player.UserId })
		return false, why
	end
	local after = Party.membersOf(state, leader)
	table.move(before, 1, #before, #after + 1, after)
	changed(after)
	return true, nil
end

function PartyService:Respond(player: Player, from: number, yes: boolean): (boolean, string?)
	if not yes then
		Party.decline(state, player.UserId, from)
		push({ player.UserId })
		return true, nil
	end
	local ok, why = lobbyOnly()
	if not ok then
		return false, why
	end
	return accept(player, from)
end

function PartyService:Leave(player: Player)
	local before = Party.membersOf(state, player.UserId)
	if #before <= 1 then
		return
	end
	Party.leave(state, player.UserId)
	changed(before)
end

function PartyService:Kick(player: Player, userId: number): (boolean, string?)
	local before = Party.membersOf(state, player.UserId)
	local ok, why = Party.kick(state, player.UserId, userId)
	if ok then
		changed(before)
	end
	return ok, why
end

-- A friend's invite (launch data "party:<userId>") or a hop to their server (teleport data joinParty):
-- join their party, moving to their server first if they're on another lobby.
local function joinFriend(player: Player, leader: number, hopped: boolean)
	local okFriend, friends = pcall(player.IsFriendsWith, player, leader)
	if not (okFriend and friends) then
		return
	end
	if Players:GetPlayerByUserId(leader) then
		-- An invite from the friend, accepted straight away: they asked to join by accepting Roblox's invite.
		-- (If it can't be made, e.g. the party's full, accepting fails quietly.)
		Party.invite(state, leader, player.UserId, now())
		accept(player, leader)
		return
	end
	if hopped or RunService:IsStudio() or not ServerRole.isLobby() then
		return
	end
	local ok, here, _, placeId, jobId = pcall(TeleportService.GetPlayerPlaceInstanceAsync, TeleportService, leader)
	if not (ok and here and placeId == game.PlaceId and jobId and jobId ~= game.JobId) then
		return
	end
	local options = Instance.new("TeleportOptions")
	options.ServerInstanceId = jobId
	options:SetTeleportData({ joinParty = leader })
	pcall(TeleportService.TeleportAsync, TeleportService, game.PlaceId, { player }, options)
end

-- Back from a match: put the party back together once its members are here (or the wait is over).
local function tryRestore(leader: number)
	local pending = restoring[leader]
	if not pending then
		return
	end
	local present = {}
	for _, userId in pending.members do
		if Players:GetPlayerByUserId(userId) then
			table.insert(present, userId)
		end
	end
	if #present == #pending.members or now() >= pending.deadline then
		restoring[leader] = nil
		if Party.restore(state, leader, present) then
			changed(present)
		end
	end
end

local function arrived(player: Player)
	local join = player:GetJoinData()
	local data = join.TeleportData
	if type(data) == "table" and type(data.party) == "table" then
		local leader, members = data.party.leader, data.party.members
		if type(leader) == "number" and type(members) == "table" and table.find(members, player.UserId) then
			local list = {}
			for _, id in members do
				if type(id) == "number" then
					table.insert(list, id)
				end
			end
			restoring[leader] = restoring[leader] or { members = list, deadline = now() + RESTORE_WAIT }
			tryRestore(leader)
			return
		end
	end
	if type(data) == "table" and type(data.joinParty) == "number" then
		joinFriend(player, data.joinParty, true)
		return
	end
	local launch = join.LaunchData
	local leader = type(launch) == "string" and tonumber(string.match(launch, "^party:(%d+)$"))
	if leader and leader ~= player.UserId then
		joinFriend(player, leader, false)
	end
end

function PartyService:Init()
	Net.Server.handle("PartyInvite", function(player: Player, userId: number)
		return self:Invite(player, userId)
	end)
	Net.Server.handle("PartyRespond", function(player: Player, from: number, yes: boolean)
		return self:Respond(player, from, yes)
	end)
	Net.Server.handle("PartyKick", function(player: Player, userId: number)
		return self:Kick(player, userId)
	end)
	Net.Server.on("PartyLeave", function(player: Player)
		self:Leave(player)
	end)
end

function PartyService:Start()
	Players.PlayerAdded:Connect(function(player)
		task.spawn(arrived, player)
		push({ player.UserId })
	end)
	Players.PlayerRemoving:Connect(function(player)
		self:Leave(player)
		for _, list in state.invites do
			list[player.UserId] = nil
		end
		state.invites[player.UserId] = nil
	end)
	-- Parties waiting on members who never came back
	task.spawn(function()
		while true do
			task.wait(5)
			for leader in restoring do
				tryRestore(leader)
			end
		end
	end)
end

return PartyService
