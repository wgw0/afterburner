--!strict
-- Economy pacing (PRG-06): an average free player, simulated with the real reward and research code,
-- reaches the DESIGN §7.3 milestones on time. Tolerances are wider than the targets on purpose: this
-- guards against an economy change that breaks pacing, not against small tuning.

return function(ctx)
	local describe, it, expect = ctx.describe, ctx.it, ctx.expect
	local EconomySim = require(game:GetService("ServerStorage").Tools.EconomySim:Clone())

	describe("pacing", function()
		local milestones = EconomySim.run(14, ctx.Shared)

		it("the first new jet comes in about 20–30 minutes", function()
			local m = milestones["first new jet"]
			if not m then
				error("never reached", 0)
			end
			expect(m >= 15 and m <= 40).toBe(true)
		end)

		it("Tier II comes in about 2–3 hours", function()
			local m = milestones["Tier II"]
			if not m then
				error("never reached", 0)
			end
			expect(m >= 90 and m <= 210).toBe(true)
		end)

		it("Tier III comes in about 8–10 hours", function()
			local m = milestones["Tier III"]
			if not m then
				error("never reached in 14 hours", 0)
			end
			expect(m >= 6 * 60 and m <= 12 * 60).toBe(true)
		end)
	end)
end
