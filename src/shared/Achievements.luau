--!strict
-- Achievements (DEVELOPMENT.md §26.2, LIV-02; DESIGN §10). Each has a Roblox badge once its id is set in
-- Config/Badges. Pure: ChallengeService decides from match events which ones a player has just earned.
-- Saved per player as data.Achievements = { [id] = { At = unix, Badge = true once the badge was awarded } }.
-- Something new to earn all the time (Will, November 2026): every achievement pays a reward by its rarity
-- (REWARDS), and ranked series (SERIES: Hunter I, II, III…) put the next one always in reach.

local AircraftData = require(script.Parent.AircraftData)
local Economy = require(script.Parent.Config.Economy)
local LevelRewards = require(script.Parent.Config.LevelRewards)

-- rarity: how hard it is, Common → Legendary (Achievements.RARITIES); shown as the card's colour in Career.
-- secret: hidden until earned. series / level / target / stat: one level of a ranked series (SERIES).
export type Def = {
	id: string,
	rarity: string,
	name: string,
	text: string,
	secret: boolean?,
	series: string?,
	level: number?,
	target: number?,
	stat: string?,
}

local Achievements = {}

Achievements.RARITIES = table.freeze({ "Common", "Uncommon", "Rare", "Epic", "Legendary" })

-- What each achievement pays when it's earned, by rarity
Achievements.REWARDS = table.freeze({
	Common = { credits = 1000, wings = 0 },
	Uncommon = { credits = 2500, wings = 0 },
	Rare = { credits = 5000, wings = 10 },
	Epic = { credits = 10000, wings = 25 },
	Legendary = { credits = 25000, wings = 50 },
})

function Achievements.reward(def: Def): { credits: number, wings: number }
	return Achievements.REWARDS[def.rarity] or Achievements.REWARDS.Common
end

local ROMAN = { "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X" }
Achievements.ROMAN = ROMAN

-- Ranked series: one achievement per level, rarer as it climbs. stat: a field of Achievements.career.
-- names: a name per level instead of "<name> I/II/…"; textRoman: the level's target written as a numeral.
export type Series = {
	id: string,
	name: string,
	stat: string,
	text: string,
	levels: { number },
	names: { string }?,
	textRoman: boolean?,
}

Achievements.SERIES = table.freeze({
	{
		id = "Hunter",
		name = "Hunter",
		stat = "totalKills",
		text = "Shoot down %s jets.",
		levels = { 10, 25, 50, 250, 500, 1000, 2500 },
	},
	{
		id = "Dogfighter",
		name = "Dogfighter",
		stat = "playerKills",
		text = "Shoot down %s other players.",
		levels = { 5, 25, 100, 250, 500, 1000 },
	},
	{
		id = "Champion",
		name = "Champion",
		stat = "wins",
		text = "Win %s matches.",
		levels = { 5, 10, 25, 50, 100, 250, 500 },
	},
	{
		id = "FrequentFlyer",
		name = "Frequent Flyer",
		stat = "matches",
		text = "Finish %s matches.",
		levels = { 10, 25, 100, 250, 500, 1000 },
	},
	{
		id = "Wingman",
		name = "Wingman",
		stat = "assists",
		text = "Get %s assists.",
		levels = { 10, 50, 150, 500, 1000 },
	},
	{
		id = "Evader",
		name = "Evader",
		stat = "missilesDefeated",
		text = "Defeat %s missiles.",
		levels = { 10, 50, 150, 500 },
	},
	{
		id = "ZoneCommander",
		name = "Zone Commander",
		stat = "captures",
		text = "Capture %s zones.",
		levels = { 10, 50, 150, 500 },
	},
	{ id = "Fleet", name = "Fleet", stat = "ownedJets", text = "Own %s jets.", levels = { 3, 5, 15, 20 } },
	{
		id = "RisingStar",
		name = "Rising Star",
		stat = "level",
		text = "Reach pilot level %s.",
		levels = { 5, 10, 15, 40, 50, 75, 100 },
	},
	{ id = "Duelist", name = "Duelist", stat = "duelWins", text = "Win %s duels.", levels = { 1, 10, 50, 150, 500 } },
	{
		id = "Taskmaster",
		name = "Taskmaster",
		stat = "challengesDone",
		text = "Complete %s challenges.",
		levels = { 5, 25, 100, 250 },
	},
	{
		id = "Mechanic",
		name = "Mechanic",
		stat = "modulesFitted",
		text = "Buy %s upgrades.",
		levels = { 1, 10, 25, 50, 100, 250 },
	},
	{
		id = "Promotion",
		name = "Promotion",
		stat = "topTier",
		text = "Own a Tier %s jet.",
		textRoman = true,
		levels = { 2, 3, 4, 5, 6, 7, 8 },
		names = {
			"Tier II Pilot",
			"Tier III Pilot",
			"Tier IV Pilot",
			"Tier V Pilot",
			"Tier VI Pilot",
			"Tier VII Pilot",
			"Prestige Pilot",
		},
	},
}) :: { Series }

local function commas(n: number): string
	local text = tostring(math.floor(n))
	return (text:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end

-- One achievement per series level (rarer as the series climbs)
local seriesDefs: { Def } = {}
for _, series in Achievements.SERIES do
	local count = #series.levels
	for i, target in series.levels do
		local rank = math.clamp(math.ceil(i / count * #Achievements.RARITIES), 1, #Achievements.RARITIES)
		table.insert(seriesDefs, {
			id = `{series.id}{i}`,
			rarity = Achievements.RARITIES[rank],
			name = if series.names then series.names[i] else `{series.name} {ROMAN[i]}`,
			text = string.format(series.text, if series.textRoman then ROMAN[target] else commas(target)),
			series = series.id,
			level = i,
			target = target,
			stat = series.stat,
		})
	end
end

local BASE: { Def } = {
	{ id = "FirstBlood", rarity = "Common", name = "First Blood", text = "Shoot down your first jet." },
	{ id = "GunsOnly", rarity = "Common", name = "Guns Only", text = "Shoot a jet down with your guns." },
	{ id = "Victor", rarity = "Common", name = "Victor", text = "Win a match." },
	{ id = "AceInADay", rarity = "Epic", name = "Ace in a Day", text = "Get 5 kills in one life." },
	{ id = "Untouchable", rarity = "Epic", name = "Untouchable", text = "Win a match without taking a hit." },
	{ id = "Notched", rarity = "Uncommon", name = "Notched", text = "Defeat a radar missile fired at you." },
	{ id = "ZoneHunter", rarity = "Common", name = "Zone Hunter", text = "Capture a zone in Air Superiority." },
	{ id = "Veteran", rarity = "Rare", name = "Veteran", text = "Finish 50 matches." },
	{ id = "TestPilot", rarity = "Legendary", name = "Test Pilot", text = "Fly the Tempest in a match." },
	{
		id = "FoxOne",
		rarity = "Uncommon",
		name = "Fox One",
		text = "Shoot a jet down with a semi-active radar missile.",
	},
	{
		id = "FoxThree",
		rarity = "Uncommon",
		name = "Fox Three",
		text = "Shoot a jet down with an active radar missile.",
	},
	{ id = "DoubleTrouble", rarity = "Rare", name = "Double Trouble", text = "Get 2 kills within 10 seconds." },
	{ id = "HatTrick", rarity = "Uncommon", name = "Hat Trick", text = "Get 3 kills in one life." },
	{ id = "Flawless", rarity = "Epic", name = "Flawless", text = "Get 3 kills in a match without being shot down." },
	{ id = "TeamPlayer", rarity = "Uncommon", name = "Team Player", text = "Get 3 assists in one match." },
	{ id = "EscapeArtist", rarity = "Rare", name = "Escape Artist", text = "Defeat 3 missiles in one life." },
	{
		id = "TopOfTheTable",
		rarity = "Rare",
		name = "Top of the Table",
		text = "Finish first in a free-for-all Dogfight.",
	},
	{ id = "Centurion", rarity = "Epic", name = "Centurion", text = "Shoot down 100 jets." },
	{ id = "Collector", rarity = "Rare", name = "Collector", text = "Own 10 jets." },
	{ id = "HighFlyer", rarity = "Legendary", name = "High Flyer", text = "Reach pilot level 25." },
	-- The hangar and the bank (Will): jets, upgrades, Credits, RP and skins owned
	{ id = "FullHangar", rarity = "Legendary", name = "Full Hangar", text = "Own every jet." },
	{ id = "FullyKitted", rarity = "Uncommon", name = "Fully Kitted", text = "Own every upgrade for one jet." },
	{
		id = "MasterMechanic",
		rarity = "Legendary",
		name = "Master Mechanic",
		text = "Own every upgrade for every jet.",
	},
	{ id = "Savings", rarity = "Uncommon", name = "Rainy Day Fund", text = "Have 50,000 Credits at once." },
	{ id = "HighRoller", rarity = "Rare", name = "High Roller", text = "Have 250,000 Credits at once." },
	{ id = "Tycoon", rarity = "Epic", name = "Tycoon", text = "Have 1,000,000 Credits at once." },
	{ id = "Researcher", rarity = "Uncommon", name = "Researcher", text = "Have 10,000 RP banked." },
	{ id = "Boffin", rarity = "Rare", name = "Boffin", text = "Have 100,000 RP banked." },
	{ id = "SharpDresser", rarity = "Uncommon", name = "Sharp Dresser", text = "Own 5 skins." },
	{ id = "FashionIcon", rarity = "Rare", name = "Fashion Icon", text = "Own 25 skins." },
	{ id = "Wardrobe", rarity = "Epic", name = "Walk-in Wardrobe", text = "Own 50 skins." },
	-- Secret: not shown in Career until earned
	{
		id = "ThreadTheNeedle",
		rarity = "Epic",
		name = "Threading the Needle",
		text = "Fly under a bridge.",
		secret = true,
	},
}

local list = table.clone(BASE)
for _, def in seriesDefs do
	table.insert(list, def)
end
Achievements.LIST = table.freeze(list) :: { Def }

-- The levels of a series, in order.
function Achievements.seriesLevels(seriesId: string): { Def }
	local levels = {}
	for _, def in seriesDefs do
		if def.series == seriesId then
			table.insert(levels, def)
		end
	end
	return levels
end

Achievements.ACE_KILLS = 5
Achievements.HAT_TRICK_KILLS = 3
Achievements.DOUBLE_KILL_SECONDS = 10
Achievements.FLAWLESS_KILLS = 3
Achievements.TEAM_PLAYER_ASSISTS = 3
Achievements.ESCAPE_DEFEATS = 3
Achievements.VETERAN_MATCHES = 50
Achievements.CENTURION_KILLS = 100
Achievements.COLLECTOR_JETS = 10
Achievements.HIGH_FLYER_LEVEL = 25
-- Credits and RP (banked: Free RP plus every jet's RP) at once, and skins owned (bought or earned, not the
-- ones jets come with): { id, amount }, lowest first
Achievements.CREDITS = table.freeze({ { "Savings", 50000 }, { "HighRoller", 250000 }, { "Tycoon", 1000000 } })
Achievements.RP = table.freeze({ { "Researcher", 10000 }, { "Boffin", 100000 } })
Achievements.SKINS = table.freeze({ { "SharpDresser", 5 }, { "FashionIcon", 25 }, { "Wardrobe", 50 } })

local BY_ID: { [string]: Def } = {}
for _, def in Achievements.LIST do
	BY_ID[def.id] = def
end

function Achievements.get(id: string): Def?
	return BY_ID[id]
end

-- What happened, as ChallengeService sees it.
export type Event = {
	kind: string, -- Kill | Win | MissileDefeated | Capture | MatchFinished | Spawn | Career | BridgeRun
	weapon: string?, -- Gun | IR | Radar
	missileClass: string?, -- Kill: SARH, ARH, IR_* (nil for guns)
	lifeKills: number?, -- Kill: kills in this life, this one included
	sinceLastKill: number?, -- Kill: seconds since your previous kill
	hitThisMatch: boolean?, -- Win: whether you took any damage
	matches: number?, -- MatchFinished / Career: lifetime matches
	matchKills: number?, -- MatchFinished: kills this match
	matchAssists: number?, -- MatchFinished: assists this match
	survived: boolean?, -- MatchFinished: not shot down
	firstFreeForAll: boolean?, -- MatchFinished: top of the ranking in a free-for-all
	lifeDefeats: number?, -- MissileDefeated: missiles defeated this life, this one included
	totalKills: number?, -- Career: lifetime kills (players and AI)
	ownedJets: number?, -- Career
	totalJets: number?, -- Career: jets in the game
	fullyKitted: number?, -- Career: owned jets with every upgrade
	credits: number?, -- Career
	rp: number?, -- Career: Free RP plus every jet's RP
	skins: number?, -- Career: skins owned, bought or earned
	level: number?, -- Career: pilot level
	playerKills: number?, -- Career: lifetime kills of other players
	wins: number?, -- Career: lifetime wins
	assists: number?, -- Career: lifetime assists
	missilesDefeated: number?, -- Career: lifetime missiles defeated
	captures: number?, -- Career: lifetime zones captured
	challengesDone: number?, -- Career: daily and weekly challenges completed
	modulesFitted: number?, -- Career: upgrades bought, on every jet
	topTier: number?, -- Career: the highest tier owned
	duelWins: number?, -- Career: duels won (MCH-09)
	airframe: string?, -- Spawn
}

-- The achievements this event earns (whether or not the player already has them).
function Achievements.earned(event: Event): { string }
	local ids = {}
	local kind = event.kind
	if kind == "Kill" then
		table.insert(ids, "FirstBlood")
		if event.weapon == "Gun" then
			table.insert(ids, "GunsOnly")
		end
		if event.missileClass == "SARH" then
			table.insert(ids, "FoxOne")
		elseif event.missileClass == "ARH" then
			table.insert(ids, "FoxThree")
		end
		if (event.lifeKills or 0) >= Achievements.HAT_TRICK_KILLS then
			table.insert(ids, "HatTrick")
		end
		if (event.lifeKills or 0) >= Achievements.ACE_KILLS then
			table.insert(ids, "AceInADay")
		end
		if event.sinceLastKill and event.sinceLastKill <= Achievements.DOUBLE_KILL_SECONDS then
			table.insert(ids, "DoubleTrouble")
		end
	elseif kind == "Win" then
		table.insert(ids, "Victor")
		if event.hitThisMatch == false then
			table.insert(ids, "Untouchable")
		end
	elseif kind == "MissileDefeated" then
		if event.weapon == "Radar" then
			table.insert(ids, "Notched")
		end
		if (event.lifeDefeats or 0) >= Achievements.ESCAPE_DEFEATS then
			table.insert(ids, "EscapeArtist")
		end
	elseif kind == "Capture" then
		table.insert(ids, "ZoneHunter")
	elseif kind == "MatchFinished" then
		if (event.matches or 0) >= Achievements.VETERAN_MATCHES then
			table.insert(ids, "Veteran")
		end
		if event.survived and (event.matchKills or 0) >= Achievements.FLAWLESS_KILLS then
			table.insert(ids, "Flawless")
		end
		if (event.matchAssists or 0) >= Achievements.TEAM_PLAYER_ASSISTS then
			table.insert(ids, "TeamPlayer")
		end
		if event.firstFreeForAll then
			table.insert(ids, "TopOfTheTable")
		end
	elseif kind == "Spawn" and event.airframe == "Tempest" then
		table.insert(ids, "TestPilot")
	elseif kind == "BridgeRun" then
		table.insert(ids, "ThreadTheNeedle")
	end
	-- Lifetime totals: checked at the end of every match and on joining
	if kind == "MatchFinished" or kind == "Career" then
		if (event.matches or 0) >= Achievements.VETERAN_MATCHES and kind == "Career" then
			table.insert(ids, "Veteran")
		end
		if (event.totalKills or 0) >= Achievements.CENTURION_KILLS then
			table.insert(ids, "Centurion")
		end
		if (event.ownedJets or 0) >= Achievements.COLLECTOR_JETS then
			table.insert(ids, "Collector")
		end
		if (event.level or 0) >= Achievements.HIGH_FLYER_LEVEL then
			table.insert(ids, "HighFlyer")
		end
		local jets = event.totalJets or math.huge
		if (event.ownedJets or 0) >= jets then
			table.insert(ids, "FullHangar")
		end
		if (event.fullyKitted or 0) >= 1 then
			table.insert(ids, "FullyKitted")
		end
		if (event.fullyKitted or 0) >= jets then
			table.insert(ids, "MasterMechanic")
		end
		for _, list in
			{
				{ Achievements.CREDITS, event.credits },
				{ Achievements.RP, event.rp },
				{ Achievements.SKINS, event.skins },
			}
		do
			for _, step in list[1] do
				if (list[2] or 0) >= step[2] then
					table.insert(ids, step[1])
				end
			end
		end
		-- Every series level reached
		for _, def in seriesDefs do
			if ((event :: any)[def.stat :: string] or 0) >= (def.target :: number) then
				table.insert(ids, def.id)
			end
		end
	end
	return ids
end

-- A player's lifetime totals, as a Career event (checked at the end of every match and on joining; the
-- Career screen shows series progress from it). Full access (testing) owns everything without earning it,
-- so the hangar and bank totals count nothing for it.
function Achievements.career(data: { [string]: any }): Event
	local owned, kitted, skins, totalJets, fitted, topTier = 0, 0, 0, 0, 0, 1
	local rp = data.FreeRP or 0
	for _ in AircraftData.getAll() do
		totalJets += 1
	end
	for id, entry in data.Aircraft or {} do
		rp += entry.RP or 0
		if entry.Owned then
			owned += 1
			local airframe = AircraftData.get(id) :: any
			if airframe and airframe.Tier > topTier then
				topTier = airframe.Tier
			end
			local all = true
			for _, def in Economy.MODULES do
				if entry.Modules == nil or entry.Modules[def.Id] == nil then
					all = false
				else
					fitted += 1
				end
			end
			if all then
				kitted += 1
			end
		end
		for _, bought in entry.Skins or {} do
			if bought then
				skins += 1
			end
		end
	end
	for _, skin in LevelRewards.SKINS do -- the level liveries count, on every jet you own
		if (data.PilotLevel or 1) >= skin.Level then
			skins += owned
		end
	end
	local full = data.Flags and data.Flags.AllUnlocked == true
	if full then
		totalJets, kitted, rp, skins, fitted, topTier, owned = math.huge, 0, 0, 0, 0, 1, 0
	end
	local stats = data.Stats or {}
	return {
		kind = "Career",
		matches = stats.Matches or 0,
		totalKills = (stats.Kills or 0) + (stats.AIKills or 0),
		playerKills = stats.Kills or 0,
		wins = stats.Wins or 0,
		assists = stats.Assists or 0,
		missilesDefeated = stats.MissilesDefeated or 0,
		captures = stats.Captures or 0,
		challengesDone = stats.Challenges or 0,
		modulesFitted = fitted,
		topTier = topTier,
		duelWins = (type(data.Duel) == "table" and data.Duel.Won) or 0,
		ownedJets = owned,
		totalJets = totalJets,
		fullyKitted = kitted,
		credits = if full then 0 else data.Credits,
		rp = rp,
		skins = skins,
		level = data.PilotLevel,
	}
end

return Achievements
