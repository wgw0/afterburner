--!strict
-- Economy pacing (PRG-06): an average free player, simulated with the real reward and research code,
-- reaches the DESIGN §7.3 milestones on time (Will, November 2026: Tier II in 20–30 minutes, then scaling
-- up). Tolerances are wider than the targets on purpose: this guards against an economy change that breaks
-- pacing, not against small tuning. Matches are 11 minutes, so times come in steps of 11.

return function(ctx)
	local describe, it, expect = ctx.describe, ctx.it, ctx.expect
	local EconomySim = require(game:GetService("ServerStorage").Tools.EconomySim:Clone())

	describe("pacing", function()
		local milestones = EconomySim.run(80, ctx.Shared)

		-- name, target text, lowest and highest minutes accepted
		local TARGETS = {
			{ "first new jet", "about 10 minutes", 5, 25 },
			{ "Tier II", "20–30 minutes", 15, 35 },
			{ "Tier III", "about 1½ hours", 60, 120 },
			{ "Tier IV", "about 4 hours", 2.5 * 60, 5.5 * 60 },
			{ "Tier V", "about 9 hours", 6 * 60, 12 * 60 },
			{ "Tier VI", "about 18 hours", 12 * 60, 24 * 60 },
			{ "Tier VII", "about 30–35 hours", 22 * 60, 45 * 60 },
			{ "researched Tempest", "about 50–60 hours (the trials counted as flown)", 40 * 60, 75 * 60 },
		}
		for _, target in TARGETS do
			local name, text, low, high = target[1], target[2], target[3], target[4]
			it(`{name}: {text}`, function()
				local m = milestones[name]
				if not m then
					error("never reached in 80 hours", 0)
				end
				expect(m >= low and m <= high).toBe(true)
			end)
		end
	end)
end
