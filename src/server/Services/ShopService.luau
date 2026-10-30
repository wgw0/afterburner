--!strict
-- Robux purchases (DEVELOPMENT.md §27, SHP-01/02). The game's one MarketplaceService.ProcessReceipt:
--   1. no loaded save, an unknown product or any error → NotProcessedYet (Roblox retries later);
--   2. Shop.processReceipt grants the product to a copy of the save and keeps it only if that worked,
--      remembering the purchase id, so a repeated receipt is never granted twice;
--   3. the save is written straight away, then PurchaseGranted.
-- Tier Unlocks: the client picks two jets first (ChooseTierUnlock); the choice is checked, kept in the save
-- as PendingTierUnlock and the server prompts the purchase, so the receipt knows what to grant.
-- Test servers can grant any product without Robux (admin shop.grant), through the same receipt path.

local AnalyticsService = game:GetService("AnalyticsService")
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
		pcall(function()
			AnalyticsService:LogEconomyEvent(
				player,
				Enum.AnalyticsEconomyFlowType.Source,
				"Robux",
				product.Price,
				0,
				Enum.AnalyticsEconomyTransactionType.IAP.Name,
				key
			)
		end)
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

function ShopService:Init()
	MarketplaceService.ProcessReceipt = processReceipt
	Net.Server.handle("ChooseTierUnlock", function(player: Player, picks: { any })
		return self:ChooseTierUnlock(player, picks)
	end)
end

return ShopService
