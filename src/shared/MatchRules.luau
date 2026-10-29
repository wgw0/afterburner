--!strict
-- Match rules (DEVELOPMENT.md §17): mode configs, scoring, end conditions and respawn rules. Pure, so the
-- server's MatchService and the tests share one source of truth.
--
-- Scores are keyed by "pilot identity": a Player, or an AI pilot record. Anything usable as a table key.

local MatchRules = {}

export type RespawnRule = { Type: "Timer", Delay: number } | { Type: "Lives", Lives: number, Delay: number }

export type ModeConfig = {
	Id: string,
	DisplayName: string,
	ScoreLimit: number, -- kills to win (0 = none)
	TimeLimit: number, -- seconds (0 = none)
	Respawn: RespawnRule,
	AIFill: number, -- keep this many pilots in the match with AI (0 = none)
	Scored: boolean,
	CountdownSeconds: number,
	ResultsSeconds: number,
	Teams: { string }?, -- team modes: the team ids (ScoreLimit is then team kills)
}

export type Score = {
	name: string,
	isAI: boolean,
	userId: number,
	kills: number,
	assists: number,
	deaths: number,
	score: number,
	team: string?,
}

MatchRules.POINTS = table.freeze({ Kill = 100, Assist = 50, ForcedCrashKill = 100 })

MatchRules.MODES = table.freeze({
	FreeFlight = table.freeze({
		Id = "FreeFlight",
		DisplayName = "Free Flight",
		ScoreLimit = 0,
		TimeLimit = 0,
		Respawn = { Type = "Timer", Delay = 0 },
		AIFill = 0,
		Scored = false,
		CountdownSeconds = 0,
		ResultsSeconds = 0,
	} :: ModeConfig),
	Dogfight = table.freeze({
		Id = "Dogfight",
		DisplayName = "Dogfight (Free for all)",
		ScoreLimit = 15,
		TimeLimit = 600,
		-- Respawn model is still to be decided after playtesting (DESIGN §11): both types are supported.
		Respawn = { Type = "Timer", Delay = 5 },
		AIFill = 8,
		Scored = true,
		CountdownSeconds = 8,
		ResultsSeconds = 12,
	} :: ModeConfig),
	-- MCH-05: two teams, West and East (they spawn over their own coast). Team kills score; no friendly fire.
	TeamDeathmatch = table.freeze({
		Id = "TeamDeathmatch",
		DisplayName = "Team Deathmatch",
		ScoreLimit = 30,
		TimeLimit = 600,
		Respawn = { Type = "Timer", Delay = 5 },
		AIFill = 8,
		Scored = true,
		CountdownSeconds = 8,
		ResultsSeconds = 12,
		Teams = table.freeze({ "West", "East" }),
	} :: ModeConfig),
	-- Test environment only (DebugSetMode): the PRF-02 stress test, bots fill the match to 24 jets.
	Stress = table.freeze({
		Id = "Stress",
		DisplayName = "Stress test (24 jets)",
		ScoreLimit = 0,
		TimeLimit = 0,
		Respawn = { Type = "Timer", Delay = 2 },
		AIFill = 24,
		Scored = true,
		CountdownSeconds = 3,
		ResultsSeconds = 5,
	} :: ModeConfig),
})

function MatchRules.newScore(name: string, isAI: boolean, userId: number): Score
	return { name = name, isAI = isAI, userId = userId, kills = 0, assists = 0, deaths = 0, score = 0 }
end

-- Records a destroyed jet. killer/assists/victim are identity keys (killer nil = nobody's kill).
function MatchRules.recordKill(
	scores: { [any]: Score },
	victim: any,
	killer: any?,
	assists: { any },
	forcedCrash: boolean
)
	local victimScore = scores[victim]
	if victimScore then
		victimScore.deaths += 1
	end
	local victimTeam = victimScore and victimScore.team
	local function teammate(identity: any): boolean
		local s = scores[identity]
		return victimTeam ~= nil and s ~= nil and s.team == victimTeam
	end
	if teammate(killer) then
		return -- a teammate's crash or a stray hit scores nothing
	end
	if killer ~= nil and killer ~= victim and scores[killer] then
		local k = scores[killer]
		k.kills += 1
		k.score += if forcedCrash then MatchRules.POINTS.ForcedCrashKill else MatchRules.POINTS.Kill
	end
	for _, assist in assists do
		local a = scores[assist]
		if a and assist ~= killer and assist ~= victim and not teammate(assist) then
			a.assists += 1
			a.score += MatchRules.POINTS.Assist
		end
	end
end

-- Scores sorted best first: score, then kills, then fewest deaths, then name.
function MatchRules.ranking(scores: { [any]: Score }): { Score }
	local list = {}
	for _, s in scores do
		table.insert(list, s)
	end
	table.sort(list, function(a, b)
		if a.score ~= b.score then
			return a.score > b.score
		elseif a.kills ~= b.kills then
			return a.kills > b.kills
		elseif a.deaths ~= b.deaths then
			return a.deaths < b.deaths
		end
		return a.name < b.name
	end)
	return list
end

-- Kills per team (team modes). Every team appears, at 0 if it has none.
function MatchRules.teamScores(config: ModeConfig, scores: { [any]: Score }): { [string]: number }
	local totals = {}
	for _, team in config.Teams or {} do
		totals[team] = 0
	end
	for _, s in scores do
		if s.team and totals[s.team] then
			totals[s.team] += s.kills
		end
	end
	return totals
end

-- The team a new pilot joins: the one with the fewest pilots, then the one behind on kills, then the first.
-- `humansFirst` counts only human pilots, so players spread evenly and AI fills the gaps.
function MatchRules.pickTeam(config: ModeConfig, scores: { [any]: Score }, humansFirst: boolean?): string?
	local teams = config.Teams
	if not teams then
		return nil
	end
	local counts = {}
	for _, team in teams do
		counts[team] = 0
	end
	for _, s in scores do
		if s.team and counts[s.team] and not (humansFirst and s.isAI) then
			counts[s.team] += 1
		end
	end
	local kills = MatchRules.teamScores(config, scores)
	local best = teams[1]
	for _, team in teams do
		if counts[team] < counts[best] or (counts[team] == counts[best] and kills[team] < kills[best]) then
			best = team
		end
	end
	return best
end

-- The leading team, or nil for a draw (team modes).
function MatchRules.winningTeam(config: ModeConfig, scores: { [any]: Score }): string?
	local best, bestKills, tied = nil, -1, false
	for _, team in config.Teams or {} do
		local kills = MatchRules.teamScores(config, scores)[team]
		if kills > bestKills then
			best, bestKills, tied = team, kills, false
		elseif kills == bestKills then
			tied = true
		end
	end
	return if tied then nil else best
end

-- Has the match ended? Returns (ended, reason).
function MatchRules.checkEnd(config: ModeConfig, scores: { [any]: Score }, elapsed: number): (boolean, string?)
	if config.ScoreLimit > 0 and config.Teams then
		for _, kills in MatchRules.teamScores(config, scores) do
			if kills >= config.ScoreLimit then
				return true, "ScoreLimit"
			end
		end
	elseif config.ScoreLimit > 0 then
		for _, s in scores do
			if s.kills >= config.ScoreLimit then
				return true, "ScoreLimit"
			end
		end
	end
	if config.TimeLimit > 0 and elapsed >= config.TimeLimit then
		return true, "TimeLimit"
	end
	return false, nil
end

export type PilotState = { diedAt: number?, livesUsed: number }

-- Can this pilot spawn now? Returns (allowed, secondsToWait, livesLeft or nil when unlimited).
function MatchRules.canSpawn(config: ModeConfig, pilot: PilotState, now: number): (boolean, number, number?)
	local rule = config.Respawn
	local livesLeft: number? = nil
	if rule.Type == "Lives" then
		livesLeft = math.max((rule :: any).Lives - pilot.livesUsed, 0)
		if livesLeft <= 0 then
			return false, math.huge, 0
		end
	end
	if pilot.diedAt then
		local wait = pilot.diedAt + rule.Delay - now
		if wait > 0 then
			return false, wait, livesLeft
		end
	end
	return true, 0, livesLeft
end

return MatchRules
