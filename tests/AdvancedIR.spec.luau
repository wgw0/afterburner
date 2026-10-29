--!strict
-- MSL-09: helmet cueing and imaging-seeker flare rules for the advanced heat-seekers (IR_Adv).
return function(ctx)
	local describe, it, expect = ctx.describe, ctx.it, ctx.expect
	local Countermeasures = require(ctx.Shared.Countermeasures)
	local Guidance = require(ctx.Shared.Guidance)
	local Units = require(ctx.Shared.Units)
	local WeaponData = require(ctx.Shared.WeaponData)

	local AIM9X = WeaponData.getMissile("AIM9X") :: any
	local AIM9M = WeaponData.getMissile("AIM9M") :: any
	local shooter = CFrame.new(0, Units.toStuds(3000), 0)

	-- A target `angle` degrees off the shooter's nose at `metres`, flying away (hot tail towards us).
	local function targetAt(angle: number, metres: number): CFrame
		local dir = (shooter * CFrame.Angles(0, math.rad(angle), 0)).LookVector
		local position = shooter.Position + dir * Units.toStuds(metres)
		return CFrame.lookAt(position, position + dir)
	end

	describe("helmet cueing", function()
		it("only the IR_Adv missiles are imaging, helmet-cued seekers", function()
			for _, id in { "AIM9X", "R74M", "IRIST", "ASRAAM", "MICAIR" } do
				expect(Guidance.isImaging(WeaponData.getMissile(id) :: any)).toBe(true)
			end
			expect(Guidance.isImaging(AIM9M)).toBe(false)
		end)

		it("an AIM-9X can be cued onto a jet 70 degrees off the nose that its seeker cone can't see", function()
			local target = targetAt(70, 1500)
			expect(Guidance.irLockable(AIM9X, shooter, target, 1, false)).toBe(false)
			expect(Guidance.irCueLockable(AIM9X, shooter, target, 1, false)).toBe(true)
		end)

		it("not outside the missile's gimbal, and never for older missiles", function()
			expect(Guidance.irCueLockable(AIM9X, shooter, targetAt(100, 1500), 1, false)).toBe(false)
			expect(Guidance.irCueLockable(AIM9M, shooter, targetAt(20, 1500), 1, false)).toBe(false)
		end)

		it("not beyond the missile's reach", function()
			expect(Guidance.irCueLockable(AIM9X, shooter, targetAt(60, 20000), 1, false)).toBe(false)
		end)
	end)

	describe("imaging seekers and flares", function()
		it("a burst works far better against a beaming target than a straight one", function()
			local straight = Countermeasures.burstDecoyChance(AIM9X.FlareResistance, 0)
			local beam = Countermeasures.burstDecoyChance(AIM9X.FlareResistance, 1)
			expect(straight < 0.05).toBe(true)
			expect(beam > straight * 5).toBe(true)
		end)

		it("a single flare never gets a roll; the third in a second does", function()
			local seeker = Guidance.newIRSeeker(1, 1)
			local missile = Guidance.launch(Vector3.zero, Vector3.new(0, 0, -260))
			local function sources(flares: number)
				local list = {
					{ id = 1, position = Vector3.new(0, 0, -400), velocity = Vector3.new(200, 0, 0), heat = 1 },
				}
				for i = 1, flares do
					table.insert(list, {
						id = `flare:{i}`,
						position = Vector3.new(0, -1, -399),
						velocity = Vector3.zero,
						heat = Countermeasures.FLARE_HEAT,
					})
				end
				return list
			end
			Guidance.updateIRSeeker(seeker, missile, AIM9X, sources(1))
			expect(seeker.bursts).toBe(0)
			Guidance.updateIRSeeker(seeker, missile, AIM9X, sources(3))
			expect(seeker.bursts).toBe(1)
		end)
	end)
end
