--!strict
-- The analytics funnels' step order (ANL-02, DEVELOPMENT.md §30.3).

return function(ctx)
	local describe, it, expect = ctx.describe, ctx.it, ctx.expect
	local Funnels = require(ctx.Shared.Funnels)

	describe("onboarding", function()
		it("logs each step once, in order", function()
			local reached = {}
			expect(#Funnels.reach(reached, "Joined")).toBe(1)
			expect(Funnels.reach(reached, "Joined")[1]).toBe(nil)
			expect(Funnels.reach(reached, "Onboarded")[1]).toBe(2)
			expect(Funnels.reach(reached, "FirstMatch")[1]).toBe(3)
		end)

		it("a step reached early waits for the ones before it", function()
			local reached = { Joined = true, Onboarded = true }
			expect(#Funnels.reach(reached, "FirstKill")).toBe(0) -- a kill before the first match is over
			local due = Funnels.reach(reached, "FirstMatch")
			expect(#due).toBe(2)
			expect(due[1]).toBe(3)
			expect(due[2]).toBe(4)
		end)

		it("ignores unknown and retired steps", function()
			local reached = { Joined = true }
			expect(#Funnels.reach(reached, "Lesson1")).toBe(0)
			expect(reached.Lesson1).toBe(nil)
		end)
	end)

	describe("training", function()
		it("starts with arriving, then the six lessons", function()
			expect(Funnels.TRAINING[1]).toBe("Arrived")
			expect(#Funnels.TRAINING).toBe(7)
		end)
	end)
end
