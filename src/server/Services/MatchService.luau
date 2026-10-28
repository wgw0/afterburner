--!strict
-- Matches (DEVELOPMENT.md §17, MCH-01/02/03). One mode runs per server:
--   Free Flight: fly whenever, no scoring, no AI (test drones still available).
--   Dogfight:    free-for-all. Waiting → Countdown → InProgress → Results → Countdown …
--                First to the kill limit or most points at the time limit wins. AI pilots fill the
--                match up to the mode's AIFill. Respawns follow the mode's rule (timer or lives).
-- The mode comes from the GameMode attribute on ReplicatedStorage (default Dogfight); in the test
-- environment it can be switched live from the tuning panel.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Environment = require(Shared.Config.Environment)
local Flight = require(Shared.Config.Flight)
local MatchRules = require(Shared.MatchRules)
local Matchmaking = require(Shared.Matchmaking)
local Net = require(Shared.Net)
local Scale = require(Shared.Config.Scale)
local Signal = require(Shared.Util.Signal)

local Telemetry = require(ServerScriptService.Server.Lib.Telemetry)
local AIService = require(script.Parent.AIService)
local DataService = require(script.Parent.DataService)
local AircraftService = require(script.Parent.AircraftService)
local CombatService = require(script.Parent.CombatService)

type Jet = AircraftService.Jet

local BROADCAST_INTERVAL = 0.5
local QUIET_CAUSES = { Respawn = true, PilotLeft = true, Despawn = true }

local MatchService = {
	Priority = 50,
	MatchEnded = Signal.new(), -- (ranking, reason)
	MatchStarted = Signal.new(), -- (mode) a match went live (also Free Flight, which never ends)
}

local mode: MatchRules.ModeConfig = MatchRules.MODES.Dogfight
local band: Matchmaking.Band = Matchmaking.band({}) -- BR band of the current match (MMK-01)
local state = "Waiting"
local stateSince = 0
local scores: { [any]: MatchRules.Score } = {}
local pilotStates: { [any]: MatchRules.PilotState } = {}
local results: { winner: string?, reason: string?, ranking: { MatchRules.Score } }? = nil
local broadcastTimer = 0

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
		scores[identity] = MatchRules.newScore(name, isAI, userId)
	end
	if not pilotStates[identity] then
		pilotStates[identity] = { diedAt = nil, livesUsed = 0 }
	end
end

-- Candidate airborne spawns: tagged SpawnPoint parts on the map, or a ring around the centre.
local function spawnCandidates(): { CFrame }
	local list = {}
	for _, part in CollectionService:GetTagged("SpawnPoint") do
		if part:IsA("BasePart") and part:IsDescendantOf(workspace) and part:GetAttribute("Type") ~= "Runway" then
			table.insert(list, part.CFrame)
		end
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

-- The spawn slot furthest from every other jet, so nobody spawns into a fight (or into another jet).
function MatchService:PickSpawn(): CFrame
	local best, bestScore = nil, -math.huge
	local jets = AircraftService:GetJets()
	local slots = {}
	for _, point in spawnCandidates() do
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
	if mode.Id == "FreeFlight" then
		return true, 0, nil
	end
	if state ~= "InProgress" then
		return false, math.huge, nil
	end
	local pilot = pilotStates[identity] or { diedAt = nil, livesUsed = 0 }
	return MatchRules.canSpawn(mode, pilot, os.clock())
end

local function spawnGate(player: Player, _airframeId: string): (boolean, CFrame?, string?)
	ensureScore(player, player.Name, false, player.UserId)
	local allowed = canSpawn(player)
	if not allowed then
		return false, nil
	end
	-- No BR cap on spawning (Will: let any lineup jet fly). The band still picks the AI's jets; proper
	-- BR matching comes with separate match servers (MMK-02–04).
	pilotStates[player].livesUsed += 1
	return true, MatchService:PickSpawn()
end

local function clearJets()
	for _, jet in AircraftService:GetJets() do
		AircraftService:Despawn(jet, "Despawn")
	end
end

-- The match's BR band from the lineups of the players here (MMK-01), and AI jets to match it.
local function refreshBand()
	local lineups = {}
	for _, player in humans() do
		local data = DataService:GetData(player)
		if data then
			table.insert(lineups, data.Lineup)
		end
	end
	band = Matchmaking.band(lineups)
	local choices = Matchmaking.aiAirframes(band)
	for i, pilot in AIService:GetPilots() do
		AIService:SetAirframe(pilot, choices[(i - 1) % #choices + 1])
	end
end

local function syncAIFill()
	local wanted = if mode.AIFill > 0 and state ~= "Waiting" then math.max(mode.AIFill - #humans(), 0) else 0
	local current = AIService:GetPilots()
	while #current > wanted do
		local pilot = current[#current]
		scores[pilot.identity] = nil
		pilotStates[pilot.identity] = nil
		AIService:RemovePilot(pilot)
	end
	while #AIService:GetPilots() < wanted do
		local choices = Matchmaking.aiAirframes(band)
		local pilot = AIService:CreatePilot("Normal", choices[#AIService:GetPilots() % #choices + 1])
		ensureScore(pilot.identity, pilot.identity.Name, true, 0)
	end
end

local function startMatch()
	scores = {}
	pilotStates = {}
	results = nil
	clearJets()
	refreshBand()
	for _, player in humans() do
		ensureScore(player, player.Name, false, player.UserId)
	end
	for _, pilot in AIService:GetPilots() do
		ensureScore(pilot.identity, pilot.identity.Name, true, 0)
	end
	setState("InProgress")
end

local function endMatch(reason: string)
	local ranking = MatchRules.ranking(scores)
	results = { winner = ranking[1] and ranking[1].name, reason = reason, ranking = ranking }
	setState("Results")
	clearJets()
	MatchService.MatchEnded:Fire(ranking, reason)
	Telemetry.event("MatchEnded", os.clock() - stateSince, {
		mode = mode.Id,
		reason = reason,
		pilots = #ranking,
	})
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
	if QUIET_CAUSES[cause] and credit.killer == nil then
		return -- leaving or respawning with nobody's damage on you isn't a death
	end
	MatchRules.recordKill(scores, victim, credit.killer, credit.assists, credit.forcedCrash)
	Telemetry.event("Death", 1, { cause = cause, mode = mode.Id })
end

local function respawnAI()
	if state ~= "InProgress" and mode.Id ~= "FreeFlight" then
		return
	end
	for _, pilot in AIService:GetPilots() do
		if not pilot.jet then
			ensureScore(pilot.identity, pilot.identity.Name, true, 0)
			local allowed = canSpawn(pilot.identity)
			if allowed then
				pilotStates[pilot.identity].livesUsed += 1
				AIService:SpawnPilot(pilot, MatchService:PickSpawn())
			end
		end
	end
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
	if state == "Countdown" then
		timeLeft = mode.CountdownSeconds - elapsed
	elseif state == "InProgress" and mode.TimeLimit > 0 then
		timeLeft = mode.TimeLimit - elapsed
	elseif state == "Results" then
		timeLeft = mode.ResultsSeconds - elapsed
	end
	local ranking = if results then results.ranking else MatchRules.ranking(scores)
	Net.Server.fireAll("MatchState", {
		mode = mode.Id,
		modeName = mode.DisplayName,
		state = state,
		timeLeft = math.max(math.ceil(timeLeft), 0),
		scoreLimit = mode.ScoreLimit,
		scored = mode.Scored,
		ranking = ranking,
		winner = results and results.winner,
		reason = results and results.reason,
		br = if mode.Scored then { min = band.min, max = band.max } else nil,
	})
end

local function tick(dt: number)
	local elapsed = os.clock() - stateSince
	if mode.Id == "FreeFlight" then
		if state ~= "InProgress" then
			setState("InProgress")
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
	elseif state == "InProgress" then
		if #humans() == 0 then
			clearJets()
			setState("Waiting")
		else
			local ended, reason = MatchRules.checkEnd(mode, scores, elapsed)
			if ended then
				endMatch(reason :: string)
			end
		end
	elseif state == "Results" then
		if elapsed >= mode.ResultsSeconds then
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

function MatchService:SetMode(modeId: string)
	local config = (MatchRules.MODES :: any)[modeId]
	if not config then
		return
	end
	mode = config
	ReplicatedStorage:SetAttribute("GameMode", modeId)
	clearJets()
	scores = {}
	pilotStates = {}
	results = nil
	AIService:RemoveAll()
	setState(if modeId == "FreeFlight" then "InProgress" else "Waiting")
end

function MatchService:GetMode(): MatchRules.ModeConfig
	return mode
end

function MatchService:GetState(): string
	return state
end

function MatchService:Init()
	local configured = ReplicatedStorage:GetAttribute("GameMode")
	if type(configured) == "string" and (MatchRules.MODES :: any)[configured] then
		mode = (MatchRules.MODES :: any)[configured]
	end
	ReplicatedStorage:SetAttribute("GameMode", mode.Id)
	AircraftService.spawnGate = spawnGate
	CombatService.Kill:Connect(onKill)

	Players.PlayerAdded:Connect(function(player)
		ensureScore(player, player.Name, false, player.UserId)
		broadcastTimer = BROADCAST_INTERVAL
	end)
	Players.PlayerRemoving:Connect(function(player)
		scores[player] = nil
		pilotStates[player] = nil
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
