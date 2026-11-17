--!strict
-- A new pilot's journey (Will: good coverage data on where new players drop out). For pilots with fewer than
-- NEWCOMER_MATCHES finished, each server tracks how far they got on it, in order:
--   Lobby:    Arrived, Queued (pressed PLAY), Leaving (a teleport to a match or training started)
--   Training: Arrived, MapReady (the map streamed in), InJet, HitEnemy, FirstKill, Won (the first sortie)
--   Match:    Arrived, MapReady, InJet, HitEnemy, FirstKill, MatchOver
-- TelemetryService logs "LeftServer" when they leave a server (value: seconds there; fields: the server's
-- role and the furthest stage), "Travel" when they arrive from a teleport (value: seconds the trip took),
-- "MapReadyTime" (seconds from arriving until the map was in), and on a first visit to training the
-- FirstSortie funnel (one step per stage). Pure: which stage counts.

local Journey = {}

Journey.NEWCOMER_MATCHES = 3
Journey.FUNNEL = "FirstSortie"

Journey.STAGES = table.freeze({
	Lobby = table.freeze({ "Arrived", "Queued", "Leaving" }),
	Training = table.freeze({ "Arrived", "MapReady", "InJet", "HitEnemy", "FirstKill", "Won" }),
	Match = table.freeze({ "Arrived", "MapReady", "InJet", "HitEnemy", "FirstKill", "MatchOver" }),
})

-- Whether a save belongs to a pilot whose journey is tracked.
function Journey.newcomer(data: { [string]: any }?): boolean
	return data ~= nil and ((data.Stats and data.Stats.Matches) or 0) < Journey.NEWCOMER_MATCHES
end

-- Reaching stage `name` on a `role` server, from stage index `at` (0: none yet): the new index, or nil if
-- it isn't a stage there or isn't further on (stages only go forward).
function Journey.advance(role: string, at: number, name: string): number?
	local list = (Journey.STAGES :: any)[role]
	local index = list and table.find(list, name)
	if index and index > at then
		return index
	end
	return nil
end

-- The stage's name at `index` on a `role` server ("None" before the first).
function Journey.name(role: string, index: number): string
	local list = (Journey.STAGES :: any)[role]
	return list and list[index] or "None"
end

return Journey
