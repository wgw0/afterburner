--!strict
-- Air Superiority (DEVELOPMENT.md §17.3, MCH-06): three airspace zones and two ticket counts. Pure, so the
-- server's MatchService and the tests share it.
--   Zones are upright cylinders over the Strait's centre line (equally far from both coasts' spawns):
--   A in the north, B over the island, C in the south.
--   Capture by presence: each zone's progress runs from -1 (West's) to +1 (East's). The team with more jets
--   inside pushes it their way, faster with more jets; equal numbers stall it. A zone has to be pulled back
--   to neutral before the other team can take it.
--   Tickets: both teams start with TICKETS. Every jet lost costs KILL_COST. Holding more zones than the
--   other team drains it by BLEED_PER_ZONE per second for each zone of advantage. A team on 0 loses.

local AirSuperiority = {}

AirSuperiority.TICKETS = 400
AirSuperiority.KILL_COST = 5
AirSuperiority.BLEED_PER_ZONE = 1 -- tickets per second per zone of advantage
AirSuperiority.CAPTURE_SECONDS = 10 -- neutral to owned with one jet inside
AirSuperiority.MAX_CAPTURERS = 3 -- more jets than this don't capture any faster

export type Zone = {
	id: string,
	position: Vector3, -- centre of the base (studs)
	radius: number, -- studs
	top: number, -- studs above sea level
	progress: number, -- -1 West … 0 neutral … +1 East
	owner: string?,
}

export type State = {
	zones: { Zone },
	tickets: { [string]: number },
	teams: { string }, -- { first, second }: the first team pulls progress negative
}

local ZONE_LAYOUT = {
	{ id = "A", x = 0, z = -2800 },
	{ id = "B", x = 0, z = 0 },
	{ id = "C", x = 0, z = 2800 },
}
local ZONE_RADIUS = 800
local ZONE_TOP = 2500

function AirSuperiority.newState(teams: { string }): State
	local zones = {}
	for _, layout in ZONE_LAYOUT do
		table.insert(zones, {
			id = layout.id,
			position = Vector3.new(layout.x, 0, layout.z),
			radius = ZONE_RADIUS,
			top = ZONE_TOP,
			progress = 0,
			owner = nil,
		})
	end
	local tickets = {}
	for _, team in teams do
		tickets[team] = AirSuperiority.TICKETS
	end
	return { zones = zones, tickets = tickets, teams = teams }
end

function AirSuperiority.contains(zone: Zone, position: Vector3): boolean
	local flat = Vector3.new(position.X - zone.position.X, 0, position.Z - zone.position.Z)
	return flat.Magnitude <= zone.radius and position.Y <= zone.top
end

-- How many zones each team owns.
function AirSuperiority.owned(state: State): { [string]: number }
	local counts = {}
	for _, team in state.teams do
		counts[team] = 0
	end
	for _, zone in state.zones do
		if zone.owner then
			counts[zone.owner] += 1
		end
	end
	return counts
end

-- Advances captures and the ticket bleed by dt seconds. presence[zoneId][team] = jets of that team inside.
-- Returns the captures that happened: { { zone = id, team = team } }.
function AirSuperiority.step(state: State, presence: { [string]: { [string]: number } }, dt: number): { any }
	local first, second = state.teams[1], state.teams[2]
	local captures = {}
	for _, zone in state.zones do
		local here = presence[zone.id] or {}
		local diff = (here[second] or 0) - (here[first] or 0) -- positive pushes toward the second team
		if diff ~= 0 then
			local push = math.sign(diff) * math.min(math.abs(diff), AirSuperiority.MAX_CAPTURERS)
			local before = zone.progress
			local after = math.clamp(before + push * dt / AirSuperiority.CAPTURE_SECONDS, -1, 1)
			if math.abs(after) > 1 - 1e-6 then
				after = math.sign(after) -- don't let rounding leave a zone a hair short of captured
			end
			-- Pulling an owned zone to neutral clears its owner; reaching ±1 gives it to that team
			if zone.owner and math.sign(after) ~= (if zone.owner == first then -1 else 1) then
				zone.owner = nil
			end
			if after <= -1 and zone.owner ~= first then
				zone.owner = first
				table.insert(captures, { zone = zone.id, team = first })
			elseif after >= 1 and zone.owner ~= second then
				zone.owner = second
				table.insert(captures, { zone = zone.id, team = second })
			end
			zone.progress = after
		end
	end
	local owned = AirSuperiority.owned(state)
	local lead = owned[first] - owned[second]
	if lead ~= 0 then
		local loser = if lead > 0 then second else first
		state.tickets[loser] = math.max(state.tickets[loser] - math.abs(lead) * AirSuperiority.BLEED_PER_ZONE * dt, 0)
	end
	return captures
end

-- A jet of `team` was lost.
function AirSuperiority.jetLost(state: State, team: string?)
	if team and state.tickets[team] then
		state.tickets[team] = math.max(state.tickets[team] - AirSuperiority.KILL_COST, 0)
	end
end

-- A team out of tickets has lost. Returns (ended, winner) with winner nil only for a dead heat.
function AirSuperiority.checkEnd(state: State): (boolean, string?)
	local first, second = state.teams[1], state.teams[2]
	if state.tickets[first] <= 0 or state.tickets[second] <= 0 then
		return true, AirSuperiority.leader(state)
	end
	return false, nil
end

-- The team with more tickets, or nil if level.
function AirSuperiority.leader(state: State): string?
	local first, second = state.teams[1], state.teams[2]
	local a, b = state.tickets[first], state.tickets[second]
	return if a > b then first elseif b > a then second else nil
end

return AirSuperiority
