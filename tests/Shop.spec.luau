--!strict
-- SHP-01/02: product config, exactly-once receipts and Tier Unlocks (Shared/Shop, Config/Products).
return function(ctx)
	local describe, it, expect = ctx.describe, ctx.it, ctx.expect
	local PlayerData = require(ctx.Shared.PlayerData)
	local Products = require(ctx.Shared.Config.Products)
	local Shop = require(ctx.Shared.Shop)
	local TechTree = require(ctx.Shared.TechTree)

	local function fresh()
		return PlayerData.template()
	end

	local function give(data, ...)
		for _, id in { ... } do
			data.Aircraft[id] = PlayerData.newAircraft(true)
		end
	end

	describe("products", function()
		it("grant only Wings, Tier Unlocks, boosters, the season pass or the starter bundle (never power)", function()
			for key, product in Products.LIST do
				expect(
					product.Kind == "Wings"
						or product.Kind == "TierUnlock"
						or product.Kind == "Booster"
						or product.Kind == "SeasonPass"
						or product.Kind == "Starter"
				).toBe(true)
				expect(product.Price > 0).toBe(true)
				if product.Kind == "TierUnlock" then
					expect((product.Tier :: number) <= Products.MAX_UNLOCK_TIER).toBe(true)
					expect(Products.tierUnlockKey(product.Tier :: number)).toBe(key)
				end
			end
		end)

		it("the smallest Wings pack buys at least one skin", function()
			local Skins = require(ctx.Shared.Skins)
			local smallest = math.huge
			for _, product in Products.LIST do
				if product.Kind == "Wings" then
					smallest = math.min(smallest, product.Amount :: number)
				end
			end
			expect(smallest >= Skins.WINGS_PRICE).toBe(true)
		end)

		it("Tier Unlocks exist for Tiers IV and V only, and cost more each tier", function()
			expect(Products.tierUnlockKey(2)).toBe(nil)
			expect(Products.tierUnlockKey(3)).toBe(nil)
			local last = 0
			for tier = 4, 5 do
				local product = Products.LIST[`TierUnlock{tier}`]
				expect(product ~= nil).toBe(true)
				expect(product.Price > last).toBe(true)
				last = product.Price
			end
			expect(Products.tierUnlockKey(6)).toBe(nil)
		end)
	end)

	describe("Tier Unlock offer", function()
		it("nothing before Tier IV: Tiers II and III come quickly enough to play for", function()
			local data = fresh()
			expect(Shop.tierUnlockOffer(data)).toBe(nil)
			give(data, "F4E")
			expect(Shop.tierUnlockOffer(data)).toBe(nil)
		end)

		it("a Tier III pilot is offered Tier IV, all of its jets to pick from", function()
			local data = fresh()
			give(data, "F16A")
			local offer = Shop.tierUnlockOffer(data) :: Shop.Offer
			expect(offer.tier).toBe(4)
			table.sort(offer.jets)
			expect(table.concat(offer.jets, ",")).toBe("F15C,FA18C,Su27S,TornadoF3")
		end)

		it("always the tier above your highest owned jet, and nothing past Tier V", function()
			local data = fresh()
			give(data, "F16A")
			expect((Shop.tierUnlockOffer(data) :: Shop.Offer).tier).toBe(4)
			give(data, "F16C")
			expect(Shop.tierUnlockOffer(data)).toBe(nil)
		end)

		it("the choice must be two different jets of that tier", function()
			local data = fresh()
			give(data, "F16A")
			expect((Shop.checkTierUnlockChoice(data, { "F15C", "Su27S" }))).toBe(4)
			expect((Shop.checkTierUnlockChoice(data, { "F15C" }))).toBe(nil)
			expect((Shop.checkTierUnlockChoice(data, { "F15C", "F15C" }))).toBe(nil)
			expect((Shop.checkTierUnlockChoice(data, { "F15C", "F16C" }))).toBe(nil)
			expect((Shop.checkTierUnlockChoice(data, { "F15C", "Su27S", "FA18C" }))).toBe(nil)
		end)
	end)

	describe("receipts", function()
		it("grant once: the same purchase id again changes nothing", function()
			local data = fresh()
			expect((Shop.processReceipt(data, "p1", "Wings550"))).toBe("Granted")
			expect(data.Wings).toBe(550)
			expect((Shop.processReceipt(data, "p1", "Wings550"))).toBe("AlreadyGranted")
			expect(data.Wings).toBe(550)
			expect((Shop.processReceipt(data, "p2", "Wings150"))).toBe("Granted")
			expect(data.Wings).toBe(700)
		end)

		it("an error mid-grant leaves the save untouched and the receipt unprocessed (so Roblox retries)", function()
			local data = fresh()
			local before = PlayerData.deepCopy(data)
			local ok = pcall(Shop.processReceipt, data, "p1", "NoSuchProduct")
			expect(ok).toBe(false)
			expect(PlayerData.deepEqual(data, before)).toBe(true)
			expect(table.find(data.ProcessedReceipts, "p1")).toBe(nil)
		end)

		it("a Tier Unlock grants the two chosen jets, researched and owned, and clears the choice", function()
			local data = fresh()
			give(data, "F16A")
			data.PendingTierUnlock = { Tier = 4, Jets = { "Su27S", "TornadoF3" } }
			local result, detail = Shop.processReceipt(data, "p1", "TierUnlock4")
			expect(result).toBe("Granted")
			expect(detail ~= nil).toBe(true)
			for _, id in { "Su27S", "TornadoF3" } do
				expect(data.Aircraft[id].Owned and data.Aircraft[id].Researched).toBe(true)
			end
			expect(data.Aircraft.F15C).toBe(nil)
			expect(data.PendingTierUnlock).toBe(false)
			expect((Shop.tierUnlockOffer(data) :: Shop.Offer).tier).toBe(5)
		end)

		it("a Tier Unlock with its choice lost still grants two jets of that tier", function()
			local data = fresh()
			give(data, "F16A")
			Shop.processReceipt(data, "p1", "TierUnlock4")
			local count = 0
			for _, node in TechTree.NODES do
				if node.Tier == 4 and data.Aircraft[node.Id] and data.Aircraft[node.Id].Owned then
					count += 1
				end
			end
			expect(count).toBe(Products.UNLOCK_JETS)
		end)
	end)

	describe("spending Wings (SHP-04)", function()
		local Progression = require(ctx.Shared.Progression)
		local Skins = require(ctx.Shared.Skins)

		it("a skin sold for Credits can be bought for Wings instead; default and level skins can't", function()
			local data = fresh()
			data.Wings = Skins.WINGS_PRICE + 10
			local credits = data.Credits
			expect((Progression.buySkin(data, "F5E", "Desert", "Wings"))).toBe(true)
			expect(data.Wings).toBe(10)
			expect(data.Credits).toBe(credits)
			expect(Progression.ownsSkin(data, "F5E", "Desert")).toBe(true)
			expect((Progression.canBuySkin(data, "F5E", "Ghost", "Wings"))).toBe(false)
		end)

		it("not without enough Wings, and nothing changes", function()
			local data = fresh()
			data.Wings = Skins.WINGS_PRICE - 1
			local ok, why = Progression.buySkin(data, "F5E", "Pacific", "Wings")
			expect(ok).toBe(false)
			expect(string.find(why :: string, "Wings", 1, true) ~= nil).toBe(true)
			expect(data.Wings).toBe(Skins.WINGS_PRICE - 1)
			expect(Progression.ownsSkin(data, "F5E", "Pacific")).toBe(false)
		end)
	end)
	describe("Starter Bundle (SHP-05)", function()
		local Catalogue = require(ctx.Shared.Config.Cosmetics)
		local NOW = 1793577600

		it("grants the camo picked, the booster hours and the Wings, once per player", function()
			local data = fresh()
			local offer = Shop.starterOffer(data) :: { string }
			expect(#offer > 0).toBe(true)
			expect(table.find(offer, "CamoVIP")).toBe(nil) -- a pass camo isn't sold, so it isn't offered
			expect((Shop.checkStarterChoice(data, "CamoNope"))).toBe(false)
			expect((Shop.checkStarterChoice(data, offer[1]))).toBe(true)
			data.PendingStarter = offer[1]
			Shop.processReceipt(data, "s1", "Starter", NOW)
			expect(data.Cosmetics.Owned[offer[1]]).toBe(true)
			expect(data.Cosmetics.Equipped.Camo).toBe(offer[1])
			expect(data.Wings).toBe(Shop.STARTER.Wings)
			expect(data.Boosters.Credits).toBe(NOW + Shop.STARTER.BoosterHours * 3600)
			expect(data.StarterBought).toBe(true)
			expect(Shop.starterOffer(data)).toBe(nil)
		end)

		it("with its choice lost, gives a camo's worth of Wings instead", function()
			local data = fresh()
			Shop.processReceipt(data, "s1", "Starter", NOW)
			expect(data.Wings).toBe(Shop.STARTER.Wings + Catalogue.LIST.CamoArctic.Wings)
		end)

		it("is far cheaper than its parts", function()
			local camo = Catalogue.LIST.CamoArctic.Wings :: number
			local booster = Products.LIST.CreditsBooster.Price * Shop.STARTER.BoosterHours
			expect(Products.LIST.Starter.Price * 3 < camo + Shop.STARTER.Wings + booster).toBe(true)
		end)
	end)

	describe("weekly bundle (SHP-05)", function()
		local Bundles = require(ctx.Shared.Config.Bundles)
		local Catalogue = require(ctx.Shared.Config.Cosmetics)
		local MONDAY = 1793577600 -- Monday 2 November 2026, 00:00 UTC

		it("changes on Monday at midnight UTC, the same for everyone, through the whole list", function()
			local week, nextAt = Shop.week(MONDAY)
			expect(nextAt).toBe(MONDAY + 7 * 86400)
			expect(Shop.week(MONDAY - 1)).toBe(week - 1)
			expect(Shop.week(MONDAY + 7 * 86400 - 1)).toBe(week)
			local seen = {}
			for i = 0, #Bundles.LIST - 1 do
				seen[Shop.bundleFor(MONDAY + i * 7 * 86400).Id] = true
			end
			for _, bundle in Bundles.LIST do
				expect(seen[bundle.Id]).toBe(true)
			end
		end)

		it("every bundle is cosmetics sold for Wings, and costs less than its items", function()
			for _, bundle in Bundles.LIST do
				expect(#bundle.Items >= 2).toBe(true)
				for _, id in bundle.Items do
					local item = Catalogue.get(id)
					expect(item ~= nil and item.Wings ~= nil).toBe(true)
				end
				local price, items, full = Shop.bundlePrice(fresh(), bundle)
				expect(#items).toBe(#bundle.Items)
				expect(price < full).toBe(true)
			end
		end)

		it("charges only for what you don't own, and only this week's bundle", function()
			local data = fresh()
			local bundle = Shop.bundleFor(MONDAY)
			local fullPrice = Shop.bundlePrice(data, bundle)
			data.Cosmetics.Owned[bundle.Items[1]] = true
			local price, items = Shop.bundlePrice(data, bundle)
			expect(price < fullPrice).toBe(true)
			expect(#items).toBe(#bundle.Items - 1)
			data.Wings = price
			local other = Shop.bundleFor(MONDAY + 7 * 86400)
			expect((Shop.buyBundle(data, other.Id, MONDAY))).toBe(false)
			expect((Shop.buyBundle(data, bundle.Id, MONDAY))).toBe(true)
			expect(data.Wings).toBe(0)
			for _, id in bundle.Items do
				expect(data.Cosmetics.Owned[id]).toBe(true)
			end
			expect((Shop.buyBundle(data, bundle.Id, MONDAY))).toBe(false) -- nothing left to buy
		end)
	end)
end
