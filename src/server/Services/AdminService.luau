--!strict
-- Admin commands (DEVELOPMENT.md §31.2, OPS-02; data commands DAT-05). Called through AdminCommand
-- (command, args) -> (ok, message). Every call is checked here; the client's debug panel is only a UI.
--   Admins: the place's creator (or group owner), anyone listed in ADMINS, and everyone in Studio.
--   Data-changing commands only run in the test environment; inspection and kicks work everywhere.
--   Owners (the creator, group owner or ADMINS; not everyone in Studio) also get full access to every
--   jet, module, skin and lineup slot, in test and live (Progression.unlockEverything).
-- Every command is logged to analytics.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Environment = require(Shared.Config.Environment)
local Net = require(Shared.Net)
local PlayerData = require(Shared.PlayerData)
local Progression = require(Shared.Progression)
local TechTree = require(Shared.TechTree)
local Telemetry = require(ServerScriptService.Server.Lib.Telemetry)

local DataService = require(script.Parent.DataService)
local MatchmakingService = require(script.Parent.MatchmakingService)

local ADMINS: { number } = {} -- extra admin user ids (live config later, §31.1)
local MAX_GRANT = 1e7

local AdminService = {
	Priority = 80,
}

function AdminService:IsAdmin(player: Player): boolean
	return RunService:IsStudio() or self:IsOwner(player)
end

-- The game's owner: its creator, the owner of the group that owns it, or anyone listed in ADMINS.
function AdminService:IsOwner(player: Player): boolean
	if table.find(ADMINS, player.UserId) then
		return true
	end
	if game.CreatorType == Enum.CreatorType.User then
		return player.UserId == game.CreatorId
	end
	local ok, rank = pcall(function()
		return player:GetRankInGroup(game.CreatorId)
	end)
	return ok and rank == 255
end

-- The player a command targets: args.userId if given, otherwise the admin.
local function target(admin: Player, args: { [string]: any }): Player?
	local userId = tonumber(args.userId)
	return if userId then Players:GetPlayerByUserId(userId) else admin
end

local function amount(args: { [string]: any }): number?
	local n = tonumber(args.amount)
	if not n or n ~= n or n <= 0 or n > MAX_GRANT then
		return nil
	end
	return math.floor(n)
end

type Command = {
	testOnly: boolean,
	run: (admin: Player, args: { [string]: any }) -> (boolean, string),
}

local COMMANDS: { [string]: Command } = {
	-- Shows a player's save (replicated fields and a few others), as JSON.
	["data.inspect"] = {
		testOnly = false,
		run = function(admin, args)
			local who = target(admin, args)
			local data = who and DataService:GetData(who)
			if not (who and data) then
				return false, "No loaded save for that player"
			end
			local view = PlayerData.replica(data)
			view.Version = data.Version
			view.LastWinDay = data.LastWinDay
			return true, HttpService:JSONEncode(view)
		end,
	},
	-- The latest analytics events this server sent (ANL-04), newest last: { count? = 30, name? = filter }.
	["telemetry.recent"] = {
		testOnly = false,
		run = function(_admin, args)
			local count = math.clamp(tonumber(args.count) or 30, 1, 200)
			local list = {}
			for _, entry in Telemetry.recent do
				if args.name == nil or entry.name == args.name then
					table.insert(list, entry)
				end
			end
			return true, HttpService:JSONEncode({ table.unpack(list, math.max(#list - count + 1, 1), #list) })
		end,
	},
	-- Resets a save to a fresh account.
	["data.reset"] = {
		testOnly = true,
		run = function(admin, args)
			local who = target(admin, args)
			if not who then
				return false, "Player not found"
			end
			local ok = DataService:Update(who, function(data)
				local fresh = PlayerData.template()
				table.clear(data)
				for k, v in fresh do
					data[k] = v
				end
				return true
			end)
			return ok == true, if ok then `Reset {who.Name}'s save` else "Save not loaded"
		end,
	},
	-- Replays the first-session flow (TUT-04 testing): clears the lessons and the onboarded flag, then sends
	-- the player to training as a new pilot. The training reward isn't paid twice (TutorialComplete stays).
	["onboarding.restart"] = {
		testOnly = true,
		run = function(admin, args)
			local who = target(admin, args)
			if not who then
				return false, "Player not found"
			end
			local ok = DataService:Update(who, function(data)
				data.Lessons = {}
				data.Flags.Onboarded = nil
				return true
			end)
			if ok then
				MatchmakingService:StartFirstSession(who)
			end
			return ok == true, if ok then `{who.Name} starts the first session again` else "Save not loaded"
		end,
	},
	-- Clears challenges and achievements back to a fresh account's (LIV-01/02 testing). Stats are kept.
	["career.reset"] = {
		testOnly = true,
		run = function(admin, args)
			local who = target(admin, args)
			if not who then
				return false, "Player not found"
			end
			local ok = DataService:Update(who, function(data)
				local fresh = PlayerData.template()
				data.Challenges = fresh.Challenges
				data.Achievements = fresh.Achievements
				return true
			end)
			return ok == true, if ok then `Reset {who.Name}'s challenges and achievements` else "Save not loaded"
		end,
	},
	["give.credits"] = {
		testOnly = true,
		run = function(admin, args)
			local who, n = target(admin, args), amount(args)
			if not (who and n) then
				return false, "Usage: give.credits { amount }"
			end
			local ok = DataService:Update(who, function(data)
				data.Credits += n
				return true
			end)
			return ok == true, `+{n} Credits`
		end,
	},
	["give.xp"] = {
		testOnly = true,
		run = function(admin, args)
			local who, n = target(admin, args), amount(args)
			if not (who and n) then
				return false, "Usage: give.xp { amount }"
			end
			local levels = DataService:Update(who, function(data)
				return Progression.addXP(data, n)
			end)
			return levels ~= nil, `+{n} XP ({levels or 0} levels)`
		end,
	},
	-- RP on one jet (args.airframe), or the free pool when no jet is given.
	["give.rp"] = {
		testOnly = true,
		run = function(admin, args)
			local who, n = target(admin, args), amount(args)
			if not (who and n) then
				return false, "Usage: give.rp { amount, airframe? }"
			end
			local airframe = args.airframe
			local ok, err = DataService:Update(who, function(data)
				if type(airframe) == "string" then
					local entry = data.Aircraft[airframe]
					if not entry then
						return false, "That jet isn't researched or owned"
					end
					entry.RP += n
				else
					data.FreeRP += n
				end
				return true
			end)
			return ok == true, if ok then `+{n} RP` else err or "Save not loaded"
		end,
	},
	-- Researches and buys a jet (or every jet with airframe = "all") without spending anything.
	["unlock"] = {
		testOnly = true,
		run = function(admin, args)
			local who = target(admin, args)
			local which = args.airframe
			if not (who and type(which) == "string") then
				return false, "Usage: unlock { airframe | 'all' }"
			end
			local count = DataService:Update(who, function(data)
				local n = 0
				for _, node in TechTree.NODES do
					if which == "all" or node.Id == which then
						local entry = data.Aircraft[node.Id] or PlayerData.newAircraft(true)
						entry.Owned, entry.Researched = true, true
						data.Aircraft[node.Id] = entry
						n += 1
					end
				end
				return n
			end)
			return (count or 0) > 0, `Unlocked {count or 0} jet(s)`
		end,
	},
	["kick"] = {
		testOnly = false,
		run = function(admin, args)
			local who = target(admin, args)
			if not who or who == admin then
				return false, "Usage: kick { userId, reason? }"
			end
			who:Kick(if type(args.reason) == "string" then args.reason else "Removed by an admin")
			return true, `Kicked {who.Name}`
		end,
	},
}

function AdminService:Run(admin: Player, command: string, args: { [string]: any }?): (boolean, string)
	if not self:IsAdmin(admin) then
		Telemetry.event("AdminDenied", 1, { command = command }, admin)
		return false, "Not allowed"
	end
	local def = COMMANDS[command]
	if not def then
		return false, `Unknown command "{command}"`
	end
	if def.testOnly and not Environment.isTest() then
		return false, "Test environment only"
	end
	local ok, result, message = pcall(def.run, admin, args or {})
	Telemetry.event("AdminCommand", 1, { command = command, ok = ok and result }, admin)
	if not ok then
		return false, `Command failed: {result}`
	end
	return result, message
end

local function grantFullAccess(player: Player)
	if AdminService:IsOwner(player) then
		DataService:Update(player, Progression.unlockEverything)
		Telemetry.event("FullAccess", 1, {}, player)
	end
end

function AdminService:Init()
	Net.Server.handle("AdminCommand", function(player: Player, command: string, args: { [string]: any }?)
		return self:Run(player, command, args)
	end)
	DataService.ProfileLoaded:Connect(grantFullAccess)
end

function AdminService:Start()
	for _, player in Players:GetPlayers() do
		if DataService:IsLoaded(player) then
			grantFullAccess(player)
		end
	end
end

return AdminService
