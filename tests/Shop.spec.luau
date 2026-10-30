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
		it("grant only Wings or Tier Unlocks (never modules, performance or top-tier jets)", function()
			for key, product in Products.LIST do
				expect(product.Kind == "Wings" or product.Kind == "TierUnlock").toBe(true)
				expect(product.Price > 0).toBe(true)
				if product.Kind == "TierUnlock" then
					expect((product.Tier :: number) <= Products.MAX_UNLOCK_TIER).toBe(true)
					expect(Products.tierUnlockKey(product.Tier :: number)).toBe(key)
				end
			end
		end)

		it("Tier Unlocks exist for Tiers II to V and cost more each tier", function()
			local last = 0
			for tier = 2, 5 do
				local product = Products.LIST[`TierUnlock{tier}`]
				expect(product ~= nil).toBe(true)
				expect(product.Price > last).toBe(true)
				last = product.Price
			end
			expect(Products.tierUnlockKey(6)).toBe(nil)
		end)
	end)

	describe("Tier Unlock offer", function()
		it("a new account is offered Tier II, all of its jets to pick from", function()
			local offer = Shop.tierUnlockOffer(fresh()) :: Shop.Offer
			expect(offer.tier).toBe(2)
			table.sort(offer.jets)
			expect(table.concat(offer.jets, ",")).toBe("F4E,MiG23MLD,MirageF1")
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
			expect((Shop.checkTierUnlockChoice(data, { "F4E", "MirageF1" }))).toBe(2)
			expect((Shop.checkTierUnlockChoice(data, { "F4E" }))).toBe(nil)
			expect((Shop.checkTierUnlockChoice(data, { "F4E", "F4E" }))).toBe(nil)
			expect((Shop.checkTierUnlockChoice(data, { "F4E", "F16A" }))).toBe(nil)
			expect((Shop.checkTierUnlockChoice(data, { "F4E", "MirageF1", "MiG23MLD" }))).toBe(nil)
		end)
	end)

	describe("receipts", function()
		it("grant once: the same purchase id again changes nothing", function()
			local data = fresh()
			expect((Shop.processReceipt(data, "p1", "Wings550"))).toBe("Granted")
			expect(data.Wings).toBe(550)
			expect((Shop.processReceipt(data, "p1", "Wings550"))).toBe("AlreadyGranted")
			expect(data.Wings).toBe(550)
			expect((Shop.processReceipt(data, "p2", "Wings100"))).toBe("Granted")
			expect(data.Wings).toBe(650)
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
			data.PendingTierUnlock = { Tier = 2, Jets = { "MiG23MLD", "MirageF1" } }
			local result, detail = Shop.processReceipt(data, "p1", "TierUnlock2")
			expect(result).toBe("Granted")
			expect(detail ~= nil).toBe(true)
			for _, id in { "MiG23MLD", "MirageF1" } do
				expect(data.Aircraft[id].Owned and data.Aircraft[id].Researched).toBe(true)
			end
			expect(data.Aircraft.F4E).toBe(nil)
			expect(data.PendingTierUnlock).toBe(false)
			expect((Shop.tierUnlockOffer(data) :: Shop.Offer).tier).toBe(3)
		end)

		it("a Tier Unlock with its choice lost still grants two jets of that tier", function()
			local data = fresh()
			Shop.processReceipt(data, "p1", "TierUnlock2")
			local count = 0
			for _, node in TechTree.NODES do
				if node.Tier == 2 and data.Aircraft[node.Id] and data.Aircraft[node.Id].Owned then
					count += 1
				end
			end
			expect(count).toBe(Products.UNLOCK_JETS)
		end)
	end)
end
