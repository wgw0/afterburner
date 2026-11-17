--!strict
-- New pilots' journeys: who's tracked and which stages count.

return function(ctx)
	local describe, it, expect = ctx.describe, ctx.it, ctx.expect
	local Journey = require(ctx.Shared.Journey)

	describe("newcomer", function()
		it("pilots with fewer than 3 finished matches", function()
			expect(Journey.newcomer({ Stats = { Matches = 0 } })).toBe(true)
			expect(Journey.newcomer({ Stats = { Matches = 2 } })).toBe(true)
			expect(Journey.newcomer({ Stats = { Matches = 3 } })).toBe(false)
			expect(Journey.newcomer(nil)).toBe(false)
		end)
	end)

	describe("advance", function()
		it("stages only go forward", function()
			expect(Journey.advance("Training", 0, "Arrived")).toBe(1)
			expect(Journey.advance("Training", 1, "InJet")).toBe(3)
			expect(Journey.advance("Training", 3, "InJet")).toBe(nil)
			expect(Journey.advance("Training", 5, "HitEnemy")).toBe(nil)
		end)

		it("ignores stages that aren't on that server", function()
			expect(Journey.advance("Lobby", 0, "Won")).toBe(nil)
			expect(Journey.advance("Training", 0, "Queued")).toBe(nil)
			expect(Journey.advance("Pending", 0, "Arrived")).toBe(nil)
		end)

		it("names the furthest stage", function()
			expect(Journey.name("Training", 6)).toBe("Won")
			expect(Journey.name("Match", 0)).toBe("None")
		end)
	end)
end
