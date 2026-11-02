--!strict
-- Leaderboards (LIV-05, DAT-04; DEVELOPMENT.md §26.8). Five boards, each an OrderedDataStore: kills and
-- wins this week (a new store every Monday 00:00 UTC, the same week as the Shop's bundle), the season's XP
-- (a store per season), all-time kills, squadrons this week and duel ratings (MCH-09). Only scored matches count (not training or free flight), and
-- only other players shot down (Will: AI pilots filling empty seats don't count). Pure: LeaderboardService
-- writes and reads the stores; data.Weekly holds this week's counts.

local Seasons = require(script.Parent.Config.Seasons)

local Leaderboards = {}

Leaderboards.TOP = 50 -- entries shown per board
Leaderboards.WEEK = 7 * 86400
local MONDAY = 4 * 86400 -- the unix epoch was a Thursday

export type Board = { id: string, name: string, unit: string, squadron: boolean? } -- squadron: keyed by squadron id

Leaderboards.BOARDS = table.freeze({
	{ id = "KillsWeek", name = "Kills this week", unit = "kills" },
	{ id = "WinsWeek", name = "Wins this week", unit = "wins" },
	{ id = "Season", name = "Season XP", unit = "XP" },
	{ id = "KillsAll", name = "All-time kills", unit = "kills" },
	{ id = "SquadronWeek", name = "Squadrons this week", unit = "points", squadron = true },
	{ id = "Duel", name = "Duel rating", unit = "rating" },
}) :: { Board }

function Leaderboards.get(id: string): Board?
	for _, board in Leaderboards.BOARDS do
		if board.id == id then
			return board
		end
	end
	return nil
end

-- The week number (changes on Monday at 00:00 UTC).
function Leaderboards.week(now: number): number
	return (now - MONDAY) // Leaderboards.WEEK
end

-- The OrderedDataStore a board uses at a time, or nil if it has none then (Season between seasons).
function Leaderboards.storeName(id: string, now: number): string?
	if id == "KillsWeek" or id == "WinsWeek" or id == "SquadronWeek" then
		return `LB_{id}_{Leaderboards.week(now)}`
	elseif id == "Season" then
		local season = Seasons.at(now)
		return if season then `LB_Season_{season.Id}` else nil
	elseif id == "KillsAll" then
		return "LB_KillsAll"
	elseif id == "Duel" then
		return "LB_DuelRating"
	end
	return nil
end

function Leaderboards.newWeekly(): { [string]: any }
	return { Week = 0, Kills = 0, Wins = 0 }
end

-- This week's counts, started afresh if the save's are from an earlier week.
function Leaderboards.weekly(data: { [string]: any }, now: number): { [string]: any }
	local week = Leaderboards.week(now)
	if type(data.Weekly) ~= "table" or data.Weekly.Week ~= week then
		data.Weekly = { Week = week, Kills = 0, Wins = 0 }
	end
	return data.Weekly
end

-- A scored match's kills and win, added to this week's counts.
function Leaderboards.record(data: { [string]: any }, kills: number, won: boolean, now: number)
	local weekly = Leaderboards.weekly(data, now)
	weekly.Kills += kills
	if won then
		weekly.Wins += 1
	end
end

-- A player's score on a board now (0 if they've none).
function Leaderboards.score(data: { [string]: any }, id: string, now: number): number
	if id == "KillsWeek" or id == "WinsWeek" then
		local weekly = data.Weekly
		if type(weekly) ~= "table" or weekly.Week ~= Leaderboards.week(now) then
			return 0
		end
		return if id == "KillsWeek" then weekly.Kills or 0 else weekly.Wins or 0
	elseif id == "Season" then
		local season = Seasons.at(now)
		local saved = data.Season
		return if season and type(saved) == "table" and saved.Id == season.Id then math.floor(saved.XP or 0) else 0
	elseif id == "KillsAll" then
		return (data.Stats and data.Stats.Kills) or 0 -- players only
	elseif id == "Duel" then
		-- Only pilots who've played a ranked-or-casual duel are on it
		local duel = data.Duel
		return if type(duel) == "table" and (duel.Played or 0) > 0 then math.floor(duel.Rating or 0) else 0
	end
	return 0
end

return Leaderboards
