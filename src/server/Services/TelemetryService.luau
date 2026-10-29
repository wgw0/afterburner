--!strict
-- What we learn from play (DEVELOPMENT.md §30, ANL-02/04). Everything goes through Lib/Telemetry.
--   Onboarding funnel (once per player, saved in data.Onboarding): 1 Joined, 2 Lesson 1 done (Basic flight),
--     3 Lesson 3 done (Guns), 4 First match finished, 5 First kill, 6 First research.
--   Progression: the highest tier a player has owned a jet of (path "Tier").
--   Balance (scored matches only: not training, the stress test or free flight). Each event sends two
--   fields; the value is 1 unless said:
--     Spawn          airframe, mode                    which jets get flown
--     Kill           airframe (the killer's), victim   kills per jet and who beats whom
--     ShotDown       airframe, cause                   deaths per jet and what caused them
--     AirframeResult airframe, mode; value 1 won / 0   win rate per jet
--     MissileFired   class, weapon                     fire rate per missile
--     MissileResult  class, weapon; value 1 hit / 0    hit rate per missile (Pk)
--   (Also elsewhere: MatchEnded, Death, QueueMatched, MatchFormed, AntiCheatStrike, Economy*.)
--   LessonCompleted(lessonId) from the client marks a lesson done (data.Lessons) on a training server.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AircraftData = require(Shared.AircraftData)
local Net = require(Shared.Net)
local ServerRole = require(Shared.ServerRole)
local WeaponData = require(Shared.WeaponData)

local Telemetry = require(ServerScriptService.Server.Lib.Telemetry)
local AircraftService = require(script.Parent.AircraftService)
local CombatService = require(script.Parent.CombatService)
local DataService = require(script.Parent.DataService)
local MatchService = require(script.Parent.MatchService)
local MissileService = require(script.Parent.MissileService)
local ProgressionService = require(script.Parent.ProgressionService)

local ONBOARDING = { "Joined", "Lesson1", "Lesson3", "FirstMatch", "FirstKill", "FirstResearch" }
local LESSONS = { Flight = true, Energy = true, Guns = true, Missiles = true, Defend = true, Fight = true }
local QUIET_CAUSES = { Respawn = true, PilotLeft = true, Despawn = true }

local TelemetryService = {
	Priority = 78, -- after ProgressionService and ChallengeService
}

-- Players' current jet (for match results) and whether they flew in this match
local flying: { [Player]: string } = {}
local flew: { [Player]: boolean } = {}

local function counting(): boolean
	local mode = MatchService:GetMode()
	return mode.Scored and mode.Id ~= "Stress" and not ServerRole.isTraining()
end

local function live(): boolean
	return counting() and MatchService:GetState() == "InProgress"
end

local function missileClass(weaponId: string?): string
	local missile = weaponId and WeaponData.getMissile(weaponId) :: any
	return if missile then missile.Class else "Gun"
end

-- Logs onboarding step `name` once per player.
local function onboarding(player: Player, name: string)
	local step = table.find(ONBOARDING, name)
	if not step then
		return
	end
	local fresh = false
	DataService:Update(player, function(data)
		if not data.Onboarding[name] then
			data.Onboarding[name] = true
			fresh = true
		end
	end)
	if fresh then
		Telemetry.onboarding(player, step, name)
	end
end

-- The highest tier the player has owned a jet of, logged when it goes up.
local function checkTier(player: Player)
	local top = 0
	local data = DataService:GetData(player)
	if not data then
		return
	end
	for id, entry in data.Aircraft do
		local airframe = AircraftData.get(id) :: any
		if entry.Owned and airframe and airframe.Tier > top then
			top = airframe.Tier
		end
	end
	if top > (data.TopTier or 0) then
		DataService:Update(player, function(d)
			d.TopTier = top
		end)
		Telemetry.progression(player, "Tier", top, `Tier {top}`)
	end
end

local function airframeOf(jet: any): string
	return jet and jet.airframeId or "?"
end

function TelemetryService:Init()
	Net.Server.on("LessonCompleted", function(player: Player, lessonId: string)
		if not (LESSONS[lessonId] and ServerRole.isTraining()) then
			return
		end
		DataService:Update(player, function(data)
			data.Lessons[lessonId] = true
		end)
		Telemetry.event("LessonCompleted", 1, { lesson = lessonId }, player)
		if lessonId == "Flight" then
			onboarding(player, "Lesson1")
		elseif lessonId == "Guns" then
			onboarding(player, "Lesson3")
		end
	end)

	DataService.ProfileLoaded:Connect(function(player)
		onboarding(player, "Joined")
		checkTier(player)
	end)

	ProgressionService.IntentDone:Connect(function(player, action)
		if action == "Research" then
			onboarding(player, "FirstResearch")
		end
		if action == "Research" or action == "BuyAircraft" then
			checkTier(player)
		end
	end)

	AircraftService.JetSpawned:Connect(function(jet)
		local player = jet.pilot
		if not player then
			return
		end
		flying[player] = jet.airframeId
		if counting() then
			flew[player] = true
			Telemetry.event("Spawn", 1, { airframe = jet.airframeId, mode = MatchService:GetMode().Id }, player, {
				"airframe",
				"mode",
			})
		end
	end)

	CombatService.Kill:Connect(function(victimJet, credit, cause)
		if not live() then
			return
		end
		local killer = credit.killer
		local killerJet = nil
		if killer then
			for _, jet in AircraftService:GetJets() do
				if jet.identity == killer then
					killerJet = jet
				end
			end
		end
		local isPlayer = typeof(killer) == "Instance" and killer:IsA("Player")
		if killer and killer ~= victimJet.identity then
			Telemetry.event(
				"Kill",
				1,
				{ airframe = airframeOf(killerJet), victim = airframeOf(victimJet), weapon = credit.weapon },
				if isPlayer then killer else victimJet.pilot,
				{ "airframe", "victim" }
			)
			if isPlayer then
				onboarding(killer, "FirstKill")
			end
		end
		if not (QUIET_CAUSES[cause] and killer == nil) then
			Telemetry.event(
				"ShotDown",
				1,
				{ airframe = airframeOf(victimJet), cause = cause },
				victimJet.pilot,
				{ "airframe", "cause" }
			)
		end
	end)

	MissileService.MissileLaunched:Connect(function(jet, weaponId: string)
		if live() then
			Telemetry.event(
				"MissileFired",
				1,
				{ class = missileClass(weaponId), weapon = weaponId },
				jet.pilot,
				{ "class", "weapon" }
			)
		end
	end)
	MissileService.MissileEnded:Connect(function(owner, weaponId: string, hit: boolean)
		if live() then
			local player = if typeof(owner) == "Instance" and owner:IsA("Player") then owner else nil
			Telemetry.event(
				"MissileResult",
				if hit then 1 else 0,
				{ class = missileClass(weaponId), weapon = weaponId },
				player,
				{ "class", "weapon" }
			)
		end
	end)

	MatchService.MatchStarted:Connect(function()
		table.clear(flew)
		for _, player in Players:GetPlayers() do
			if AircraftService:GetJet(player) then
				flew[player] = true
			end
		end
	end)
	MatchService.MatchEnded:Connect(function(ranking, _reason, winnerTeam: string?)
		if not counting() then
			return
		end
		local mode = MatchService:GetMode().Id
		local winner = ranking[1]
		for _, player in Players:GetPlayers() do
			if flew[player] and flying[player] then
				local won = if winnerTeam
					then player:GetAttribute("Team") == winnerTeam
					else winner ~= nil and not winner.isAI and winner.userId == player.UserId
				Telemetry.event(
					"AirframeResult",
					if won then 1 else 0,
					{ airframe = flying[player], mode = mode },
					player,
					{ "airframe", "mode" }
				)
				onboarding(player, "FirstMatch")
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		flying[player] = nil
		flew[player] = nil
	end)
end

return TelemetryService
