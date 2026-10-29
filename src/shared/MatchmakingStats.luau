--!strict
-- Matchmaking telemetry (DEVELOPMENT.md §25.6, MMK-06). Pure: how close a finished match was, and summaries
-- of queue wait times for the admin command matchmaking.stats.

local MatchmakingStats = {}

-- How close a match finished, 1 when level and towards 0 for a walkover: the top two of `points` (team
-- kills, Air Superiority tickets left, or the two best pilots' kills) as (second + 1) / (first + 1). The
-- +1 keeps low-scoring matches fair: 1–0 is 0.5, not a walkover; 10–0 is 0.09.
function MatchmakingStats.closeness(points: { number }): number
	local sorted = table.clone(points)
	table.sort(sorted, function(a, b)
		return a > b
	end)
	local first, second = math.max(sorted[1] or 0, 0), math.max(sorted[2] or 0, 0)
	return (second + 1) / (first + 1)
end

-- The value at fraction p (0..1) of a sorted list, nearest rank.
local function percentile(sorted: { number }, p: number): number
	if #sorted == 0 then
		return 0
	end
	return sorted[math.clamp(math.ceil(p * #sorted), 1, #sorted)]
end

-- Count, median, 90th percentile and longest of a list of seconds, rounded to whole seconds.
function MatchmakingStats.waits(seconds: { number }): { count: number, median: number, p90: number, max: number }
	local sorted = table.clone(seconds)
	table.sort(sorted)
	return {
		count = #sorted,
		median = math.round(percentile(sorted, 0.5)),
		p90 = math.round(percentile(sorted, 0.9)),
		max = math.round(sorted[#sorted] or 0),
	}
end

-- Appends to a rolling window, dropping the oldest past `limit`.
function MatchmakingStats.push(list: { any }, value: any, limit: number)
	table.insert(list, value)
	if #list > limit then
		table.remove(list, 1)
	end
end

return MatchmakingStats
