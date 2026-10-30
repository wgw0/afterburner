--!strict
-- Roblox badge ids for the achievements (LIV-02), per universe: badges belong to one experience, so the
-- test and live experiences each have their own. Create a badge on the Creator Dashboard (Monetization →
-- Badges) for each achievement in Achievements.LIST and put its id here. An achievement with no badge id is
-- still earned and saved; its badge is awarded the next time the player joins once the id is filled in.

local BY_UNIVERSE: { [number]: { [string]: number } } = {
	[10773135125] = { -- the test experience
		-- FirstBlood = 0,
	},
	[10773807904] = { -- the live experience (place 95037764806358)
		-- Roblox allows 5 free badges per experience per day (then 100 R$ each): the rest are added as made
		FirstBlood = 3539253452079701,
		Victor = 1811915741907712,
		GunsOnly = 4067644470962128,
		ZoneHunter = 858516138670573,
		HatTrick = 139601879190386,
	},
}

local Badges = {}

function Badges.idFor(achievementId: string): number?
	local ids = BY_UNIVERSE[game.GameId]
	return ids and ids[achievementId]
end

return Badges
