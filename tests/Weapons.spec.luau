--!strict
-- Weapon data, ballistics and lag-compensation history.
return function(ctx)
	local describe, it, expect = ctx.describe, ctx.it, ctx.expect
	local WeaponData = require(ctx.Shared.WeaponData)
	local AircraftData = require(ctx.Shared.AircraftData)
	local Ballistics = require(ctx.Shared.Ballistics)
	local PoseHistory = require(ctx.Shared.PoseHistory)
	local Units = require(ctx.Shared.Units)

	describe("WeaponData", function()
		it("every airframe's gun exists", function()
			for id, airframe in AircraftData.getAll() do
				if WeaponData.get(airframe.Gun) == nil then
					error(`{id} references unknown gun {airframe.Gun}`, 0)
				end
			end
		end)
		it("rejects a bad weapon with named problems", function()
			local bad = table.clone(WeaponData.get("GSh23L") :: any)
			bad.RateOfFire = 99999
			bad.Ammo = nil
			local problems = WeaponData.validate("GSh23L", bad)
			expect(#problems).toBe(2)
		end)
	end)

	describe("Ballistics", function()
		local gun = WeaponData.get("M39A2_Twin") :: any

		it("spread is deterministic for a seed and stays inside the cone", function()
			local muzzle = CFrame.new(0, 100, 0)
			local a = Ballistics.shotDirection(muzzle, gun, 1234, 7)
			local b = Ballistics.shotDirection(muzzle, gun, 1234, 7)
			expect(a == b).toBe(true)
			for i = 1, 200 do
				local d = Ballistics.shotDirection(muzzle, gun, 99, i)
				local angle = math.deg(math.acos(math.clamp(d:Dot(muzzle.LookVector), -1, 1)))
				expect(angle <= gun.Spread + 1e-6).toBe(true)
			end
		end)

		it("rounds inherit the shooter's velocity", function()
			local round = Ballistics.fire(CFrame.new(), Vector3.new(0, 0, -200), gun, 1, 0)
			local forward = -round.velocity.Z
			expect(forward > gun.MuzzleVelocity + 150).toBe(true)
		end)

		it("rounds drop under gravity and slow with drag", function()
			local round = Ballistics.fire(
				CFrame.new(0, 1000, 0),
				Vector3.zero,
				{ Spread = 0, MuzzleVelocity = 1000, RateOfFire = 1000, Drag = gun.Drag, Lifetime = 2 },
				1,
				0
			)
			local r = round
			for _ = 1, 60 do
				r = Ballistics.step(r, 1 / 60, gun.Drag)
			end
			expect(r.position.Y).toBeLessThan(1000)
			expect(r.velocity.Magnitude).toBeLessThan(1000)
			expect(r.age).toBeCloseTo(1, 1e-9)
		end)

		it("the lead solution hits a crossing target", function()
			-- Target 600 m ahead crossing left-to-right at 200 m/s; shooter flying 220 m/s forward.
			local shooterPos = Vector3.new(0, Units.toStuds(3000), 0)
			local shooterVel = Vector3.new(0, 0, -220)
			local targetPos = shooterPos + Units.toStuds(1) * Vector3.new(-150, 0, -600)
			local targetVel = Vector3.new(200, 0, -220)
			local spec = { Spread = 0, MuzzleVelocity = gun.MuzzleVelocity, RateOfFire = 1000, Drag = 0, Lifetime = 3 }
			local dir, tof = Ballistics.leadDirection(
				shooterPos,
				shooterVel,
				targetPos,
				targetVel,
				spec.MuzzleVelocity,
				spec.Lifetime
			)
			expect(dir ~= nil and tof ~= nil).toBe(true)
			local round =
				Ballistics.fire(CFrame.lookAt(shooterPos, shooterPos + (dir :: Vector3)), shooterVel, spec, 1, 0)
			local target = targetPos
			local closest = math.huge
			for _ = 1, 180 do
				round = Ballistics.step(round, 1 / 120, 0)
				target += Units.velocityToStuds(targetVel) / 120
				closest = math.min(closest, Units.toMetres((round.position - target).Magnitude))
			end
			expect(closest).toBeLessThan(3) -- metres
		end)

		it("no lead solution beyond the round's lifetime", function()
			local dir = Ballistics.leadDirection(
				Vector3.zero,
				Vector3.zero,
				Units.toStuds(1) * Vector3.new(0, 0, -5000),
				Vector3.zero,
				1000,
				2
			)
			expect(dir).toBe(nil)
		end)

		it("segment vs box: hits, misses, and finds the entry point", function()
			local box = CFrame.new(0, 0, -10) * CFrame.Angles(0, math.rad(30), 0)
			local size = Vector3.new(4, 4, 4)
			local t = Ballistics.segmentBox(Vector3.new(0, 0, 0), Vector3.new(0, 0, -20), box, size)
			expect(t ~= nil).toBe(true)
			expect((t :: number) > 0.35 and (t :: number) < 0.45).toBe(true)
			expect(Ballistics.segmentBox(Vector3.new(10, 0, 0), Vector3.new(10, 0, -20), box, size)).toBe(nil)
			expect(Ballistics.segmentBox(Vector3.new(0, 0, 0), Vector3.new(0, 0, -5), box, size)).toBe(nil) -- stops short
			expect(Ballistics.segmentBox(Vector3.new(0, 0, -10), Vector3.new(0, 0, -11), box, size)).toBe(0) -- starts inside
		end)
	end)

	describe("PoseHistory", function()
		it("interpolates between recorded poses and clamps at the ends", function()
			local h = PoseHistory.new(10)
			h:record(1, CFrame.new(0, 0, 0))
			h:record(2, CFrame.new(10, 0, 0))
			expect((h:sample(1.5) :: CFrame).Position).toBeCloseTo(Vector3.new(5, 0, 0), 1e-6)
			expect((h:sample(0) :: CFrame).Position).toBeCloseTo(Vector3.new(0, 0, 0), 1e-6)
			expect((h:sample(9) :: CFrame).Position).toBeCloseTo(Vector3.new(10, 0, 0), 1e-6)
		end)
		it("is empty until something is recorded", function()
			expect(PoseHistory.new():sample(1)).toBe(nil)
		end)
	end)
end
