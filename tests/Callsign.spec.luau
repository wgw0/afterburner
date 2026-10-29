--!strict
-- CMP-01: custom callsign rules (Shared/Callsign). The Roblox filter itself runs on the server only.
return function(ctx)
	local describe, it, expect = ctx.describe, ctx.it, ctx.expect
	local Callsign = require(ctx.Shared.Callsign)
	local PlayerData = require(ctx.Shared.PlayerData)

	describe("Callsign.clean", function()
		it("trims and squeezes spaces", function()
			expect((Callsign.clean("  Iron   Eagle  "))).toBe("Iron Eagle")
		end)

		it("keeps letters, numbers, - and _", function()
			expect((Callsign.clean("Viper_07-B"))).toBe("Viper_07-B")
		end)

		it("refuses too short, too long, odd characters and no letters", function()
			local short, why = Callsign.clean("ab")
			expect(short).toBe(nil)
			expect(why ~= nil).toBe(true)
			expect((Callsign.clean(string.rep("a", Callsign.MAX + 1)))).toBe(nil)
			expect((Callsign.clean("Maverick!"))).toBe(nil)
			expect((Callsign.clean("[AI] Ghost"))).toBe(nil)
			expect((Callsign.clean("12345"))).toBe(nil)
		end)

		it("counts length after tidying", function()
			expect((Callsign.clean("   a b   "))).toBe("a b")
			expect((Callsign.clean(string.rep("a", Callsign.MAX) .. "    "))).toBe(string.rep("a", Callsign.MAX))
		end)
	end)

	describe("Callsign.accepted", function()
		it("only when the filter left it exactly as typed", function()
			expect(Callsign.accepted("Iron Eagle", "Iron Eagle")).toBe(true)
			expect(Callsign.accepted("Iron Eagle", "Iron #####")).toBe(false)
			expect(Callsign.accepted("Iron Eagle", nil)).toBe(false)
		end)
	end)

	describe("Callsign.nameOf", function()
		it("an AI pilot record shows its Name", function()
			expect(Callsign.nameOf({ Name = "Hawk [AI]", UserId = 0, IsAI = true })).toBe("Hawk [AI]")
			expect(Callsign.nameOf(nil)).toBe("?")
		end)
	end)

	describe("save data", function()
		it("a new save has no callsign, and the client can see its own", function()
			expect(PlayerData.template().Callsign).toBe("")
			expect(table.find(PlayerData.REPLICATED, "Callsign") ~= nil).toBe(true)
		end)
	end)
end
