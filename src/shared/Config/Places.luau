--!strict
-- The places in each universe (DEVELOPMENT.md §25.1, MMK-02). Every place runs the same code; a server
-- works out its role from where it is:
--   a public server         → Lobby (the hangar and the matchmaking queue)
--   a reserved server       → Match or Training, from the record the lobby wrote for it (MatchmakingService)
-- BATTLE maps a lobby (start) place to the place its matches and training run in. With no entry, matches
-- run on reserved servers of the lobby place itself, which works the same; a separate Battle place only
-- lets the lobby drop the map later. Add the Battle place's id here once it exists.

local BATTLE: { [number]: number } = {
	-- [72582604278324] = <Battle place id>, -- the test universe
}

local Places = {}

-- Where matches and training go from this server.
function Places.battle(): number
	if BATTLE[game.PlaceId] then
		return BATTLE[game.PlaceId]
	end
	return game.PlaceId
end

-- Where players go back to after a match or training.
function Places.lobby(): number
	for lobby, battle in BATTLE do
		if battle == game.PlaceId then
			return lobby
		end
	end
	return game.PlaceId
end

-- "Lobby" or "Battle" when this universe has separate places, else "Single".
function Places.kind(): string
	if BATTLE[game.PlaceId] then
		return "Lobby"
	end
	for _, battle in BATTLE do
		if battle == game.PlaceId then
			return "Battle"
		end
	end
	return "Single"
end

return Places
