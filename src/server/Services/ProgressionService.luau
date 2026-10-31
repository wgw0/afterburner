--!strict
-- Progression (DEVELOPMENT.md §23, PRG-01–05, ANL-03). Server side only: the client sends intents.
--   During a scored match it records each player's events (kills with the victim and the jet flown,
--   assists, missiles defeated), whether they're still flying, and when they last touched the controls.
--   At the end of the match the events become rewards (Progression.matchRewards: tier multipliers, win
--   and first-win bonuses, anti-farming) and are saved; the player gets a MatchRewards breakdown.
--   Leaving mid-match still saves the rewards earned so far (DataService.BeforeRelease).
--   Research / buy / modules / lineup / settings arrive as remotes and go through the Progression rules.
--   Spawning is limited to jets in your lineup; fitted modules ride on the jet (AircraftService.modulesFor).
--   Training servers (ServerRole): any jet, owned or not. Vs AI pays pilot XP only (Progression.vsAIRewards);
--   Free Flight and lessons pay nothing (the results show why).
--   Economy events (sources and sinks) go to analytics.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AircraftData = require(Shared.AircraftData)
local Callsign = require(Shared.Callsign)
local Cosmetics = require(Shared.Cosmetics)
local CosmeticsCatalogue = require(Shared.Config.Cosmetics)
local Economy = require(Shared.Config.Economy)
local Net = require(Shared.Net)
local Progression = require(Shared.Progression)
local ServerRole = require(Shared.ServerRole)
local LevelRewards = require(Shared.Config.LevelRewards)
local LiveConfig = require(Shared.LiveConfig)
local Mastery = require(Shared.Mastery)
local Perks = require(Shared.Perks)
local Settings = require(Shared.Config.Settings)
local Signal = require(Shared.Util.Signal)
local Telemetry = require(ServerScriptService.Server.Lib.Telemetry)

local AircraftService = require(script.Parent.AircraftService)
local CombatService = require(script.Parent.CombatService)
local DataService = require(script.Parent.DataService)
local MatchService = require(script.Parent.MatchService)
local MissileService = require(script.Parent.MissileService)
local PassService = require(script.Parent.PassService)
local TextFilterService = require(script.Parent.TextFilterService)

local ProgressionService = {
	Priority = 70, -- after MatchService, so the spawn gate can wrap its own
	IntentDone = Signal.new(), -- (player, action, item) a research, purchase or change went through
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

-- Economy analytics (ANL-03): an item's SKU is the jet for modules and skins ("F16A:Engine2" -> "F16A"), so
-- they stay under the dashboard's 100 SKUs. The custom event keeps the full item.
local function skuOf(item: string): string
	return string.match(item, "^[^:]+") or item
end

-- Logs mastery stars reached (PRG-07) and, if the player is staying, shows a toast for each.
local function announceMastery(player: Player, data: { [string]: any }, gains: { Mastery.Gain }, toast: boolean)
	for _, gain in gains do
		Telemetry.event("MasteryStar", gain.Stars, { airframe = gain.Airframe }, player)
		Telemetry.economy(
			player,
			"Source",
			"Credits",
			gain.Credits,
			data.Credits,
			Telemetry.SOURCES.Mastery,
			gain.Airframe
		)
		if toast then
			local airframe = AircraftData.get(gain.Airframe) :: any
			Net.Server.fire("ChallengeNotice", player, {
				kind = "Mastery",
				heading = `MASTERY  {Mastery.starText(gain.Stars)}`,
				text = `{airframe and airframe.DisplayName or gain.Airframe}: {gain.Stars} star{if gain.Stars
						== 1
					then ""
					else "s"}`,
				credits = gain.Credits,
				detail = gain.Title and `Title: {LevelRewards.titleName(gain.Title)}` or nil,
			})
		end
	end
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
		Boost = {
			XP = LiveConfig.get("economy.xp"),
			Credits = LiveConfig.get("economy.credits"),
			RP = LiveConfig.get("economy.rp"),
			Label = if LiveConfig.get("event") ~= "" then LiveConfig.get("event") else "Event bonus",
		},
		Personal = Perks.boost(data, os.time()), -- VIP and boosters (SHP-03)
	}
	local rewards = Progression.matchRewards(summary, data.LastWinDay)
	local levels = 0
	local levelCredits = 0
	local mastery: { Mastery.Gain } = {}
	local function apply(d: { [string]: any })
		local before = d.Credits
		levels = Progression.applyRewards(d, rewards, summary)
		levelCredits = d.Credits - before - rewards.Credits -- levelling up pays too
		mastery = Mastery.record(d, summary.Events) -- stars from this match's kills (PRG-07)
	end
	if push then
		DataService:Update(player, apply)
	else
		apply(data) -- the session is being released; DataService saves it
	end
	tallies[player] = nil
	local balance = data.Credits
	for _, gain in mastery do
		balance -= gain.Credits
	end
	Telemetry.economy(
		player,
		"Source",
		"Credits",
		rewards.Credits,
		balance - levelCredits,
		Telemetry.SOURCES.MatchReward,
		"Match"
	)
	Telemetry.economy(player, "Source", "Credits", levelCredits, balance, Telemetry.SOURCES.LevelUp, "Level")
	Telemetry.event(
		"MatchRewards",
		rewards.XP,
		{ credits = rewards.Credits, afk = summary.Afk, won = won },
		player,
		{ "won", "afk" }
	)
	announceMastery(player, data, mastery, push)
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
		Mastery = mastery,
	}
end

-- Vs AI on a training server: pilot XP only. Returns the results screen's payload, or nil (never flew).
local function awardVsAI(player: Player, data: { [string]: any }, won: boolean): { [string]: any }?
	local tally = tallies[player]
	tallies[player] = nil
	if not (tally and tally.lastAirframe) then
		return nil
	end
	local afk = os.clock() - tally.lastActive > Economy.AFK_SECONDS
	local rewards = Progression.vsAIRewards({
		Events = tally.events,
		LastAirframe = tally.lastAirframe,
		Survived = tally.alive,
		Won = won,
		Afk = afk,
		Day = os.time() // 86400,
		Boost = {
			XP = LiveConfig.get("economy.xp"),
			Credits = 1,
			RP = 1,
			Label = if LiveConfig.get("event") ~= "" then LiveConfig.get("event") else "Event bonus",
		},
	})
	local levels = 0
	local levelCredits = 0
	DataService:Update(player, function(d)
		local before = d.Credits
		levels = Progression.addXP(d, rewards.XP)
		levelCredits = d.Credits - before
	end)
	Telemetry.economy(player, "Source", "Credits", levelCredits, data.Credits, Telemetry.SOURCES.LevelUp, "Level")
	Telemetry.event("VsAIRewards", rewards.XP, { won = won, afk = afk }, player)
	return {
		XP = rewards.XP,
		Credits = 0,
		RP = {},
		FreeRP = 0,
		Lines = rewards.Lines,
		FirstWin = false,
		LevelsGained = levels,
		Level = data.PilotLevel,
		Afk = afk,
		Training = true,
	}
end

-- Testing (admin mastery.add): counts `kills` kills in a jet as if from a match, paying any stars reached.
-- Returns the stars gained.
function ProgressionService:AddMastery(player: Player, airframeId: string, kills: number): { Mastery.Gain }
	local events = {}
	for i = 1, kills do
		table.insert(events, { Kind = "Kill", Airframe = airframeId, Victim = `test{i}`, VictimAI = true })
	end
	local gains = {}
	DataService:Update(player, function(data)
		gains = Mastery.record(data, events)
	end)
	local data = DataService:GetData(player)
	if data then
		announceMastery(player, data, gains, true)
	end
	return gains
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
		ProgressionService.IntentDone:Fire(player, action, item)
		local data = DataService:GetData(player)
		if data and spendsCredits then
			Telemetry.economy(
				player,
				"Sink",
				"Credits",
				creditsBefore - data.Credits,
				data.Credits,
				action,
				skuOf(item)
			)
		end
		Telemetry.event(action, 1, { item = item }, player)
	end
	return ok == true, err
end

-- What a player has equipped and still owns, { [kind] = id } (SHP-07).
local function looksFor(data: { [string]: any }): { [string]: string }
	local looks = {}
	for _, kind in CosmeticsCatalogue.KINDS do
		looks[kind] = Cosmetics.equipped(data, kind)
	end
	return looks
end

-- Re-dresses a player's jet if they're flying (after they buy or equip something).
local function redress(player: Player)
	local jet = AircraftService:GetJet(player)
	local data = DataService:GetData(player)
	if jet and data then
		AircraftService.dress(jet.model, looksFor(data))
	end
end

-- Shows a callsign (already filtered) as the player's name, on their jet too if they're flying ("" = username).
local function showCallsign(player: Player, callsign: string)
	player:SetAttribute("Callsign", callsign)
	local jet = AircraftService:GetJet(player)
	if jet then
		jet.name = Callsign.nameOf(player)
		jet.model:SetAttribute("PilotName", jet.name)
	end
end

-- Shows the saved callsign if the player owns the Custom Callsign pass and Roblox's filter (run again: it
-- changes over time) still passes it; otherwise their username. A callsign the filter now refuses is cleared.
local function refreshCallsign(player: Player)
	local saved = DataService:Update(player, function(data)
		return data.Callsign
	end)
	if not (type(saved) == "string" and saved ~= "" and PassService:Owns(player, "CustomCallsign")) then
		showCallsign(player, "")
		return
	end
	local filtered = TextFilterService:Filter(saved, player.UserId)
	if not player.Parent or not PassService:Owns(player, "CustomCallsign") then
		return
	elseif Callsign.accepted(saved, filtered) then
		showCallsign(player, saved)
	elseif filtered ~= nil then
		DataService:Update(player, function(data)
			data.Callsign = "" -- no longer allowed
		end)
		showCallsign(player, "")
	end
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
	-- currency: "Credits" (default) or "Wings" (SHP-04)
	Net.Server.handle("BuySkin", function(player: Player, airframeId: string, skinId: string, currency: string?)
		if currency == "Wings" then
			local before = DataService:GetData(player)
			local wingsBefore = before and before.Wings or 0
			local ok, err = handleIntent(player, "BuySkin", function(data)
				return Progression.buySkin(data, airframeId, skinId, "Wings")
			end, false, `{airframeId}:{skinId}`)
			local data = DataService:GetData(player)
			if ok and data then
				Telemetry.economy(player, "Sink", "Wings", wingsBefore - data.Wings, data.Wings, "BuySkin", airframeId)
			end
			return ok, err
		end
		return handleIntent(player, "BuySkin", function(data)
			return Progression.buySkin(data, airframeId, skinId)
		end, true, `{airframeId}:{skinId}`)
	end)
	Net.Server.handle("SetSkin", function(player: Player, airframeId: string, skinId: string)
		return handleIntent(player, "SetSkin", function(data)
			return Progression.setSkin(data, airframeId, skinId)
		end, false, `{airframeId}:{skinId}`)
	end)
	Net.Server.handle("BuyCosmetic", function(player: Player, id: string)
		local before = DataService:GetData(player)
		local wingsBefore = before and before.Wings or 0
		local ok, err = handleIntent(player, "BuyCosmetic", function(data)
			return Cosmetics.buy(data, id)
		end, false, id)
		local data = DataService:GetData(player)
		if ok and data then
			Telemetry.economy(player, "Sink", "Wings", wingsBefore - data.Wings, data.Wings, "BuyCosmetic", id)
			redress(player)
		end
		return ok, err
	end)
	Net.Server.handle("EquipCosmetic", function(player: Player, kind: string, id: string)
		local ok, err = handleIntent(player, "EquipCosmetic", function(data)
			return Cosmetics.equip(data, kind, id)
		end, false, `{kind}:{id}`)
		if ok then
			redress(player)
		end
		return ok, err
	end)
	Net.Server.handle("SetLineup", function(player: Player, ids: { any })
		return handleIntent(player, "SetLineup", function(data)
			return Progression.setLineup(data, ids)
		end, false, "Lineup")
	end)
	-- The title next to your name (Config/LevelRewards); "" for none
	Net.Server.handle("SetTitle", function(player: Player, titleId: string)
		local ok, err = DataService:Update(player, function(data)
			local allUnlocked = data.Flags and data.Flags.AllUnlocked == true
			if not LevelRewards.titleUnlocked(titleId, data.PilotLevel, allUnlocked, data.Titles) then
				return false, "That title isn't unlocked yet"
			end
			data.Title = titleId
			return true, nil
		end)
		if ok then
			player:SetAttribute("Title", LevelRewards.titleName(titleId) or "")
		end
		return ok == true, err
	end)
	-- Your custom callsign (CMP-01, needs the Custom Callsign pass): cleaned, then shown only if Roblox's filter
	-- leaves it untouched. Clearing it is always allowed.
	PassService.Changed:Connect(function(player, name)
		if name == "CustomCallsign" then
			task.spawn(refreshCallsign, player)
		end
	end)
	Net.Server.handle("SetCallsign", function(player: Player, text: string)
		if text == "" then
			DataService:Update(player, function(data)
				data.Callsign = ""
			end)
			showCallsign(player, "")
			return true, nil
		end
		if not PassService:Owns(player, "CustomCallsign") then
			return false, "Needs the Custom Callsign pass"
		end
		local callsign, why = Callsign.clean(text)
		if not callsign then
			return false, why
		end
		local filtered = TextFilterService:Filter(callsign, player.UserId)
		if filtered == nil then
			return false, "Couldn't check that callsign just now. Try again in a moment."
		elseif not Callsign.accepted(callsign, filtered) then
			return false, "That callsign isn't allowed"
		end
		local ok, err = DataService:Update(player, function(data)
			data.Callsign = callsign
			return true, nil
		end)
		if ok then
			showCallsign(player, callsign)
		end
		return ok == true, err
	end)
	-- On joining: levels reached before their milestones existed still pay, and the title shows
	DataService.ProfileLoaded:Connect(function(player, data)
		task.spawn(refreshCallsign, player)
		local paid = 0
		DataService:Update(player, function(d)
			local before = d.Credits
			Progression.claimLevelRewards(d)
			paid = d.Credits - before
		end)
		Telemetry.economy(player, "Source", "Credits", paid, data.Credits, Telemetry.SOURCES.LevelUp, "Level")
		local allUnlocked = data.Flags and data.Flags.AllUnlocked == true
		local title = if LevelRewards.titleUnlocked(data.Title or "", data.PilotLevel, allUnlocked, data.Titles)
			then data.Title
			else ""
		player:SetAttribute("Title", LevelRewards.titleName(title) or "")
	end)
	Net.Server.on("SettingsUpdate", function(player: Player, changes: { [any]: any })
		DataService:Update(player, function(data)
			local merged = table.clone(data.Settings)
			for key, value in changes do
				if type(key) == "string" and Settings.valid(key, value) then
					-- Some HUD colours unlock with pilot level (Config/LevelRewards)
					local needed = key == "HUDColour" and LevelRewards.HUD_COLOURS[value]
					local allUnlocked = data.Flags and data.Flags.AllUnlocked == true
					if not needed or allUnlocked or data.PilotLevel >= needed then
						merged[key] = value
					end
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
	AircraftService.cosmeticsFor = function(player: Player): { [string]: string }
		local data = DataService:GetData(player)
		return if data then looksFor(data) else {}
	end
	AircraftService.masteryFor = function(player: Player, airframeId: string): number
		local data = DataService:GetData(player)
		local entry = data and data.Aircraft[airframeId]
		return Mastery.stars(entry and entry.Mastery or 0)
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
			if data and ServerRole.isTraining() and MatchService:GetMode().AIDifficulty then
				-- Vs AI: pilot XP only (Progression.vsAIRewards)
				local payload = awardVsAI(
					player,
					data,
					if winnerTeam
						then player:GetAttribute("Team") == winnerTeam
						else winner ~= nil and not winner.isAI and winner.userId == player.UserId
				)
				if payload then
					Net.Server.fire("MatchRewards", player, payload)
				end
			elseif data and ServerRole.isTraining() then
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
