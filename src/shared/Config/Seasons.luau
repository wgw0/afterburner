--!strict
-- Seasons (DESIGN §7.6, §8.2; LIV-04): about 8 weeks each, with a pass of TIERS tiers. Every tier has a free
-- reward and a premium one; the premium track is bought once a season, with Wings (PASS_WINGS) or Robux (the
-- SeasonPass developer product, Config/Products). Season XP is every bit of pilot XP earned while the season
-- runs (matches, challenges, bridge runs). The premium track gives back about 800 Wings, so a finished
-- season almost pays for the next pass. Season-only cosmetics (Config/Cosmetics, Season = the season's id)
-- are never sold; they're won here and kept for good. Shared/Season has the rules.
-- Rewards:
--   Credits / FreeRP / Wings   Amount of that currency
--   Cosmetic                   Id: a Config/Cosmetics item, owned for good
--   Title                      Id: a Config/LevelRewards title, unlocked for good

export type Reward = { Kind: "Credits" | "FreeRP" | "Wings" | "Cosmetic" | "Title", Amount: number?, Id: string? }

export type Season = {
	Id: number,
	Name: string,
	Start: number, -- unix time (UTC) it begins
	End: number, -- unix time (UTC) it ends
	Free: { Reward }, -- [tier] = reward
	Premium: { Reward },
}

local Seasons = {}

Seasons.TIERS = 30
Seasons.XP_PER_TIER = 2500 -- about 3–4 matches a day plus challenges reaches tier 30 in 6–7 weeks *(tune)*
Seasons.PASS_WINGS = 900

local function credits(n: number): Reward
	return { Kind = "Credits", Amount = n }
end
local function rp(n: number): Reward
	return { Kind = "FreeRP", Amount = n }
end
local function wings(n: number): Reward
	return { Kind = "Wings", Amount = n }
end
local function cosmetic(id: string): Reward
	return { Kind = "Cosmetic", Id = id }
end
local function title(id: string): Reward
	return { Kind = "Title", Id = id }
end

-- Free: Credits and Free RP every tier, growing, with a title at 15 and some Wings at 30.
-- Premium: a season cosmetic at 1, 5, 10, 20 and 25 and a title at 30; Wings every third tier and at 15 and 29
-- (800 in all); double the free Credits or Free RP in between.
local function season1(): ({ Reward }, { Reward })
	local free, premium = {}, {}
	for tier = 1, Seasons.TIERS do
		local amount = 500 + 100 * tier
		free[tier] = if tier % 2 == 1 then credits(amount * 2) else rp(amount)
		premium[tier] = if tier % 2 == 1 then credits(amount * 4) else rp(amount * 2)
	end
	free[15] = title("FirstLight")
	free[30] = wings(100)
	for _, tier in { 3, 6, 9, 12, 18, 21, 24, 27 } do
		premium[tier] = wings(75)
	end
	premium[1] = cosmetic("HUDLime")
	premium[5] = cosmetic("MarkerDiamonds")
	premium[10] = cosmetic("WingComet")
	premium[15] = wings(100)
	premium[20] = cosmetic("TrailAurora")
	premium[25] = cosmetic("WingSunburst")
	premium[29] = wings(100)
	premium[30] = title("Dawnbreaker")
	return free, premium
end

local free1, premium1 = season1()

-- (Each season is frozen; the list isn't, so the tests can add a season after this one.)
Seasons.LIST = {
	table.freeze({
		Id = 1,
		Name = "First Light",
		Start = 1793577600, -- Monday 2 November 2026, 00:00 UTC
		End = 1798416000, -- Monday 28 December 2026, 00:00 UTC (8 weeks)
		Free = free1,
		Premium = premium1,
	}),
} :: { Season }

function Seasons.get(id: number): Season?
	for _, season in Seasons.LIST do
		if season.Id == id then
			return season
		end
	end
	return nil
end

-- Test servers can preview a season before it starts (admin season.preview): this ReplicatedStorage attribute
-- holds the time the preview began, and the first season then runs for a week from it, for everyone on the
-- server.
Seasons.PREVIEW_ATTRIBUTE = "SeasonPreview"
Seasons.PREVIEW_LENGTH = 7 * 86400

local previews: { [number]: Season } = {}

local function preview(now: number): Season?
	local ok, began = pcall(function()
		return game:GetService("ReplicatedStorage"):GetAttribute(Seasons.PREVIEW_ATTRIBUTE)
	end)
	if not ok or type(began) ~= "number" or now < began or now >= began + Seasons.PREVIEW_LENGTH then
		return nil
	end
	if not previews[began] then
		local copy = table.clone(Seasons.LIST[1])
		copy.Start, copy.End = began, began + Seasons.PREVIEW_LENGTH
		previews[began] = table.freeze(copy)
	end
	return previews[began]
end

-- The season running at a time, or nil between seasons.
function Seasons.at(now: number): Season?
	for _, season in Seasons.LIST do
		if now >= season.Start and now < season.End then
			return season
		end
	end
	return preview(now)
end

return Seasons
