--!strict
-- Quick check-ins: which moment is due.

return function(ctx)
	local describe, it, expect = ctx.describe, ctx.it, ctx.expect
	local Pulse = require(ctx.Shared.Pulse)
	local PlayerData = require(ctx.Shared.PlayerData)

	local function save(matches: number, sortie: boolean, done: { [string]: boolean }?): any
		return { Stats = { Matches = matches }, Lessons = { Sortie = sortie or nil }, Pulse = done or {} }
	end

	describe("due", function()
		it("nothing before any moment is reached", function()
			expect(Pulse.due(save(0, false))).toBe(nil)
		end)

		it("the latest moment reached, once", function()
			expect(Pulse.due(save(0, true))).toBe("Sortie")
			expect(Pulse.due(save(1, true, { Sortie = true }))).toBe("Match1")
			expect(Pulse.due(save(3, true, { Sortie = true, Match1 = true }))).toBe("Match3")
			expect(Pulse.due(save(9, true, { Sortie = true, Match1 = true, Match3 = true }))).toBe(nil)
		end)

		it("a pilot past several moments is asked once, about the latest", function()
			local data = save(40, true)
			expect(Pulse.due(data)).toBe("Match3")
			Pulse.answer(data, "Match3")
			expect(data.Pulse.Sortie and data.Pulse.Match1 and data.Pulse.Match3).toBe(true)
			expect(Pulse.due(data)).toBe(nil)
		end)

		it("a pilot who skipped the sortie is still asked after matches", function()
			expect(Pulse.due(save(1, false))).toBe("Match1")
		end)
	end)

	describe("save", function()
		it("answers reach the client, so it isn't asked again", function()
			expect(table.find(PlayerData.REPLICATED, "Pulse") ~= nil).toBe(true)
			expect(type(PlayerData.template().Pulse)).toBe("table")
		end)
	end)
end
