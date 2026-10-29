--!strict
-- What pilot levels unlock (DESIGN §7.5, PRG-03; the Career tab's level track). Every level also pays
-- Economy.LEVEL_CREDITS. Milestones:
--   Credits / FreeRP   paid once when the level is reached (Progression.claimLevelRewards)
--   Slot               a lineup slot (the numbers live in Economy.LINEUP_SLOTS; shown here for the track)
--   Skin               a level skin: works on every jet whose paint for it is installed (Skins.list)
--   Title              shown next to your name on the scoreboard, picked in Career
--   HUDColour          an extra HUD colour preset in Settings

local Economy = require(script.Parent.Economy)

export type Milestone = {
	Level: number,
	Kind: string,
	Amount: number?, -- Credits / FreeRP
	Id: string?, -- Skin / Title / HUDColour
}

local LevelRewards = {}

LevelRewards.SKINS = table.freeze({
	{ Id = "Squadron", DisplayName = "Squadron Black", Level = 10 },
	{ Id = "AceGold", DisplayName = "Ace Gold", Level = 25 },
	{ Id = "Legend", DisplayName = "Legend Chrome", Level = 50 },
})

LevelRewards.TITLES = table.freeze({
	Wingman = "Wingman",
	FlightLead = "Flight Lead",
	Ace = "Ace",
	SquadronLeader = "Squadron Leader",
	WingCommander = "Wing Commander",
	Legend = "Legend",
	GroupCaptain = "Group Captain",
	AirMarshal = "Air Marshal",
	-- Not from levels: the login streak (Streak.MILESTONES), unlocked in data.Titles
	Regular = "Regular",
	Devoted = "Devoted",
})
LevelRewards.OTHER_TITLES = table.freeze({ "Regular", "Devoted" })

LevelRewards.HUD_COLOURS = table.freeze({ Pink = 7, Blue = 18, Violet = 40 }) -- colour → level

local MILESTONES: { Milestone } = {
	{ Level = 2, Kind = "Credits", Amount = 1000 },
	{ Level = 3, Kind = "Title", Id = "Wingman" },
	{ Level = 7, Kind = "HUDColour", Id = "Pink" },
	{ Level = 10, Kind = "Skin", Id = "Squadron" },
	{ Level = 10, Kind = "Title", Id = "FlightLead" },
	{ Level = 12, Kind = "FreeRP", Amount = 3000 },
	{ Level = 18, Kind = "HUDColour", Id = "Blue" },
	{ Level = 20, Kind = "Title", Id = "Ace" },
	{ Level = 20, Kind = "Credits", Amount = 10000 },
	{ Level = 25, Kind = "Skin", Id = "AceGold" },
	{ Level = 30, Kind = "Title", Id = "SquadronLeader" },
	{ Level = 30, Kind = "FreeRP", Amount = 10000 },
	{ Level = 35, Kind = "Credits", Amount = 20000 },
	{ Level = 40, Kind = "HUDColour", Id = "Violet" },
	{ Level = 40, Kind = "Title", Id = "WingCommander" },
	{ Level = 50, Kind = "Skin", Id = "Legend" },
	{ Level = 50, Kind = "Title", Id = "Legend" },
	{ Level = 75, Kind = "Credits", Amount = 30000 },
	{ Level = 75, Kind = "Title", Id = "GroupCaptain" },
	{ Level = 100, Kind = "Credits", Amount = 50000 },
	{ Level = 100, Kind = "Title", Id = "AirMarshal" },
}
for _, step in Economy.LINEUP_SLOTS do
	if step.level > 1 then
		table.insert(MILESTONES, { Level = step.level, Kind = "Slot", Amount = step.slots })
	end
end
table.sort(MILESTONES, function(a, b)
	return a.Level < b.Level
end)
LevelRewards.MILESTONES = table.freeze(MILESTONES)

-- The level a title, HUD colour or level skin unlocks at (nil if it isn't level-gated).
function LevelRewards.levelFor(kind: string, id: string): number?
	for _, milestone in MILESTONES do
		if milestone.Kind == kind and milestone.Id == id then
			return milestone.Level
		end
	end
	return nil
end

-- The milestones grouped by level, in order: { { Level, Rewards = { Milestone } } }.
function LevelRewards.byLevel(): { { Level: number, Rewards: { Milestone } } }
	local groups = {}
	for _, milestone in MILESTONES do
		local last = groups[#groups]
		if last and last.Level == milestone.Level then
			table.insert(last.Rewards, milestone)
		else
			table.insert(groups, { Level = milestone.Level, Rewards = { milestone } })
		end
	end
	return groups
end

local function commas(n: number): string
	local text = tostring(math.floor(n)):reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (text:gsub("^,", ""))
end

-- How a milestone reads on the track.
function LevelRewards.describe(milestone: Milestone): string
	local kind = milestone.Kind
	if kind == "Credits" then
		return `{commas(milestone.Amount :: number)} Credits`
	elseif kind == "FreeRP" then
		return `{commas(milestone.Amount :: number)} Free RP`
	elseif kind == "Slot" then
		return `Lineup slot {milestone.Amount}`
	elseif kind == "Title" then
		return `Title: {LevelRewards.TITLES[milestone.Id :: string] or milestone.Id}`
	elseif kind == "HUDColour" then
		return `{milestone.Id} HUD`
	elseif kind == "Skin" then
		for _, skin in LevelRewards.SKINS do
			if skin.Id == milestone.Id then
				return `{skin.DisplayName} skin`
			end
		end
	end
	return kind
end

-- Whether a title can be worn: "" (none) always; a level title from its level; any title unlocked some other
-- way (`owned`: data.Titles, e.g. the login streak).
function LevelRewards.titleUnlocked(
	titleId: string,
	level: number,
	allUnlocked: boolean?,
	owned: { [string]: boolean }?
): boolean
	if titleId == "" or (owned ~= nil and owned[titleId] == true and LevelRewards.TITLES[titleId] ~= nil) then
		return true
	end
	local needed = LevelRewards.levelFor("Title", titleId)
	return needed ~= nil and (allUnlocked == true or level >= needed)
end

return LevelRewards
