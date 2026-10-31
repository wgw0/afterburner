--!strict
-- Vs AI bots that adapt to how the player is doing (Will: "so they aren't having a terrible time"). Pure.
--   The player's form in the match is kills + half their assists - deaths. Each point of bad form makes the
--   bots EASE_STEP of a difficulty level easier (down to EASIER levels below the one picked, and below Easy
--   to FLOOR); each point of good form makes them HARDEN_STEP of a level harder (up to HARDER levels, Ace at
--   most). Between levels the profiles' numbers are blended, so the change is gradual.

local AIBrain = require(script.Parent.AIBrain)

local AdaptiveAI = {}

AdaptiveAI.ORDER = table.freeze({ "Easy", "Normal", "Hard", "Ace" })
AdaptiveAI.EASE_STEP = 0.3 -- levels easier per point of bad form
AdaptiveAI.HARDEN_STEP = 0.2 -- levels harder per point of good form (slower: struggling matters more)
AdaptiveAI.EASIER = 1.5 -- at most this many levels below the one picked
AdaptiveAI.HARDER = 1.0 -- at most this many above
-- One level below Easy, for a new pilot who's still being shot down on Easy
AdaptiveAI.FLOOR = table.freeze({
	Name = "Floor",
	ReactionTime = 1.8,
	AimError = 6,
	FireTolerance = 4,
	FlareSkill = 0.1,
	EnergySkill = 0.1,
	MaxGUse = 0.55,
	GunRange = 600,
	MissileInterval = 25,
	MissileRange = 0.4,
})

-- How many levels to move the bots from the one picked: negative is easier.
function AdaptiveAI.offset(kills: number, deaths: number, assists: number): number
	local form = kills + assists * 0.5 - deaths
	local step = if form < 0 then AdaptiveAI.EASE_STEP else AdaptiveAI.HARDEN_STEP
	return math.clamp(form * step, -AdaptiveAI.EASIER, AdaptiveAI.HARDER)
end

local function level(index: number): any
	return if index <= 0 then AdaptiveAI.FLOOR else (AIBrain.PROFILES :: any)[AdaptiveAI.ORDER[index]]
end

-- The profile for bots picked at `difficulty`, moved `offset` levels. Keeps the picked difficulty's name.
function AdaptiveAI.profile(difficulty: string, offset: number): any
	local base = table.find(AdaptiveAI.ORDER, difficulty) or 2
	local at = math.clamp(base + offset, 0, #AdaptiveAI.ORDER)
	local low = math.floor(at)
	local t = at - low
	local a, b = level(low), level(math.min(low + 1, #AdaptiveAI.ORDER))
	local blended = { Name = difficulty }
	for key, value in a do
		if type(value) == "number" then
			blended[key] = value + (b[key] - value) * t
		end
	end
	return blended
end

return AdaptiveAI
