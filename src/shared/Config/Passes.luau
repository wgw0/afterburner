--!strict
-- Roblox game passes (DESIGN §8, DEVELOPMENT.md §27), per universe: a pass belongs to one experience, so the
-- test and live experiences each have their own. Create the pass on the Creator Dashboard (Monetization →
-- Passes) at the price below and put its id here. A pass with no id can't be bought yet, and nobody owns it
-- (test servers can grant it with the admin command give.pass). Benefits: the Shop card's bullet points.

local Passes = {}

Passes.LIST = table.freeze({
	-- What these give is in Shared/Perks (SHP-03)
	VIP = table.freeze({
		DisplayName = "VIP Pilot",
		Price = 399, -- Robux
		Description = "+25% Credits from every match, a VIP tag by your name and an extra daily challenge reroll.",
		Benefits = {
			"+25% Credits from every match",
			"Gold VIP tag by your name",
			"VIP Gold contrails",
			"An extra daily challenge reroll",
		},
	}),
	ExtraLineupSlot = table.freeze({
		DisplayName = "Extra Lineup Slot",
		Price = 149,
		Description = "One more jet in your lineup to spawn in.",
		Benefits = { "One more jet in your lineup", "More choice every time you respawn" },
	}),
	CustomCallsign = table.freeze({
		DisplayName = "Custom Callsign",
		Price = 99, -- Robux
		Description = "Fly under a callsign of your own instead of your username.",
		Benefits = { "Your own name over your jet", "On the scoreboard and kill feed" },
	}),
})

local BY_UNIVERSE: { [number]: { [string]: number } } = {
	[10773135125] = { -- the test experience
		CustomCallsign = 2061869361,
		VIP = 2061545520,
		ExtraLineupSlot = 2058366843,
	},
	[10773807904] = { -- the live experience (place 95037764806358)
		CustomCallsign = 2062133118,
		VIP = 2058336824,
		ExtraLineupSlot = 2062883080,
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
