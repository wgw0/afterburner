--!strict
-- The season pass (LIV-04; the seasons are Config/Seasons). Saved as data.Season = { Id, XP, Premium,
-- FreeClaimed, PremiumClaimed }: the season it's for, its XP, whether the premium track is bought, and the
-- highest tier claimed on each track (claiming takes every reward reached so far). When a new season starts,
-- anything reached but not claimed in the old one is handed out first, so nothing is lost. Pure.

local Seasons = require(script.Parent.Config.Seasons)

local Season = {}

export type Granted = { Track: "Free" | "Premium", Tier: number, Reward: Seasons.Reward }

function Season.newState(): { [string]: any }
	return { Id = 0, XP = 0, Premium = false, FreeClaimed = 0, PremiumClaimed = 0 }
end

local function state(data: { [string]: any }): { [string]: any }
	if type(data.Season) ~= "table" then
		data.Season = Season.newState()
	end
	local s = data.Season
	s.Id = if type(s.Id) == "number" then s.Id else 0
	s.XP = if type(s.XP) == "number" then s.XP else 0
	s.Premium = s.Premium == true
	s.FreeClaimed = if type(s.FreeClaimed) == "number" then s.FreeClaimed else 0
	s.PremiumClaimed = if type(s.PremiumClaimed) == "number" then s.PremiumClaimed else 0
	return s
end

-- The tier reached with this much XP (0 to Seasons.TIERS).
function Season.tierFor(xp: number): number
	return math.clamp(xp // Seasons.XP_PER_TIER, 0, Seasons.TIERS)
end

-- XP into the next tier and the XP a tier needs (0, 0 once at the top).
function Season.progress(xp: number): (number, number)
	if Season.tierFor(xp) >= Seasons.TIERS then
		return 0, 0
	end
	return xp % Seasons.XP_PER_TIER, Seasons.XP_PER_TIER
end

-- Applies a reward to a save.
function Season.give(data: { [string]: any }, reward: Seasons.Reward)
	local amount = reward.Amount or 0
	if reward.Kind == "Credits" then
		data.Credits = (data.Credits or 0) + amount
	elseif reward.Kind == "FreeRP" then
		data.FreeRP = (data.FreeRP or 0) + amount
	elseif reward.Kind == "Wings" then
		data.Wings = (data.Wings or 0) + amount
	elseif reward.Kind == "Cosmetic" then
		data.Cosmetics = data.Cosmetics or {}
		data.Cosmetics.Owned = data.Cosmetics.Owned or {}
		data.Cosmetics.Owned[reward.Id :: string] = true
	elseif reward.Kind == "Title" then
		data.Titles = data.Titles or {}
		data.Titles[reward.Id :: string] = true
	end
end

-- The rewards reached but not claimed yet, free track first. (s: data.Season; season: its config)
local function unclaimed(s: { [string]: any }, season: Seasons.Season): { Granted }
	local list = {}
	local tier = Season.tierFor(s.XP)
	for t = s.FreeClaimed + 1, tier do
		table.insert(list, { Track = "Free", Tier = t, Reward = season.Free[t] })
	end
	if s.Premium then
		for t = s.PremiumClaimed + 1, tier do
			table.insert(list, { Track = "Premium", Tier = t, Reward = season.Premium[t] })
		end
	end
	return list
end

local function claimAll(data: { [string]: any }, s: { [string]: any }, season: Seasons.Season): { Granted }
	local list = unclaimed(s, season)
	for _, granted in list do
		Season.give(data, granted.Reward)
	end
	local tier = Season.tierFor(s.XP)
	s.FreeClaimed = math.max(s.FreeClaimed, tier)
	if s.Premium then
		s.PremiumClaimed = math.max(s.PremiumClaimed, tier)
	end
	return list
end

-- Brings the save's pass up to the season running now: if a new season has started, hands out what was
-- reached but not claimed in the old one, then starts afresh. Between seasons the last one stays (its
-- rewards can still be claimed). Returns what was handed out.
function Season.sync(data: { [string]: any }, now: number): { Granted }
	local s = state(data)
	local current = Seasons.at(now)
	if not current or current.Id == s.Id then
		return {}
	end
	local old = Seasons.get(s.Id)
	local handed = if old then claimAll(data, s, old) else {}
	data.Season = Season.newState()
	data.Season.Id = current.Id
	return handed
end

-- Adds season XP (all pilot XP counts while a season runs).
function Season.addXP(data: { [string]: any }, amount: number, now: number)
	Season.sync(data, now)
	local s = state(data)
	local current = Seasons.at(now)
	if current and current.Id == s.Id and amount > 0 then
		s.XP = math.min(s.XP + amount, Seasons.TIERS * Seasons.XP_PER_TIER)
	end
end

-- How many rewards are waiting to be claimed.
function Season.claimable(data: { [string]: any }): number
	local s = data.Season
	local season = type(s) == "table" and Seasons.get(s.Id)
	if not season then
		return 0
	end
	return #unclaimed(state(data), season)
end

-- Claims every reward reached. Returns what was granted (empty if nothing was waiting).
function Season.claim(data: { [string]: any }, now: number): { Granted }
	Season.sync(data, now)
	local s = state(data)
	local season = Seasons.get(s.Id)
	if not season then
		return {}
	end
	return claimAll(data, s, season)
end

-- Whether the premium track can be bought now, and why not.
function Season.canBuyPremium(data: { [string]: any }, now: number): (boolean, string?)
	Season.sync(data, now)
	local s = state(data)
	local current = Seasons.at(now)
	if not current or current.Id ~= s.Id then
		return false, "There's no season running"
	elseif s.Premium then
		return false, "You already have this season's pass"
	end
	return true, nil
end

-- Buys the premium track with Wings.
function Season.buyPremium(data: { [string]: any }, now: number): (boolean, string?)
	local ok, why = Season.canBuyPremium(data, now)
	if not ok then
		return false, why
	elseif (data.Wings or 0) < Seasons.PASS_WINGS then
		return false, "Not enough Wings"
	end
	data.Wings -= Seasons.PASS_WINGS
	state(data).Premium = true
	return true, nil
end

-- The Robux pass (the SeasonPass product): the premium track for the season running now. Bought twice (or
-- just after the season ended), it can't be undone, so it gives the pass's Wings price instead. Returns what
-- was granted.
function Season.grantPremium(data: { [string]: any }, now: number): string
	if Season.canBuyPremium(data, now) then
		state(data).Premium = true
		return `Season {data.Season.Id} pass`
	end
	data.Wings = (data.Wings or 0) + Seasons.PASS_WINGS
	return `+{Seasons.PASS_WINGS} Wings (pass already owned or no season)`
end

return Season
