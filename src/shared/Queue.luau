--!strict
-- Forming matches from the matchmaking queue (DEVELOPMENT.md §25.2, MMK-03). Pure: the lobby's
-- MatchmakingService feeds it the queue and gets back the matches to make.
--   Each entry is one player or one party (MMK-05: members, keyed by its leader): its BR (a party's is its
--   highest), the mode asked for ("Any" or a mode id) and when it joined. The longest-waiting entry anchors a
--   group: entries whose mode fits and whose BR is within the spread join it (closest BR first, while their
--   pilots still fit in MATCH_SIZE seats). The longer the wait, the looser the rules (Will): the spread
--   starts at BR 1.0, widens to 1.7 over the first minute (DESIGN §5.2), then on to 3.0 by two and a half
--   minutes (SPREAD_STAGES); after ANY_MODE_AFTER seconds a player who picked a mode takes any mode. A full
--   group becomes a match at once; a smaller one once its anchor has waited FILL_AFTER seconds, and AI
--   fills the empty seats on the battle server.
-- Duels (MCH-09) are two seats, one pilot each (no parties). A ranked duel also needs the two ratings within
-- Duel.ratingSpread of each other; after Duel.AI_AFTER seconds alone an AI pilot takes the other seat. "Any"
-- never means a duel, and a duel never turns into another mode.

local Duel = require(script.Parent.Duel)
local Matchmaking = require(script.Parent.Matchmaking)

local Queue = {}

Queue.MATCH_SIZE = 6 -- pilots in a match (Will: 6), so at most this many players
Queue.FILL_AFTER = 30 -- seconds before a match starts short-handed, with AI in the empty seats
-- { seconds waited, BR spread }: the spread grows linearly between these and stops at the last
Queue.SPREAD_STAGES = table.freeze({ { 0, 1.0 }, { 60, 1.7 }, { 150, 3.0 } })
Queue.SPREAD_MIN = Queue.SPREAD_STAGES[1][2]
Queue.SPREAD_MAX = Queue.SPREAD_STAGES[#Queue.SPREAD_STAGES][2]
Queue.ANY_MODE_AFTER = 120 -- seconds before a player who picked a mode will take any mode
Queue.MODES = table.freeze({ "Duel", "DuelCasual", "Dogfight", "TeamDeathmatch", "AirSuperiority", "GunsOnly" })
Queue.ANY_MODES = table.freeze({ "Dogfight", "TeamDeathmatch", "AirSuperiority", "GunsOnly" }) -- what "Any" can be
Queue.DUEL_MODES = table.freeze({ Duel = true, DuelCasual = true })

export type Entry = {
	userId: number, -- the player, or the party's leader
	members: { number }?, -- a party: everyone in it, leader first (nil for one player)
	br: number,
	mode: string, -- "Any" or one of Queue.MODES
	joinedAt: number, -- seconds (any clock, the same for every entry)
	jobId: string, -- the lobby server the player is on
	rating: number?, -- duels: the player's duel rating
	airframe: string?, -- the jet PLAY was clicked with (a duel launches in it)
}

export type Match = {
	mode: string,
	entries: { Entry },
	band: Matchmaking.Band,
	spread: number, -- BR spread of the players in it
	longestWait: number,
	players: number, -- pilots in it (a party counts each member)
}

export type Options = {
	now: number,
	fillAfter: number?, -- defaults to FILL_AFTER (shorter in Studio)
	duelFillAfter: number?, -- defaults to Duel.AI_AFTER (shorter in Studio)
	pickMode: (() -> string)?, -- the mode for an all-"Any" group (defaults to the first)
}

-- Seats in a match of this mode.
function Queue.sizeFor(mode: string): number
	return if Queue.DUEL_MODES[mode] then 2 else Queue.MATCH_SIZE
end

-- The BR spread allowed for a group whose anchor has waited `waited` seconds.
function Queue.spreadFor(waited: number): number
	local stages = Queue.SPREAD_STAGES
	for i = 2, #stages do
		local from, to = stages[i - 1], stages[i]
		if waited < to[1] then
			local t = math.clamp((waited - from[1]) / (to[1] - from[1]), 0, 1)
			return from[2] + (to[2] - from[2]) * t
		end
	end
	return stages[#stages][2]
end

-- The mode a player is matched as after waiting: their pick, or "Any" once they've waited ANY_MODE_AFTER.
function Queue.modeAfter(mode: string, waited: number): string
	return if waited >= Queue.ANY_MODE_AFTER and not Queue.DUEL_MODES[mode] then "Any" else mode
end

function Queue.validMode(mode: string): boolean
	return mode == "Any" or table.find(Queue.MODES, mode) ~= nil
end

-- The pilots an entry brings: a party's members, else one.
function Queue.seats(entry: Entry): number
	return if entry.members then math.max(#entry.members, 1) else 1
end

-- Everyone an entry brings, leader first.
function Queue.users(entry: Entry): { number }
	return if entry.members then table.clone(entry.members) else { entry.userId }
end

local function fits(entry: Entry, mode: string): boolean
	if Queue.DUEL_MODES[mode] then
		return entry.mode == mode and entry.members == nil
	end
	return entry.mode == "Any" or entry.mode == mode
end

-- The mode a group led by `anchor` plays: the anchor's choice, else the mode most of the candidates asked
-- for, else pickMode() (everyone said Any).
local function chooseMode(anchor: Entry, candidates: { Entry }, pickMode: () -> string): string
	if anchor.mode ~= "Any" then
		return anchor.mode
	end
	local counts: { [string]: number } = {}
	local best, bestCount = nil, 0
	for _, entry in candidates do
		if entry.mode ~= "Any" and not Queue.DUEL_MODES[entry.mode] then
			counts[entry.mode] = (counts[entry.mode] or 0) + 1
			if counts[entry.mode] > bestCount then
				best, bestCount = entry.mode, counts[entry.mode]
			end
		end
	end
	return best or pickMode()
end

-- The matches to make now. Entries not in a match stay queued.
function Queue.form(entries: { Entry }, options: Options): { Match }
	local now = options.now
	local fillAfter = options.fillAfter or Queue.FILL_AFTER
	local duelFillAfter = options.duelFillAfter or Duel.AI_AFTER
	local pickMode = options.pickMode or function()
		return Queue.ANY_MODES[1]
	end

	-- Players who've waited long enough take any mode (the match keeps their original entry)
	local waiting = {}
	local original: { [Entry]: Entry } = {}
	for _, entry in entries do
		local mode = Queue.modeAfter(entry.mode, now - entry.joinedAt)
		local view = entry
		if mode ~= entry.mode then
			view = table.clone(entry)
			view.mode = mode
		end
		original[view] = entry
		table.insert(waiting, view)
	end
	table.sort(waiting, function(a, b)
		if a.joinedAt ~= b.joinedAt then
			return a.joinedAt < b.joinedAt
		end
		return a.userId < b.userId
	end)
	local taken: { [number]: boolean } = {}
	local matches: { Match } = {}

	for _, anchor in waiting do
		if taken[anchor.userId] then
			continue
		end
		local waited = now - anchor.joinedAt
		local spread = Queue.spreadFor(waited)

		-- Everyone still free whose BR is close enough to the anchor's
		local near = {}
		for _, entry in waiting do
			if entry ~= anchor and not taken[entry.userId] and math.abs(entry.br - anchor.br) <= spread + 1e-6 then
				table.insert(near, entry)
			end
		end
		local mode = chooseMode(anchor, near, pickMode)
		if Queue.DUEL_MODES[mode] and anchor.members then
			continue -- duels are one on one (the lobby refuses a party anyway)
		end
		local size = Queue.sizeFor(mode)
		local ratingSpread = if mode == "Duel" then Duel.ratingSpread(waited) else math.huge

		-- Closest BR first, keeping the whole group within the spread
		table.sort(near, function(a, b)
			local da, db = math.abs(a.br - anchor.br), math.abs(b.br - anchor.br)
			if da ~= db then
				return da < db
			end
			return a.joinedAt < b.joinedAt
		end)
		local group = { anchor }
		local count = Queue.seats(anchor)
		local low, high = anchor.br, anchor.br
		for _, entry in near do
			if count >= size then
				break
			end
			if
				fits(entry, mode)
				and count + Queue.seats(entry) <= size
				and math.max(high, entry.br) - math.min(low, entry.br) <= spread + 1e-6
				and math.abs((entry.rating or Duel.START_RATING) - (anchor.rating or Duel.START_RATING))
					<= ratingSpread
			then
				table.insert(group, entry)
				count += Queue.seats(entry)
				low, high = math.min(low, entry.br), math.max(high, entry.br)
			end
		end

		if count >= size or waited >= (if Queue.DUEL_MODES[mode] then duelFillAfter else fillAfter) then
			local kept = {}
			for _, entry in group do
				taken[entry.userId] = true
				table.insert(kept, original[entry])
			end
			table.insert(matches, {
				mode = mode,
				entries = kept,
				band = Matchmaking.bandFor(high),
				spread = high - low,
				longestWait = waited,
				players = count,
			})
		end
	end
	return matches
end

return Queue
