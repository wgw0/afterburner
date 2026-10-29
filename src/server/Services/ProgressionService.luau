--!strict
-- Progression (DEVELOPMENT.md §23, PRG-01–05, ANL-03). Server side only: the client sends intents.
--   During a scored match it records each player's events (kills with the victim and the jet flown,
--   assists, missiles defeated), whether they're still flying, and when they last touched the controls.
--   At the end of the match the events become rewards (Progression.matchRewards: tier multipliers, win
--   and first-win bonuses, anti-farming) and are saved; the player gets a MatchRewards breakdown.
--   Leaving mid-match still saves the rewards earned so far (DataService.BeforeRelease).
--   Research / buy / modules / lineup / settings arrive as remotes and go through the Progression rules.
--   Spawning is limited to jets in your lineup; fitted modules ride on the jet (AircraftService.modulesFor).
--   Training servers (ServerRole): any jet, owned or not, and no rewards at all (the results show why).
--   Economy events (sources and sinks) go to analytics.

local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AircraftData = require(Shared.AircraftData)
local Economy = require(Shared.Config.Economy)
local Net = require(Shared.Net)
local Progression = require(Shared.Progression)
local ServerRole = require(Shared.ServerRole)
local Settings = require(Shared.Config.Settings)
local Telemetry = require(ServerScriptService.Server.Lib.Telemetry)

local AircraftService = require(script.Parent.AircraftService)
local CombatService = require(script.Parent.CombatService)
local DataService = require(script.Parent.DataService)
local MatchService = require(script.Parent.MatchService)
local MissileService = require(script.Parent.MissileService)

local ProgressionService = {
	Priority = 70, -- after MatchService, so the spawn gate can wrap its own
}

type Tally = {
	events: { Progression.MatchEvent },
	lastAirframe: string?,
	alive: boolean,
	lastActive: number,
	lastSample: string,
}

local tallies: { [Player]: Tally } = {}

local function scoredMatchLive(): boolean
	return MatchService:GetState() == "InProgress" and MatchService:GetMode().Scored
end

local function tallyFor(player: Player): Tally
	local tally = tallies[player]
	if not tally then
		tally = { events = {}, lastAirframe = nil, alive = false, lastActive = os.clock(), lastSample = "" }
		tallies[player] = tally
	end
	return tally
end

local function victimKey(identity: any): (string, boolean)
	if typeof(identity) == "Instance" and identity:IsA("Player") then
		return `u{identity.UserId}`, false
	end
	return `ai:{identity and identity.Name or "?"}`, true
end

-- Economy analytics (ANL-03): every source and sink of Credits.
local function economyEvent(
	player: Player,
	flow: "Source" | "Sink",
	amount: number,
	balance: number,
	kind: string,
	sku: string
)
	if amount <= 0 then
		return
	end
	pcall(function()
		local flowType = if flow == "Source"
			then Enum.AnalyticsEconomyFlowType.Source
			else Enum.AnalyticsEconomyFlowType.Sink
		AnalyticsService:LogEconomyEvent(player, flowType, "Credits", amount, balance, kind, sku)
	end)
	Telemetry.event(`Economy{flow}`, amount, { kind = kind, item = sku }, player)
end

-- Builds a match summary for a player and saves the rewards. Returns the reward payload (or nil).
local function award(player: Player, data: { [string]: any }, won: boolean, push: boolean): { [string]: any }?
	local tally = tallies[player]
	if not (tally and tally.lastAirframe) then
		return nil
	end
	local summary: Progression.MatchSummary = {
		Events = tally.events,
		LastAirframe = tally.lastAirframe,
		Survived = tally.alive,
		Won = won,
		Afk = os.clock() - tally.lastActive > Economy.AFK_SECONDS,
		Day = os.time() // 86400,
	}
	local rewards = Progression.matchRewards(summary, data.LastWinDay)
	local levels = 0
	local function apply(d: { [string]: any })
		levels = Progression.applyRewards(d, rewards, summary)
	end
	if push then
		DataService:Update(player, apply)
	else
		apply(data) -- the session is being released; DataService saves it
	end
	tallies[player] = nil
	economyEvent(player, "Source", rewards.Credits, data.Credits, "MatchReward", "Match")
	Telemetry.event("MatchRewards", rewards.XP, { credits = rewards.Credits, afk = summary.Afk, won = won }, player)
	return {
		XP = rewards.XP,
		Credits = rewards.Credits,
		RP = rewards.RP,
		FreeRP = rewards.FreeRP,
		Lines = rewards.Lines,
		FirstWin = rewards.FirstWin,
		LevelsGained = levels,
		Level = data.PilotLevel,
		Afk = summary.Afk,
	}
end

-- Can this player fly this jet right now? (owned and in the lineup)
function ProgressionService:CanFly(player: Player, airframeId: string): (boolean, string?)
	local data = DataService:GetData(player)
	if not data then
		return false, "Your save is still loading"
	end
	if ServerRole.isTraining() then
		return AircraftData.get(airframeId) ~= nil, "Unknown jet" -- try anything, earn nothing
	end
	local entry = data.Aircraft[airframeId]
	if not (entry and entry.Owned) then
		return false, "You don't own that jet"
	end
	if not table.find(data.Lineup, airframeId) then
		return false, "That jet isn't in your lineup"
	end
	return true, nil
end

local function handleIntent(
	player: Player,
	action: string,
	fn: (data: { [string]: any }) -> (boolean, string?),
	spendsCredits: boolean,
	item: string
): (boolean, string?)
	local before = DataService:GetData(player)
	local creditsBefore = before and before.Credits or 0
	local ok, err = DataService:Update(player, fn)
	if ok then
		local data = DataService:GetData(player)
		if data and spendsCredits then
			economyEvent(player, "Sink", creditsBefore - data.Credits, data.Credits, action, item)
		end
		Telemetry.event(action, 1, { item = item }, player)
	end
	return ok == true, err
end

function ProgressionService:Init()
	Net.Server.handle("ResearchAircraft", function(player: Player, id: string)
		return handleIntent(player, "Research", function(data)
			return Progression.research(data, id)
		end, false, id)
	end)
	Net.Server.handle("BuyAircraft", function(player: Player, id: string)
		return handleIntent(player, "BuyAircraft", function(data)
			return Progression.buy(data, id)
		end, true, id)
	end)
	Net.Server.handle("BuyModule", function(player: Player, airframeId: string, moduleId: string)
		return handleIntent(player, "BuyModule", function(data)
			return Progression.buyModule(data, airframeId, moduleId)
		end, true, `{airframeId}:{moduleId}`)
	end)
	Net.Server.handle("SetModuleFitted", function(player: Player, airframeId: string, moduleId: string, fitted: boolean)
		return handleIntent(player, if fitted then "FitModule" else "UnfitModule", function(data)
			return Progression.setModuleFitted(data, airframeId, moduleId, fitted)
		end, false, `{airframeId}:{moduleId}`)
	end)
	Net.Server.handle("BuySkin", function(player: Player, airframeId: string, skinId: string)
		return handleIntent(player, "BuySkin", function(data)
			return Progression.buySkin(data, airframeId, skinId)
		end, true, `{airframeId}:{skinId}`)
	end)
	Net.Server.handle("SetSkin", function(player: Player, airframeId: string, skinId: string)
		return handleIntent(player, "SetSkin", function(data)
			return Progression.setSkin(data, airframeId, skinId)
		end, false, `{airframeId}:{skinId}`)
	end)
	Net.Server.handle("SetLineup", function(player: Player, ids: { any })
		return handleIntent(player, "SetLineup", function(data)
			return Progression.setLineup(data, ids)
		end, false, "Lineup")
	end)
	Net.Server.on("SettingsUpdate", function(player: Player, changes: { [any]: any })
		DataService:Update(player, function(data)
			local merged = table.clone(data.Settings)
			for key, value in changes do
				if type(key) == "string" and Settings.valid(key, value) then
					merged[key] = value
				end
			end
			data.Settings = Settings.sanitize(merged)
		end)
	end)
end

function ProgressionService:Start()
	-- Spawning: only jets you own and have in your lineup; modules ride on the jet
	local matchGate = AircraftService.spawnGate
	AircraftService.spawnGate = function(player: Player, airframeId: string): (boolean, CFrame?)
		local ok, reason = self:CanFly(player, airframeId)
		if not ok then
			Net.Server.fire("SpawnRefused", player, reason or "You can't fly that jet")
			return false, nil
		end
		if matchGate then
			local allowed, at, why = (matchGate :: any)(player, airframeId)
			if not allowed and why then
				Net.Server.fire("SpawnRefused", player, why)
			end
			return allowed, at
		end
		return true, nil
	end
	AircraftService.modulesFor = function(player: Player, airframeId: string): string
		local data = DataService:GetData(player)
		local entry = data and data.Aircraft[airframeId]
		return Progression.encodeModules(entry and entry.Modules)
	end
	AircraftService.skinFor = function(player: Player, airframeId: string): string?
		local data = DataService:GetData(player)
		return data and Progression.skinFor(data, airframeId)
	end

	-- Match events
	MatchService.MatchStarted:Connect(function()
		table.clear(tallies)
		for _, jet in AircraftService:GetJets() do
			if jet.pilot then
				local tally = tallyFor(jet.pilot)
				tally.lastAirframe = jet.airframeId
				tally.alive = true
			end
		end
	end)
	AircraftService.JetSpawned:Connect(function(jet)
		if jet.pilot then
			local tally = tallyFor(jet.pilot)
			tally.lastAirframe = jet.airframeId
			tally.alive = true
			tally.lastActive = os.clock()
		end
	end)
	AircraftService.JetDestroyed:Connect(function(jet, cause)
		-- The end-of-match clear-out isn't a death
		if jet.pilot and not (cause == "Despawn" and MatchService:GetState() == "Results") then
			tallyFor(jet.pilot).alive = false
		end
	end)
	CombatService.Kill:Connect(function(victimJet, credit)
		if not scoredMatchLive() then
			return
		end
		local victim, victimAI = victimKey(victimJet.identity)
		local killer = credit.killer
		if typeof(killer) == "Instance" and killer:IsA("Player") and killer ~= victimJet.pilot then
			local tally = tallyFor(killer)
			if tally.lastAirframe then
				table.insert(
					tally.events,
					{ Kind = "Kill", Airframe = tally.lastAirframe, Victim = victim, VictimAI = victimAI }
				)
			end
		end
		for _, helper in credit.assists or {} do
			if typeof(helper) == "Instance" and helper:IsA("Player") then
				local tally = tallyFor(helper)
				if tally.lastAirframe then
					table.insert(tally.events, { Kind = "Assist", Airframe = tally.lastAirframe })
				end
			end
		end
	end)
	MissileService.MissileDefeated:Connect(function(targetJet)
		if scoredMatchLive() and targetJet.pilot then
			table.insert(
				tallyFor(targetJet.pilot).events,
				{ Kind = "MissileDefeated", Airframe = targetJet.airframeId }
			)
		end
	end)
	MatchService.MatchEnded:Connect(function(ranking, _reason, winnerTeam: string?)
		local winner = ranking[1]
		for _, player in Players:GetPlayers() do
			local data = DataService:GetData(player)
			if data and ServerRole.isTraining() then
				-- Training: nothing is earned, but the results screen still gets a payload to say so
				tallies[player] = nil
				Net.Server.fire("MatchRewards", player, {
					XP = 0,
					Credits = 0,
					RP = {},
					FreeRP = 0,
					Lines = { { Label = "Training: no rewards", XP = 0, RP = 0, Credits = 0 } },
					FirstWin = false,
					LevelsGained = 0,
					Level = data.PilotLevel,
					Afk = false,
					Training = true,
				})
			elseif data then
				-- Team modes: everyone on the winning team won; otherwise the top of the ranking
				local won = if winnerTeam
					then player:GetAttribute("Team") == winnerTeam
					else winner ~= nil and not winner.isAI and winner.userId == player.UserId
				local payload = award(player, data, won, true)
				if payload then
					Net.Server.fire("MatchRewards", player, payload)
				end
			end
		end
	end)
	DataService.BeforeRelease:Connect(function(player, data)
		if scoredMatchLive() and not ServerRole.isTraining() then
			award(player, data, false, false) -- leaving keeps what you'd earned
		end
		tallies[player] = nil
	end)

	-- Activity (AFK detection): any change in a pilot's throttle or G counts as input
	local timer = 0
	RunService.Heartbeat:Connect(function(dt)
		timer += dt
		if timer < 1 then
			return
		end
		timer = 0
		for _, jet in AircraftService:GetJets() do
			local tally = jet.pilot and tallies[jet.pilot]
			if tally then
				local sample = string.format(
					"%.2f|%.1f",
					(jet.model:GetAttribute("Throttle") :: number?) or 0,
					(jet.model:GetAttribute("GLoad") :: number?) or 1
				)
				if sample ~= tally.lastSample then
					tally.lastSample = sample
					tally.lastActive = os.clock()
				end
			end
		end
	end)
end

return ProgressionService
