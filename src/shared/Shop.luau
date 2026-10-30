--!strict
-- What Robux purchases grant, and the receipt rule that makes each grant happen exactly once
-- (DEVELOPMENT.md §27, SHP-01/02). Pure: ShopService wraps it around MarketplaceService.ProcessReceipt and
-- the save; the tests drive it directly.

local Perks = require(script.Parent.Perks)
local Products = require(script.Parent.Config.Products)
local PlayerData = require(script.Parent.PlayerData)
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
-- they could pick from; nil once they own a Tier V jet or above (Tiers VI–VIII are only ever researched).
function Shop.tierUnlockOffer(data: { [string]: any }): Offer?
	local tier = Shop.highestTier(data) + 1
	if tier > Products.MAX_UNLOCK_TIER then
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
