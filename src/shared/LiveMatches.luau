--!strict
-- Matches in progress that a pilot in a lobby can jump into (Will: show ongoing games and let people join them
-- easily). Pure: match servers report themselves (MatchmakingService, a short-lived MemoryStore entry each);
-- lobbies list the joinable ones on the Hangar with a JOIN button. A joiner takes an AI pilot's seat (MatchService
-- evens the teams). Also whether "Any mode" is recommended: while few pilots are online it finds a match
-- fastest.

local Queue = require(script.Parent.Queue)

local LiveMatches = {}

export type Entry = {
	id: string, -- the reserved server's id
	mode: string,
	map: string?,
	state: string, -- MatchService's state
	humans: number,
	seats: number,
	timeLeft: number, -- seconds left in the match (or the countdown)
	at: number, -- when the match server last reported (unix seconds)
}

LiveMatches.REPORT_EVERY = 5 -- seconds between a match server's reports
LiveMatches.STALE_AFTER = 20 -- a report older than this is a match that's gone
LiveMatches.MIN_TIME_LEFT = 60 -- seconds: not worth joining a match about to end
LiveMatches.SHOWN = 3 -- on the Hangar
LiveMatches.LOW_POPULATION = 20 -- fewer pilots online than this: "Any mode" is recommended

-- Whether a pilot in a lobby can join it now: in progress (or counting down), a free seat, time left, still
-- reporting. Duels are one on one, so never.
function LiveMatches.joinable(entry: Entry, now: number): boolean
	if Queue.DUEL_MODES[entry.mode] then
		return false
	end
	if entry.state ~= "InProgress" and entry.state ~= "Countdown" then
		return false
	end
	if entry.humans >= entry.seats then
		return false
	end
	if entry.state == "InProgress" and entry.timeLeft < LiveMatches.MIN_TIME_LEFT then
		return false
	end
	return now - entry.at <= LiveMatches.STALE_AFTER
end

-- The joinable ones, best first: the most players (more fun), then the most time left.
function LiveMatches.list(entries: { Entry }, now: number): { Entry }
	local out = {}
	for _, entry in entries do
		if LiveMatches.joinable(entry, now) then
			table.insert(out, entry)
		end
	end
	table.sort(out, function(a, b)
		if a.humans ~= b.humans then
			return a.humans > b.humans
		end
		if a.timeLeft ~= b.timeLeft then
			return a.timeLeft > b.timeLeft
		end
		return a.id < b.id
	end)
	return out
end

-- Pilots online across the game, roughly: in matches, queuing and in this lobby.
function LiveMatches.online(entries: { Entry }, queued: number, inLobby: number, now: number): number
	local total = queued + inLobby
	for _, entry in entries do
		if now - entry.at <= LiveMatches.STALE_AFTER then
			total += entry.humans
		end
	end
	return total
end

function LiveMatches.recommendAny(online: number): boolean
	return online < LiveMatches.LOW_POPULATION
end

return LiveMatches
