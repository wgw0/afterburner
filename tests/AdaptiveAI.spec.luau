--!strict
-- Vs AI bots that adapt to how the player is doing.

return function(ctx)
	local describe, it, expect = ctx.describe, ctx.it, ctx.expect
	local AdaptiveAI = require(ctx.Shared.AdaptiveAI)
	local AIBrain = require(ctx.Shared.AIBrain)

	describe("adaptive bots", function()
		it("an even match leaves the bots at the difficulty picked", function()
			expect(AdaptiveAI.offset(0, 0, 0)).toBe(0)
			expect(AdaptiveAI.offset(2, 2, 0)).toBe(0)
			local profile = AdaptiveAI.profile("Hard", 0)
			expect(profile.AimError).toBe(AIBrain.PROFILES.Hard.AimError)
			expect(profile.Name).toBe("Hard")
		end)

		it("being shot down eases them off; doing well sharpens them, more slowly", function()
			expect(AdaptiveAI.offset(0, 3, 0) < 0).toBe(true)
			expect(AdaptiveAI.offset(3, 0, 0) > 0).toBe(true)
			expect(math.abs(AdaptiveAI.offset(0, 3, 0)) > AdaptiveAI.offset(3, 0, 0)).toBe(true)
			-- assists count half a kill
			expect(AdaptiveAI.offset(0, 1, 2)).toBe(0)
		end)

		it("stays within its limits", function()
			expect(AdaptiveAI.offset(0, 50, 0)).toBe(-AdaptiveAI.EASIER)
			expect(AdaptiveAI.offset(50, 0, 0)).toBe(AdaptiveAI.HARDER)
		end)

		it("blends between levels, and goes below Easy for a struggling new pilot", function()
			local halfway = AdaptiveAI.profile("Hard", -0.5)
			local normal, hard = AIBrain.PROFILES.Normal, AIBrain.PROFILES.Hard
			expect(math.abs(halfway.ReactionTime - (normal.ReactionTime + hard.ReactionTime) / 2) < 1e-6).toBe(true)
			local floor = AdaptiveAI.profile("Easy", -AdaptiveAI.EASIER)
			expect(floor.AimError).toBe(AdaptiveAI.FLOOR.AimError)
			expect(floor.ReactionTime > AIBrain.PROFILES.Easy.ReactionTime).toBe(true)
			-- an Ace on a roll can't go beyond Ace
			expect(AdaptiveAI.profile("Ace", AdaptiveAI.HARDER).AimError).toBe(AIBrain.PROFILES.Ace.AimError)
		end)
	end)
end
