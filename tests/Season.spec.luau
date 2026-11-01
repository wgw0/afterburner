--!strict
-- LIV-04: the season pass (Shared/Season, Config/Seasons).
return function(ctx)
	local describe, it, expect = ctx.describe, ctx.it, ctx.expect
	local Catalogue = require(ctx.Shared.Config.Cosmetics)
	local LevelRewards = require(ctx.Shared.Config.LevelRewards)
	local PlayerData = require(ctx.Shared.PlayerData)
	local Products = require(ctx.Shared.Config.Products)
	local Season = require(ctx.Shared.Season)
	local Seasons = require(ctx.Shared.Config.Seasons)
	local Shop = require(ctx.Shared.Shop)

	local S1 = Seasons.LIST[1]
	local DURING = S1.Start + 86400
	local XP_TIER = Seasons.XP_PER_TIER

	local function fresh()
		local data = PlayerData.template()
		Season.sync(data, DURING)
		return data
	end

	describe("seasons", function()
		it("every season has a reward for every tier on both tracks, and real cosmetics and titles", function()
			for _, season in Seasons.LIST do
				expect(season.End > season.Start).toBe(true)
				for tier = 1, Seasons.TIERS do
					for _, reward in { season.Free[tier], season.Premium[tier] } do
						expect(reward ~= nil).toBe(true)
						if reward.Kind == "Cosmetic" then
							local item = Catalogue.get(reward.Id :: string)
							expect(item ~= nil and item.Season == season.Id and item.Wings == nil).toBe(true)
						elseif reward.Kind == "Title" then
							expect(LevelRewards.titleName(reward.Id :: string) ~= nil).toBe(true)
							expect(table.find(LevelRewards.OTHER_TITLES, reward.Id) ~= nil).toBe(true)
						else
							expect((reward.Amount or 0) > 0).toBe(true)
						end
					end
				end
			end
		end)

		it("seasons don't overlap", function()
			for i = 2, #Seasons.LIST do
				expect(Seasons.LIST[i].Start >= Seasons.LIST[i - 1].End).toBe(true)
			end
		end)

		it("a finished premium track gives back most of a pass's Wings", function()
			for _, season in Seasons.LIST do
				local total = 0
				for tier = 1, Seasons.TIERS do
					if season.Premium[tier].Kind == "Wings" then
						total += season.Premium[tier].Amount :: number
					end
				end
				expect(total >= Seasons.PASS_WINGS * 0.8 and total < Seasons.PASS_WINGS).toBe(true)
			end
		end)

		it("every season cosmetic is a reward on its season's pass", function()
			for id, item in Catalogue.LIST do
				if item.Season then
					local season = Seasons.get(item.Season) :: Seasons.Season
					local found = false
					for tier = 1, Seasons.TIERS do
						local r = season.Premium[tier]
						local f = season.Free[tier]
						found = found or (r.Kind == "Cosmetic" and r.Id == id) or (f.Kind == "Cosmetic" and f.Id == id)
					end
					expect(found).toBe(true)
				end
			end
		end)
	end)

	describe("XP and tiers", function()
		it("XP earned during the season counts; none outside it", function()
			local data = fresh()
			Season.addXP(data, XP_TIER * 2 + 10, DURING)
			expect(Season.tierFor(data.Season.XP)).toBe(2)
			local before = PlayerData.template()
			Season.addXP(before, 5000, S1.Start - 10)
			expect(before.Season.XP).toBe(0)
		end)

		it("stops at the top tier", function()
			local data = fresh()
			Season.addXP(data, XP_TIER * 100, DURING)
			expect(Season.tierFor(data.Season.XP)).toBe(Seasons.TIERS)
			expect(select(2, Season.progress(data.Season.XP))).toBe(0)
		end)
	end)

	describe("claiming", function()
		it("claims every free reward reached, once", function()
			local data = fresh()
			Season.addXP(data, XP_TIER * 3, DURING)
			local credits = data.Credits
			local granted = Season.claim(data, DURING)
			expect(#granted).toBe(3)
			expect(data.Credits > credits).toBe(true)
			expect(#Season.claim(data, DURING)).toBe(0)
			expect(Season.claimable(data)).toBe(0)
		end)

		it("premium bought later still pays the premium tiers already reached", function()
			local data = fresh()
			Season.addXP(data, XP_TIER * 5, DURING)
			Season.claim(data, DURING)
			data.Wings = Seasons.PASS_WINGS
			expect(Season.buyPremium(data, DURING)).toBe(true)
			expect(data.Wings).toBe(0)
			expect(Season.claimable(data)).toBe(5)
			Season.claim(data, DURING)
			expect(data.Cosmetics.Owned.HUDLime).toBe(true) -- tier 1
			expect(data.Cosmetics.Owned.MarkerDiamonds).toBe(true) -- tier 5
		end)

		it("rewards left unclaimed are handed out when the next season starts", function()
			local data = fresh()
			data.Season.Premium = true
			Season.addXP(data, XP_TIER * 10, DURING)
			local nextSeason =
				{ Id = 2, Name = "Test", Start = S1.End, End = S1.End + 86400 * 56, Free = {}, Premium = {} }
			local list = Seasons.LIST :: any
			table.insert(list, nextSeason)
			local ok, err = pcall(function()
				local handed = Season.sync(data, S1.End + 10)
				expect(#handed).toBe(20)
				expect(data.Cosmetics.Owned.WingComet).toBe(true)
				expect(data.Season.Id).toBe(2)
				expect(data.Season.XP).toBe(0)
				expect(data.Season.Premium).toBe(false)
			end)
			table.remove(list)
			if not ok then
				error(err)
			end
		end)
	end)

	describe("buying the pass", function()
		it("with Wings: needs the Wings and a running season, and only once", function()
			local data = fresh()
			data.Wings = Seasons.PASS_WINGS - 1
			expect((Season.buyPremium(data, DURING))).toBe(false)
			data.Wings = Seasons.PASS_WINGS * 2
			expect((Season.buyPremium(data, DURING))).toBe(true)
			expect((Season.buyPremium(data, DURING))).toBe(false)
			expect(data.Wings).toBe(Seasons.PASS_WINGS)
			local between = PlayerData.template()
			between.Wings = 5000
			expect((Season.buyPremium(between, S1.Start - 10))).toBe(false)
		end)

		it("with Robux: the receipt grants the pass once; a second one gives its Wings instead", function()
			expect(Products.LIST.SeasonPass.Kind).toBe("SeasonPass")
			local data = fresh()
			Shop.processReceipt(data, "p1", "SeasonPass", DURING)
			expect(data.Season.Premium).toBe(true)
			expect(Shop.processReceipt(data, "p1", "SeasonPass", DURING)).toBe("AlreadyGranted")
			local wings = data.Wings
			Shop.processReceipt(data, "p2", "SeasonPass", DURING)
			expect(data.Wings).toBe(wings + Seasons.PASS_WINGS)
		end)
	end)

	describe("saves", function()
		it("an old save gets the new season fields", function()
			local data = PlayerData.template()
			data.Season = { Id = 1, XP = 0, Premium = false, Claimed = {} } -- the placeholder older saves have
			PlayerData.reconcile(data)
			expect(data.Season.FreeClaimed).toBe(0)
			expect(data.Season.PremiumClaimed).toBe(0)
			expect(table.find(PlayerData.REPLICATED, "Season") ~= nil).toBe(true)
		end)
	end)
end
