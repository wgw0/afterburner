--!strict
-- Matches in progress a lobby can list and join, and when "Any mode" is recommended.

return function(ctx)
	local describe, it, expect = ctx.describe, ctx.it, ctx.expect
	local LiveMatches = require(ctx.Shared.LiveMatches)

	local function entry(fields: { [string]: any }): any
		local e = {
			id = "a",
			mode = "Dogfight",
			state = "InProgress",
			humans = 2,
			seats = 6,
			timeLeft = 300,
			at = 1000,
		}
		for k, v in fields do
			e[k] = v
		end
		return e
	end

	describe("joinable", function()
		it("a match in progress with a free seat and time left", function()
			expect(LiveMatches.joinable(entry({}), 1005)).toBe(true)
			expect(LiveMatches.joinable(entry({ state = "Countdown", timeLeft = 5 }), 1005)).toBe(true)
		end)

		it("not full, ending, over, stale or a duel", function()
			expect(LiveMatches.joinable(entry({ humans = 6 }), 1005)).toBe(false)
			expect(LiveMatches.joinable(entry({ timeLeft = LiveMatches.MIN_TIME_LEFT - 1 }), 1005)).toBe(false)
			expect(LiveMatches.joinable(entry({ state = "Results" }), 1005)).toBe(false)
			expect(LiveMatches.joinable(entry({}), 1000 + LiveMatches.STALE_AFTER + 1)).toBe(false)
			expect(LiveMatches.joinable(entry({ mode = "Duel", seats = 2, humans = 1 }), 1005)).toBe(false)
		end)
	end)

	describe("list", function()
		it("the joinable ones, most players first, then most time left", function()
			local list = LiveMatches.list({
				entry({ id = "few", humans = 1, timeLeft = 500 }),
				entry({ id = "full", humans = 6 }),
				entry({ id = "busy", humans = 4, timeLeft = 200 }),
				entry({ id = "busy2", humans = 4, timeLeft = 400 }),
			}, 1005)
			expect(#list).toBe(3)
			expect(list[1].id).toBe("busy2")
			expect(list[2].id).toBe("busy")
			expect(list[3].id).toBe("few")
		end)
	end)

	describe("online and Any mode", function()
		it("counts pilots in fresh matches, the queue and the lobby", function()
			local online = LiveMatches.online({ entry({ humans = 3 }), entry({ humans = 5, at = 0 }) }, 2, 4, 1005)
			expect(online).toBe(9)
		end)

		it("recommends Any while few pilots are online", function()
			expect(LiveMatches.recommendAny(LiveMatches.LOW_POPULATION - 1)).toBe(true)
			expect(LiveMatches.recommendAny(LiveMatches.LOW_POPULATION)).toBe(false)
		end)
	end)
end
