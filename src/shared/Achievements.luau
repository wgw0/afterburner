--!strict
-- Achievements (DEVELOPMENT.md §26.2, LIV-02; DESIGN §10). Each has a Roblox badge once its id is set in
-- Config/Badges. Pure: ChallengeService decides from match events which ones a player has just earned.
-- Saved per player as data.Achievements = { [id] = { At = unix, Badge = true once the badge was awarded } }.

export type Def = { id: string, name: string, text: string, secret: boolean? } -- secret: hidden until earned

local Achievements = {}

Achievements.LIST = table.freeze({
	{ id = "FirstBlood", name = "First Blood", text = "Shoot down your first jet." },
	{ id = "GunsOnly", name = "Guns Only", text = "Shoot a jet down with your guns." },
	{ id = "Victor", name = "Victor", text = "Win a match." },
	{ id = "AceInADay", name = "Ace in a Day", text = "Get 5 kills in one life." },
	{ id = "Untouchable", name = "Untouchable", text = "Win a match without taking a hit." },
	{ id = "Notched", name = "Notched", text = "Defeat a radar missile fired at you." },
	{ id = "ZoneHunter", name = "Zone Hunter", text = "Capture a zone in Air Superiority." },
	{ id = "Veteran", name = "Veteran", text = "Finish 50 matches." },
	{ id = "TestPilot", name = "Test Pilot", text = "Fly the Tempest in a match." },
	{ id = "FoxOne", name = "Fox One", text = "Shoot a jet down with a semi-active radar missile." },
	{ id = "FoxThree", name = "Fox Three", text = "Shoot a jet down with an active radar missile." },
	{ id = "DoubleTrouble", name = "Double Trouble", text = "Get 2 kills within 10 seconds." },
	{ id = "HatTrick", name = "Hat Trick", text = "Get 3 kills in one life." },
	{ id = "Flawless", name = "Flawless", text = "Get 3 kills in a match without being shot down." },
	{ id = "TeamPlayer", name = "Team Player", text = "Get 3 assists in one match." },
	{ id = "EscapeArtist", name = "Escape Artist", text = "Defeat 3 missiles in one life." },
	{ id = "TopOfTheTable", name = "Top of the Table", text = "Finish first in a free-for-all Dogfight." },
	{ id = "Centurion", name = "Centurion", text = "Shoot down 100 jets." },
	{ id = "Collector", name = "Collector", text = "Own 10 jets." },
	{ id = "HighFlyer", name = "High Flyer", text = "Reach pilot level 25." },
	-- Secret: not shown in Career until earned
	{ id = "ThreadTheNeedle", name = "Threading the Needle", text = "Fly under a bridge.", secret = true },
} :: { Def })

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
	level: number?, -- Career: pilot level
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
	end
	return ids
end

return Achievements
