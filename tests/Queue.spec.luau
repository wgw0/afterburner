--!strict
-- Forming matches from the matchmaking queue (MMK-03).

return function(ctx)
	local describe, it, expect = ctx.describe, ctx.it, ctx.expect
	local Queue = require(ctx.Shared.Queue)

	local function entry(userId: number, br: number, mode: string?, joinedAt: number?): any
		return { userId = userId, br = br, mode = mode or "Any", joinedAt = joinedAt or 0, jobId = "lobby" }
	end

	local function ids(match: any): { number }
		local list = {}
		for _, e in match.entries do
			table.insert(list, e.userId)
		end
		table.sort(list)
		return list
	end

	describe("when a match forms", function()
		it("a full group forms at once", function()
			local entries = {}
			for i = 1, Queue.MATCH_SIZE do
				table.insert(entries, entry(i, 4.7))
			end
			local matches = Queue.form(entries, { now = 1 })
			expect(#matches).toBe(1)
			expect(#matches[1].entries).toBe(Queue.MATCH_SIZE)
		end)

		it("a short group waits, then forms after the fill time", function()
			local entries = { entry(1, 4.7, "Any", 0), entry(2, 5.0, "Any", 5) }
			expect(#Queue.form(entries, { now = Queue.FILL_AFTER - 1 })).toBe(0)
			local matches = Queue.form(entries, { now = Queue.FILL_AFTER })
			expect(#matches).toBe(1)
			expect(#matches[1].entries).toBe(2)
		end)

		it("a lone player gets a match (with AI) after the fill time", function()
			local matches = Queue.form({ entry(1, 2.0) }, { now = Queue.FILL_AFTER, fillAfter = Queue.FILL_AFTER })
			expect(#matches).toBe(1)
			expect(#matches[1].entries).toBe(1)
		end)

		it("never puts more than MATCH_SIZE players in a match", function()
			local entries = {}
			for i = 1, Queue.MATCH_SIZE * 2 + 1 do
				table.insert(entries, entry(i, 4.7, "Any", i * 0.01))
			end
			local matches = Queue.form(entries, { now = 1 })
			expect(#matches).toBe(2)
			for _, match in matches do
				expect(#match.entries).toBe(Queue.MATCH_SIZE)
			end
		end)

		it("the longest-waiting players go first", function()
			local entries = {}
			for i = 1, Queue.MATCH_SIZE + 1 do
				table.insert(entries, entry(i, 4.7, "Any", 100 - i)) -- higher ids joined earlier
			end
			local matches = Queue.form(entries, { now = 101 })
			expect(#matches).toBe(1)
			expect(table.find(ids(matches[1]), 1)).toBe(nil) -- the newest waits
		end)
	end)

	describe("battle rating", function()
		it("keeps far-apart BRs out of one match", function()
			local entries = { entry(1, 2.0, "Any", 0), entry(2, 9.0, "Any", 0) }
			local matches = Queue.form(entries, { now = Queue.FILL_AFTER })
			expect(#matches).toBe(2)
		end)

		it("the spread widens from 1.0 to 1.7 over a minute, then on to 3.0", function()
			expect(Queue.spreadFor(0)).toBe(1.0)
			expect(math.abs(Queue.spreadFor(60) - 1.7) < 1e-6).toBe(true)
			expect(math.abs(Queue.spreadFor(105) - 2.35) < 1e-6).toBe(true)
			expect(math.abs(Queue.spreadFor(150) - 3.0) < 1e-6).toBe(true)
			expect(math.abs(Queue.spreadFor(600) - 3.0) < 1e-6).toBe(true)
			local far = { entry(1, 2.0, "Any", 0), entry(2, 4.5, "Any", 0) }
			expect(#Queue.form(far, { now = 60 })).toBe(2)
			expect(#Queue.form(far, { now = 150 })).toBe(1)
			-- 1.5 apart: separate early, together after a minute
			local entries = { entry(1, 4.0, "Any", 0), entry(2, 5.5, "Any", 0) }
			local early = Queue.form(entries, { now = Queue.FILL_AFTER })
			expect(#early).toBe(2)
			local late = Queue.form(entries, { now = 60 })
			expect(#late).toBe(1)
		end)

		it("the whole group stays within the spread, not just each player against the anchor", function()
			-- 4.0 and 6.0 are each 1.0 from 5.0 but 2.0 from each other
			local entries = { entry(1, 5.0, "Any", 0), entry(2, 4.0, "Any", 1), entry(3, 6.0, "Any", 2) }
			local matches = Queue.form(entries, { now = 10, fillAfter = 5 })
			for _, match in matches do
				expect(match.spread <= Queue.spreadFor(10) + 1e-6).toBe(true)
			end
		end)

		it("the band tops out at the highest BR in the match", function()
			local matches = Queue.form({ entry(1, 4.7), entry(2, 5.0) }, { now = Queue.FILL_AFTER })
			expect(matches[1].band.max).toBe(5.0)
		end)
	end)

	describe("modes", function()
		it("players who picked different modes don't share a match", function()
			local entries = { entry(1, 4.7, "Dogfight", 0), entry(2, 4.7, "TeamDeathmatch", 0) }
			local matches = Queue.form(entries, { now = Queue.FILL_AFTER })
			expect(#matches).toBe(2)
			expect(matches[1].mode ~= matches[2].mode).toBe(true)
		end)

		it("Any joins a match of any mode", function()
			local entries = { entry(1, 4.7, "AirSuperiority", 0), entry(2, 4.7, "Any", 1) }
			local matches = Queue.form(entries, { now = Queue.FILL_AFTER })
			expect(#matches).toBe(1)
			expect(matches[1].mode).toBe("AirSuperiority")
		end)

		it("an Any anchor plays what most of its group asked for", function()
			local entries = {
				entry(1, 4.7, "Any", 0),
				entry(2, 4.7, "TeamDeathmatch", 1),
				entry(3, 4.7, "TeamDeathmatch", 2),
				entry(4, 4.7, "Dogfight", 3),
			}
			local matches = Queue.form(entries, { now = Queue.FILL_AFTER })
			expect(matches[1].mode).toBe("TeamDeathmatch")
			expect(table.find(ids(matches[1]), 4)).toBe(nil)
		end)

		it("an all-Any group plays the picked mode", function()
			local matches = Queue.form({ entry(1, 4.7), entry(2, 4.7) }, {
				now = Queue.FILL_AFTER,
				pickMode = function()
					return "AirSuperiority"
				end,
			})
			expect(matches[1].mode).toBe("AirSuperiority")
		end)

		it("after a long wait, a player who picked a mode takes any mode", function()
			local entries = { entry(1, 4.7, "Dogfight", 0), entry(2, 4.7, "TeamDeathmatch", 1) }
			expect(#Queue.form(entries, { now = Queue.ANY_MODE_AFTER - 5 })).toBe(2)
			local matches = Queue.form(entries, { now = Queue.ANY_MODE_AFTER + 2 })
			expect(#matches).toBe(1)
			expect(matches[1].entries[1].mode).toBe("Dogfight") -- the entries handed back are the originals
		end)

		it("only known modes are valid", function()
			expect(Queue.validMode("Any")).toBe(true)
			expect(Queue.validMode("Dogfight")).toBe(true)
			expect(Queue.validMode("GunsOnly")).toBe(true)
			expect(Queue.validMode("FreeFlight")).toBe(false)
			expect(Queue.validMode("Stress")).toBe(false)
		end)
	end)
	describe("duels (MCH-09)", function()
		local Duel = require(ctx.Shared.Duel)
		local function duelist(userId: number, rating: number, mode: string?, joinedAt: number?): any
			local e = entry(userId, 3, mode or "Duel", joinedAt)
			e.rating = rating
			return e
		end

		it("two duellists make a two-seat match at once", function()
			local matches = Queue.form(
				{ duelist(1, 1000), duelist(2, 1050), duelist(3, 1000, "Dogfight") },
				{ now = 1 }
			)
			expect(#matches).toBe(1)
			expect(matches[1].mode).toBe("Duel")
			expect(matches[1].players).toBe(2)
			expect(Queue.sizeFor("Duel")).toBe(2)
		end)

		it("ranked duels pair close ratings, loosening with the wait", function()
			expect(#Queue.form({ duelist(1, 1000), duelist(2, 1500) }, { now = 1 })).toBe(0)
			local matches = Queue.form({ duelist(1, 1000), duelist(2, 1500) }, { now = 44, duelFillAfter = 999 })
			expect(#matches).toBe(1) -- the spread reached 500+ by then
		end)

		it("casual duels ignore ratings", function()
			expect(#Queue.form({ duelist(1, 800, "DuelCasual"), duelist(2, 2000, "DuelCasual") }, { now = 1 })).toBe(1)
		end)

		it("a lone duellist gets an AI opponent after AI_AFTER seconds", function()
			expect(#Queue.form({ duelist(1, 1000) }, { now = Duel.AI_AFTER - 1 })).toBe(0)
			local matches = Queue.form({ duelist(1, 1000) }, { now = Duel.AI_AFTER })
			expect(#matches).toBe(1)
			expect(matches[1].players).toBe(1)
		end)

		it("Any never becomes a duel, and a duellist never takes another mode", function()
			local matches = Queue.form({ duelist(1, 1000, "Duel", 0), entry(2, 3, "Any", 0) }, { now = 500 })
			for _, match in matches do
				for _, e in match.entries do
					expect((e.userId == 1) == (match.mode == "Duel")).toBe(true)
				end
			end
		end)

		it("parties can't duel", function()
			local party = duelist(1, 1000)
			party.members = { 1, 4 }
			expect(#Queue.form({ party, duelist(2, 1000) }, { now = 1 })).toBe(0)
		end)
	end)
end
