--!strict
-- Challenges, achievements and badges (DEVELOPMENT.md §26, LIV-01/02).
-- Watches scored matches (not training servers, not the stress test) and turns what happens into events:
--   Kill (weapon class, tier of the jet flown), Assist, MissileDefeated (missiles fired at you that missed),
--   Capture (Air Superiority), and at the end MatchFinished (survived?) and Win.
-- Each event goes through Challenges.record (completed challenges pay their Credits and XP at once) and
-- Achievements.earned (new achievements are saved and their Roblox badge awarded, with retries; a badge
-- that couldn't be awarded, or had no id yet, is tried again the next time the player joins).
-- The player hears about each one through ChallengeNotice (a toast on their screen).
--   RerollChallenge(index) swaps one unfinished daily challenge, once a day.

local BadgeService = game:GetService("BadgeService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Achievements = require(Shared.Achievements)
local BridgeRun = require(Shared.BridgeRun)
local AircraftData = require(Shared.AircraftData)
local Badges = require(Shared.Config.Badges)
local Challenges = require(Shared.Challenges)
local Net = require(Shared.Net)
local Perks = require(Shared.Perks)
local Progression = require(Shared.Progression)
local Streak = require(Shared.Streak)
local ServerRole = require(Shared.ServerRole)
local WeaponData = require(Shared.WeaponData)

local Telemetry = require(ServerScriptService.Server.Lib.Telemetry)
local AircraftService = require(script.Parent.AircraftService)
local CombatService = require(script.Parent.CombatService)
local DataService = require(script.Parent.DataService)
local MatchService = require(script.Parent.MatchService)
local MissileService = require(script.Parent.MissileService)

local QUIET_CAUSES = { Respawn = true, PilotLeft = true, Despawn = true }
local BADGE_TRIES = 3
local BRIDGE_XP = 100 -- flying under a bridge (BridgeRun)
local BRIDGE_COOLDOWN = 60 -- seconds before the next one pays
local BRIDGE_CHECK = 0.1 -- seconds between checks

local ChallengeService = {
	Priority = 75, -- after ProgressionService
}

-- This match, per player: the jet flown now, kills and missiles defeated this life, the last kill's time,
-- kills, assists and deaths this match, whether they were hit, whether they flew
type Session = {
	airframe: string?,
	lifeKills: number,
	lifeDefeats: number,
	lastKillAt: number?,
	kills: number,
	assists: number,
	deaths: number,
	hit: boolean,
	flew: boolean,
}
local sessions: { [Player]: Session } = {}

local function now(): number
	return os.time()
end

local function sessionOf(player: Player): Session
	local session = sessions[player]
	if not session then
		session = {
			airframe = nil,
			lifeKills = 0,
			lifeDefeats = 0,
			lastKillAt = nil,
			kills = 0,
			assists = 0,
			deaths = 0,
			hit = false,
			flew = false,
		}
		sessions[player] = session
	end
	return session
end

-- Only scored matches count: not training, not the stress test, not free flight.
local function counting(): boolean
	local mode = MatchService:GetMode()
	return mode.Scored and mode.Id ~= "Stress" and not ServerRole.isTraining()
end

local function live(): boolean
	return counting() and MatchService:GetState() == "InProgress"
end

local function tierOf(airframeId: string?): number?
	local airframe = airframeId and AircraftData.get(airframeId) :: any
	return airframe and airframe.Tier
end

-- Lifetime totals for the career achievements (Veteran, Centurion, Collector, High Flyer).
local function careerEvent(data: { [string]: any }): Achievements.Event
	local owned = 0
	for _, entry in data.Aircraft do
		if entry.Owned then
			owned += 1
		end
	end
	return {
		kind = "Career",
		matches = data.Stats.Matches,
		totalKills = data.Stats.Kills + data.Stats.AIKills,
		ownedJets = owned,
		level = data.PilotLevel,
	}
end

local function missileClass(weaponId: string?): string?
	local missile = weaponId and WeaponData.getMissile(weaponId) :: any
	return missile and missile.Class
end

local function weaponClass(weaponId: string?): string
	local missile = weaponId and WeaponData.getMissile(weaponId) :: any
	return Challenges.weaponClass(missile and missile.Class)
end

-- Awards an achievement's badge (if it has one) and marks it awarded.
local function awardBadge(player: Player, id: string)
	local badgeId = Badges.idFor(id)
	if not badgeId then
		return
	end
	task.spawn(function()
		for attempt = 1, BADGE_TRIES do
			local ok, err = pcall(function()
				BadgeService:AwardBadge(player.UserId, badgeId)
			end)
			if ok then
				DataService:Update(player, function(data)
					local entry = data.Achievements[id]
					if entry then
						entry.Badge = true
					end
				end)
				return
			end
			warn(`[Challenges] badge {id} for {player.Name}, try {attempt}: {err}`)
			task.wait(attempt * 3)
		end
	end)
end

-- Bridge runs: each jet's last position in each bridge's frame, and when each player was last paid
local bridgeSeen: { [number]: { [Model]: Vector3 } } = {}
local bridgePaidAt: { [Player]: number } = {}

-- Records events for a player: challenge progress and rewards, achievements, then tells them.
-- `extra` is added to a new achievement's toast (e.g. the XP that came with it).
local function record(
	player: Player,
	challengeEvents: { Challenges.Event },
	achievementEvents: { Achievements.Event },
	extra: string?
)
	local notices = {}
	local newAchievements = {}
	DataService:Update(player, function(data)
		local unix = now()
		for _, event in challengeEvents do
			for _, def in Challenges.record(data.Challenges, event, unix) do
				data.Credits += def.credits
				Progression.addXP(data, def.xp)
				local weekly = table.find(Challenges.WEEKLY_POOL, def) ~= nil
				table.insert(notices, {
					kind = if weekly then "Weekly challenge" else "Daily challenge",
					text = def.text,
					credits = def.credits,
					xp = def.xp,
				})
				Telemetry.event("ChallengeCompleted", def.credits, { id = def.id }, player)
			end
		end
		for _, event in achievementEvents do
			for _, id in Achievements.earned(event) do
				if not data.Achievements[id] then
					data.Achievements[id] = { At = unix, Badge = false }
					table.insert(newAchievements, id)
					local def = Achievements.get(id) :: Achievements.Def
					table.insert(notices, {
						kind = "Achievement",
						heading = if def.secret then "SECRET ACHIEVEMENT" else nil,
						text = def.name,
						detail = if extra then `{def.text}  ·  {extra}` else def.text,
						rarity = def.rarity,
					})
					Telemetry.event("AchievementEarned", 1, { id = id }, player)
				end
			end
		end
	end)
	for _, notice in notices do
		Net.Server.fire("ChallengeNotice", player, notice)
	end
	for _, id in newAchievements do
		awardBadge(player, id)
	end
end

function ChallengeService:Init()
	-- The daily login reward (LIV-03): claims today's day of the streak and pays it.
	Net.Server.handle("ClaimDailyReward", function(player: Player)
		local result = nil
		DataService:Update(player, function(data)
			local reward, count = Streak.claim(data.Streak, os.time() // 86400)
			if reward then
				data.Credits += reward.credits
				data.FreeRP += reward.freeRP
				if reward.title then
					data.Titles[reward.title] = true
				end
				result = { count = count, credits = reward.credits, freeRP = reward.freeRP, title = reward.title }
			end
		end)
		if result then
			Telemetry.event("DailyReward", result.count, { credits = result.credits }, player)
		end
		return result
	end)
	Net.Server.handle("RerollChallenge", function(player: Player, index: number)
		local ok, err = DataService:Update(player, function(data)
			return Challenges.reroll(data.Challenges, index, now(), Perks.rerolls(data, Challenges.REROLLS_PER_DAY))
		end)
		if ok then
			Telemetry.event("ChallengeRerolled", 1, {}, player)
		end
		return ok == true, err
	end)

	AircraftService.JetSpawned:Connect(function(jet)
		local player = jet.pilot
		if not player then
			return
		end
		local session = sessionOf(player)
		session.airframe = jet.airframeId
		session.lifeKills = 0
		session.lifeDefeats = 0
		if counting() then
			session.flew = true
			record(player, {}, { { kind = "Spawn", airframe = jet.airframeId } })
		end
	end)

	CombatService.JetDamaged:Connect(function(target, _component, _amount, attacker)
		local player = target.pilot
		if player and attacker ~= nil and attacker ~= player and live() then
			sessionOf(player).hit = true
		end
	end)

	CombatService.Kill:Connect(function(victimJet, credit, cause)
		if not live() then
			return
		end
		local killer = credit.killer
		local victim = victimJet.pilot
		if typeof(killer) == "Instance" and killer:IsA("Player") and killer ~= victim then
			local session = sessionOf(killer)
			session.lifeKills += 1
			session.kills += 1
			local sinceLastKill = if session.lastKillAt then os.clock() - session.lastKillAt else nil
			session.lastKillAt = os.clock()
			local weapon = weaponClass(credit.weapon)
			local tier = tierOf(session.airframe)
			record(killer, { { kind = "Kill", weapon = weapon, tier = tier, mode = MatchService:GetMode().Id } }, {
				{
					kind = "Kill",
					weapon = weapon,
					missileClass = missileClass(credit.weapon),
					lifeKills = session.lifeKills,
					sinceLastKill = sinceLastKill,
				},
			})
		end
		for _, helper in credit.assists or {} do
			if typeof(helper) == "Instance" and helper:IsA("Player") then
				local session = sessionOf(helper)
				session.assists += 1
				record(helper, { { kind = "Assist", tier = tierOf(session.airframe) } }, {})
			end
		end
		if victim and not (QUIET_CAUSES[cause] and killer == nil) then
			sessionOf(victim).deaths += 1
		end
	end)

	MissileService.MissileDefeated:Connect(function(targetJet, _owner, weaponId: string)
		local player = targetJet.pilot
		if player and live() then
			local weapon = weaponClass(weaponId)
			local session = sessionOf(player)
			session.lifeDefeats += 1
			record(
				player,
				{ { kind = "MissileDefeated", weapon = weapon } },
				{ { kind = "MissileDefeated", weapon = weapon, lifeDefeats = session.lifeDefeats } }
			)
		end
	end)

	MatchService.ZoneCaptured:Connect(function(identity)
		if typeof(identity) == "Instance" and identity:IsA("Player") and live() then
			record(identity, { { kind = "Capture", mode = MatchService:GetMode().Id } }, { { kind = "Capture" } })
		end
	end)

	MatchService.MatchStarted:Connect(function()
		for _, session in sessions do
			session.deaths, session.hit, session.flew, session.lifeKills = 0, false, false, 0
			session.kills, session.assists, session.lifeDefeats, session.lastKillAt = 0, 0, 0, nil
		end
		for _, player in Players:GetPlayers() do
			-- Already in the air as the match starts (a training repeat): they're flying it
			if AircraftService:GetJet(player) then
				sessionOf(player).flew = true
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
			local session = sessions[player]
			if session and session.flew then
				local won = if winnerTeam
					then player:GetAttribute("Team") == winnerTeam
					else winner ~= nil and not winner.isAI and winner.userId == player.UserId
				-- Lifetime stats are counted with the match rewards (Progression.applyRewards)
				local data = DataService:GetData(player)
				local tier = tierOf(session.airframe)
				local survived = session.deaths == 0
				local events: { Challenges.Event } =
					{ { kind = "MatchFinished", survived = survived, mode = mode, tier = tier } }
				local finished: Achievements.Event = if data then careerEvent(data) else { kind = "MatchFinished" }
				finished.kind = "MatchFinished"
				finished.survived = survived
				finished.matchKills = session.kills
				finished.matchAssists = session.assists
				finished.firstFreeForAll = mode == "Dogfight"
					and winner ~= nil
					and not winner.isAI
					and winner.userId == player.UserId
				local earned: { Achievements.Event } = { finished }
				if won then
					table.insert(events, { kind = "Win", mode = mode, tier = tier })
					table.insert(earned, { kind = "Win", hitThisMatch = session.hit })
				end
				record(player, events, earned)
			end
		end
	end)

	-- On joining: today's challenges, achievements already earned by the lifetime stats (for pilots who
	-- played before achievements existed), and any badges still owed
	DataService.ProfileLoaded:Connect(function(player, data)
		DataService:Update(player, function(d)
			Challenges.refresh(d.Challenges, now())
		end)
		local stats = data.Stats
		local past: { Achievements.Event } = { careerEvent(data) }
		if stats.Kills + stats.AIKills > 0 then
			table.insert(past, { kind = "Kill", lifeKills = 1 })
		end
		if stats.Wins > 0 then
			table.insert(past, { kind = "Win" })
		end
		task.delay(6, function() -- after the client is listening, so the toasts arrive
			if player.Parent then
				record(player, {}, past)
			end
		end)
		for id, entry in data.Achievements do
			if not entry.Badge then
				awardBadge(player, id)
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		sessions[player] = nil
		bridgePaidAt[player] = nil
	end)
end

-- Flew under a bridge: the secret achievement (anywhere you fly) and a little XP (in scored matches, once a
-- minute). The first time, the achievement's toast carries the XP; after that a small UNDER THE BRIDGE one.
local function bridgeRun(player: Player)
	local data = DataService:GetData(player)
	if not data then
		return
	end
	local firstTime = data.Achievements.ThreadTheNeedle == nil
	local now = os.clock()
	local paid = live() and (not bridgePaidAt[player] or now - bridgePaidAt[player] >= BRIDGE_COOLDOWN)
	if paid then
		bridgePaidAt[player] = now
		DataService:Update(player, function(d)
			Progression.addXP(d, BRIDGE_XP)
		end)
		Telemetry.event("BridgeRun", 1, {}, player)
		if not firstTime then
			Net.Server.fire("ChallengeNotice", player, {
				kind = "Bonus",
				heading = "UNDER THE BRIDGE",
				text = "Threaded the Severn Bridge",
				xp = BRIDGE_XP,
			})
		end
	end
	if firstTime then
		record(player, {}, { { kind = "BridgeRun" } }, if paid then `+{BRIDGE_XP} XP` else nil)
	end
end

-- Watches players' jets near the bridges for a pass under a deck (BridgeRun.passedUnder).
local function checkBridges()
	local map = workspace:FindFirstChild("Map")
	local folder = map and map:FindFirstChild("Bridges")
	if not folder then
		return
	end
	for id, jet in AircraftService:GetJets() do
		local player = jet.pilot
		if player then
			local seen = bridgeSeen[id] or {}
			bridgeSeen[id] = seen
			for _, bridge in folder:GetChildren() do
				if bridge:IsA("Model") then
					local here = bridge:GetPivot():PointToObjectSpace(jet.root.Position)
					local before = seen[bridge]
					if before and BridgeRun.passedUnder(before, here) then
						bridgeRun(player)
					end
					-- Only remember jets near the bridge
					seen[bridge] = if math.abs(here.X) < 600 and math.abs(here.Z) < 1100 then here else nil
				end
			end
		end
	end
end

function ChallengeService:Start()
	local sinceBridgeCheck = 0
	RunService.Heartbeat:Connect(function(dt)
		sinceBridgeCheck += dt
		if sinceBridgeCheck >= BRIDGE_CHECK then
			sinceBridgeCheck = 0
			checkBridges()
		end
	end)
	AircraftService.JetDestroyed:Connect(function(jet)
		bridgeSeen[jet.id] = nil
	end)
	-- A new UTC day (or week) while playing: new challenges
	task.spawn(function()
		while true do
			task.wait(60)
			local unix = now()
			for _, player in Players:GetPlayers() do
				local data = DataService:GetData(player)
				if
					data
					and (data.Challenges.Day ~= Challenges.day(unix) or data.Challenges.Week ~= Challenges.week(unix))
				then
					DataService:Update(player, function(d)
						Challenges.refresh(d.Challenges, unix)
					end)
				end
			end
		end
	end)
end

return ChallengeService
