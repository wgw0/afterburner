--!strict
-- Battle rating matching inside one server (DEVELOPMENT.md §25, MMK-01; DESIGN §5.2). Pure apart from reading
-- each jet's BR through LiveConfig (which can be overridden live, OPS-01).
--   A lineup's BR is its highest jet. A match's BR is the highest lineup BR among the pilots present
--   when it starts; its band runs BAND_WIDTH below that. AI pilots fly jets inside the band, and jets
--   above the band can't join that match (they'll get their own match once there are lobby servers,
--   MMK-03). Free Flight has no band.

local AircraftData = require(script.Parent.AircraftData)
local LiveConfig = require(script.Parent.LiveConfig)

local Matchmaking = {}

Matchmaking.BAND_WIDTH = 1.0
Matchmaking.DEFAULT_BR = 1.7 -- with nobody to measure, a starter-jet match
Matchmaking.VS_AI_SPREAD = 0.3 -- Vs AI: the bots' jets are within this of the player's (Will: the same level)
Matchmaking.VS_AI_MIN = 3 -- ...or, where few jets are that close, the closest this many

export type Band = { br: number, min: number, max: number }

local function brOf(id: string): number?
	local airframe = AircraftData.get(id) :: any
	return airframe and LiveConfig.battleRating(id) -- live config can move a jet's BR (OPS-01)
end

function Matchmaking.lineupBR(lineup: { string }): number?
	local best: number? = nil
	for _, id in lineup do
		local br = brOf(id)
		if br and (best == nil or br > best) then
			best = br
		end
	end
	return best
end

-- The band for a match from the lineups of the pilots present.
function Matchmaking.band(lineups: { { string } }): Band
	local top: number? = nil
	for _, lineup in lineups do
		local br = Matchmaking.lineupBR(lineup)
		if br and (top == nil or br > top) then
			top = br
		end
	end
	return Matchmaking.bandFor(top or Matchmaking.DEFAULT_BR)
end

-- The band for a match whose highest lineup BR is `br`.
function Matchmaking.bandFor(br: number): Band
	return { br = br, min = br - Matchmaking.BAND_WIDTH, max = br }
end

-- Whether a jet may join a match with this band (nothing above the top; anything lower may fly).
function Matchmaking.allowed(airframeId: string, band: Band): boolean
	local br = brOf(airframeId)
	return br ~= nil and br <= band.max + 1e-6
end

-- Jets for AI pilots: every airframe inside the band, sorted by BR. If none fits, the closest below.
function Matchmaking.aiAirframes(band: Band): { string }
	local inside, below = {}, {}
	for id in AircraftData.getAll() do
		local br = LiveConfig.battleRating(id) :: number
		if br >= band.min - 1e-6 and br <= band.max + 1e-6 then
			table.insert(inside, id)
		elseif br < band.min then
			table.insert(below, id)
		end
	end
	local function byBR(a: string, b: string): boolean
		return (brOf(a) or 0) < (brOf(b) or 0)
	end
	if #inside > 0 then
		table.sort(inside, byBR)
		return inside
	end
	table.sort(below, byBR)
	return if #below > 0 then { below[#below] } else { "F5E" }
end

-- Jets for AI pilots in a Vs AI match against a jet of BR `br`: every jet within VS_AI_SPREAD of it, above
-- or below, or the VS_AI_MIN closest if fewer are that close. Sorted by BR.
function Matchmaking.vsAIAirframes(br: number): { string }
	local all = {}
	for id in AircraftData.getAll() do
		table.insert(all, id)
	end
	local function gap(id: string): number
		return math.abs((brOf(id) or 0) - br)
	end
	table.sort(all, function(a: string, b: string): boolean
		if gap(a) ~= gap(b) then
			return gap(a) < gap(b)
		end
		return a < b
	end)
	local chosen = {}
	for i, id in all do
		if gap(id) <= Matchmaking.VS_AI_SPREAD + 1e-6 or i <= Matchmaking.VS_AI_MIN then
			table.insert(chosen, id)
		end
	end
	table.sort(chosen, function(a: string, b: string): boolean
		return (brOf(a) or 0) < (brOf(b) or 0)
	end)
	return chosen
end

return Matchmaking
