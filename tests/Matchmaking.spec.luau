--!strict
-- Battle rating matching inside one server (MMK-01).

return function(ctx)
	local describe, it, expect = ctx.describe, ctx.it, ctx.expect
	local AircraftData = require(ctx.Shared.AircraftData)
	local Matchmaking = require(ctx.Shared.Matchmaking)

	local function br(id: string): number
		return (AircraftData.get(id) :: any).BattleRating
	end

	describe("bands", function()
		it("a lineup's BR is its highest jet", function()
			expect(Matchmaking.lineupBR({ "F5E", "F4E" })).toBe(br("F4E"))
			expect(Matchmaking.lineupBR({})).toBe(nil)
		end)

		it("the match band runs from the top lineup BR down by the band width", function()
			local band = Matchmaking.band({ { "F5E" }, { "MiG23MLD", "F5E" } })
			expect(band.max).toBe(br("MiG23MLD"))
			expect(math.abs(band.min - (br("MiG23MLD") - Matchmaking.BAND_WIDTH)) < 1e-6).toBe(true)
		end)

		it("with nobody to measure, it's a starter-jet match", function()
			expect(Matchmaking.band({}).max).toBe(Matchmaking.DEFAULT_BR)
		end)
	end)

	describe("who may fly", function()
		it("jets above the band are refused; lower jets may still fly", function()
			local band = Matchmaking.band({ { "MirageF1" } }) -- BR 3.0
			expect(Matchmaking.allowed("F16A", band)).toBe(false)
			expect(Matchmaking.allowed("MirageF1", band)).toBe(true)
			expect(Matchmaking.allowed("F5E", band)).toBe(true)
			expect(Matchmaking.allowed("SR71", band)).toBe(false)
		end)

		it("AI pilots get jets inside the band", function()
			local band = Matchmaking.band({ { "F4E" } })
			local jets = Matchmaking.aiAirframes(band)
			expect(#jets > 0).toBe(true)
			for _, id in jets do
				expect(br(id) >= band.min - 1e-6 and br(id) <= band.max + 1e-6).toBe(true)
			end
		end)

		it("a band with no jets inside falls back to the closest one below", function()
			local jets = Matchmaking.aiAirframes({ br = 15, min = 14, max = 15 })
			expect(#jets).toBe(1)
			expect(br(jets[1]) < 14).toBe(true)
		end)
	end)
end
