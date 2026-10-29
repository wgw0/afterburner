--!strict
-- Matchmaking telemetry (MMK-06).

return function(ctx)
	local describe, it, expect = ctx.describe, ctx.it, ctx.expect
	local MatchmakingStats = require(ctx.Shared.MatchmakingStats)

	describe("closeness", function()
		it("is 1 for a level finish, falling towards 0 for a walkover", function()
			expect(MatchmakingStats.closeness({ 10, 10 })).toBe(1)
			expect(MatchmakingStats.closeness({ 0, 0 })).toBe(1)
			expect(MatchmakingStats.closeness({ 1, 0 })).toBe(0.5)
			expect(MatchmakingStats.closeness({ 10, 0 })).toBeCloseTo(1 / 11, 1e-6)
		end)

		it("compares the top two, in any order", function()
			expect(MatchmakingStats.closeness({ 5, 10 })).toBeCloseTo(6 / 11, 1e-6)
			expect(MatchmakingStats.closeness({ 3, 8, 6, 1 })).toBeCloseTo(7 / 9, 1e-6)
			expect(MatchmakingStats.closeness({ 7 })).toBe(1 / 8)
		end)
	end)

	describe("waits", function()
		it("summarises count, median, 90th percentile and longest", function()
			local w = MatchmakingStats.waits({ 40, 10, 20, 30, 50, 60, 70, 80, 90, 100 })
			expect(w.count).toBe(10)
			expect(w.median).toBe(50)
			expect(w.p90).toBe(90)
			expect(w.max).toBe(100)
		end)

		it("is all zeros with nothing recorded", function()
			local w = MatchmakingStats.waits({})
			expect(w.count).toBe(0)
			expect(w.median).toBe(0)
			expect(w.max).toBe(0)
		end)
	end)

	describe("push", function()
		it("keeps the newest up to the limit", function()
			local list = {}
			for i = 1, 7 do
				MatchmakingStats.push(list, i, 5)
			end
			expect(#list).toBe(5)
			expect(list[1]).toBe(3)
			expect(list[5]).toBe(7)
		end)
	end)
end
