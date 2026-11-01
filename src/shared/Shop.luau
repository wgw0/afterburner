--!strict
-- What Robux purchases grant, and the receipt rule that makes each grant happen exactly once
-- (DEVELOPMENT.md §27, SHP-01/02), plus the Starter Bundle and the weekly bundle (SHP-05). Pure: ShopService
-- wraps it around MarketplaceService.ProcessReceipt and the save; the tests drive it directly.

local Bundles = require(script.Parent.Config.Bundles)
local Catalogue = require(script.Parent.Config.Cosmetics)
local Cosmetics = require(script.Parent.Cosmetics)
local Perks = require(script.Parent.Perks)
local Products = require(script.Parent.Config.Products)
local PlayerData = require(script.Parent.PlayerData)
local Season = require(script.Parent.Season)
local TechTree = require(script.Parent.TechTree)

local Shop = {}

export type Offer = { tier: number, jets: { string } } -- the Tier Unlock you could buy, and its jets

local function owns(data: { [string]: any }, id: string): boolean
	local entry = data.Aircraft and data.Aircraft[id]
	return entry ~= nil and entry.Owned == true
end

-- The highest tier the player owns a jet in (1 for a new account).
function Shop.highestTier(data: { [string]: any }): number
	local top = 1
	for _, node in TechTree.NODES do
		if node.Tier > top and owns(data, node.Id) then
			top = node.Tier
		end
	end
	return top
end

-- The Tier Unlock this player can buy: the tier above their highest owned jet, with the jets of that tier
-- they could pick from; nil until that's Tier IV (Products.MIN_UNLOCK_TIER) and once they own a Tier V jet
-- or above (Tiers VI–VIII are only ever researched).
function Shop.tierUnlockOffer(data: { [string]: any }): Offer?
	local tier = Shop.highestTier(data) + 1
	if tier < Products.MIN_UNLOCK_TIER or tier > Products.MAX_UNLOCK_TIER then
		return nil
	end
	local jets = {}
	for _, node in TechTree.NODES do
		if node.Tier == tier and not owns(data, node.Id) then
			table.insert(jets, node.Id)
		end
	end
	if #jets < Products.UNLOCK_JETS then
		return nil
	end
	return { tier = tier, jets = jets }
end

-- Whether picks is a valid choice for the player's Tier Unlock: exactly UNLOCK_JETS different jets from
-- the offer. Returns the tier, or nil and why not.
function Shop.checkTierUnlockChoice(data: { [string]: any }, picks: { any }): (number?, string?)
	local offer = Shop.tierUnlockOffer(data)
	if not offer then
		return nil, "There's no tier to unlock"
	end
	if type(picks) ~= "table" or #picks ~= Products.UNLOCK_JETS then
		return nil, `Pick {Products.UNLOCK_JETS} jets`
	end
	local seen = {}
	for _, id in picks do
		if type(id) ~= "string" or seen[id] or not table.find(offer.jets, id) then
			return nil, "Pick jets from the next tier"
		end
		seen[id] = true
	end
	return offer.tier, nil
end

-- The jets a Tier Unlock grants: the pending choice if it's for that tier, otherwise the first jets of the
-- tier the player doesn't own yet (a choice lost on the way still gets them two jets).
local function unlockJets(data: { [string]: any }, tier: number): { string }
	local pending = data.PendingTierUnlock
	if type(pending) == "table" and pending.Tier == tier and type(pending.Jets) == "table" then
		local valid = {}
		for _, id in pending.Jets do
			local node = type(id) == "string" and TechTree.get(id)
			if node and node.Tier == tier then
				table.insert(valid, id)
			end
		end
		if #valid == Products.UNLOCK_JETS then
			return valid
		end
	end
	local jets = {}
	for _, node in TechTree.NODES do
		if node.Tier == tier and not owns(data, node.Id) and #jets < Products.UNLOCK_JETS then
			table.insert(jets, node.Id)
		end
	end
	return jets
end

-- The Starter Bundle (DESIGN §8.4): once per player, a camo they pick (from the ones sold for Wings), hours
-- of double Credits and some Wings, for far less than they'd cost on their own.
Shop.STARTER = table.freeze({ BoosterHours = 3, Wings = 300 })

-- The camos the player could pick for the Starter Bundle (sold for Wings, ready, not owned yet), or nil once
-- they've bought it.
function Shop.starterOffer(data: { [string]: any }): { string }?
	if data.StarterBought == true then
		return nil
	end
	local camos = {}
	for _, id in Catalogue.ofKind("Camo") do
		local item = Catalogue.LIST[id]
		if item.Wings and Cosmetics.ready(id) and not Cosmetics.owns(data, id) then
			table.insert(camos, id)
		end
	end
	return camos
end

-- Whether camoId is a valid pick for the player's Starter Bundle. Returns ok, or false and why not.
function Shop.checkStarterChoice(data: { [string]: any }, camoId: any): (boolean, string?)
	local offer = Shop.starterOffer(data)
	if not offer then
		return false, "You've already got the Starter Bundle"
	elseif #offer == 0 and camoId == "" then
		return true, nil -- they own every camo: the bundle gives a camo's Wings instead
	elseif type(camoId) ~= "string" or not table.find(offer, camoId) then
		return false, "Pick a camo"
	end
	return true, nil
end

local function cheapestCamo(): number
	local price = math.huge
	for _, id in Catalogue.ofKind("Camo") do
		price = math.min(price, Catalogue.LIST[id].Wings or math.huge)
	end
	return price
end

local function grantStarter(data: { [string]: any }, now: number): string
	if data.StarterBought == true then
		-- Bought twice somehow: Roblox has taken the Robux, so give its Wings rather than nothing
		data.Wings = (data.Wings or 0) + Shop.STARTER.Wings
		return `+{Shop.STARTER.Wings} Wings (Starter Bundle already bought)`
	end
	local camo = data.PendingStarter
	local granted
	if type(camo) == "string" and Shop.checkStarterChoice(data, camo) and camo ~= "" then
		data.Cosmetics = data.Cosmetics or { Owned = {}, Equipped = {} }
		data.Cosmetics.Owned[camo] = true
		data.Cosmetics.Equipped = data.Cosmetics.Equipped or {}
		data.Cosmetics.Equipped.Camo = camo
		granted = camo
	else
		-- The choice was lost (or they own every camo): a camo's worth of Wings instead
		local price = cheapestCamo()
		data.Wings = (data.Wings or 0) + (if price < math.huge then price else 0)
		granted = "a camo's Wings"
	end
	for _ = 1, Shop.STARTER.BoosterHours do
		Perks.extendBooster(data, "Credits", now)
	end
	data.Wings = (data.Wings or 0) + Shop.STARTER.Wings
	data.StarterBought = true
	data.PendingStarter = false
	return `Starter Bundle: {granted}, {Shop.STARTER.BoosterHours}h Credits booster, +{Shop.STARTER.Wings} Wings`
end

-- The weekly bundle ------------------------------------------------------------------------------

local WEEK = 7 * 86400
local MONDAY = 4 * 86400 -- the unix epoch was a Thursday; weeks start on Monday 00:00 UTC

-- The week number (changes on Monday at 00:00 UTC) and when the next one starts.
function Shop.week(now: number): (number, number)
	local week = (now - MONDAY) // WEEK
	return week, MONDAY + (week + 1) * WEEK
end

-- This week's featured bundle: the same for everyone, in Config/Bundles' order.
function Shop.bundleFor(now: number): Bundles.Bundle
	local week = Shop.week(now)
	return Bundles.LIST[week % #Bundles.LIST + 1]
end

-- What a bundle costs this player: DISCOUNT off the items they don't own yet (rounded to 10 Wings). Returns
-- the price, the items it would give, and the items' full price.
function Shop.bundlePrice(data: { [string]: any }, bundle: Bundles.Bundle): (number, { string }, number)
	local items, full = {}, 0
	for _, id in bundle.Items do
		local item = Catalogue.get(id)
		if item and item.Wings and Cosmetics.ready(id) and not Cosmetics.owns(data, id) then
			table.insert(items, id)
			full += item.Wings
		end
	end
	return math.round(full * (1 - Bundles.DISCOUNT) / 10) * 10, items, full
end

-- Buys this week's bundle (bundleId must be it, so a purchase can't land on next week's by accident).
function Shop.buyBundle(data: { [string]: any }, bundleId: string, now: number): (boolean, string?)
	local bundle = Shop.bundleFor(now)
	if bundle.Id ~= bundleId then
		return false, "That bundle isn't on this week"
	end
	local price, items = Shop.bundlePrice(data, bundle)
	if #items == 0 then
		return false, "You already own all of it"
	elseif (data.Wings or 0) < price then
		return false, "Not enough Wings"
	end
	data.Wings -= price
	data.Cosmetics = data.Cosmetics or { Owned = {}, Equipped = {} }
	for _, id in items do
		data.Cosmetics.Owned[id] = true
	end
	return true, nil
end

-- Applies a product to a save. Returns a short description of what was granted, or errors.
-- now: the unix time (boosters start from it); os.time() if not given.
function Shop.grant(data: { [string]: any }, key: string, now: number?): string
	local product = Products.LIST[key]
	if not product then
		error(`unknown product {key}`)
	end
	if product.Kind == "Wings" then
		data.Wings = (data.Wings or 0) + (product.Amount :: number)
		return `+{product.Amount} Wings`
	elseif product.Kind == "TierUnlock" then
		local jets = unlockJets(data, product.Tier :: number)
		for _, id in jets do
			local entry = data.Aircraft[id]
			if entry then
				entry.Owned, entry.Researched = true, true
			else
				data.Aircraft[id] = PlayerData.newAircraft(true)
			end
		end
		data.PendingTierUnlock = false
		return `Tier {product.Tier}: {table.concat(jets, ", ")}`
	elseif product.Kind == "Booster" then
		Perks.extendBooster(data, product.Booster :: string, now or os.time())
		return `{product.Booster} booster, +1 hour`
	elseif product.Kind == "SeasonPass" then
		return Season.grantPremium(data, now or os.time())
	elseif product.Kind == "Starter" then
		return grantStarter(data, now or os.time())
	end
	error(`no grant for {product.Kind}`)
end

export type ReceiptResult = "Granted" | "AlreadyGranted"

-- The receipt rule (DEVELOPMENT.md §27.3): a purchase id already in the save was granted before and is
-- granted again never; otherwise the product is applied to a copy of the save, and only if that works is
-- the copy written back with the purchase id remembered. An error leaves the save untouched (the caller
-- answers NotProcessedYet and Roblox retries). Returns the result and what was granted.
function Shop.processReceipt(
	data: { [string]: any },
	purchaseId: string,
	key: string,
	now: number?
): (ReceiptResult, string?)
	if table.find(data.ProcessedReceipts, purchaseId) then
		return "AlreadyGranted", nil
	end
	local copy = PlayerData.deepCopy(data)
	local detail = Shop.grant(copy, key, now)
	for field in data do
		if copy[field] == nil then
			data[field] = nil
		end
	end
	for field, value in copy do
		data[field] = value
	end
	PlayerData.rememberReceipt(data, purchaseId)
	return "Granted", detail
end

return Shop
