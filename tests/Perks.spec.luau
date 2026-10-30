--!strict
-- SHP-03: what the passes and boosters give (Shared/Perks), and that it reaches match rewards.
return function(ctx)
	local describe, it, expect = ctx.describe, ctx.it, ctx.expect
	local Perks = require(ctx.Shared.Perks)
	local PlayerData = require(ctx.Shared.PlayerData)
	local Progression = require(ctx.Shared.Progression)
	local Shop = require(ctx.Shared.Shop)
	local Challenges = require(ctx.Shared.Challenges)

	local NOW = 1_800_000_000

	local function fresh()
		return PlayerData.template()
	end

	describe("passes", function()
		it("VIP: +25% Credits and one more daily reroll", function()
			local data = fresh()
			expect(Perks.boost(data, NOW)).toBe(nil)
			data.Passes.VIP = true
			local boost = Perks.boost(data, NOW) :: Perks.Boost
			expect(boost.Credits).toBe(Perks.VIP_CREDITS)
			expect(boost.RP).toBe(1)
			expect(Perks.rerolls(data, Challenges.REROLLS_PER_DAY)).toBe(Challenges.REROLLS_PER_DAY + 1)
		end)

		it("Extra Lineup Slot: one more slot than the level gives", function()
			local data = fresh()
			local before = Progression.slotsFor(data)
			data.Passes.ExtraLineupSlot = true
			expect(Progression.slotsFor(data)).toBe(before + 1)
		end)
	end)

	describe("boosters", function()
		it("a booster product runs for an hour; buying another adds an hour", function()
			local data = fresh()
			Shop.processReceipt(data, "b1", "CreditsBooster", NOW)
			expect(Perks.boosterLeft(data, "Credits", NOW)).toBe(Perks.BOOSTER_SECONDS)
			Shop.processReceipt(data, "b2", "CreditsBooster", NOW + 600)
			expect(Perks.boosterLeft(data, "Credits", NOW + 600)).toBe(2 * Perks.BOOSTER_SECONDS - 600)
			expect(Perks.boosterLeft(data, "Credits", NOW + 3 * Perks.BOOSTER_SECONDS)).toBe(0)
		end)

		it("doubles Credits or RP, and never more than x2 with VIP as well", function()
			local data = fresh()
			Perks.extendBooster(data, "RP", NOW)
			local rpOnly = Perks.boost(data, NOW) :: Perks.Boost
			expect(rpOnly.RP).toBe(2)
			expect(rpOnly.Credits).toBe(1)
			data.Passes.VIP = true
			Perks.extendBooster(data, "Credits", NOW)
			local both = Perks.boost(data, NOW) :: Perks.Boost
			expect(both.Credits).toBe(Perks.CAP)
			expect(both.Label).toBe("VIP + Booster")
		end)
	end)

	describe("match rewards", function()
		local function summary(personal)
			return {
				Events = { { Kind = "Kill", Airframe = "F5E", Victim = "a", VictimAI = true } },
				LastAirframe = "F5E",
				Survived = true,
				Won = false,
				Afk = false,
				Day = 1,
				Personal = personal,
			}
		end

		it("a perk adds its own line and multiplies Credits and RP", function()
			local plain = Progression.matchRewards(summary(nil) :: any, 1)
			local boosted = Progression.matchRewards(summary({ Credits = 2, RP = 2, Label = "Booster" }) :: any, 1)
			expect(boosted.Credits).toBe(plain.Credits * 2)
			expect(boosted.RP.F5E).toBe(plain.RP.F5E * 2)
			expect(boosted.Lines[#boosted.Lines].Label).toBe("Booster")
		end)
	end)
end
