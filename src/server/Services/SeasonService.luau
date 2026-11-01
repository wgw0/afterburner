--!strict
-- The season pass (LIV-04; rules in Shared/Season, seasons in Config/Seasons). Season XP is added with all
-- pilot XP (Progression.addXP). This service brings each save up to the running season when it loads (a new
-- season hands out what was left unclaimed in the old one), claims rewards and sells the premium track:
-- for Wings here, or for Robux through the SeasonPass product (its receipt is ShopService's).

local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Products = require(Shared.Config.Products)
local Season = require(Shared.Season)
local Seasons = require(Shared.Config.Seasons)
local Telemetry = require(ServerScriptService.Server.Lib.Telemetry)

local DataService = require(script.Parent.DataService)

local SeasonService = {
	Priority = 56,
}

-- Logs the currencies a batch of rewards paid (the economy dashboard)
local function logRewards(player: Player, granted: { Season.Granted })
	local data = DataService:GetData(player)
	if not data then
		return
	end
	local totals = { Credits = 0, Wings = 0 }
	for _, g in granted do
		if totals[g.Reward.Kind] then
			totals[g.Reward.Kind] += g.Reward.Amount or 0
		end
	end
	for currency, amount in totals do
		if amount > 0 then
			Telemetry.economy(
				player,
				"Source",
				currency,
				amount,
				data[currency],
				Telemetry.SOURCES.Season,
				"SeasonPass"
			)
		end
	end
end

-- Claims every reward reached. Returns how many were claimed, or nil and why not.
function SeasonService:Claim(player: Player): (number?, string?)
	local granted = DataService:Update(player, function(data)
		return Season.claim(data, os.time())
	end)
	if type(granted) ~= "table" then
		return nil, "Your data isn't loaded yet"
	end
	if #granted == 0 then
		return nil, "Nothing to claim yet"
	end
	logRewards(player, granted)
	return #granted, nil
end

-- Buys the premium track: "Wings" spends PASS_WINGS; "Robux" opens the SeasonPass purchase.
function SeasonService:BuyPass(player: Player, how: string): (boolean, string?)
	local data = DataService:GetData(player)
	if not data then
		return false, "Your data isn't loaded yet"
	end
	if how == "Robux" then
		local ok, why = Season.canBuyPremium(data, os.time())
		if not ok then
			return false, why
		end
		local id = Products.idFor("SeasonPass")
		if not id then
			return false, "Coming soon"
		end
		MarketplaceService:PromptProductPurchase(player, id)
		return true, nil
	elseif how == "Wings" then
		local ok, why = DataService:Update(player, function(d)
			return Season.buyPremium(d, os.time())
		end)
		if ok then
			local after = DataService:GetData(player)
			Telemetry.economy(
				player,
				"Sink",
				"Wings",
				Seasons.PASS_WINGS,
				after and after.Wings or 0,
				"SeasonPass",
				`Season{after and after.Season.Id}`
			)
		end
		return ok == true, why
	end
	return false, "Unknown payment"
end

function SeasonService:Init()
	DataService.ProfileLoaded:Connect(function(player, data)
		local handed = Season.sync(data, os.time())
		if #handed > 0 then
			logRewards(player, handed)
		end
	end)
	Net.Server.handle("ClaimSeason", function(player: Player)
		local count, why = self:Claim(player)
		return count ~= nil, why or `{count} rewards claimed`
	end)
	Net.Server.handle("BuySeasonPass", function(player: Player, how: string)
		return self:BuyPass(player, how)
	end)
end

return SeasonService
