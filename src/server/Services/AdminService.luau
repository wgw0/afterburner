--!strict
-- Admin commands (DEVELOPMENT.md §31.2, OPS-02; data commands DAT-05). Called through AdminCommand
-- (command, args) -> (ok, message). Every call is checked here; the client's debug panel is only a UI.
--   Admins: the place's creator (or group owner), anyone listed in ADMINS, and everyone in Studio.
--   Data-changing commands only run in the test environment; inspection, kicks and live config (config.*,
--   which exists to change live servers) work everywhere.
--   Owners (the creator, group owner or ADMINS; not everyone in Studio) also get full access to every
--   jet, module, skin and lineup slot, in test and live (Progression.unlockEverything).
-- Every command is logged to analytics.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AircraftData = require(Shared.AircraftData)
local Environment = require(Shared.Config.Environment)
local Passes = require(Shared.Config.Passes)
local Products = require(Shared.Config.Products)
local Shop = require(Shared.Shop)
local Mastery = require(Shared.Mastery)
local Net = require(Shared.Net)
local PlayerData = require(Shared.PlayerData)
local Progression = require(Shared.Progression)
local ServerRole = require(Shared.ServerRole)
local TechTree = require(Shared.TechTree)
local Version = require(Shared.Version)
local Telemetry = require(ServerScriptService.Server.Lib.Telemetry)

local ConfigService = require(script.Parent.ConfigService)
local DataService = require(script.Parent.DataService)
local MatchmakingService = require(script.Parent.MatchmakingService)
local PassService = require(script.Parent.PassService)
local ShopService = require(script.Parent.ShopService)
local SpinService = require(script.Parent.SpinService)
local ProgressionService = require(script.Parent.ProgressionService)
local ReportService = require(script.Parent.ReportService)

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
	-- Live config (OPS-01): change a value on every server of this experience, no update needed.
	-- config.set { key, value }, e.g. { key = "economy.xp", value = 2 } or { key = "br.F16A", value = 5 }
	["config.set"] = {
		testOnly = false,
		run = function(admin, args)
			if type(args.key) ~= "string" or args.value == nil then
				return false,
					"Usage: config.set { key, value } (keys: economy.xp / .credits / .rp, event, motd, br.<Jet>)"
			end
			return ConfigService:Set(admin, args.key, args.value)
		end,
	},
	["config.clear"] = {
		testOnly = false,
		run = function(admin, args)
			if type(args.key) ~= "string" then
				return false, "Usage: config.clear { key }"
			end
			return ConfigService:Clear(admin, args.key)
		end,
	},
	-- The overrides in force and the last changes (who, when, what)
	["config.show"] = {
		testOnly = false,
		run = function()
			return true,
				HttpService:JSONEncode({ overrides = ConfigService:Overrides(), recent = ConfigService:Audit(10) })
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
	-- This server's version and where it runs (REL-04: which servers are on which release during an update or
	-- rollback).
	["server.info"] = {
		testOnly = false,
		run = function(_admin, _args)
			return true,
				HttpService:JSONEncode({
					version = Version.NUMBER,
					saveVersion = PlayerData.VERSION,
					environment = Environment.get(),
					role = ServerRole.get(),
					placeId = game.PlaceId,
					placeVersion = game.PlaceVersion,
					jobId = game.JobId,
					uptime = math.round(workspace.DistributedGameTime),
					players = #Players:GetPlayers(),
				})
		end,
	},
	-- What this lobby's queue saw lately (MMK-06): wait times (median, 90th percentile, longest) of players
	-- matched and of those who gave up, and the matches formed while it ran the matchmaker.
	["matchmaking.stats"] = {
		testOnly = false,
		run = function(_admin, _args)
			return true, HttpService:JSONEncode(MatchmakingService:Stats())
		end,
	},
	-- The most-reported pilots (CMP-03): { count? = 10 } -> [{ userId, count }], most first.
	["reports.top"] = {
		testOnly = false,
		run = function(_admin, args)
			local count = math.clamp(tonumber(args.count) or 10, 1, 100)
			return true, HttpService:JSONEncode(ReportService:Top(count))
		end,
	},
	-- One pilot's reports with the anti-cheat data attached to each: { userId }.
	["reports.show"] = {
		testOnly = false,
		run = function(_admin, args)
			local userId = tonumber(args.userId)
			if not userId then
				return false, "Give a userId"
			end
			local record = ReportService:Get(userId)
			if not record then
				return true, "No reports for that pilot"
			end
			return true, HttpService:JSONEncode(record)
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
	-- Game passes (test servers): own a pass for this session without buying it, or lose it again
	["give.pass"] = {
		testOnly = true,
		run = function(admin, args)
			local who, name = target(admin, args), args.name
			if not (who and type(name) == "string" and Passes.LIST[name]) then
				return false, 'Usage: give.pass { name = "CustomCallsign" }'
			end
			PassService:Grant(who, name, true)
			return true, `{who.Name} owns {name} this session`
		end,
	},
	-- Developer products (test servers): grant one as if bought, through the real receipt path. A Tier
	-- Unlock takes the two jets as jets = { "F16A", "MiG29A" } (else the first two of the tier). The same
	-- purchase id twice shows a repeat receipt isn't granted again.
	["shop.grant"] = {
		testOnly = true,
		run = function(admin, args)
			local who, key = target(admin, args), args.key
			if not (who and type(key) == "string" and Products.LIST[key]) then
				return false, 'Usage: shop.grant { key = "Wings150" | "TierUnlock3", jets = {...}?, purchaseId = ...? }'
			end
			if type(args.jets) == "table" then
				local data = DataService:GetData(who)
				if not data then
					return false, "Save not loaded"
				end
				local tier, why = Shop.checkTierUnlockChoice(data, args.jets)
				if not tier then
					return false, why
				end
				DataService:Update(who, function(d)
					d.PendingTierUnlock = { Tier = tier, Jets = { args.jets[1], args.jets[2] } }
				end)
			end
			local purchaseId = if type(args.purchaseId) == "string"
				then args.purchaseId
				else `admin-{os.time()}-{math.random(1e6)}`
			local result, why = ShopService:Grant(who, purchaseId, key)
			return result ~= nil, if result then `{key}: {result} ({purchaseId})` else `Failed: {why}`
		end,
	},
	["take.pass"] = {
		testOnly = true,
		run = function(admin, args)
			local who, name = target(admin, args), args.name
			if not (who and type(name) == "string" and Passes.LIST[name]) then
				return false, 'Usage: take.pass { name = "CustomCallsign" }'
			end
			PassService:Grant(who, name, false)
			return true, `{who.Name} no longer owns {name} this session`
		end,
	},
	["take.credits"] = {
		testOnly = true,
		run = function(admin, args)
			local who, n = target(admin, args), amount(args)
			if not (who and n) then
				return false, "Usage: take.credits { amount }"
			end
			local ok = DataService:Update(who, function(data)
				data.Credits = math.max(data.Credits - n, 0)
				return true
			end)
			return ok == true, `-{n} Credits`
		end,
	},
	-- Free spins (test servers): bank some to try the spin (up to the bank's limit)
	["spin.give"] = {
		testOnly = true,
		run = function(admin, args)
			local who, n = target(admin, args), amount(args)
			if not (who and n) then
				return false, "Usage: spin.give { amount }"
			end
			local banked = SpinService:Give(who, n)
			return banked ~= nil, `{who.Name} has {banked} spins ready`
		end,
	},
	["take.wings"] = {
		testOnly = true,
		run = function(admin, args)
			local who, n = target(admin, args), amount(args)
			if not (who and n) then
				return false, "Usage: take.wings { amount }"
			end
			local ok = DataService:Update(who, function(data)
				data.Wings = math.max((data.Wings or 0) - n, 0)
				return true
			end)
			return ok == true, `-{n} Wings`
		end,
	},
	-- Mastery (PRG-07) testing: add kills in a jet as a match would (stars, Credits, title, toast)...
	["mastery.add"] = {
		testOnly = true,
		run = function(admin, args)
			local who, n = target(admin, args), amount({ amount = args.kills })
			local id = tostring(args.airframe)
			if not (who and n and AircraftData.get(id)) then
				return false, "Usage: mastery.add { airframe, kills }"
			end
			local gains = ProgressionService:AddMastery(who, id, n)
			local credits = 0
			for _, gain in gains do
				credits += gain.Credits
			end
			return true, `+{n} kills in {id}: {#gains} star(s), +{credits} Credits`
		end,
	},
	-- ...or set a jet's kill count directly (no Credits; the 5-star title goes if it drops below 5 stars)
	["mastery.set"] = {
		testOnly = true,
		run = function(admin, args)
			local who = target(admin, args)
			local kills = tonumber(args.kills)
			local id = tostring(args.airframe)
			if not (who and kills and kills >= 0 and AircraftData.get(id)) then
				return false, "Usage: mastery.set { airframe, kills }"
			end
			local ok = DataService:Update(who, function(data)
				local entry = data.Aircraft[id]
				if not entry then
					return false
				end
				entry.Mastery = math.floor(kills)
				if Mastery.stars(entry.Mastery) < #Mastery.STARS then
					local title = Mastery.titleId(id)
					data.Titles[title] = nil
					if data.Title == title then
						data.Title = ""
						who:SetAttribute("Title", "")
					end
				end
				return true
			end)
			return ok == true, if ok then `{id} mastery: {math.floor(kills)} kills` else "Jet not in the save"
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
