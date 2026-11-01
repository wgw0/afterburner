--!strict
-- Squadrons (LIV-06; rules in Shared/Squadron). Records live in the Squadrons DataStore: s:<id> (the record)
-- and tag:<TAG> (its id, so tags are unique and squadrons can be found by tag). A member's save holds
-- Squadron = { Id, ClaimWeek }; when it loads, the record is checked and a player who isn't in it any more
-- (removed while away) is cleared. A member's tag is the SquadronTag attribute, shown before their name
-- (Callsign.nameOf). Records are cached for CACHE seconds per server.
-- Points: each scored match's player kills and win add to the squadron's weekly score (an OrderedDataStore,
-- Leaderboards "SquadronWeek"); at Squadron.GOAL every member can claim Squadron.REWARD once that week.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local UserService = game:GetService("UserService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Leaderboards = require(Shared.Leaderboards)
local Net = require(Shared.Net)
local Squadron = require(Shared.Squadron)
local Telemetry = require(ServerScriptService.Server.Lib.Telemetry)

local DataService = require(script.Parent.DataService)
local ProgressionService = require(script.Parent.ProgressionService)
local TextFilterService = require(script.Parent.TextFilterService)

local SquadronService = {
	Priority = 73,
}

local CACHE = 30
local INVITE_TTL = 120

local cache: { [string]: { at: number, record: Squadron.Record? } } = {}
local invites: { [number]: { [string]: number } } = {} -- invitee → { squadron id → expires }
local lastWeekly: { [Player]: { Week: number, Kills: number, Wins: number } } = {}
local names: { [number]: string } = {}

local function store(): DataStore
	return DataStoreService:GetDataStore("Squadrons")
end

local function now(): number
	return os.time()
end

-- A squadron record (cached), or nil if there's no such squadron. Yields.
function SquadronService:Get(id: string, fresh: boolean?): Squadron.Record?
	local cached = cache[id]
	if cached and not fresh and now() - cached.at < CACHE then
		return cached.record
	end
	local ok, raw = pcall(function()
		return store():GetAsync(`s:{id}`)
	end)
	if not ok then
		return if cached then cached.record else nil
	end
	local record = Squadron.clean(raw)
	cache[id] = { at = now(), record = record }
	return record
end

-- "[TAG] Name" for a squadron id (leaderboards).
function SquadronService:Label(id: string): string
	local record = self:Get(id)
	return if record then `[{record.tag}] {record.name}` else "Disbanded squadron"
end

-- Changes a record: edit returns (ok, why); the record is written only if it's ok. Returns the record after.
local function change(id: string, edit: (Squadron.Record) -> (boolean, string?)): (Squadron.Record?, string?)
	local result: Squadron.Record? = nil
	local why: string? = nil
	local ok, err = pcall(function()
		store():UpdateAsync(`s:{id}`, function(raw)
			local record = Squadron.clean(raw)
			if not record then
				why = "That squadron doesn't exist any more"
				return nil
			end
			local fine, problem = edit(record)
			if not fine then
				why = problem
				return nil
			end
			result = record
			return record
		end)
	end)
	if not ok then
		return nil, `Couldn't save just now ({err})`
	end
	if result then
		cache[id] = { at = now(), record = result }
	end
	return result, why
end

local function setMembership(player: Player, record: Squadron.Record?)
	DataService:Update(player, function(data)
		data.Squadron = data.Squadron or { Id = "", ClaimWeek = 0 }
		data.Squadron.Id = if record then record.id else ""
	end)
	player:SetAttribute("SquadronTag", if record then record.tag else nil)
end

local function disband(record: Squadron.Record)
	pcall(function()
		store():RemoveAsync(`s:{record.id}`)
		store():RemoveAsync(`tag:{record.tag}`)
	end)
	cache[record.id] = { at = now(), record = nil }
end

local function myId(player: Player): string?
	local data = DataService:GetData(player)
	local id = data and data.Squadron and data.Squadron.Id
	return if type(id) == "string" and id ~= "" then id else nil
end

function SquadronService:Create(player: Player, name: any, tag: any, open: any): (boolean, string?)
	local data = DataService:GetData(player)
	if not data then
		return false, "Your data isn't loaded yet"
	elseif myId(player) then
		return false, "Leave your squadron first"
	elseif (data.Credits or 0) < Squadron.COST then
		return false, `Creating a squadron costs {Squadron.COST} Credits`
	end
	local cleanName, whyName = Squadron.cleanName(name)
	local cleanTag, whyTag = Squadron.cleanTag(tag)
	if not cleanName or not cleanTag then
		return false, whyName or whyTag
	end
	local filteredName = TextFilterService:Filter(cleanName, player.UserId)
	local filteredTag = TextFilterService:Filter(cleanTag, player.UserId)
	if filteredName ~= cleanName or filteredTag ~= cleanTag then
		return false, "Roblox's filter didn't allow that name or tag"
	end
	local id = string.sub(HttpService:GenerateGUID(false):gsub("-", ""), 1, 12)
	local taken = false
	local ok, err = pcall(function()
		store():UpdateAsync(`tag:{cleanTag}`, function(existing)
			if existing ~= nil then
				taken = true
				return nil
			end
			return id
		end)
	end)
	if not ok then
		return false, `Couldn't create it just now ({err})`
	elseif taken then
		return false, `The tag {cleanTag} is taken`
	end
	local record = Squadron.new(id, cleanName, cleanTag, player.UserId, open == true, now())
	local saved = pcall(function()
		store():SetAsync(`s:{id}`, record)
	end)
	if not saved then
		pcall(function()
			store():RemoveAsync(`tag:{cleanTag}`)
		end)
		return false, "Couldn't create it just now"
	end
	cache[id] = { at = now(), record = record }
	DataService:Update(player, function(d)
		d.Credits -= Squadron.COST
	end)
	setMembership(player, record)
	local after = DataService:GetData(player)
	Telemetry.economy(player, "Sink", "Credits", Squadron.COST, after and after.Credits or 0, "Squadron", "Create")
	return true, `[{cleanTag}] {cleanName} is yours`
end

local function joinRecord(player: Player, id: string, invited: boolean): (boolean, string?)
	if myId(player) then
		return false, "Leave your squadron first"
	end
	local record, why = change(id, function(r)
		return Squadron.join(r, player.UserId, invited, now())
	end)
	if not record then
		return false, why
	end
	invites[player.UserId] = nil
	setMembership(player, record)
	return true, `You're in [{record.tag}] {record.name}`
end

function SquadronService:Join(player: Player, tag: any): (boolean, string?)
	local clean, why = Squadron.cleanTag(tag)
	if not clean then
		return false, why
	end
	local ok, id = pcall(function()
		return store():GetAsync(`tag:{clean}`)
	end)
	if not ok or type(id) ~= "string" then
		return false, `No squadron has the tag {clean}`
	end
	local invite = invites[player.UserId] and invites[player.UserId][id]
	return joinRecord(player, id, invite ~= nil and invite > now())
end

function SquadronService:Leave(player: Player): (boolean, string?)
	local id = myId(player)
	if not id then
		return false, "You're not in a squadron"
	end
	local empty = false
	local record = change(id, function(r)
		empty = not Squadron.leave(r, player.UserId)
		return true, nil
	end)
	if record and empty then
		disband(record)
	end
	setMembership(player, nil)
	return true, if empty then "You left, and the squadron was disbanded" else "You left the squadron"
end

local function managed(player: Player, edit: (Squadron.Record) -> (boolean, string?)): (Squadron.Record?, string?)
	local id = myId(player)
	if not id then
		return nil, "You're not in a squadron"
	end
	return change(id, edit)
end

function SquadronService:Kick(player: Player, userId: number): (boolean, string?)
	local record, why = managed(player, function(r)
		return Squadron.kick(r, player.UserId, userId)
	end)
	if not record then
		return false, why
	end
	local target = Players:GetPlayerByUserId(userId)
	if target then
		setMembership(target, nil)
	end
	return true, "Removed"
end

function SquadronService:SetRole(player: Player, userId: number, role: string): (boolean, string?)
	local record, why = managed(player, function(r)
		return Squadron.setRole(r, player.UserId, userId, role)
	end)
	return record ~= nil, why
end

function SquadronService:SetOpen(player: Player, open: boolean): (boolean, string?)
	local record, why = managed(player, function(r)
		if not Squadron.canManage(r, player.UserId) then
			return false, "Only the owner and officers can do that"
		end
		r.open = open
		return true, nil
	end)
	return record ~= nil, why
end

function SquadronService:Invite(player: Player, userId: number): (boolean, string?)
	local id = myId(player)
	local record = id and self:Get(id, true)
	local target = Players:GetPlayerByUserId(userId)
	if not record then
		return false, "You're not in a squadron"
	elseif not Squadron.canManage(record, player.UserId) then
		return false, "Only the owner and officers can invite"
	elseif not target then
		return false, "They're not on this server"
	elseif myId(target) then
		return false, "They're already in a squadron"
	end
	invites[userId] = invites[userId] or {}
	invites[userId][record.id] = now() + INVITE_TTL
	Net.Server.fire("SquadronChanged", target)
	return true, `Invited {target.DisplayName}`
end

function SquadronService:Respond(player: Player, id: string, yes: boolean): (boolean, string?)
	local invite = invites[player.UserId] and invites[player.UserId][id]
	if not invite or invite <= now() then
		return false, "That invite has run out"
	end
	invites[player.UserId][id] = nil
	if not yes then
		return true, nil
	end
	return joinRecord(player, id, true)
end

local function weekScore(id: string): number
	local name = Leaderboards.storeName("SquadronWeek", now()) :: string
	local ok, value = pcall(function()
		return DataStoreService:GetOrderedDataStore(name):GetAsync(id)
	end)
	return if ok and type(value) == "number" then value else 0
end

function SquadronService:Claim(player: Player): (boolean, string?)
	local id = myId(player)
	if not id then
		return false, "You're not in a squadron"
	end
	local week = Leaderboards.week(now())
	local data = DataService:GetData(player)
	if data and data.Squadron.ClaimWeek == week then
		return false, "You've claimed this week's reward"
	elseif weekScore(id) < Squadron.GOAL then
		return false, `The squadron needs {Squadron.GOAL} points this week`
	end
	DataService:Update(player, function(d)
		d.Squadron.ClaimWeek = week
		d.Credits += Squadron.REWARD
	end)
	local after = DataService:GetData(player)
	Telemetry.economy(player, "Source", "Credits", Squadron.REWARD, after and after.Credits or 0, "Squadron", "Weekly")
	return true, `+{Squadron.REWARD} Credits`
end

local function fillNames(userIds: { number })
	local missing = {}
	for _, userId in userIds do
		local player = Players:GetPlayerByUserId(userId)
		if player then
			names[userId] = player.DisplayName
		elseif not names[userId] then
			table.insert(missing, userId)
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

-- What a player sees on the SQUADRON tab.
function SquadronService:View(player: Player): { [string]: any }
	local id = myId(player)
	local record = id and self:Get(id, true)
	local pending = {}
	for squadronId, expires in invites[player.UserId] or {} do
		local invitedTo = expires > now() and self:Get(squadronId)
		if invitedTo then
			table.insert(pending, { id = squadronId, tag = invitedTo.tag, name = invitedTo.name })
		end
	end
	local view: { [string]: any } = {
		cost = Squadron.COST,
		goal = Squadron.GOAL,
		reward = Squadron.REWARD,
		points = Squadron.POINTS,
		invites = pending,
	}
	if record then
		local ids = {}
		for key in record.members do
			table.insert(ids, tonumber(key) :: number)
		end
		fillNames(ids)
		local members = {}
		for key, member in record.members do
			local userId = tonumber(key) :: number
			table.insert(members, {
				userId = userId,
				name = names[userId] or `Pilot {userId}`,
				role = member.role,
				online = Players:GetPlayerByUserId(userId) ~= nil,
			})
		end
		local order = { Owner = 1, Officer = 2, Member = 3 }
		table.sort(members, function(a, b)
			if order[a.role] ~= order[b.role] then
				return order[a.role] < order[b.role]
			end
			return a.name < b.name
		end)
		local data = DataService:GetData(player)
		view.squadron = {
			id = record.id,
			name = record.name,
			tag = record.tag,
			open = record.open,
			members = members,
			max = Squadron.MAX_MEMBERS,
			role = Squadron.roleOf(record, player.UserId),
			score = weekScore(record.id),
			claimed = data ~= nil and data.Squadron.ClaimWeek == Leaderboards.week(now()),
		}
	end
	return view
end

-- A scored match's points for the member's squadron (this week's new player kills and win).
local function addPoints(player: Player, data: { [string]: any })
	local weekly = data.Weekly
	local id = myId(player)
	if type(weekly) ~= "table" then
		return
	end
	local last = lastWeekly[player]
	local kills, wins = weekly.Kills or 0, weekly.Wins or 0
	if last and last.Week == weekly.Week then
		kills -= last.Kills
		wins -= last.Wins
	end
	lastWeekly[player] = { Week = weekly.Week, Kills = weekly.Kills or 0, Wins = weekly.Wins or 0 }
	local points = kills * Squadron.POINTS.kill + wins * Squadron.POINTS.win
	if not id or points <= 0 then
		return
	end
	local name = Leaderboards.storeName("SquadronWeek", now()) :: string
	local ok, err = pcall(function()
		DataStoreService:GetOrderedDataStore(name):IncrementAsync(id, points)
	end)
	if not ok then
		warn(`[Squadrons] couldn't add {points} points to {id}: {err}`)
	end
end

-- On joining: still a member? (They may have been removed while away.)
local function checkMembership(player: Player, data: { [string]: any })
	local weekly = data.Weekly
	if type(weekly) == "table" then
		lastWeekly[player] = { Week = weekly.Week, Kills = weekly.Kills or 0, Wins = weekly.Wins or 0 }
	end
	local id = myId(player)
	if not id then
		return
	end
	local record = SquadronService:Get(id, true)
	if record and record.members[tostring(player.UserId)] then
		player:SetAttribute("SquadronTag", record.tag)
	else
		setMembership(player, nil)
	end
end

function SquadronService:Init()
	Net.Server.handle("SquadronGet", function(player: Player)
		return self:View(player)
	end)
	Net.Server.handle("SquadronAction", function(player: Player, action: string, a: any, b: any)
		if action == "Create" then
			return self:Create(player, a, b, true)
		elseif action == "CreateClosed" then
			return self:Create(player, a, b, false)
		elseif action == "Join" then
			return self:Join(player, a)
		elseif action == "Leave" then
			return self:Leave(player)
		elseif action == "Kick" and type(a) == "number" then
			return self:Kick(player, a)
		elseif action == "Role" and type(a) == "number" and type(b) == "string" then
			return self:SetRole(player, a, b)
		elseif action == "Open" then
			return self:SetOpen(player, a == true)
		elseif action == "Invite" and type(a) == "number" then
			return self:Invite(player, a)
		elseif action == "Respond" and type(a) == "string" then
			return self:Respond(player, a, b == true)
		elseif action == "Claim" then
			return self:Claim(player)
		end
		return false, "Unknown action"
	end)
	DataService.ProfileLoaded:Connect(function(player, data)
		task.spawn(checkMembership, player, data)
	end)
	ProgressionService.MatchRewarded:Connect(function(player: Player, data: { [string]: any })
		task.spawn(addPoints, player, data)
	end)
end

function SquadronService:Start()
	Players.PlayerRemoving:Connect(function(player)
		lastWeekly[player] = nil
		invites[player.UserId] = nil
	end)
end

return SquadronService
