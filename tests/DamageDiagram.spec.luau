--!strict
-- The pilot's damage diagram (DMG-05).

return function(ctx)
	local describe, it, expect = ctx.describe, ctx.it, ctx.expect
	local DamageModel = require(ctx.Shared.DamageModel)

	describe("condition", function()
		it("reads health as Ok, Damaged, Critical or Lost", function()
			expect(DamageModel.condition(1)).toBe("Ok")
			expect(DamageModel.condition(0.75)).toBe("Ok")
			expect(DamageModel.condition(0.6)).toBe("Damaged")
			expect(DamageModel.condition(0.39)).toBe("Critical")
			expect(DamageModel.condition(0.01)).toBe("Critical")
			expect(DamageModel.condition(0)).toBe("Lost")
		end)
	end)
end
