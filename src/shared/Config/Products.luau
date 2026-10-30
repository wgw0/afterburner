--!strict
-- Roblox Developer Products (DESIGN §8, DEVELOPMENT.md §27): what each one grants and its Robux price,
-- plus its id in each experience. A product belongs to one experience, so the test and live experiences
-- each have their own ids. Create the product on the Creator Dashboard (Monetization → Developer Products)
-- at the price below and put its id here. A product with no id can't be bought yet (test servers can grant
-- one with the admin command shop.grant). Game passes are in Config/Passes.
--
-- Kinds:
--   Wings: adds Amount Wings (the premium currency for cosmetics).
--   TierUnlock: two jets of Tier, chosen by the buyer, researched and owned (Shop.tierUnlockOffer has the
--     rules: only the tier above your highest owned jet, never past Tier V).
--   Booster: doubles Credits or RP from matches for an hour (Shared/Perks: another adds an hour; capped at
--     ×2 with VIP).

export type Product = {
	Kind: "Wings" | "TierUnlock" | "Booster",
	DisplayName: string,
	Price: number, -- Robux, as set on the dashboard
	Amount: number?, -- Wings
	Tier: number?, -- TierUnlock
	Booster: string?, -- Booster: "Credits" | "RP"
}

local Products = {}

Products.MAX_UNLOCK_TIER = 5 -- Tiers VI–VIII are only ever researched (DESIGN §8.3)
Products.UNLOCK_JETS = 2 -- jets a Tier Unlock grants

Products.LIST = table.freeze({
	-- The smallest pack buys at least one skin (Skins.WINGS_PRICE): no pack leaves you just short
	Wings150 = table.freeze({ Kind = "Wings", DisplayName = "150 Wings", Price = 149, Amount = 150 }),
	Wings550 = table.freeze({ Kind = "Wings", DisplayName = "550 Wings", Price = 499, Amount = 550 }),
	Wings1200 = table.freeze({ Kind = "Wings", DisplayName = "1,200 Wings", Price = 999, Amount = 1200 }),
	Wings2500 = table.freeze({ Kind = "Wings", DisplayName = "2,500 Wings", Price = 1999, Amount = 2500 }),
	TierUnlock2 = table.freeze({ Kind = "TierUnlock", DisplayName = "Unlock Tier II", Price = 99, Tier = 2 }),
	TierUnlock3 = table.freeze({ Kind = "TierUnlock", DisplayName = "Unlock Tier III", Price = 199, Tier = 3 }),
	TierUnlock4 = table.freeze({ Kind = "TierUnlock", DisplayName = "Unlock Tier IV", Price = 299, Tier = 4 }),
	TierUnlock5 = table.freeze({ Kind = "TierUnlock", DisplayName = "Unlock Tier V", Price = 399, Tier = 5 }),
	CreditsBooster = table.freeze({
		Kind = "Booster",
		DisplayName = "2x Credits (1 hour)",
		Price = 75,
		Booster = "Credits",
	}),
	RPBooster = table.freeze({ Kind = "Booster", DisplayName = "2x RP (1 hour)", Price = 75, Booster = "RP" }),
}) :: { [string]: Product }

local BY_UNIVERSE: { [number]: { [string]: number } } = {
	[10773135125] = { -- the test experience
		Wings150 = 3723989018,
		Wings550 = 3723989234,
		Wings1200 = 3723989437,
		Wings2500 = 3723989686,
		TierUnlock2 = 3723989940,
		TierUnlock3 = 3723990190,
		TierUnlock4 = 3723990459,
		TierUnlock5 = 3723990665,
		CreditsBooster = 3724025598,
		RPBooster = 3724025817,
	},
	[10773807904] = { -- the live experience (place 95037764806358)
		Wings150 = 3723986676,
		Wings550 = 3723986944,
		Wings1200 = 3723987123,
		Wings2500 = 3723987371,
		TierUnlock2 = 3723987579,
		TierUnlock3 = 3723987793,
		TierUnlock4 = 3723988148,
		TierUnlock5 = 3723988280,
		CreditsBooster = 3724023374,
		RPBooster = 3724023704,
	},
}

-- The product's id in this experience, or nil if it hasn't been created here yet.
function Products.idFor(key: string): number?
	local ids = BY_UNIVERSE[game.GameId]
	local id = ids and ids[key]
	return if id and id > 0 then id else nil
end

-- The product key for an id in this experience (receipts carry the id), or nil.
function Products.keyFor(productId: number): string?
	for key, id in BY_UNIVERSE[game.GameId] or {} do
		if id == productId then
			return key
		end
	end
	return nil
end

-- The Tier Unlock product for a tier, or nil.
function Products.tierUnlockKey(tier: number): string?
	local key = `TierUnlock{tier}`
	return if Products.LIST[key] then key else nil
end

return Products
