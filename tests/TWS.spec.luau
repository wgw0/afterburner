--!strict
-- Track-while-scan (SNS-07).

return function(ctx)
	local describe, it, expect = ctx.describe, ctx.it, ctx.expect
	local Signature = require(ctx.Shared.Signature)
	local AircraftData = require(ctx.Shared.AircraftData)

	describe("hasTWS", function()
		it("pulse-Doppler radars on Tier IV+ jets", function()
			local pd = { Range = 20000, Cone = 30, CanNotch = true }
			local pulse = { Range = 15000, Cone = 30, CanNotch = false }
			expect(Signature.hasTWS(4, pd)).toBe(true)
			expect(Signature.hasTWS(3, pd)).toBe(false)
			expect(Signature.hasTWS(6, pulse)).toBe(false)
			expect(Signature.hasTWS(6, nil)).toBe(false)
		end)

		it("a radar's CanTWS overrides the rule", function()
			expect(Signature.hasTWS(3, { Range = 1, Cone = 1, CanNotch = true, CanTWS = true })).toBe(true)
			expect(Signature.hasTWS(7, { Range = 1, Cone = 1, CanNotch = true, CanTWS = false })).toBe(false)
		end)

		it("every Tier IV+ jet that carries an active radar missile can fire it on TWS", function()
			local WeaponData = require(ctx.Shared.WeaponData)
			for id, airframe in AircraftData.getAll() do
				local a = airframe :: any
				local hasArh = false
				for _, slot in a.Missiles or {} do
					local spec = WeaponData.getMissile(slot.Weapon) :: any
					if spec and spec.Class == "ARH" then
						hasArh = true
					end
				end
				if hasArh and a.Tier >= 4 and not Signature.hasTWS(a.Tier, a.Radar) then
					error(`{id} carries an active radar missile but has no TWS`)
				end
			end
		end)
	end)
end
