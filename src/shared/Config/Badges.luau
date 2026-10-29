--!strict
-- Roblox badge ids for the achievements (LIV-02), per universe: badges belong to one experience, so the
-- test and live experiences each have their own. Create a badge on the Creator Dashboard (Monetization →
-- Badges) for each achievement in Achievements.LIST and put its id here. An achievement with no badge id is
-- still earned and saved; its badge is awarded the next time the player joins once the id is filled in.

local BY_UNIVERSE: { [number]: { [string]: number } } = {
	[10773135125] = { -- the test experience
		-- FirstBlood = 0,
	},
}

local Badges = {}

function Badges.idFor(achievementId: string): number?
	local ids = BY_UNIVERSE[game.GameId]
	return ids and ids[achievementId]
end

return Badges
