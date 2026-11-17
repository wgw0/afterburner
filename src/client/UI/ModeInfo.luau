--!strict
-- What each queue mode is (UI-05): its name, kind (and the kind's colour), team size, length, a one-line pitch
-- and a full description. Shared by the mode picker (ModeSelect) and the live-matches panel.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Duel = require(Shared.Duel)
local MatchRules = require(Shared.MatchRules)
local Strike = require(Shared.Strike)

local Theme = require(script.Parent.Theme)

-- Each kind of mode has its colour, on the card's stripe and tag
local KINDS = {
	Duels = { name = "DUELS", colour = Theme.Rarity.Legendary },
	Teams = { name = "TEAM BATTLE", colour = Theme.Rarity.Rare },
	FreeForAll = { name = "FREE FOR ALL", colour = Theme.Bad },
	Coop = { name = "CO-OP", colour = Theme.Good },
	Quick = { name = "QUICK PLAY", colour = Theme.Accent },
}

local function minutes(modeId: string): string
	return `{math.floor((MatchRules.MODES :: any)[modeId].TimeLimit / 60)} min`
end

export type Mode = { name: string, kind: string, size: string, length: string, pitch: string, about: string }

local MODES: { [string]: Mode } = {
	Duel = {
		name = "Ranked Duel",
		kind = "Duels",
		size = "1v1",
		length = "Best of 5",
		pitch = "Climb the ranks, one pilot at a time.",
		about = `1v1 against a pilot near your rating, best of five rounds with one life each. You start in opposite corners; first to {Duel.ROUNDS_TO_WIN} round wins. Wins and losses move your duel rating.`,
	},
	DuelCasual = {
		name = "Casual Duel",
		kind = "Duels",
		size = "1v1",
		length = "Best of 5",
		pitch = "Duel practice. No rating on the line.",
		about = "The same 1v1 rounds as Ranked Duel, for practice: your rating doesn't move.",
	},
	Any = {
		name = "Any Mode",
		kind = "Quick",
		size = "3v3 or FFA",
		length = "Fastest",
		pitch = "Jump into whichever match is ready first.",
		about = "Whichever of the team and free-for-all modes finds you a match fastest.",
	},
	TeamDeathmatch = {
		name = "Teams",
		kind = "Teams",
		size = "3v3",
		length = minutes("TeamDeathmatch"),
		pitch = "Fly with your wingmen. Most kills wins.",
		about = `Two teams of three. First team to {MatchRules.MODES.TeamDeathmatch.ScoreLimit} kills, or the most after {minutes(
			"TeamDeathmatch"
		)}.`,
	},
	AirSuperiority = {
		name = "Zones",
		kind = "Teams",
		size = "3v3",
		length = minutes("AirSuperiority"),
		pitch = "Seize the sky. Hold zones, drain tickets.",
		about = "Two teams fight for three zones. Hold more zones than the enemy and their tickets drain; every jet lost costs tickets too.",
	},
	StrikeEscort = {
		name = "Strike Escort",
		kind = "Teams",
		size = "3v3",
		length = minutes("StrikeEscort"),
		pitch = "Escort your bombers. Stop theirs.",
		about = `Two teams escort AI bombers to the enemy airbase and hunt theirs. First to {Strike.STRIKE_LIMIT} bomber strikes wins.`,
	},
	BVR = {
		name = "BVR Battle",
		kind = "Teams",
		size = "3v3",
		length = minutes("BVR"),
		pitch = "Radar missiles from 20 km out.",
		about = "Beyond visual range: two teams start about 20 km apart with radar missiles only. Needs a Tier IV+ jet with radar missiles.",
	},
	Dogfight = {
		name = "Dogfight",
		kind = "FreeForAll",
		size = "6 pilots",
		length = minutes("Dogfight"),
		pitch = "Everyone's a target. Most kills wins.",
		about = `Free for all: every other jet is an enemy. First to {MatchRules.MODES.Dogfight.ScoreLimit} kills, or the most after {minutes(
			"Dogfight"
		)}.`,
	},
	GunsOnly = {
		name = "Guns Only",
		kind = "FreeForAll",
		size = "6 pilots",
		length = minutes("GunsOnly"),
		pitch = "No missiles. Just guns and nerve.",
		about = `Free for all with no missiles: guns only, with {MatchRules.GUNS_ONLY_AMMO} times the ammo. Close-in turning fights.`,
	},
	Waves = {
		name = "PvE Waves",
		kind = "Coop",
		size = "Co-op, up to 3",
		length = `{Strike.WAVES} waves`,
		pitch = "Team up against waves of AI raiders.",
		about = `Co-op for up to three: defend your airbase from {Strike.WAVES} waves of AI fighters and bombers, each bigger than the last.`,
	},
}

return table.freeze({ KINDS = KINDS, MODES = MODES })
