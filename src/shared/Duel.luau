--!strict
-- Duels (MCH-09, Will: the main mode): 1v1 in rounds. Pure: MatchService runs the rounds, the matchmaker and
-- ProgressionService use the ratings.
--
-- Rounds: each pilot has one life a round. Both jets start head-on at the same height and speed (spawnPair);
-- the last one flying wins the round. Both down within GRACE of each other (a missile already on its way
-- when its shooter died counts), or the round's time running out, is a drawn round. First to ROUNDS_TO_WIN round wins takes the duel; after MAX_ROUNDS the one ahead wins, else
-- it's a draw.
--
-- Ratings (Elo): Ranked duels move both pilots' ratings by K × (result − expected); a pilot's first
-- PROVISIONAL_GAMES duels use the bigger K so a new pilot finds their level fast. Casual duels and duels
-- against an AI pilot (nobody to duel within AI_AFTER seconds) move nothing. Ranks are rating bands; the first
-- time a pilot reaches a rank (above Bronze) they get its title ("Gold Duelist") and RANK_CREDITS.

local Duel = {}

Duel.ROUNDS_TO_WIN = 3 -- best of five
Duel.MAX_ROUNDS = 7 -- drawn rounds don't count towards a win, so stop somewhere
Duel.ROUND_TIME = 150 -- seconds before a round is drawn
Duel.INTERMISSION = 4 -- seconds between rounds (the result shown, then both jets reset)
Duel.GRACE = 2 -- seconds after the first jet goes down before the round is decided
Duel.SEPARATION = 2400 -- studs between the two jets at the start of a round (~6.3 km real, ~14 s to merge)

Duel.START_RATING = 1000
Duel.K = 32
Duel.K_PROVISIONAL = 48
Duel.PROVISIONAL_GAMES = 10
Duel.AI_AFTER = 45 -- seconds in the queue before an AI pilot takes the other seat (unranked)
-- { seconds waited, rating spread }: who a ranked duel may pair you with, loosening the longer you wait
Duel.RATING_STAGES = table.freeze({ { 0, 150 }, { 30, 300 }, { 45, 600 } })

export type Rank = { id: string, name: string, min: number, colour: Color3 }

-- Credits for reaching each rank the first time (titles: LevelRewards "Duelist<Rank>")
Duel.RANK_CREDITS = table.freeze({ Silver = 2500, Gold = 5000, Platinum = 10000, Diamond = 20000, Ace = 40000 })

Duel.RANKS = table.freeze({
	{ id = "Bronze", name = "Bronze", min = 0, colour = Color3.fromRGB(205, 127, 50) },
	{ id = "Silver", name = "Silver", min = 1100, colour = Color3.fromRGB(192, 200, 212) },
	{ id = "Gold", name = "Gold", min = 1250, colour = Color3.fromRGB(255, 201, 60) },
	{ id = "Platinum", name = "Platinum", min = 1400, colour = Color3.fromRGB(110, 230, 220) },
	{ id = "Diamond", name = "Diamond", min = 1600, colour = Color3.fromRGB(120, 170, 255) },
	{ id = "Ace", name = "Ace", min = 1800, colour = Color3.fromRGB(255, 90, 90) },
}) :: { Rank }

-- The saved duel record (data.Duel).
function Duel.newRecord(): { [string]: any }
	return { Rating = Duel.START_RATING, Peak = Duel.START_RATING, Played = 0, Won = 0, Lost = 0, Drawn = 0 }
end

function Duel.record(data: { [string]: any }): { [string]: any }
	if type(data.Duel) ~= "table" then
		data.Duel = Duel.newRecord()
	end
	return data.Duel
end

function Duel.rankFor(rating: number): Rank
	local best = Duel.RANKS[1]
	for _, rank in Duel.RANKS do
		if rating >= rank.min then
			best = rank
		end
	end
	return best
end

-- The next rank up and the rating it needs, or nil at the top.
function Duel.nextRank(rating: number): Rank?
	for _, rank in Duel.RANKS do
		if rank.min > rating then
			return rank
		end
	end
	return nil
end

-- The chance (0–1) a pilot rated `a` beats one rated `b`.
function Duel.expected(a: number, b: number): number
	return 1 / (1 + 10 ^ ((b - a) / 400))
end

-- The rating change for a pilot rated `mine` who scored `result` (1 win, 0.5 draw, 0 loss) against
-- `theirs`, after `played` earlier duels. Whole points, at least 1 either way for a win or a loss.
function Duel.change(mine: number, theirs: number, result: number, played: number): number
	local k = if played < Duel.PROVISIONAL_GAMES then Duel.K_PROVISIONAL else Duel.K
	local delta = k * (result - Duel.expected(mine, theirs))
	local rounded = math.round(delta)
	if result == 1 and rounded < 1 then
		return 1
	elseif result == 0 and rounded > -1 then
		return -1
	end
	return rounded
end

-- Applies a finished duel to a save: the record's counts, and (ranked) the rating, with the title and Credits
-- for any rank reached for the first time. Returns the change and the ranks newly reached (lowest first).
function Duel.apply(data: { [string]: any }, theirs: number, result: number, ranked: boolean): (number, { Rank })
	local rec = Duel.record(data)
	local delta = if ranked then Duel.change(rec.Rating, theirs, result, rec.Played) else 0
	rec.Played += 1
	if result == 1 then
		rec.Won += 1
	elseif result == 0 then
		rec.Lost += 1
	else
		rec.Drawn += 1
	end
	local peakBefore = rec.Peak or rec.Rating
	rec.Rating = math.max(rec.Rating + delta, 0)
	rec.Peak = math.max(peakBefore, rec.Rating)
	local reached = {}
	for _, rank in Duel.RANKS do
		local credits = Duel.RANK_CREDITS[rank.id]
		if credits and rank.min > peakBefore and rank.min <= rec.Peak then
			table.insert(reached, rank)
			data.Titles = data.Titles or {}
			data.Titles[`Duelist{rank.id}`] = true
			data.Credits = (data.Credits or 0) + credits
		end
	end
	return delta, reached
end

-- The rating spread a ranked duel allows after waiting `waited` seconds.
function Duel.ratingSpread(waited: number): number
	local stages = Duel.RATING_STAGES
	for i = 2, #stages do
		local from, to = stages[i - 1], stages[i]
		if waited < to[1] then
			local t = math.clamp((waited - from[1]) / (to[1] - from[1]), 0, 1)
			return from[2] + (to[2] - from[2]) * t
		end
	end
	return stages[#stages][2]
end

------------------------------------------------------------------------------------------------ rounds

export type State = {
	pilots: { any }, -- the two pilot identities, in seat order
	wins: { [any]: number },
	round: number,
	phase: "Fight" | "Deciding" | "Intermission" | "Over",
	phaseSince: number,
	alive: { [any]: boolean },
	decidingAt: number?, -- when the first jet of the round went down
	lastRound: { winner: any?, reason: string }?, -- the round just finished
}

function Duel.newState(now: number): State
	return {
		pilots = {},
		wins = {},
		round = 0,
		phase = "Intermission",
		phaseSince = now - Duel.INTERMISSION,
		alive = {},
	}
end

-- Seats a pilot (up to two). Returns their seat, or nil if both are taken.
function Duel.seat(state: State, identity: any): number?
	local index = table.find(state.pilots, identity)
	if index then
		return index
	end
	if #state.pilots >= 2 then
		return nil
	end
	table.insert(state.pilots, identity)
	state.wins[identity] = state.wins[identity] or 0
	return #state.pilots
end

function Duel.unseat(state: State, identity: any)
	local index = table.find(state.pilots, identity)
	if index then
		table.remove(state.pilots, index)
	end
	state.alive[identity] = nil
end

-- Starts the next round: everyone seated is alive again.
function Duel.startRound(state: State, now: number)
	state.round += 1
	state.phase = "Fight"
	state.phaseSince = now
	state.alive = {}
	state.decidingAt = nil
	for _, identity in state.pilots do
		state.alive[identity] = true
	end
end

-- The match winner (an identity), "Draw", or nil while it goes on.
function Duel.matchResult(state: State): any?
	for _, identity in state.pilots do
		if (state.wins[identity] or 0) >= Duel.ROUNDS_TO_WIN then
			return identity
		end
	end
	if state.round >= Duel.MAX_ROUNDS then
		local a, b = state.pilots[1], state.pilots[2]
		local wa, wb = a and state.wins[a] or 0, b and state.wins[b] or 0
		if wa == wb then
			return "Draw"
		end
		return if wa > wb then a else b
	end
	return nil
end

local function finishRound(state: State, winner: any?, reason: string, now: number)
	if winner ~= nil then
		state.wins[winner] = (state.wins[winner] or 0) + 1
	end
	state.lastRound = { winner = winner, reason = reason }
	state.phase = if Duel.matchResult(state) ~= nil then "Over" else "Intermission"
	state.phaseSince = now
end

local function flying(state: State): { any }
	local left = {}
	for _, pilot in state.pilots do
		if state.alive[pilot] then
			table.insert(left, pilot)
		end
	end
	return left
end

-- A pilot went down this round. With one or none left flying the round is decided GRACE later (or at once
-- if nobody's left).
function Duel.down(state: State, identity: any, now: number)
	if (state.phase ~= "Fight" and state.phase ~= "Deciding") or not state.alive[identity] then
		return
	end
	state.alive[identity] = nil
	local left = flying(state)
	if #left == 0 then
		finishRound(state, nil, "Both down", now)
	elseif #left == 1 and state.phase == "Fight" then
		state.phase = "Deciding"
		state.decidingAt = now
	end
end

-- Moves the rounds on with time: a drawn round at the time limit. Returns "Start" when the next round
-- should begin (after the intermission), else nil.
function Duel.step(state: State, now: number): string?
	if state.phase == "Fight" and now - state.phaseSince >= Duel.ROUND_TIME then
		finishRound(state, nil, "Time", now)
	elseif state.phase == "Deciding" and now - (state.decidingAt or now) >= Duel.GRACE then
		finishRound(state, flying(state)[1], "Shot down", now)
	elseif state.phase == "Intermission" and now - state.phaseSince >= Duel.INTERMISSION and #state.pilots == 2 then
		return "Start"
	end
	return nil
end

-- A pilot left (or forfeited): the other one wins the duel outright.
function Duel.forfeit(state: State, identity: any, now: number): any?
	local other = nil
	for _, pilot in state.pilots do
		if pilot ~= identity then
			other = pilot
		end
	end
	if other ~= nil and state.phase ~= "Over" then
		state.wins[other] = Duel.ROUNDS_TO_WIN
		state.lastRound = { winner = other, reason = "Forfeit" }
		state.phase = "Over"
		state.phaseSince = now
	end
	return other
end

-- The two start positions for a round: head-on over the map centre, SEPARATION apart, both level at
-- `altitude` facing each other. Seat 1 starts in the west.
function Duel.spawnPair(centre: Vector3, altitude: number): { CFrame }
	local half = Duel.SEPARATION / 2
	local a = Vector3.new(centre.X - half, altitude, centre.Z)
	local b = Vector3.new(centre.X + half, altitude, centre.Z)
	return { CFrame.lookAt(a, b), CFrame.lookAt(b, a) }
end

return Duel
