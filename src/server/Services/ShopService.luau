--!strict
-- Robux purchases (DEVELOPMENT.md §27, SHP-01/02). The game's one MarketplaceService.ProcessReceipt:
--   1. no loaded save, an unknown product or any error → NotProcessedYet (Roblox retries later);
--   2. Shop.processReceipt grants the product to a copy of the save and keeps it only if that worked,
--      remembering the purchase id, so a repeated receipt is never granted twice;
--   3. the save is written straight away, then PurchaseGranted.
-- Tier Unlocks: the client picks two jets first (ChooseTierUnlock); the choice is checked, kept in the save
-- as PendingTierUnlock and the server prompts the purchase, so the receipt knows what to grant.
-- The Starter Bundle works the same way: the camo is picked first (ChooseStarter, kept as PendingStarter).
-- The weekly bundle is bought with Wings (BuyBundle).
-- Test servers can grant any product without Robux (admin shop.grant), through the same receipt path.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Products = require(Shared.Config.Products)
local Shop = require(Shared.Shop)
local Telemetry = require(ServerScriptService.Server.Lib.Telemetry)

local DataService = require(script.Parent.DataService)

local ShopService = {
	Priority = 55,
}

-- Grants a product for a purchase id, exactly once. Returns the receipt result, or nil and why not.
function ShopService:Grant(player: Player, purchaseId: string, key: string): (string?, string?)
	if not DataService:IsLoaded(player) then
		return nil, "save not loaded"
	end
	local before = DataService:GetData(player)
	local wingsBefore = before and before.Wings or 0
	local ok, result, detail = pcall(function()
		return DataService:Update(player, function(data)
			return Shop.processReceipt(data, purchaseId, key)
		end)
	end)
	if not ok then
		warn(`[Shop] granting {key} ({purchaseId}) to {player.UserId} failed: {result}`)
		return nil, tostring(result)
	end
	if result == "Granted" then
		DataService:Save(player)
		local product = Products.LIST[key]
		-- Robux sales are on the dashboard's Monetization pages already; the economy gets the Wings they buy
		-- (a Wings pack, or the Wings in the Starter Bundle)
		local data = DataService:GetData(player)
		local gained = (data and data.Wings or 0) - wingsBefore
		if gained > 0 then
			Telemetry.economy(player, "Source", "Wings", gained, data.Wings, Telemetry.SOURCES.Purchase, key)
		end
		Telemetry.event("Purchase", product.Price, { product = key, granted = detail }, player)
		print(`[Shop] {player.UserId} bought {key}: {detail}`)
	end
	return result, nil
end

local function processReceipt(receipt: { [string]: any }): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	local key = Products.keyFor(receipt.ProductId)
	if not (player and key) then
		if not key then
			warn(`[Shop] receipt for unknown product {receipt.ProductId}`)
		end
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local result = ShopService:Grant(player, receipt.PurchaseId, key)
	return if result then Enum.ProductPurchaseDecision.PurchaseGranted else Enum.ProductPurchaseDecision.NotProcessedYet
end

-- Picks the jets for the next Tier Unlock and opens the purchase. Returns ok, or false and why not.
function ShopService:ChooseTierUnlock(player: Player, picks: { any }): (boolean, string?)
	local data = DataService:GetData(player)
	if not data then
		return false, "Your data isn't loaded yet"
	end
	local tier, why = Shop.checkTierUnlockChoice(data, picks)
	if not tier then
		return false, why
	end
	local key = Products.tierUnlockKey(tier) :: string
	local id = Products.idFor(key)
	if not id then
		return false, "Tier Unlocks aren't on sale yet"
	end
	DataService:Update(player, function(d)
		d.PendingTierUnlock = { Tier = tier, Jets = { picks[1], picks[2] } }
	end)
	MarketplaceService:PromptProductPurchase(player, id)
	return true, nil
end

-- Picks the camo for the Starter Bundle and opens the purchase ("" when they own every camo).
function ShopService:ChooseStarter(player: Player, camoId: string): (boolean, string?)
	local data = DataService:GetData(player)
	if not data then
		return false, "Your data isn't loaded yet"
	end
	local ok, why = Shop.checkStarterChoice(data, camoId)
	if not ok then
		return false, why
	end
	local id = Products.idFor("Starter")
	if not id then
		return false, "Coming soon"
	end
	DataService:Update(player, function(d)
		d.PendingStarter = if camoId == "" then false else camoId
	end)
	MarketplaceService:PromptProductPurchase(player, id)
	return true, nil
end

-- Buys this week's featured bundle with Wings.
function ShopService:BuyBundle(player: Player, bundleId: string): (boolean, string?)
	local before = DataService:GetData(player)
	local wingsBefore = before and before.Wings or 0
	local ok, why = DataService:Update(player, function(data)
		return Shop.buyBundle(data, bundleId, os.time())
	end)
	local data = DataService:GetData(player)
	if ok and data then
		Telemetry.economy(player, "Sink", "Wings", wingsBefore - data.Wings, data.Wings, "BuyBundle", bundleId)
	end
	return ok == true, why
end

function ShopService:Init()
	MarketplaceService.ProcessReceipt = processReceipt
	Net.Server.handle("ChooseTierUnlock", function(player: Player, picks: { any })
		return self:ChooseTierUnlock(player, picks)
	end)
	Net.Server.handle("ChooseStarter", function(player: Player, camoId: string)
		return self:ChooseStarter(player, camoId)
	end)
	Net.Server.handle("BuyBundle", function(player: Player, bundleId: string)
		return self:BuyBundle(player, bundleId)
	end)
end

return ShopService
