--!strict
-- Scheduled events (OPS-03; DEVELOPMENT.md §31.4): a name, a start and an end (UTC), and match reward
-- multipliers, set up ahead of time so a double XP weekend starts and stops on its own. ConfigService keeps
-- the schedule with the live config and shares it as the LiveEvents attribute; LiveConfig folds the running
-- event into the reward multipliers and the hangar banner. Pure.

local Events = {}

Events.MAX_LENGTH = 14 * 86400 -- an event lasts at most two weeks
Events.MAX_NAME = 60
Events.MULTIPLIER_MIN, Events.MULTIPLIER_MAX = 1, 3
Events.KEEP = 20 -- events in the schedule at most (ended ones drop off first)

export type Event = {
	id: string,
	name: string,
	start: number, -- unix time, UTC
	finish: number,
	xp: number, -- match reward multipliers (1 = no change)
	credits: number,
	rp: number,
}

-- Days from 1 January 1970 to a date (proleptic Gregorian; Howard Hinnant's days_from_civil).
local function daysFromCivil(y: number, m: number, d: number): number
	if m <= 2 then
		y -= 1
	end
	local era = y // 400
	local yoe = y - era * 400
	local doy = (153 * (if m > 2 then m - 3 else m + 9) + 2) // 5 + d - 1
	local doe = yoe * 365 + yoe // 4 - yoe // 100 + doy
	return era * 146097 + doe - 719468
end

-- "2026-11-14 18:00" (UTC; the time is optional) or a unix time, as a unix time. Nil if it isn't either.
function Events.parseTime(value: any): number?
	if type(value) == "number" then
		return math.floor(value)
	end
	if type(value) ~= "string" then
		return nil
	end
	local y, m, d, rest = string.match(value, "^%s*(%d%d%d%d)%-(%d%d?)%-(%d%d?)(.*)$")
	if not y then
		return nil
	end
	local hour, minute = 0, 0
	if rest and string.match(rest, "%S") then
		local h, mi = string.match(rest, "^[%sT]+(%d%d?):(%d%d)%s*$")
		if not h then
			return nil
		end
		hour, minute = tonumber(h) :: number, tonumber(mi) :: number
	end
	local year, month, day = tonumber(y) :: number, tonumber(m) :: number, tonumber(d) :: number
	if month < 1 or month > 12 or day < 1 or day > 31 or hour > 23 or minute > 59 then
		return nil
	end
	return daysFromCivil(year, month, day) * 86400 + hour * 3600 + minute * 60
end

local function multiplier(value: any, name: string): (number?, string?)
	if value == nil then
		return 1, nil
	end
	local n = tonumber(value)
	if not n or n ~= n or n < Events.MULTIPLIER_MIN or n > Events.MULTIPLIER_MAX then
		return nil, `{name} must be between {Events.MULTIPLIER_MIN} and {Events.MULTIPLIER_MAX}`
	end
	return math.round(n * 100) / 100, nil
end

-- Checks a new event against the schedule. args: { name, start, finish | hours, xp?, credits?, rp? }.
-- Returns the event (with id), or nil and why not.
function Events.make(args: { [string]: any }, schedule: { Event }, now: number, id: string): (Event?, string?)
	local name = args.name
	if type(name) ~= "string" or not string.match(name, "%S") then
		return nil, "An event needs a name"
	elseif #name > Events.MAX_NAME then
		return nil, `The name is limited to {Events.MAX_NAME} characters`
	end
	local start = Events.parseTime(args.start)
	if not start then
		return nil, 'start must be a date like "2026-11-14 18:00" (UTC)'
	end
	local finish = Events.parseTime(args.finish)
	if not finish and tonumber(args.hours) then
		finish = start + math.floor((tonumber(args.hours) :: number) * 3600)
	end
	if not finish then
		return nil, "Give a finish date or hours"
	elseif finish <= start then
		return nil, "It has to finish after it starts"
	elseif finish - start > Events.MAX_LENGTH then
		return nil, "An event lasts at most 14 days"
	elseif finish <= now then
		return nil, "That's already over"
	end
	local xp, whyXP = multiplier(args.xp, "xp")
	local credits, whyCredits = multiplier(args.credits, "credits")
	local rp, whyRP = multiplier(args.rp, "rp")
	if not (xp and credits and rp) then
		return nil, whyXP or whyCredits or whyRP
	end
	for _, other in schedule do
		if start < other.finish and other.start < finish then
			return nil, `It overlaps "{other.name}"`
		end
	end
	return {
		id = id,
		name = name,
		start = start,
		finish = finish,
		xp = xp :: number,
		credits = credits :: number,
		rp = rp :: number,
	},
		nil
end

-- A stored schedule with anything malformed left out, oldest start first.
function Events.clean(raw: any): { Event }
	local list = {}
	if type(raw) ~= "table" then
		return list
	end
	for _, event in raw do
		if
			type(event) == "table"
			and type(event.id) == "string"
			and type(event.name) == "string"
			and type(event.start) == "number"
			and type(event.finish) == "number"
		then
			table.insert(list, {
				id = event.id,
				name = event.name,
				start = event.start,
				finish = event.finish,
				xp = tonumber(event.xp) or 1,
				credits = tonumber(event.credits) or 1,
				rp = tonumber(event.rp) or 1,
			})
		end
	end
	table.sort(list, function(a, b)
		return a.start < b.start
	end)
	return list
end

-- The schedule with ended events dropped once it's over KEEP long.
function Events.trim(schedule: { Event }, now: number): { Event }
	local list = table.clone(schedule)
	local i = 1
	while #list > Events.KEEP and i <= #list do
		if list[i].finish <= now then
			table.remove(list, i)
		else
			i += 1
		end
	end
	return list
end

-- The event running now, or nil.
function Events.active(schedule: { Event }, now: number): Event?
	for _, event in schedule do
		if now >= event.start and now < event.finish then
			return event
		end
	end
	return nil
end

return Events
