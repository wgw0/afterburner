--!strict
-- Forming matches from the matchmaking queue (DEVELOPMENT.md §25.2, MMK-03). Pure: the lobby's
-- MatchmakingService feeds it the queue and gets back the matches to make.
--   Each entry is one player: their lineup BR, the mode they asked for ("Any" or a mode id) and when they
--   joined. The longest-waiting player anchors a group: players whose mode fits and whose BR is within the
--   spread join it (closest BR first, up to MATCH_SIZE). The spread starts at BR 1.0 and widens to 1.7 over
--   a minute of waiting (DESIGN §5.2). A full group becomes a match at once; a smaller one once its anchor
--   has waited FILL_AFTER seconds, and AI fills the empty seats on the battle server.

local Matchmaking = require(script.Parent.Matchmaking)

local Queue = {}

Queue.MATCH_SIZE = 6 -- pilots in a match (Will: 6), so at most this many players
Queue.FILL_AFTER = 30 -- seconds before a match starts short-handed, with AI in the empty seats
Queue.SPREAD_MIN = 1.0
Queue.SPREAD_MAX = 1.7
Queue.SPREAD_GROW_SECONDS = 60
Queue.MODES = table.freeze({ "Dogfight", "TeamDeathmatch", "AirSuperiority", "GunsOnly" })

export type Entry = {
	userId: number,
	br: number,
	mode: string, -- "Any" or one of Queue.MODES
	joinedAt: number, -- seconds (any clock, the same for every entry)
	jobId: string, -- the lobby server the player is on
}

export type Match = {
	mode: string,
	entries: { Entry },
	band: Matchmaking.Band,
	spread: number, -- BR spread of the players in it
	longestWait: number,
}

export type Options = {
	now: number,
	fillAfter: number?, -- defaults to FILL_AFTER (shorter in Studio)
	pickMode: (() -> string)?, -- the mode for an all-"Any" group (defaults to the first)
}

-- The BR spread allowed for a group whose anchor has waited `waited` seconds.
function Queue.spreadFor(waited: number): number
	local t = math.clamp(waited / Queue.SPREAD_GROW_SECONDS, 0, 1)
	return Queue.SPREAD_MIN + (Queue.SPREAD_MAX - Queue.SPREAD_MIN) * t
end

function Queue.validMode(mode: string): boolean
	return mode == "Any" or table.find(Queue.MODES, mode) ~= nil
end

local function fits(entry: Entry, mode: string): boolean
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
		if entry.mode ~= "Any" then
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
	local pickMode = options.pickMode or function()
		return Queue.MODES[1]
	end

	local waiting = table.clone(entries)
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

		-- Closest BR first, keeping the whole group within the spread
		table.sort(near, function(a, b)
			local da, db = math.abs(a.br - anchor.br), math.abs(b.br - anchor.br)
			if da ~= db then
				return da < db
			end
			return a.joinedAt < b.joinedAt
		end)
		local group = { anchor }
		local low, high = anchor.br, anchor.br
		for _, entry in near do
			if #group >= Queue.MATCH_SIZE then
				break
			end
			if fits(entry, mode) and math.max(high, entry.br) - math.min(low, entry.br) <= spread + 1e-6 then
				table.insert(group, entry)
				low, high = math.min(low, entry.br), math.max(high, entry.br)
			end
		end

		if #group >= Queue.MATCH_SIZE or waited >= fillAfter then
			for _, entry in group do
				taken[entry.userId] = true
			end
			table.insert(matches, {
				mode = mode,
				entries = group,
				band = Matchmaking.bandFor(high),
				spread = high - low,
				longestWait = waited,
			})
		end
	end
	return matches
end

return Queue
