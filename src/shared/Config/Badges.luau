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
		AceInADay = 2437927528297019,
		Untouchable = 1802830480582760,
		Notched = 382988331028907,
		Veteran = 3249765653485432,
		TestPilot = 4020009935250881,
		FoxOne = 150169737820363,
		FoxThree = 1691382039070789,
		DoubleTrouble = 4123972696428656,
		Flawless = 546288875820281,
		TeamPlayer = 3287878670062475,
		EscapeArtist = 3536095594709869,
		TopOfTheTable = 3790279544220585,
		Centurion = 1818406163054487,
		Collector = 1450248394462966,
		HighFlyer = 712948293144706,
		FullHangar = 2320410186906146,
		FullyKitted = 1275962833263025,
		MasterMechanic = 4151205890835648,
		Savings = 348095093041880,
		HighRoller = 3267498443526002,
		Tycoon = 3604383040364869,
		Researcher = 4441548715674336,
		Boffin = 3817988340426979,
		SharpDresser = 4378878278078332,
		FashionIcon = 4436226163746060,
	},
}

local Badges = {}

function Badges.idFor(achievementId: string): number?
	local ids = BY_UNIVERSE[game.GameId]
	return ids and ids[achievementId]
end

return Badges
