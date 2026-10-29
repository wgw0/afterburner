--!strict
-- Missile loft (MSL-08).

return function(ctx)
	local describe, it, expect = ctx.describe, ctx.it, ctx.expect
	local Guidance = require(ctx.Shared.Guidance)
	local WeaponData = require(ctx.Shared.WeaponData)
	local Units = require(ctx.Shared.Units)

	-- A tail chase: the target flies straight away at 250 m/s; the missile launches `range` behind it.
	local function chase(id: string, range: number, altitude: number, loft: boolean): (boolean, number)
		local spec = WeaponData.getMissile(id) :: any
		local targetPos = Vector3.new(0, Units.toStuds(altitude), 0)
		local targetVel = Vector3.new(0, 0, -250)
		local missile = Guidance.launch(targetPos + Vector3.new(0, 0, Units.toStuds(range)), Vector3.new(0, 0, -280))
		local loftRange = if loft and Guidance.lofts(spec, range) then range else nil
		local peak = altitude
		local dt = 1 / 30
		for _ = 1, 30 * 90 do
			local nextTarget = targetPos + Units.velocityToStuds(targetVel) * dt
			local aim = if loftRange then Guidance.loftAim(missile, targetPos, loftRange) else nil
			local nextMissile = Guidance.step(missile, spec, dt, targetPos, targetVel, aim)
			local miss = Guidance.closestApproach(missile.position, nextMissile.position, targetPos, nextTarget)
			peak = math.max(peak, Units.altitudeMetres(nextMissile.position.Y))
			missile, targetPos = nextMissile, nextTarget
			if miss <= spec.ProximityFuse then
				return true, peak
			end
			if missile.age > spec.MotorBurnTime and missile.velocity.Magnitude < spec.MinSpeed * 0.6 then
				break
			end
		end
		return false, peak
	end

	describe("loft", function()
		it("long shots with a lofting missile climb, short ones don't", function()
			local amraam = WeaponData.getMissile("AIM120C") :: any
			expect(Guidance.lofts(amraam, 15000)).toBe(true)
			expect(Guidance.lofts(amraam, 5000)).toBe(false)
			expect(Guidance.lofts(WeaponData.getMissile("AIM7F") :: any, 15000)).toBe(false)
		end)

		it("aims above the target early on, and at it near the end", function()
			local target = Vector3.new(0, Units.toStuds(5000), 0)
			local far = Guidance.launch(target + Vector3.new(0, 0, Units.toStuds(20000)), Vector3.zero)
			local near = Guidance.launch(target + Vector3.new(0, 0, Units.toStuds(6000)), Vector3.zero)
			local high = Units.toMetres(Guidance.loftAim(far, target, 20000).Y - target.Y)
			expect(high).toBeCloseTo(Guidance.LOFT_MAX_HEIGHT, 1)
			expect(Guidance.loftAim(near, target, 20000)).toBe(target)
		end)

		it("reaches a fleeing target that a straight shot falls short of", function()
			local straight = chase("R77", 15000, 6000, false)
			local lofted, peak = chase("R77", 15000, 6000, true)
			expect(straight).toBe(false)
			expect(lofted).toBe(true)
			expect(peak > 7000).toBe(true)
		end)

		it("still hits at shorter ranges", function()
			expect((chase("AIM120C", 9000, 1000, true))).toBe(true)
			expect((chase("AIM120C", 17000, 6000, true))).toBe(true)
		end)

		it("is only allowed on radar missiles", function()
			local aim9 = table.clone(WeaponData.getMissile("AIM9M") :: any)
			aim9.Loft = true
			expect(#WeaponData.validate("AIM9M", aim9) > 0).toBe(true)
		end)
	end)
end
