--!strict
-- Daily login rewards (LIV-03).

return function(ctx)
	local describe, it, expect = ctx.describe, ctx.it, ctx.expect
	local Streak = require(ctx.Shared.Streak)

	local DAY = 20000

	describe("claiming", function()
		it("the first claim is day 1, once a day", function()
			local state = Streak.newState()
			local reward, count = Streak.claim(state, DAY)
			expect(count).toBe(1)
			expect((reward :: any).credits).toBe(Streak.WEEK[1].credits)
			expect((Streak.claim(state, DAY))).toBe(nil)
			expect(Streak.canClaim(state, DAY)).toBe(false)
			expect(Streak.canClaim(state, DAY + 1)).toBe(true)
		end)

		it("consecutive days count up through the week and round again", function()
			local state = Streak.newState()
			for i = 1, 9 do
				local _, count = Streak.claim(state, DAY + i)
				expect(count).toBe(i)
			end
			expect(Streak.weekDay(7)).toBe(7)
			expect(Streak.weekDay(8)).toBe(1)
			expect(Streak.weekDay(14)).toBe(7)
		end)
	end)

	describe("missed days", function()
		it("one missed day is forgiven", function()
			local state = { Day = DAY, Count = 4, Best = 4 }
			local _, count = Streak.claim(state, DAY + 2)
			expect(count).toBe(5)
		end)

		it("a longer break goes back to the start of the week, never to day 1", function()
			expect(Streak.nextCount({ Day = DAY, Count = 5, Best = 5 }, DAY + 3)).toBe(1)
			expect(Streak.nextCount({ Day = DAY, Count = 12, Best = 12 }, DAY + 10)).toBe(8)
			expect(Streak.nextCount({ Day = DAY, Count = 23, Best = 23 }, DAY + 40)).toBe(22)
			expect(Streak.nextCount({ Day = DAY, Count = 7, Best = 7 }, DAY + 5)).toBe(1)
		end)
	end)

	describe("milestones", function()
		it("day 7 unlocks Regular, day 30 Devoted with a bonus, once each", function()
			local seven = Streak.reward(7, 6)
			expect(seven.title).toBe("Regular")
			expect(seven.credits).toBe(Streak.WEEK[7].credits)
			expect(seven.freeRP).toBe(Streak.WEEK[7].freeRP)
			local thirty = Streak.reward(30, 29)
			expect(thirty.title).toBe("Devoted")
			expect(thirty.credits).toBe(Streak.WEEK[Streak.weekDay(30)].credits + 5000)
			-- Reaching day 7 again after dropping back pays the week, not the milestone
			expect(Streak.reward(7, 12).title).toBe(nil)
		end)
	end)
end
