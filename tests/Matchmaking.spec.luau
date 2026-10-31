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

		it("in the queue, the jet you clicked PLAY with sets your BR, not your lineup's best", function()
			local lineup = { "F5E", "F22A" }
			expect(Matchmaking.queueBR(lineup, "F5E")).toBe(br("F5E"))
			expect(Matchmaking.queueBR(lineup, "F22A")).toBe(br("F22A"))
			-- A jet that isn't in your lineup, or none, falls back to the lineup's best
			expect(Matchmaking.queueBR(lineup, "Tempest")).toBe(br("F22A"))
			expect(Matchmaking.queueBR(lineup, nil)).toBe(br("F22A"))
			-- ...and queueing in the F-5E keeps the F-22 out of that match
			expect(Matchmaking.allowed("F22A", Matchmaking.bandFor(br("F5E")))).toBe(false)
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

	describe("Vs AI", function()
		it("the bots fly jets at the level of the player's, above or below", function()
			for _, id in { "F5E", "F14A", "Su27S", "F22A", "Tempest" } do
				local jets = Matchmaking.vsAIAirframes(br(id))
				expect(#jets >= Matchmaking.VS_AI_MIN).toBe(true)
				expect(table.find(jets, id) ~= nil).toBe(true)
				local close = 0
				for _, other in jets do
					if math.abs(br(other) - br(id)) <= Matchmaking.VS_AI_SPREAD + 1e-6 then
						close += 1
					end
				end
				-- Only jets that close, unless there are too few: then just the closest few
				expect(close == #jets or #jets == Matchmaking.VS_AI_MIN).toBe(true)
			end
		end)

		it("a lone jet still gets the closest few, never the whole tree", function()
			local jets = Matchmaking.vsAIAirframes(br("Tempest"))
			local all = 0
			for _ in AircraftData.getAll() do
				all += 1
			end
			expect(#jets < all).toBe(true)
			for i = 2, #jets do
				expect(br(jets[i]) >= br(jets[i - 1])).toBe(true) -- sorted by BR
			end
		end)
	end)
end
