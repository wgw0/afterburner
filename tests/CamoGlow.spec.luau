--!strict
-- The Galaxy camo's breathing glow (Shared/CamoGlow).
return function(ctx)
	local describe, it, expect = ctx.describe, ctx.it, ctx.expect
	local CamoGlow = require(ctx.Shared.CamoGlow)

	describe("CamoGlow.at", function()
		it("breathes between the soft and bright ends over one period", function()
			local soft = CamoGlow.at(0, 0, false)
			local bright = CamoGlow.at(CamoGlow.PERIOD / 2, 0, false)
			expect(math.abs(soft - CamoGlow.LOW) < 1e-6).toBe(true)
			expect(math.abs(bright - CamoGlow.HIGH) < 1e-6).toBe(true)
			expect(math.abs(CamoGlow.at(CamoGlow.PERIOD, 0, false) - CamoGlow.LOW) < 1e-6).toBe(true)
		end)

		it("offsets each jet by its phase", function()
			local a = CamoGlow.at(0, 0, false)
			local b = CamoGlow.at(0, 0.5, false)
			expect(math.abs(a - b) > 0.1).toBe(true)
		end)

		it("holds still with Reduce Flashing on", function()
			expect(CamoGlow.at(0, 0, true)).toBe(CamoGlow.STEADY)
			expect(CamoGlow.at(CamoGlow.PERIOD / 2, 0.3, true)).toBe(CamoGlow.STEADY)
		end)

		it("drifts the tint from violet to pink", function()
			local _, start = CamoGlow.at(0, 0, false)
			local _, half = CamoGlow.at(CamoGlow.TINT_PERIOD / 2, 0, false)
			expect(start:ToHex()).toBe(CamoGlow.VIOLET:ToHex())
			expect(half:ToHex()).toBe(CamoGlow.PINK:ToHex())
		end)
	end)
end
