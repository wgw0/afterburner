--!strict
-- Gunsights by tier (GUN-07).

return function(ctx)
	local describe, it, expect = ctx.describe, ctx.it, ctx.expect
	local Ballistics = require(ctx.Shared.Ballistics)
	local Units = require(ctx.Shared.Units)
	local WeaponData = require(ctx.Shared.WeaponData)

	local gun = WeaponData.get("M61A1") :: any

	describe("sightFor", function()
		it("Simple for Tier I–II, LCOS for III–IV, EEGS from V", function()
			expect(Ballistics.sightFor(1)).toBe("Simple")
			expect(Ballistics.sightFor(2)).toBe("Simple")
			expect(Ballistics.sightFor(3)).toBe("LCOS")
			expect(Ballistics.sightFor(4)).toBe("LCOS")
			expect(Ballistics.sightFor(5)).toBe("EEGS")
			expect(Ballistics.sightFor(8)).toBe("EEGS")
		end)
	end)

	describe("LCOS", function()
		it("leading a turning target's curve misses by less than leading its speed alone", function()
			-- Target 600 m ahead, crossing at 200 m/s while pulling 6 G
			local shooter = Vector3.zero
			local target = Vector3.new(0, 0, -Units.toStuds(600))
			local velocity = Vector3.new(200, 0, 0)
			local accel = Vector3.new(0, 0, 6 * 9.81) -- turning away
			local function miss(useAccel: boolean): number
				local dir, t = Ballistics.leadDirection(
					shooter,
					Vector3.zero,
					target,
					velocity,
					gun.MuzzleVelocity,
					gun.Lifetime,
					if useAccel then accel else nil
				)
				assert(dir and t, "no lead solution")
				-- Where the target really is at t, against where a round fired along dir is (no drag)
				local real = Units.velocityFromStuds(target) + velocity * t + accel * (0.5 * t * t)
				local round = dir * gun.MuzzleVelocity * t + Vector3.new(0, -0.5 * 9.81 * t * t, 0)
				return (real - round).Magnitude
			end
			local plain, lcos = miss(false), miss(true)
			expect(lcos < plain).toBe(true)
			expect(lcos < 3).toBe(true)
		end)
	end)

	describe("EEGS stream", function()
		it("a round's position after t: carried forward and dropping under gravity", function()
			local muzzle = CFrame.new(0, Units.toStuds(3000), 0)
			local p = Ballistics.positionAfter(muzzle, Vector3.zero, gun, 1)
			local travelled = Units.toMetres(-(p.Z - muzzle.Position.Z))
			local dropped = Units.toMetres(muzzle.Position.Y - p.Y)
			expect(travelled > gun.MuzzleVelocity * 0.6 and travelled <= gun.MuzzleVelocity).toBe(true)
			expect(dropped > 3 and dropped < 6).toBe(true)
		end)
	end)
end
