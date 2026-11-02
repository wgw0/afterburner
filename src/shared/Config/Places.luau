--!strict
-- The places in each universe (DEVELOPMENT.md §25.1, MMK-02, MAP-05). Every place runs the same code; a server
-- works out its role from where it is:
--   a public server         → Lobby (the hangar and the matchmaking queue)
--   a reserved server       → Match or Training, from the record the lobby wrote for it (MatchmakingService)
-- Each universe has its lobby (the start place, which is also the Strait) and a place per map (Config/Maps):
-- the matchmaker picks a map for each match and reserves a server in its place. A map with no place id in
-- a universe isn't played there yet. Training stays on the lobby's place.

type Universe = { lobby: number, maps: { [string]: number } }

local UNIVERSES: { [number]: Universe } = {
	[10773135125] = { -- the test experience
		lobby = 72582604278324,
		maps = { Strait = 72582604278324, Desert = 105532168384050 },
	},
	[10773807904] = { -- the live experience
		lobby = 95037764806358,
		maps = { Strait = 95037764806358 },
	},
}

local Places = {}

local function universe(): Universe?
	return UNIVERSES[game.GameId]
end

-- The maps this universe plays (ids from Config/Maps), in a fixed order.
function Places.maps(): { string }
	local list = {}
	local u = universe()
	for map in if u then u.maps else { Strait = game.PlaceId } do
		table.insert(list, map)
	end
	table.sort(list)
	return list
end

-- Where a match on `map` is played (training and anything without a map: the lobby's place).
function Places.battle(map: string?): number
	local u = universe()
	if u and map and u.maps[map] then
		return u.maps[map]
	end
	return if u then u.lobby else game.PlaceId
end

-- Where players go back to after a match or training.
function Places.lobby(): number
	local u = universe()
	return if u then u.lobby else game.PlaceId
end

-- "Lobby" on the lobby's place, "Battle" on a map's own place, else "Single" (an unknown universe: Studio).
function Places.kind(): string
	local u = universe()
	if not u then
		return "Single"
	end
	return if game.PlaceId == u.lobby then "Lobby" else "Battle"
end

return Places
