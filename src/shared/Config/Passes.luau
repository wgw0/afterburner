--!strict
-- Roblox game passes (DESIGN §8, DEVELOPMENT.md §27), per universe: a pass belongs to one experience, so the
-- test and live experiences each have their own. Create the pass on the Creator Dashboard (Monetization →
-- Passes) at the price below and put its id here. A pass with no id can't be bought yet, and nobody owns it
-- (test servers can grant it with the admin command give.pass).

local Passes = {}

Passes.LIST = table.freeze({
	CustomCallsign = table.freeze({
		DisplayName = "Custom Callsign",
		Price = 99, -- Robux
		Description = "Fly under a callsign of your own instead of your username.",
	}),
})

local BY_UNIVERSE: { [number]: { [string]: number } } = {
	[10773135125] = { -- the test experience
		-- CustomCallsign = 0,
	},
	[10773807904] = { -- the live experience (place 95037764806358)
	},
}

-- The pass's id in this experience, or nil if it hasn't been created here yet.
function Passes.idFor(name: string): number?
	local ids = BY_UNIVERSE[game.GameId]
	local id = ids and ids[name]
	return if id and id > 0 then id else nil
end

-- The player attribute that says whether they own a pass (set by PassService).
function Passes.attribute(name: string): string
	return `Pass_{name}`
end

return Passes
