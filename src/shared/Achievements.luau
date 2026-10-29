--!strict
-- Achievements (DEVELOPMENT.md §26.2, LIV-02; DESIGN §10). Each has a Roblox badge once its id is set in
-- Config/Badges. Pure: ChallengeService decides from match events which ones a player has just earned.
-- Saved per player as data.Achievements = { [id] = { At = unix, Badge = true once the badge was awarded } }.

export type Def = { id: string, name: string, text: string }

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
} :: { Def })

Achievements.ACE_KILLS = 5
Achievements.VETERAN_MATCHES = 50

local BY_ID: { [string]: Def } = {}
for _, def in Achievements.LIST do
	BY_ID[def.id] = def
end

function Achievements.get(id: string): Def?
	return BY_ID[id]
end

-- What happened, as ChallengeService sees it.
export type Event = {
	kind: string, -- Kill | Win | MissileDefeated | Capture | MatchFinished | Spawn
	weapon: string?, -- Gun | IR | Radar
	lifeKills: number?, -- Kill: kills in this life, this one included
	hitThisMatch: boolean?, -- Win: whether you took any damage
	matches: number?, -- MatchFinished: lifetime matches, this one included
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
		if (event.lifeKills or 0) >= Achievements.ACE_KILLS then
			table.insert(ids, "AceInADay")
		end
	elseif kind == "Win" then
		table.insert(ids, "Victor")
		if event.hitThisMatch == false then
			table.insert(ids, "Untouchable")
		end
	elseif kind == "MissileDefeated" and event.weapon == "Radar" then
		table.insert(ids, "Notched")
	elseif kind == "Capture" then
		table.insert(ids, "ZoneHunter")
	elseif kind == "MatchFinished" and (event.matches or 0) >= Achievements.VETERAN_MATCHES then
		table.insert(ids, "Veteran")
	elseif kind == "Spawn" and event.airframe == "Tempest" then
		table.insert(ids, "TestPilot")
	end
	return ids
end

return Achievements
