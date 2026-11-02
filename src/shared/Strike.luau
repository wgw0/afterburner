--!strict
-- Strike missions (MCH-07 Strike Escort, MCH-08 PvE waves; AI-06 bombers). Pure: MatchService runs the
-- missions, AIService flies the bombers with Strike.bomberDecision.
--
-- Strike Escort: both teams send WAVE_BOMBERS AI bombers at the other side's airbase every WAVE_INTERVAL
-- seconds. A bomber that gets within TARGET_RADIUS of its target scores a strike for its team (and leaves
-- the fight); first to STRIKE_LIMIT strikes wins, else the most strikes (then team kills) at the time limit.
-- PvE waves: up to three players hold off WAVES waves of AI fighters and bombers sent at their airbase. The
-- base takes BASE_HITS bomber strikes; clear every wave to win. Each wave is bigger and its pilots sharper.

local Units = require(script.Parent.Units)

local Strike = {}

Strike.BOMBER_AIRFRAME = "B1B" -- the AI bomber (falls back to FALLBACK_BOMBER until its model is in)
Strike.FALLBACK_BOMBER = "F15E"
Strike.CRUISE_ALTITUDE = 900 -- real metres the bombers fly at
Strike.CRUISE_THROTTLE = 0.5 -- slow enough for fighters to catch them up
Strike.TARGET_RADIUS = 700 -- studs: a bomber this close (horizontally) to its target has bombed it
Strike.WAVE_INTERVAL = 150 -- seconds between Strike Escort waves
Strike.WAVE_BOMBERS = 2 -- bombers per team per Strike Escort wave
Strike.STRIKE_LIMIT = 6
Strike.WAVES = 10 -- PvE
Strike.BASE_HITS = 5 -- PvE: bomber strikes the players' base can take
Strike.WAVE_BREAK = 12 -- PvE: seconds between a wave cleared and the next one

------------------------------------------------------------------------------------------------ bombers

-- How a bomber flies: straight for its target at cruise height, climbing away from the ground, and
-- dropping flares and chaff while a missile is coming (no hard manoeuvring: it's a bomber).
function Strike.bomberDecision(
	memory: { [string]: any },
	position: Vector3,
	target: Vector3,
	groundClearance: number, -- real metres
	incoming: { kind: string }?,
	now: number
): { [string]: any }
	local cruise = Units.toStuds(Strike.CRUISE_ALTITUDE)
	local flat = Vector3.new(target.X - position.X, 0, target.Z - position.Z)
	local heading = if flat.Magnitude > 1 then flat.Unit else Vector3.new(1, 0, 0)
	local climb = math.clamp((cruise - position.Y) / Units.toStuds(400), -0.15, 0.25)
	if groundClearance < 250 then
		climb = 0.4
	end
	local decision = {
		state = "Strike",
		aim = (heading + Vector3.new(0, climb, 0)).Unit,
		throttle = Strike.CRUISE_THROTTLE,
		afterburner = false,
		overG = false,
		gLimit = 3,
		fire = false,
		flare = false,
		chaff = false,
	}
	if incoming and now - (memory.lastDecoy or 0) >= 0.7 then
		memory.lastDecoy = now
		decision.flare = true
		decision.chaff = true
	end
	return decision
end

-- Whether a bomber at `position` has reached `target` (horizontally).
function Strike.reached(position: Vector3, target: Vector3): boolean
	return Vector3.new(position.X - target.X, 0, position.Z - target.Z).Magnitude <= Strike.TARGET_RADIUS
end

-- Where a team's bombers start: over their own side, well behind the front, heading at the target.
function Strike.bomberStart(team: string, target: Vector3, mapHalfExtent: number, index: number): CFrame
	local x = mapHalfExtent * 0.85 * (if team == "West" then -1 else 1)
	local z = (index - 1) * 600 - 300
	local position = Vector3.new(x, Units.toStuds(Strike.CRUISE_ALTITUDE), z)
	return CFrame.lookAt(position, Vector3.new(target.X, position.Y, target.Z))
end

------------------------------------------------------------------------------------------------ Strike Escort

export type EscortState = { strikes: { [string]: number }, nextWave: number, wave: number }

function Strike.newEscort(teams: { string }, now: number): EscortState
	local strikes = {}
	for _, team in teams do
		strikes[team] = 0
	end
	return { strikes = strikes, nextWave = now, wave = 0 }
end

-- Whether a new wave of bombers should launch now (and moves the clock on if so).
function Strike.waveDue(state: EscortState, now: number): boolean
	if now >= state.nextWave then
		state.wave += 1
		state.nextWave = now + Strike.WAVE_INTERVAL
		return true
	end
	return false
end

function Strike.strike(state: EscortState, team: string)
	state.strikes[team] = (state.strikes[team] or 0) + 1
end

function Strike.escortEnded(state: EscortState): boolean
	for _, count in state.strikes do
		if count >= Strike.STRIKE_LIMIT then
			return true
		end
	end
	return false
end

-- The winning team: most strikes, then most team kills; nil for a draw.
function Strike.escortWinner(state: EscortState, teamKills: { [string]: number }): string?
	local best, bestKey, tied = nil, nil, false
	for team, count in state.strikes do
		local key = count * 10000 + (teamKills[team] or 0)
		if bestKey == nil or key > bestKey then
			best, bestKey, tied = team, key, false
		elseif key == bestKey then
			tied = true
		end
	end
	return if tied then nil else best
end

------------------------------------------------------------------------------------------------ PvE waves

export type WaveSpec = { fighters: number, bombers: number, difficulty: string }

-- What wave n sends: more fighters and bombers as it goes, sharper pilots from wave 4 and wave 7.
function Strike.waveSpec(n: number): WaveSpec
	return {
		fighters = math.min(1 + n, 8),
		bombers = 1 + (n - 1) // 3,
		difficulty = if n >= 7 then "Ace" elseif n >= 4 then "Hard" else "Normal",
	}
end

export type PveState = {
	wave: number,
	baseHits: number, -- strikes the base can still take
	phase: "Break" | "Fight" | "Won" | "Lost",
	phaseSince: number,
}

function Strike.newPve(now: number): PveState
	return { wave = 0, baseHits = Strike.BASE_HITS, phase = "Break", phaseSince = now - Strike.WAVE_BREAK + 5 }
end

-- Moves the waves on. `alive` is how many of the current wave's pilots are still in it. Returns "Launch"
-- when the next wave should go.
function Strike.stepPve(state: PveState, alive: number, now: number): string?
	if state.phase == "Fight" and alive == 0 then
		if state.wave >= Strike.WAVES then
			state.phase = "Won"
		else
			state.phase = "Break"
		end
		state.phaseSince = now
	elseif state.phase == "Break" and now - state.phaseSince >= Strike.WAVE_BREAK then
		state.wave += 1
		state.phase = "Fight"
		state.phaseSince = now
		return "Launch"
	end
	return nil
end

-- A bomber hit the players' base.
function Strike.baseHit(state: PveState, now: number)
	state.baseHits = math.max(state.baseHits - 1, 0)
	if state.baseHits == 0 and state.phase ~= "Won" then
		state.phase = "Lost"
		state.phaseSince = now
	end
end

return Strike
