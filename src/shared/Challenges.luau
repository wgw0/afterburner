--!strict
-- Daily and weekly challenges (DEVELOPMENT.md §26.1, LIV-01; DESIGN §10). Pure, so the server and the tests
-- share it; ChallengeService feeds it events from matches.
--   Daily: 3 a day from DAILY_POOL, the same 3 for every player (picked by a generator seeded with the UTC
--     day), new at 00:00 UTC. One reroll a day swaps one unfinished challenge for another from the pool.
--   Weekly: 2 a week from WEEKLY_POOL, new on Monday 00:00 UTC.
--   A challenge counts events of one kind that pass its filter; at its target it's done and pays its reward.
-- Saved per player as data.Challenges = { Day, Week, Daily = { Entry }, Weekly = { Entry }, Rerolls }.

export type Def = {
	id: string,
	text: string,
	event: string, -- Kill | Assist | Win | MatchFinished | Capture | MissileDefeated
	target: number,
	credits: number,
	xp: number,
	filter: Filter?,
}
export type Filter = { weapon: string?, maxTier: number?, mode: string?, survived: boolean? }
export type Event = {
	kind: string,
	weapon: string?, -- "Gun" | "IR" | "Radar" (kills, missiles defeated)
	tier: number?, -- tier of the jet flown
	mode: string?,
	survived: boolean?, -- MatchFinished: not shot down all match
}
export type Entry = { Id: string, Progress: number, Done: boolean }
export type State = { Day: number, Week: number, Daily: { Entry }, Weekly: { Entry }, Rerolls: number }

local Challenges = {}

Challenges.DAILY_COUNT = 3
Challenges.WEEKLY_COUNT = 2
Challenges.REROLLS_PER_DAY = 1

Challenges.DAILY_POOL = table.freeze({
	{
		id = "IRKills",
		text = "Get 2 kills with heat-seekers",
		event = "Kill",
		target = 2,
		credits = 1500,
		xp = 150,
		filter = { weapon = "IR" },
	},
	{
		id = "RadarKills",
		text = "Get 2 kills with radar missiles",
		event = "Kill",
		target = 2,
		credits = 1500,
		xp = 150,
		filter = { weapon = "Radar" },
	},
	{
		id = "GunKills",
		text = "Shoot down 3 jets with guns",
		event = "Kill",
		target = 3,
		credits = 2000,
		xp = 200,
		filter = { weapon = "Gun" },
	},
	{ id = "Kills", text = "Get 5 kills", event = "Kill", target = 5, credits = 1500, xp = 150 },
	{
		id = "LowTierKills",
		text = "Get 3 kills in a Tier I or II jet",
		event = "Kill",
		target = 3,
		credits = 2000,
		xp = 200,
		filter = { maxTier = 2 },
	},
	{ id = "Assists", text = "Get 3 assists", event = "Assist", target = 3, credits = 1200, xp = 120 },
	{ id = "Win", text = "Win a match", event = "Win", target = 1, credits = 2000, xp = 200 },
	{
		id = "TeamWin",
		text = "Win a Team Deathmatch",
		event = "Win",
		target = 1,
		credits = 2000,
		xp = 200,
		filter = { mode = "TeamDeathmatch" },
	},
	{ id = "Matches", text = "Finish 3 matches", event = "MatchFinished", target = 3, credits = 1200, xp = 120 },
	{
		id = "Survivor",
		text = "Finish a match without being shot down",
		event = "MatchFinished",
		target = 1,
		credits = 2000,
		xp = 200,
		filter = { survived = true },
	},
	{
		id = "Captures",
		text = "Capture 2 zones in Air Superiority",
		event = "Capture",
		target = 2,
		credits = 1800,
		xp = 180,
	},
	{
		id = "Evade",
		text = "Defeat 3 missiles fired at you",
		event = "MissileDefeated",
		target = 3,
		credits = 1500,
		xp = 150,
	},
} :: { Def })

Challenges.WEEKLY_POOL = table.freeze({
	{ id = "WeekKills", text = "Get 25 kills", event = "Kill", target = 25, credits = 10000, xp = 1000 },
	{ id = "WeekWins", text = "Win 5 matches", event = "Win", target = 5, credits = 12000, xp = 1200 },
	{ id = "WeekMatches", text = "Finish 15 matches", event = "MatchFinished", target = 15, credits = 8000, xp = 800 },
	{
		id = "WeekGunKills",
		text = "Shoot down 10 jets with guns",
		event = "Kill",
		target = 10,
		credits = 10000,
		xp = 1000,
		filter = { weapon = "Gun" },
	},
	{ id = "WeekCaptures", text = "Capture 10 zones", event = "Capture", target = 10, credits = 10000, xp = 1000 },
	{
		id = "WeekEvade",
		text = "Defeat 15 missiles fired at you",
		event = "MissileDefeated",
		target = 15,
		credits = 9000,
		xp = 900,
	},
} :: { Def })

local BY_ID: { [string]: Def } = {}
for _, pool in { Challenges.DAILY_POOL, Challenges.WEEKLY_POOL } do
	for _, def in pool do
		BY_ID[def.id] = def
	end
end

function Challenges.get(id: string): Def?
	return BY_ID[id]
end

-- The UTC day number and the week number (weeks start on Monday; day 0, 1 January 1970, was a Thursday).
function Challenges.day(unix: number): number
	return unix // 86400
end

function Challenges.week(unix: number): number
	return (unix // 86400 + 3) // 7
end

-- Seconds until the next daily and weekly reset.
function Challenges.untilReset(unix: number): (number, number)
	local day = Challenges.day(unix)
	local nextDay = (day + 1) * 86400
	local nextWeek = ((Challenges.week(unix) + 1) * 7 - 3) * 86400
	return nextDay - unix, nextWeek - unix
end

-- `count` ids from a pool, the same for everyone with the same seed.
local function pick(pool: { Def }, count: number, seed: number): { string }
	local ids = {}
	for _, def in pool do
		table.insert(ids, def.id)
	end
	local random = Random.new(seed)
	for i = #ids, 2, -1 do
		local j = random:NextInteger(1, i)
		ids[i], ids[j] = ids[j], ids[i]
	end
	return { table.unpack(ids, 1, math.min(count, #ids)) }
end

function Challenges.dailyFor(day: number): { string }
	return pick(Challenges.DAILY_POOL, Challenges.DAILY_COUNT, day * 7919 + 17)
end

function Challenges.weeklyFor(week: number): { string }
	return pick(Challenges.WEEKLY_POOL, Challenges.WEEKLY_COUNT, week * 104729 + 5)
end

local function entries(ids: { string }): { Entry }
	local list = {}
	for _, id in ids do
		table.insert(list, { Id = id, Progress = 0, Done = false })
	end
	return list
end

function Challenges.newState(): State
	return { Day = 0, Week = 0, Daily = {}, Weekly = {}, Rerolls = 0 }
end

-- Brings a saved state up to `unix`: new dailies (and rerolls) on a new day, new weeklies on a new week.
-- Returns true if anything changed.
function Challenges.refresh(state: State, unix: number): boolean
	local changed = false
	local day, week = Challenges.day(unix), Challenges.week(unix)
	if state.Day ~= day then
		state.Day = day
		state.Daily = entries(Challenges.dailyFor(day))
		state.Rerolls = 0
		changed = true
	end
	if state.Week ~= week then
		state.Week = week
		state.Weekly = entries(Challenges.weeklyFor(week))
		changed = true
	end
	return changed
end

-- Swaps daily challenge `index` (unfinished) for one from the pool that isn't already on the list.
function Challenges.reroll(state: State, index: number, unix: number, allowance: number?): (boolean, string?)
	Challenges.refresh(state, unix)
	local entry = state.Daily[index]
	if not entry then
		return false, "No such challenge"
	end
	if entry.Done then
		return false, "That one's already done"
	end
	if state.Rerolls >= (allowance or Challenges.REROLLS_PER_DAY) then
		return false, "No rerolls left today"
	end
	local taken: { [string]: boolean } = {}
	for _, e in state.Daily do
		taken[e.Id] = true
	end
	local choices = {}
	for _, def in Challenges.DAILY_POOL do
		if not taken[def.id] then
			table.insert(choices, def.id)
		end
	end
	if #choices == 0 then
		return false, "Nothing to swap it for"
	end
	local random = Random.new(state.Day * 31 + index * 7 + state.Rerolls)
	state.Daily[index] = { Id = choices[random:NextInteger(1, #choices)], Progress = 0, Done = false }
	state.Rerolls += 1
	return true, nil
end

function Challenges.matches(def: Def, event: Event): boolean
	if def.event ~= event.kind then
		return false
	end
	local filter = def.filter
	if not filter then
		return true
	end
	if filter.weapon and filter.weapon ~= event.weapon then
		return false
	end
	if filter.maxTier and (event.tier == nil or event.tier > filter.maxTier) then
		return false
	end
	if filter.mode and filter.mode ~= event.mode then
		return false
	end
	if filter.survived ~= nil and filter.survived ~= event.survived then
		return false
	end
	return true
end

-- Counts an event towards every open challenge it fits. Returns the defs that just completed.
function Challenges.record(state: State, event: Event, unix: number): { Def }
	Challenges.refresh(state, unix)
	local completed = {}
	for _, list in { state.Daily, state.Weekly } do
		for _, entry in list do
			local def = BY_ID[entry.Id]
			if def and not entry.Done and Challenges.matches(def, event) then
				entry.Progress = math.min(entry.Progress + 1, def.target)
				if entry.Progress >= def.target then
					entry.Done = true
					table.insert(completed, def)
				end
			end
		end
	end
	return completed
end

-- The weapon class a kill or missile counts as: Gun, IR or Radar.
function Challenges.weaponClass(missileClass: string?): string
	if missileClass == nil then
		return "Gun"
	end
	return if missileClass:sub(1, 2) == "IR" then "IR" else "Radar"
end

return Challenges
