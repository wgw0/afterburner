--!strict
-- HUD-05: HUD symbology by cockpit era (Config/HUDStyles).
return function(ctx)
	local describe, it, expect = ctx.describe, ctx.it, ctx.expect
	local AircraftData = require(ctx.Shared.AircraftData)
	local HUDStyles = require(ctx.Shared.Config.HUDStyles)

	describe("HUD styles", function()
		it("every jet's Era has its own style", function()
			for _, airframe in AircraftData.getAll() do
				local era = (airframe :: any).Era
				expect(HUDStyles.STYLES[era] ~= nil).toBe(true)
			end
		end)

		it("analogue jets get a simple sight: no tapes, flight path marker or ladder numbers", function()
			local style = HUDStyles.forEra("Analogue")
			expect(style.tapes).toBe(false)
			expect(style.headingTape).toBe(false)
			expect(style.flightPath).toBe(false)
			expect(style.ladderNumbers).toBe(false)
		end)

		it("glass jets add more as the eras go on; only the wide-area display is on the helmet", function()
			local early, full, wad =
				HUDStyles.forEra("EarlyGlass"), HUDStyles.forEra("FullGlass"), HUDStyles.forEra("WAD")
			expect(early.tapes and early.flightPath).toBe(true)
			expect(early.bankScale).toBe(false)
			expect(full.bankScale and full.speedTrend).toBe(true)
			expect(full.helmet).toBe(false)
			expect(wad.helmet).toBe(true)
		end)

		it("an unknown era falls back to EarlyGlass", function()
			expect(HUDStyles.forEra(nil)).toBe(HUDStyles.forEra("EarlyGlass"))
			expect(HUDStyles.forEra("Steam")).toBe(HUDStyles.forEra("EarlyGlass"))
		end)
	end)
end
