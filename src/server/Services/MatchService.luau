--!strict
-- Matches (DEVELOPMENT.md §17, MCH-01/02/03). One mode runs per server:
--   Free Flight: fly whenever, no scoring, no AI (test drones still available).
--   Dogfight:    free-for-all. Waiting → Countdown → InProgress → Results → Countdown …
--                First to the kill limit or most points at the time limit wins. AI pilots fill the
--                match up to the mode's AIFill. Respawns follow the mode's rule (timer or lives).
--   Team Deathmatch (MCH-05): the same loop with two teams. Players join the team with fewer players,
--                AI fills each side to even numbers, teams spawn over their own coast, the first team
--                to the kill limit (or ahead at the time limit) wins. Teammates can't hurt each other
--                (Lib/Teams, checked by the combat, missile, sensor and AI services).
--   Air Superiority (MCH-06): the same teams over three zones (AirSuperiority.luau). Holding zones
--                bleeds the enemy's tickets, every jet lost costs its team tickets, a team on 0 loses
--                (or the team ahead at the time limit wins). Pilots inside a zone as it flips score a
--                capture. AI pilots head for the zones (AIService.objectiveFor).
--   Strike Escort (MCH-07): the team match with AI bombers. Every Strike.WAVE_INTERVAL both teams launch
--                bombers at the other's airbase; one that gets there scores a strike. Most strikes wins.
--   PvE waves (MCH-08): the players (West) hold their airbase against waves of AI fighters and bombers
--                (East, Strike.waveSpec). The base takes Strike.BASE_HITS bombers; clear every wave to win.
--   Duels (MCH-09): two pilots, best of five rounds (Shared/Duel). Each round the server puts both jets up
--                head-on over the map centre; a jet lost is out until the next round. A ranked duel between
--                two players moves both duel ratings at the end; with one player an AI pilot (as hard as
--                their rating) takes the other seat and nothing is ranked. Leaving forfeits.
-- Server roles (MatchmakingService, MMK-02/04): a lobby runs no match (Idle "Lobby"); a match server runs one
-- match from the matchmaker's record (its mode and BR band; it waits for the players sent, or ARRIVAL_TIMEOUT,
-- then AI fills the empty seats) and fires MatchOver after the results so everyone goes back to a lobby; a
-- training server runs free flight or Vs AI matches that repeat.
-- Rotation: elsewhere (the test environment's DebugSetMode) the next mode after the results is the next in
-- MatchRules.ROTATION (Dogfight, Team Deathmatch, Air Superiority, Guns Only, Dogfight…).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Environment = require(Shared.Config.Environment)
local Flight = require(Shared.Config.Flight)
local AdaptiveAI = require(Shared.AdaptiveAI)
local AirSuperiority = require(Shared.AirSuperiority)
local AircraftData = require(Shared.AircraftData)
local Callsign = require(Shared.Callsign)
local Duel = require(Shared.Duel)
local Strike = require(Shared.Strike)
local MatchRules = require(Shared.MatchRules)
local MatchmakingStats = require(Shared.MatchmakingStats)
local Matchmaking = require(Shared.Matchmaking)
local Net = require(Shared.Net)
local Scale = require(Shared.Config.Scale)
local ServerRole = require(Shared.ServerRole)
local Signal = require(Shared.Util.Signal)
local Units = require(Shared.Units)

local Teams = require(ServerScriptService.Server.Lib.Teams)
local Telemetry = require(ServerScriptService.Server.Lib.Telemetry)
local AIService = require(script.Parent.AIService)
local DataService = require(script.Parent.DataService)
local AircraftService = require(script.Parent.AircraftService)
local CombatService = require(script.Parent.CombatService)

type Jet = AircraftService.Jet

local BROADCAST_INTERVAL = 0.5
local ARRIVAL_TIMEOUT = 30 -- a match server waits this long for everyone the matchmaker sent
local IDLE_STATES = { Lobby = true, Pending = true, Closing = true }
local QUIET_CAUSES = { Respawn = true, PilotLeft = true, Despawn = true, Struck = true }

local MatchService = {
	Priority = 50,
	MatchEnded = Signal.new(), -- (ranking, reason)
	MatchStarted = Signal.new(), -- (mode) a match went live (also Free Flight, which never ends)
	MatchOver = Signal.new(), -- () a match server's results are done: send everyone home
	ZoneCaptured = Signal.new(), -- (identity) a pilot was in a zone as their team captured it
}

local mode: MatchRules.ModeConfig = MatchRules.MODES.Dogfight
local band: Matchmaking.Band = Matchmaking.band({}) -- BR band of the current match (MMK-01)
local flying: { [Player]: string } = {} -- training servers: the jet each player last took up (any jet goes there)
local state = "Waiting"
local stateSince = 0
local scores: { [any]: MatchRules.Score } = {}
local aiOffset = 0 -- Vs AI: levels the bots are eased off (negative) or sharpened from the one picked
local pilotStates: { [any]: MatchRules.PilotState } = {}
local results: { winner: string?, winnerTeam: string?, reason: string?, ranking: { MatchRules.Score } }? = nil
local broadcastTimer = 0
local zoneState: AirSuperiority.State? = nil -- Air Superiority only
local duel: Duel.State? = nil -- duels only
local escort: Strike.EscortState? = nil -- Strike Escort only
local pve: Strike.PveState? = nil -- PvE waves only
local strikeTargets: { [string]: Vector3 } = {} -- each team's airbase (the other team's bombers' target)
local findStrikeTargets: () -> { [string]: Vector3 } -- defined with the strike helpers below
-- Duels: each pilot's rating change and new rating at the end ({ [tostring(userId)] = { change, rating,
-- ranked, promoted = names of ranks reached for the first time } }; string keys, as a remote sends them)
type DuelRating = { change: number, rating: number, ranked: boolean, promoted: { string } }
local duelRatings: { [string]: DuelRating }? = nil
local DUEL_ALTITUDE = Flight.SPAWN_ALTITUDE_STUDS -- the usual spawn height (well clear of the strait below)
-- Match servers only. teams: { [tostring(userId)] = team } from the matchmaker, so parties fly together (MMK-05)
-- jets: { [tostring(userId)] = the jet they clicked PLAY with }
local record: {
	mode: string,
	players: { number },
	band: Matchmaking.Band,
	teams: { [string]: string }?,
	jets: { [string]: string }?,
}? =
	nil

local function humans(): { Player }
	return Players:GetPlayers()
end

local function setState(newState: string)
	state = newState
	stateSince = os.clock()
	broadcastTimer = BROADCAST_INTERVAL -- send right away
	if newState == "InProgress" then
		MatchService.MatchStarted:Fire(mode)
	end
end

local function ensureScore(identity: any, name: string, isAI: boolean, userId: number)
	if not scores[identity] then
		local score = MatchRules.newScore(name, isAI, userId)
		-- Team modes: humans spread evenly over the teams (AI fill then evens the numbers), except that the
		-- matchmaker's pick (parties kept together) comes first
		local picked = not isAI and record and record.teams and record.teams[tostring(userId)]
		score.team = if picked
				and mode.Teams
				and table.find(mode.Teams, picked)
			then picked
			else MatchRules.pickTeam(mode, scores, not isAI)
		for _, jet in AircraftService:GetJets() do
			if jet.identity == identity then
				score.airframe = jet.airframeId -- already flying when they joined the board
			end
		end
		scores[identity] = score
		Teams.set(identity, score.team)
	elseif not isAI then
		scores[identity].name = name -- a callsign set since (CMP-01)
	end
	if not pilotStates[identity] then
		pilotStates[identity] = { diedAt = nil, livesUsed = 0 }
	end
end

-- Candidate airborne spawns: tagged SpawnPoint parts on the map, or a ring around the centre. With a team,
-- only that team's spawn points (each SpawnPoint has a Team attribute: West or East), if there are any. BVR
-- Battles: each team's start line, BVR_SEPARATION apart across the map, facing the other.
local function spawnCandidates(team: string?): { CFrame }
	local list = {}
	if mode.Bvr and team then
		local x = MatchRules.BVR_SEPARATION / 2 * (if team == "West" then -1 else 1)
		for _, z in { 0, -500, 500, -1000, 1000 } do
			local position = Vector3.new(x, Flight.SPAWN_ALTITUDE_STUDS, z)
			table.insert(list, CFrame.lookAt(position, Vector3.new(0, position.Y, z)))
		end
		return list
	end
	for _, part in CollectionService:GetTagged("SpawnPoint") do
		if part:IsA("BasePart") and part:IsDescendantOf(workspace) and part:GetAttribute("Type") ~= "Runway" then
			if team == nil or part:GetAttribute("Team") == team then
				table.insert(list, part.CFrame)
			end
		end
	end
	if #list == 0 and team ~= nil then
		return spawnCandidates(nil)
	end
	if #list == 0 then
		local radius = Scale.MAP_HALF_EXTENT * 0.4
		for i = 0, 11 do
			local angle = i / 12 * 2 * math.pi
			local position =
				Vector3.new(math.cos(angle) * radius, Flight.SPAWN_ALTITUDE_STUDS, math.sin(angle) * radius)
			table.insert(list, CFrame.lookAt(position, Vector3.new(0, position.Y, 0)))
		end
	end
	return list
end

-- Each spawn point offers a few slots (beside, above and behind it), so a full server never stacks two
-- jets on the same spot (found in the 24-jet stress test: they collided on spawn).
local SLOT_OFFSETS = {
	Vector3.zero,
	Vector3.new(-140, 0, 0),
	Vector3.new(140, 0, 0),
	Vector3.new(0, 84, 168),
	Vector3.new(-140, 84, 168),
	Vector3.new(140, 84, 168),
}

-- The spawn slot furthest from every other jet, so nobody spawns into a fight (or into another jet). With an
-- identity in a team mode, over that pilot's own coast.
function MatchService:PickSpawn(identity: any?): CFrame
	local best, bestScore = nil, -math.huge
	local jets = AircraftService:GetJets()
	local slots = {}
	for _, point in spawnCandidates(Teams.of(identity)) do
		for _, offset in SLOT_OFFSETS do
			table.insert(slots, point * CFrame.new(offset))
		end
	end
	for _, candidate in slots do
		local nearest = math.huge
		for _, jet in jets do
			nearest = math.min(nearest, (jet.root.Position - candidate.Position).Magnitude)
		end
		local score = nearest + math.random() * 56 -- a little variety between similar spawns
		if score > bestScore then
			best, bestScore = candidate, score
		end
	end
	return best :: CFrame
end

local function canSpawn(identity: any): (boolean, number, number?)
	if IDLE_STATES[state] then
		return false, math.huge, nil
	end
	if mode.Id == "FreeFlight" then
		return true, 0, nil
	end
	if state ~= "InProgress" then
		return false, math.huge, nil
	end
	if duel then
		-- The round start puts every jet up; a player whose auto-launch arrives in the round's first seconds
		-- (before their jet was known) can still take off, once
		local now = os.clock()
		if duel.phase == "Fight" and duel.alive[identity] and now - duel.phaseSince < 10 then
			return true, 0, nil
		end
		local wait = if duel.phase == "Intermission" then Duel.INTERMISSION - (now - duel.phaseSince) else math.huge
		return false, math.max(wait, 0), nil
	end
	local pilot = pilotStates[identity] or { diedAt = nil, livesUsed = 0 }
	return MatchRules.canSpawn(mode, pilot, os.clock())
end

local refreshBand: () -> ()

local function spawnGate(player: Player, airframeId: string): (boolean, CFrame?, string?)
	if state == "Lobby" then
		return false, nil, "Press PLAY to find a match"
	end
	ensureScore(player, Callsign.nameOf(player), false, player.UserId)
	local jetOk, why = MatchRules.jetAllowed(mode, airframeId)
	if not jetOk and mode.Scored then
		return false, nil, why -- BVR: Tier IV+ jets with radar missiles
	end
	if duel then
		flying[player] = airframeId -- the jet they'll fly from the next round
		if AircraftService:GetJet(player) then
			return false, nil
		end
	end
	local allowed = canSpawn(player)
	if not allowed then
		return false, nil
	end
	if duel then
		local seat = Duel.seat(duel, player)
		return true, if seat then Duel.spawnPair(Vector3.zero, DUEL_ALTITUDE)[seat] else MatchService:PickSpawn(player)
	end
	if ServerRole.isTraining() and flying[player] ~= airframeId then
		flying[player] = airframeId
		refreshBand()
	end
	-- No BR cap on spawning (Will: let any lineup jet fly). The band still picks the AI's jets; proper
	-- BR matching comes with separate match servers (MMK-02–04).
	pilotStates[player].livesUsed += 1
	return true, MatchService:PickSpawn(player)
end

local function clearJets()
	for _, jet in AircraftService:GetJets() do
		AircraftService:Despawn(jet, "Despawn")
	end
end

-- The jets AI pilots fly: inside the match's band, or on a training server (Vs AI) the jets at the level
-- of the one the player flies (Will).
local function aiChoices(): { string }
	local list = if ServerRole.isTraining() then Matchmaking.vsAIAirframes(band.br) else Matchmaking.aiAirframes(band)
	-- Only jets this mode allows (BVR: Tier IV+ with radar missiles), if any of them are allowed
	local allowed = {}
	for _, id in list do
		if MatchRules.jetAllowed(mode, id) then
			table.insert(allowed, id)
		end
	end
	if #allowed == 0 and mode.MinTier then
		for id in AircraftData.getAll() do
			if MatchRules.jetAllowed(mode, id) then
				table.insert(allowed, id)
			end
		end
		table.sort(allowed)
	end
	return if #allowed > 0 then allowed else list
end

-- The match's BR band (the matchmaker's, or from the lineups of the players here, MMK-01), and AI jets to
-- match it.
refreshBand = function()
	if record then
		band = record.band
		local choices = aiChoices()
		for i, pilot in AIService:GetMatchPilots() do
			AIService:SetAirframe(pilot, choices[(i - 1) % #choices + 1])
		end
		return
	end
	local lineups = {}
	for _, player in humans() do
		local data = DataService:GetData(player)
		if ServerRole.isTraining() and flying[player] then
			table.insert(lineups, { flying[player] }) -- Vs AI matches the jet they're trying out
		elseif data then
			table.insert(lineups, data.Lineup)
		end
	end
	band = Matchmaking.band(lineups)
	local choices = aiChoices()
	for i, pilot in AIService:GetMatchPilots() do
		AIService:SetAirframe(pilot, choices[(i - 1) % #choices + 1])
		-- Vs AI: a bot already up in a jet from another level (the player changed jets mid-match) swaps now,
		-- respawning in the new one after the usual delay, not only once it's shot down
		local jet = pilot.jet
		if ServerRole.isTraining() and jet and not table.find(choices, jet.airframeId) then
			AircraftService:Despawn(jet, "Despawn")
		end
	end
end

local function syncAIFill()
	local live = state ~= "Waiting" and not IDLE_STATES[state]
	local wanted = if mode.AIFill > 0 and live then math.max(mode.AIFill - #humans(), 0) else 0
	local current = AIService:GetMatchPilots()
	while #current > wanted do
		-- In team modes, take the AI pilot from the bigger team, so a player joining keeps the sides even
		local pilot = current[#current]
		if mode.Teams then
			local counts = {}
			for _, s in scores do
				if s.team then
					counts[s.team] = (counts[s.team] or 0) + 1
				end
			end
			local biggest = -1
			for _, candidate in current do
				local team = Teams.of(candidate.identity)
				local count = if team then counts[team] or 0 else 0
				if count > biggest then
					pilot, biggest = candidate, count
				end
			end
		end
		scores[pilot.identity] = nil
		pilotStates[pilot.identity] = nil
		Teams.set(pilot.identity, nil)
		AIService:RemovePilot(pilot)
		current = AIService:GetMatchPilots()
	end
	while #AIService:GetMatchPilots() < wanted do
		local choices = aiChoices()
		local difficulty = mode.AIDifficulty or "Normal"
		if mode.Duel and not mode.AIDifficulty then
			-- An AI duelist as good as the player it stands in for an opponent for
			local player = humans()[1]
			local data = player and DataService:GetData(player)
			local rating = if data then Duel.record(data).Rating else Duel.START_RATING
			difficulty = if rating >= 1400 then "Ace" elseif rating >= 1100 then "Hard" else "Normal"
		end
		local pilot = AIService:CreatePilot(difficulty, choices[#AIService:GetMatchPilots() % #choices + 1])
		if ServerRole.isTraining() then
			pilot.profile = AdaptiveAI.profile(mode.AIDifficulty or "Normal", aiOffset)
		end
		ensureScore(pilot.identity, pilot.identity.Name, true, 0)
	end
end

-- Vs AI: the bots ease off or sharpen up with the player's kills, assists and deaths (AdaptiveAI)
local function adaptAI()
	local player = humans()[1]
	local score = player and scores[player]
	if not (ServerRole.isTraining() and mode.AIDifficulty and score) then
		return
	end
	local offset = AdaptiveAI.offset(score.kills, score.deaths, score.assists)
	if offset == aiOffset then
		return
	end
	aiOffset = offset
	local profile = AdaptiveAI.profile(mode.AIDifficulty, offset)
	for _, pilot in AIService:GetMatchPilots() do
		pilot.profile = profile
	end
end

local function startMatch()
	scores = {}
	aiOffset = 0
	if ServerRole.isTraining() and mode.AIDifficulty then
		for _, pilot in AIService:GetMatchPilots() do
			pilot.profile = AdaptiveAI.profile(mode.AIDifficulty, 0)
		end
	end
	pilotStates = {}
	results = nil
	Teams.clear()
	zoneState = if mode.Objective == "Zones" and mode.Teams then AirSuperiority.newState(mode.Teams) else nil
	duel = if mode.Duel then Duel.newState(os.clock()) else nil
	duelRatings = nil
	for _, pilot in AIService:GetMissionPilots() do
		AIService:RemovePilot(pilot)
	end
	strikeTargets = findStrikeTargets()
	escort = if mode.Objective == "Strike" and mode.Teams then Strike.newEscort(mode.Teams, os.clock()) else nil
	pve = if mode.Objective == "Waves" then Strike.newPve(os.clock()) else nil
	clearJets()
	refreshBand()
	for _, player in humans() do
		ensureScore(player, Callsign.nameOf(player), false, player.UserId)
	end
	for _, pilot in AIService:GetMatchPilots() do
		ensureScore(pilot.identity, pilot.identity.Name, true, 0)
	end
	setState("InProgress")
end

-- A finished duel: both saves get the result, and a ranked duel between two players moves both ratings
-- (from the ratings they had before it). Returns each player's change and new rating.
local function settleDuel(state: Duel.State, result: any): { [string]: DuelRating }
	local players: { Player } = {}
	for _, identity in state.pilots do
		if typeof(identity) == "Instance" and identity:IsA("Player") then
			table.insert(players, identity)
		end
	end
	local ranked = mode.Ranked == true and #players == 2
	local before: { [Player]: number } = {}
	for _, player in players do
		local data = DataService:GetData(player)
		before[player] = if data then Duel.record(data).Rating else Duel.START_RATING
	end
	local out = {}
	for _, player in players do
		local other = if players[1] == player then players[2] else players[1]
		local score = if result == "Draw" then 0.5 elseif result == player then 1 else 0
		local theirs = if other then before[other] else Duel.START_RATING
		local promoted = {}
		local ok, change = pcall(function()
			return DataService:Update(player, function(data)
				local delta, reached = Duel.apply(data, theirs, score, ranked)
				for _, rank in reached do
					table.insert(promoted, rank.name)
				end
				return delta
			end)
		end)
		local data = DataService:GetData(player)
		out[tostring(player.UserId)] = {
			change = if ok and type(change) == "number" then change else 0,
			rating = if data then Duel.record(data).Rating else before[player],
			ranked = ranked,
			promoted = promoted,
		}
	end
	return out
end

local function endMatch(reason: string)
	local ranking = MatchRules.ranking(scores)
	local winnerTeam = if zoneState
		then AirSuperiority.leader(zoneState)
		elseif mode.Teams then MatchRules.winningTeam(mode, scores)
		else nil
	if escort then
		winnerTeam = Strike.escortWinner(escort, MatchRules.teamScores(mode, scores))
	elseif pve then
		winnerTeam = if pve.phase == "Won" then "West" else "East" -- the players are West
	end
	local winner = if mode.Teams then winnerTeam or "Draw" else ranking[1] and ranking[1].name
	if pve then
		winner = if pve.phase == "Won" then "Base held" else "Base lost"
	end
	if duel then
		local result = Duel.matchResult(duel)
		if result == "Draw" or result == nil then
			winner, reason = "Draw", "Draw"
		else
			winner = scores[result] and scores[result].name or winner
			-- The duel's winner tops the board even on a tie in points
			table.sort(ranking, function(a, b)
				return a == scores[result] and b ~= scores[result]
			end)
		end
		if not ServerRole.isTraining() then -- a Vs AI duel is practice: nothing on the record
			duelRatings = settleDuel(duel, result)
		end
	end
	results = { winner = winner, winnerTeam = winnerTeam, reason = reason, ranking = ranking }
	local duration = os.clock() - stateSince -- before the state (and its clock) moves on
	setState("Results")
	for _, pilot in AIService:GetMissionPilots() do
		Teams.set(pilot.identity, nil)
		AIService:RemovePilot(pilot)
	end
	clearJets()
	MatchService.MatchEnded:Fire(ranking, reason, winnerTeam)
	-- Value: how long it lasted (s). Sent: the mode and the BR band's top (ANL-04).
	Telemetry.event("MatchEnded", duration, {
		mode = mode.Id,
		band = band.max,
		reason = reason,
		pilots = #ranking,
	}, nil, { "mode", "band" })
	-- How close it finished (MMK-06): 100 level, towards 0 a walkover (MatchmakingStats.closeness), from the
	-- two teams' kills (tickets left in Air Superiority) or the top two pilots' kills. Sent: the mode and
	-- how many humans flew.
	local points = {}
	if zoneState then
		for _, tickets in zoneState.tickets do
			table.insert(points, tickets)
		end
	elseif mode.Teams then
		for _, kills in MatchRules.teamScores(mode, scores) do
			table.insert(points, kills)
		end
	else
		for _, score in ranking do
			table.insert(points, score.kills)
		end
	end
	local humanCount = 0
	for _, score in ranking do
		if not score.isAI then
			humanCount += 1
		end
	end
	Telemetry.event("MatchQuality", math.round(MatchmakingStats.closeness(points) * 100), {
		mode = mode.Id,
		humans = humanCount,
		ai = #ranking - humanCount,
	}, nil, { "mode", "humans" })
end

local function onKill(jet: Jet, credit: any, cause: string)
	if not mode.Scored or state ~= "InProgress" then
		return
	end
	local victim = jet.identity
	local pilot = pilotStates[victim]
	if pilot then
		pilot.diedAt = os.clock()
	end
	if duel and cause == "Despawn" and credit.killer == nil and duel.phase ~= "Fight" then
		return -- the round's reset, not a loss
	end
	if duel and QUIET_CAUSES[cause] and credit.killer == nil then
		Duel.down(duel, victim, os.clock()) -- back to the hangar mid-round gives the round away
		return
	end
	if QUIET_CAUSES[cause] and credit.killer == nil then
		return -- leaving or respawning with nobody's damage on you isn't a death
	end
	MatchRules.recordKill(scores, victim, credit.killer, credit.assists, credit.forcedCrash)
	if duel then
		Duel.down(duel, victim, os.clock())
	end
	adaptAI()
	if zoneState then
		AirSuperiority.jetLost(zoneState, Teams.of(victim))
	end
	Telemetry.event("Death", 1, { cause = cause, mode = mode.Id })
end

local function respawnAI()
	if (state ~= "InProgress" and mode.Id ~= "FreeFlight") or duel then
		return
	end
	for _, pilot in AIService:GetMatchPilots() do
		if not pilot.jet then
			ensureScore(pilot.identity, pilot.identity.Name, true, 0)
			local allowed = canSpawn(pilot.identity)
			if allowed then
				pilotStates[pilot.identity].livesUsed += 1
				AIService:SpawnPilot(pilot, MatchService:PickSpawn(pilot.identity))
			end
		end
	end
end

-- Air Superiority: who's in which zone, the captures and the ticket bleed. Pilots of the capturing team
-- inside a zone as it flips score a capture.
local function stepZones(dt: number)
	local state = zoneState
	if not state then
		return
	end
	local presence: { [string]: { [string]: number } } = {}
	local inside: { [string]: { any } } = {}
	for _, jet in AircraftService:GetJets() do
		local team = Teams.of(jet.identity)
		if team then
			for _, zone in state.zones do
				if AirSuperiority.contains(zone, jet.root.Position) then
					presence[zone.id] = presence[zone.id] or {}
					presence[zone.id][team] = (presence[zone.id][team] or 0) + 1
					inside[zone.id] = inside[zone.id] or {}
					table.insert(inside[zone.id], jet.identity)
				end
			end
		end
	end
	for _, capture in AirSuperiority.step(state, presence, dt) do
		for _, identity in inside[capture.zone] or {} do
			local score = scores[identity]
			if score and score.team == capture.team then
				score.score += MatchRules.POINTS.Capture
				MatchService.ZoneCaptured:Fire(identity)
			end
		end
		Telemetry.event("ZoneCaptured", 1, { zone = capture.zone, team = capture.team })
	end
end

-- The jet a player flies in a duel: the one they last asked for, else the one they clicked PLAY with, else
-- the one selected in the hangar, else the first in their lineup.
local function duelAirframe(player: Player): string?
	if flying[player] then
		return flying[player]
	end
	local data = DataService:GetData(player)
	local played = record and record.jets and record.jets[tostring(player.UserId)]
	if type(played) == "string" and data and table.find(data.Lineup or {}, played) then
		return played
	end
	local selected = data and data.Settings and data.Settings.SelectedJet
	if type(selected) == "string" and table.find(data.Lineup or {}, selected) then
		return selected
	end
	return data and data.Lineup and data.Lineup[1]
end

-- Puts both duellists up head-on for the next round.
local function startDuelRound(state: Duel.State)
	clearJets()
	Duel.startRound(state, os.clock())
	local pair = Duel.spawnPair(Vector3.zero, DUEL_ALTITUDE)
	for seat, identity in state.pilots do
		local at = pair[seat]
		if typeof(identity) == "Instance" and identity:IsA("Player") then
			local airframe = duelAirframe(identity)
			if airframe then
				AircraftService:Spawn(identity, airframe, at)
			end
		else
			for _, pilot in AIService:GetMatchPilots() do
				if pilot.identity == identity then
					AIService:SpawnPilot(pilot, at)
				end
			end
		end
	end
end

local function stepDuel(): boolean
	local state = duel
	if not state then
		return false
	end
	-- Seat whoever's here: players first, then the AI standing in
	for _, player in humans() do
		Duel.seat(state, player)
	end
	for _, pilot in AIService:GetMatchPilots() do
		Duel.seat(state, pilot.identity)
	end
	local now = os.clock()
	local phase = state.phase
	if Duel.step(state, now) == "Start" then
		startDuelRound(state)
	end
	if state.phase ~= phase and (state.phase == "Intermission" or state.phase == "Over") then
		-- A round just ended: the board shows round wins first
		for _, identity in state.pilots do
			local score = scores[identity]
			if score then
				score.score = (state.wins[identity] or 0) * 1000 + score.kills * 100 + score.assists * 50
			end
		end
	end
	return state.phase == "Over" and now - state.phaseSince >= Duel.INTERMISSION
end

------------------------------------------------------------------------------------------------ strikes

-- Each team's airbase: the centre of the map's AirbaseWest / AirbaseEast, else a point on its coast.
findStrikeTargets = function(): { [string]: Vector3 }
	local out = {}
	for _, team in { "West", "East" } do
		local base = workspace:FindFirstChild("Map") and (workspace :: any).Map:FindFirstChild(`Airbase{team}`)
		if base and base:IsA("Model") then
			local cf = base:GetBoundingBox()
			out[team] = cf.Position
		else
			out[team] = Vector3.new(Scale.MAP_HALF_EXTENT * 0.55 * (if team == "West" then -1 else 1), 0, 0)
		end
	end
	return out
end

local function otherTeam(team: string): string
	return if team == "West" then "East" else "West"
end

-- The bomber the missions fly: the B-1B once its model is in, else a stand-in strike jet.
local function bomberAirframe(): string
	return if AircraftData.get(Strike.BOMBER_AIRFRAME) then Strike.BOMBER_AIRFRAME else Strike.FALLBACK_BOMBER
end

local function launchBomber(team: string, index: number)
	local target = strikeTargets[otherTeam(team)]
	local pilot = AIService:CreateMissionPilot("Bomber", "Normal", bomberAirframe(), target)
	Teams.set(pilot.identity, team)
	AIService:SpawnPilot(pilot, Strike.bomberStart(team, target, Scale.MAP_HALF_EXTENT, index))
end

-- PvE: a wave fighter, coming in from the east at the players' side.
local function launchWaveFighter(difficulty: string, index: number)
	local choices = aiChoices()
	local pilot = AIService:CreateMissionPilot("Wave", difficulty, choices[(index - 1) % #choices + 1], nil)
	Teams.set(pilot.identity, "East")
	local position = Vector3.new(
		Scale.MAP_HALF_EXTENT * 0.8,
		Flight.SPAWN_ALTITUDE_STUDS + (index % 3) * 120,
		(index - 1) * 400 - 1400
	)
	AIService:SpawnPilot(
		pilot,
		CFrame.lookAt(position, Vector3.new(strikeTargets.West.X, position.Y, strikeTargets.West.Z))
	)
end

-- Strike Escort and PvE each tick: launch waves, score bombers that got through, clear out the shot down.
-- Returns true when the mission has decided the match.
local function stepMissions(): boolean
	if not (escort or pve) then
		return false
	end
	local now = os.clock()
	for _, pilot in AIService:GetMissionPilots() do
		local jet = pilot.jet
		if pilot.launched and not jet then
			Teams.set(pilot.identity, nil)
			AIService:RemovePilot(pilot) -- shot down: mission pilots don't respawn
		elseif
			jet
			and pilot.role == "Bomber"
			and pilot.strikeTarget
			and Strike.reached(jet.root.Position, pilot.strikeTarget)
		then
			local team = Teams.of(pilot.identity)
			if escort and team then
				Strike.strike(escort, team)
			elseif pve then
				Strike.baseHit(pve, now)
			end
			Telemetry.event("Strike", 1, { mode = mode.Id, team = team or "" })
			AircraftService:Despawn(jet, "Struck") -- bombs gone: it leaves the fight, nobody's kill
			pilot.jet = nil
			Teams.set(pilot.identity, nil)
			AIService:RemovePilot(pilot)
		end
	end
	if escort then
		if Strike.waveDue(escort, now) then
			for _, team in mode.Teams or {} do
				for i = 1, Strike.WAVE_BOMBERS do
					launchBomber(team, i)
				end
			end
		end
		return Strike.escortEnded(escort)
	end
	local state = pve :: Strike.PveState
	local alive = #AIService:GetMissionPilots()
	if Strike.stepPve(state, alive, now) == "Launch" then
		local spec = Strike.waveSpec(state.wave)
		for i = 1, spec.bombers do
			launchBomber("East", i)
		end
		for i = 1, spec.fighters do
			launchWaveFighter(spec.difficulty, i)
		end
	end
	return state.phase == "Won" or state.phase == "Lost"
end

-- The zone an AI pilot should go for: the nearest one its team doesn't own, else one of its own (spread
-- by pilot, so they don't all stack on one).
local function objectiveFor(pilot: any): { position: Vector3, radius: number }?
	if state == "InProgress" and pilot.jet and (escort or pve) then
		local team = Teams.of(pilot.identity)
		if pve and team == "East" then
			return { position = strikeTargets.West, radius = 1500 } -- the waves go for the players' base
		end
		-- Strike Escort: half the AI fighters hunt the nearest enemy bomber, half stay with their own (and fight
		-- whoever comes for them); with no bomber of that kind up, the other kind
		local index = table.find(AIService:GetMatchPilots(), pilot) or 1
		local hunt = index % 2 == 1
		pilot.hunter = hunt and escort ~= nil
		if hunt then
			-- A hunter chases its bomber itself (AIService: the nearest enemy bomber is its target): no zone
			for _, bomber in AIService:GetMissionPilots("Bomber") do
				if bomber.jet and Teams.of(bomber.identity) ~= team then
					return nil
				end
			end
		end
		local function nearest(enemy: boolean): Vector3?
			local best, bestDistance = nil, math.huge
			for _, bomber in AIService:GetMissionPilots("Bomber") do
				if bomber.jet and (Teams.of(bomber.identity) ~= team) == enemy then
					local root = bomber.jet.root
					local distance = (root.Position - pilot.jet.root.Position).Magnitude
					if distance < bestDistance then
						-- Hunters cut the bomber off where it'll be, not where it is
						local lead = if enemy
							then root.AssemblyLinearVelocity * math.min(distance / 100, 15)
							else Vector3.zero
						best, bestDistance = root.Position + lead, distance
					end
				end
			end
			return best
		end
		local goal = nearest(hunt) or nearest(not hunt)
		return if goal then { position = goal, radius = if hunt then 600 else 1500 } else nil
	end
	local zones = zoneState
	local team = Teams.of(pilot.identity)
	if not zones or state ~= "InProgress" or not team or not pilot.jet then
		return nil
	end
	local position = pilot.jet.root.Position
	local best, bestDistance = nil, math.huge
	for _, zone in zones.zones do
		if zone.owner ~= team then
			local distance = (Vector3.new(zone.position.X, position.Y, zone.position.Z) - position).Magnitude
			if distance < bestDistance then
				best, bestDistance = zone, distance
			end
		end
	end
	if not best then
		local index = table.find(AIService:GetMatchPilots(), pilot) or 1
		best = zones.zones[index % #zones.zones + 1]
	end
	return { position = best.position, radius = best.radius }
end

-- Match servers: how many of the players the matchmaker sent are here.
local function arrivals(): (number, number)
	if not record then
		return #humans(), #humans()
	end
	local here = 0
	for _, userId in record.players do
		if Players:GetPlayerByUserId(userId) then
			here += 1
		end
	end
	return here, #record.players
end

local function publishPlayerTimers()
	for _, player in humans() do
		local identity = player
		local _, wait, lives = canSpawn(identity)
		player:SetAttribute("RespawnIn", if wait == math.huge then -1 else math.ceil(wait))
		player:SetAttribute("LivesLeft", lives or -1)
	end
end

local function broadcast()
	local elapsed = os.clock() - stateSince
	local timeLeft = 0
	if state == "Waiting" and record then
		timeLeft = ARRIVAL_TIMEOUT - elapsed
	elseif state == "Countdown" then
		timeLeft = mode.CountdownSeconds - elapsed
	elseif state == "InProgress" and mode.TimeLimit > 0 then
		timeLeft = mode.TimeLimit - elapsed
	elseif state == "Results" then
		timeLeft = mode.ResultsSeconds - elapsed
	end
	local ranking = if results then results.ranking else MatchRules.ranking(scores)
	local zones = nil
	if zoneState then
		zones = {}
		for _, zone in zoneState.zones do
			table.insert(zones, {
				id = zone.id,
				position = zone.position,
				radius = zone.radius,
				top = zone.top,
				progress = zone.progress,
				owner = zone.owner,
			})
		end
	end
	local duelInfo = nil
	if duel then
		local seats = {}
		for _, identity in duel.pilots do
			local score = scores[identity]
			table.insert(seats, {
				name = if score then score.name else "?",
				userId = if score then score.userId else 0,
				wins = duel.wins[identity] or 0,
				alive = duel.alive[identity] == true,
			})
		end
		local last = duel.lastRound
		local roundLeft = if duel.phase == "Fight" then Duel.ROUND_TIME - (os.clock() - duel.phaseSince) else 0
		duelInfo = {
			round = duel.round,
			phase = duel.phase,
			seats = seats,
			toWin = Duel.ROUNDS_TO_WIN,
			ranked = mode.Ranked == true,
			roundLeft = math.max(math.ceil(roundLeft), 0),
			lastWinner = if last and last.winner ~= nil and scores[last.winner] then scores[last.winner].name else nil,
			lastReason = if last then last.reason else nil,
			ratings = duelRatings,
		}
	end
	local mission = nil
	if escort then
		mission = {
			kind = "Strike",
			strikes = escort.strikes,
			limit = Strike.STRIKE_LIMIT,
			nextWave = math.max(math.ceil(escort.nextWave - os.clock()), 0),
			bombers = #AIService:GetMissionPilots("Bomber"),
		}
	elseif pve then
		mission = {
			kind = "Waves",
			wave = pve.wave,
			waves = Strike.WAVES,
			baseHits = pve.baseHits,
			maxHits = Strike.BASE_HITS,
			phase = pve.phase,
			enemies = #AIService:GetMissionPilots(),
			breakLeft = if pve.phase == "Break"
				then math.max(math.ceil(Strike.WAVE_BREAK - (os.clock() - pve.phaseSince)), 0)
				else 0,
		}
	end
	if (escort or pve) and state == "InProgress" then
		-- The targets, drawn like zones: each airbase in its own team's colour
		zones = {}
		for team, position in strikeTargets do
			if escort or team == "West" then
				table.insert(zones, {
					id = if team == "West" then "W" else "E",
					position = position,
					radius = Strike.TARGET_RADIUS,
					top = Units.toStuds(Strike.CRUISE_ALTITUDE) + 400,
					progress = 0,
					owner = team,
				})
			end
		end
	end
	local arrived, expected = arrivals()
	Net.Server.fireAll("MatchState", {
		duel = duelInfo,
		mission = mission,
		arrived = if record then arrived else nil,
		expected = if record then expected else nil,
		mode = mode.Id,
		modeName = mode.DisplayName,
		state = state,
		timeLeft = math.max(math.ceil(timeLeft), 0),
		scoreLimit = mode.ScoreLimit,
		scored = mode.Scored,
		ranking = ranking,
		winner = results and results.winner,
		reason = results and results.reason,
		teams = mode.Teams,
		teamScores = if mode.Teams then MatchRules.teamScores(mode, scores) else nil,
		zones = zones,
		tickets = if zoneState
			then { West = math.ceil(zoneState.tickets.West or 0), East = math.ceil(zoneState.tickets.East or 0) }
			else nil,
		br = if mode.Scored then { min = band.min, max = band.max } else nil,
	})
end

local function tick(dt: number)
	local elapsed = os.clock() - stateSince
	if IDLE_STATES[state] then
		broadcastTimer += dt
		if broadcastTimer >= BROADCAST_INTERVAL then
			broadcastTimer = 0
			broadcast()
		end
		return
	end
	if mode.Id == "FreeFlight" then
		if state ~= "InProgress" then
			setState("InProgress")
		end
	elseif state == "Waiting" and record then
		-- Everyone the matchmaker sent, or whoever made it in time
		local arrived, expected = arrivals()
		if #humans() > 0 and (arrived >= expected or elapsed >= ARRIVAL_TIMEOUT) then
			-- Value: the share of the pilots sent who made it (%). Sent: mode and how many were sent (MMK-06)
			Telemetry.event(
				"MatchArrived",
				math.round(arrived / math.max(expected, 1) * 100),
				{ mode = mode.Id, expected = expected, arrived = arrived, waited = math.round(elapsed) },
				nil,
				{ "mode", "expected" }
			)
			refreshBand()
			setState("Countdown")
		end
	elseif state == "Waiting" then
		if #humans() > 0 then
			refreshBand()
			setState("Countdown")
		end
	elseif state == "Countdown" then
		if #humans() == 0 then
			setState("Waiting")
		elseif elapsed >= mode.CountdownSeconds then
			startMatch()
		end
	elseif state == "Results" and record then
		if elapsed >= mode.ResultsSeconds then
			setState("Closing")
			MatchService.MatchOver:Fire()
		end
	elseif state == "InProgress" then
		if #humans() == 0 then
			clearJets()
			setState("Waiting")
		else
			stepZones(dt)
			local ended, reason = MatchRules.checkEnd(mode, scores, elapsed)
			if stepDuel() then
				ended, reason = true, "Rounds"
			end
			if stepMissions() then
				ended, reason = true, if escort then "Strikes" else "Waves"
			end
			if zoneState and AirSuperiority.checkEnd(zoneState) then
				ended, reason = true, "Tickets"
			end
			if ended then
				endMatch(reason :: string)
			end
		end
	elseif state == "Results" then
		if elapsed >= mode.ResultsSeconds then
			-- The next match is the next mode in the rotation (not on training servers: a Vs AI match repeats)
			local nextId = if ServerRole.isTraining() then mode.Id else MatchRules.nextMode(mode.Id)
			if nextId ~= mode.Id then
				mode = (MatchRules.MODES :: any)[nextId]
				ReplicatedStorage:SetAttribute("GameMode", nextId)
				Teams.clear()
				zoneState = nil
			end
			setState(if #humans() > 0 then "Countdown" else "Waiting")
		end
	end

	syncAIFill()
	respawnAI()
	broadcastTimer += dt
	if broadcastTimer >= BROADCAST_INTERVAL then
		broadcastTimer = 0
		publishPlayerTimers()
		broadcast()
	end
end

local function applyMode(config: MatchRules.ModeConfig)
	local modeId = config.Id
	mode = config
	ReplicatedStorage:SetAttribute("GameMode", modeId)
	clearJets()
	scores = {}
	pilotStates = {}
	results = nil
	Teams.clear()
	zoneState = nil
	duel = nil
	duelRatings = nil
	escort = nil
	pve = nil
	AIService:RemoveAll()
	setState(if modeId == "FreeFlight" then "InProgress" else "Waiting")
end

function MatchService:SetMode(modeId: string)
	local config = (MatchRules.MODES :: any)[modeId]
	if config then
		record = nil
		applyMode(config)
	end
end

-- No match here: a lobby, or a reserved server still reading its record.
function MatchService:Idle(stateName: string)
	record = nil
	applyMode(mode)
	setState(stateName)
end

-- A match server: the match the matchmaker formed (mode, players, BR band).
function MatchService:StartFromRecord(matchRecord: any)
	local config = (MatchRules.MODES :: any)[matchRecord.mode]
	if not config then
		return
	end
	applyMode(config)
	record = {
		mode = matchRecord.mode,
		players = matchRecord.players or {},
		band = Matchmaking.bandFor(matchRecord.band and matchRecord.band.br or Matchmaking.DEFAULT_BR),
		teams = if type(matchRecord.teams) == "table" then matchRecord.teams else nil,
		jets = if type(matchRecord.jets) == "table" then matchRecord.jets else nil,
	}
	band = record.band
end

-- Training servers: a match of `modeId` against `count` AI pilots of one difficulty (pilot XP only, and the
-- bots adapt to how the player is doing: AdaptiveAI).
function MatchService:StartVsAI(modeId: string, difficulty: string, count: number)
	local base = (MatchRules.MODES :: any)[modeId]
	if not base then
		return
	end
	local config = table.clone(base)
	config.AIFill = count + 1 -- AI fill counts the player
	config.AIDifficulty = difficulty
	config.DisplayName = `{base.DisplayName} vs AI`
	applyMode(config)
end

function MatchService:GetMode(): MatchRules.ModeConfig
	return mode
end

function MatchService:GetState(): string
	return state
end

function MatchService:Init()
	-- The scoreboard shows the jet each pilot is flying
	AircraftService.JetSpawned:Connect(function(jet)
		local score = scores[jet.identity]
		if score then
			score.airframe = jet.airframeId
		end
	end)
	local configured = ReplicatedStorage:GetAttribute("GameMode")
	if type(configured) == "string" and (MatchRules.MODES :: any)[configured] then
		mode = (MatchRules.MODES :: any)[configured]
	end
	ReplicatedStorage:SetAttribute("GameMode", mode.Id)
	AircraftService.spawnGate = spawnGate
	AIService.objectiveFor = objectiveFor
	CombatService.Kill:Connect(onKill)

	Players.PlayerAdded:Connect(function(player)
		ensureScore(player, Callsign.nameOf(player), false, player.UserId)
		broadcastTimer = BROADCAST_INTERVAL
	end)
	Players.PlayerRemoving:Connect(function(player)
		if duel and state == "InProgress" and table.find(duel.pilots, player) and #duel.pilots == 2 then
			Duel.forfeit(duel, player, os.clock() - Duel.INTERMISSION)
			endMatch("Forfeit")
		end
		if duel then
			Duel.unseat(duel, player)
		end
		flying[player] = nil
		scores[player] = nil
		pilotStates[player] = nil
		Teams.set(player, nil)
	end)

	if Environment.isTest() then
		-- A mode id, or "EndMatch" to end the running match now (to check the results screen).
		Net.Server.on("DebugSetMode", function(_player: Player, modeId: string)
			if modeId == "EndMatch" then
				if state == "InProgress" and mode.Scored then
					endMatch("TimeLimit")
				end
				return
			end
			self:SetMode(modeId)
		end)
	end
	setState(if mode.Id == "FreeFlight" then "InProgress" else "Waiting")
end

function MatchService:Start()
	RunService.Heartbeat:Connect(function(dt)
		debug.profilebegin("MatchService.tick")
		tick(dt)
		debug.profileend()
	end)
end

return MatchService
