--!strict
-- Missile data, packing, signatures and guidance (ACD-05, NET-03, SNS-04/06, MSL-01).
return function(ctx)
	local describe, it, expect = ctx.describe, ctx.it, ctx.expect
	local AircraftData = require(ctx.Shared.AircraftData)
	local WeaponData = require(ctx.Shared.WeaponData)
	local Pack = require(ctx.Shared.Net.Pack)
	local Signature = require(ctx.Shared.Signature)
	local Guidance = require(ctx.Shared.Guidance)
	local Units = require(ctx.Shared.Units)

	local RAD = math.pi / 180

	describe("missile data", function()
		it("every airframe's missiles exist, are missiles, and fit on its hardpoints", function()
			local assets = game:GetService("ReplicatedStorage"):FindFirstChild("Assets")
			for id, airframe in AircraftData.getAll() do
				local total = 0
				for _, slot in airframe.Missiles or {} do
					if WeaponData.getMissile(slot.Weapon) == nil then
						error(`{id}: {slot.Weapon} is not a missile`, 0)
					end
					total += slot.Count
				end
				local model = assets and assets.Aircraft:FindFirstChild(airframe.ModelName)
				if model then
					local hardpoints = 0
					for _, a in model.Root:GetChildren() do
						if a:IsA("Attachment") and string.match(a.Name, "^Hardpoint%d+$") then
							hardpoints += 1
						end
					end
					if total > hardpoints then
						error(`{id}: {total} missiles but only {hardpoints} hardpoints`, 0)
					end
				end
			end
		end)
		it("radar missiles need a radar on the jet", function()
			for id, airframe in AircraftData.getAll() do
				for _, slot in airframe.Missiles or {} do
					if WeaponData.isRadar(WeaponData.getMissile(slot.Weapon)) and not airframe.Radar then
						error(`{id} carries {slot.Weapon} but has no radar`, 0)
					end
				end
			end
		end)
		it("get() returns guns only, getMissile() missiles only", function()
			expect(WeaponData.get("AIM9P")).toBe(nil)
			expect(WeaponData.getMissile("M39A2_Twin")).toBe(nil)
			expect(WeaponData.getMissile("R27R") ~= nil).toBe(true)
		end)
		it("rejects an unknown class and out-of-range numbers", function()
			local bad = table.clone(WeaponData.getMissile("AIM9P") :: any)
			bad.Class = "Laser"
			expect(#WeaponData.validate("AIM9P", bad)).toBe(1)
			local bad2 = table.clone(WeaponData.getMissile("AIM9P") :: any)
			bad2.MaxG = 500
			expect(#WeaponData.validate("AIM9P", bad2)).toBe(1)
		end)
	end)

	describe("Pack", function()
		it("missile state round-trips within precision", function()
			local list = {
				{
					id = 7,
					position = Vector3.new(123.5, 4567.25, -890.125),
					velocity = Vector3.new(800, -12.3, 45.6),
					burning = true,
				},
				{ id = 65535, position = Vector3.new(-1, 0, 1), velocity = Vector3.zero, burning = false },
			}
			local out = Pack.unpackMissiles(Pack.missiles(list)) :: any
			expect(#out).toBe(2)
			expect(out[1].id).toBe(7)
			expect(out[1].position).toBeCloseTo(list[1].position, 0.01)
			expect(out[1].velocity).toBeCloseTo(list[1].velocity, 0.05)
			expect(out[1].burning).toBe(true)
			expect(out[2].burning).toBe(false)
		end)
		it("a packet of the maximum size stays under 1 KB", function()
			local list = {}
			for i = 1, Pack.MAX_PER_PACKET do
				list[i] = { id = i, position = Vector3.zero, velocity = Vector3.zero, burning = false }
			end
			expect(buffer.len(Pack.missiles(list)) < 1000).toBe(true)
		end)
		it("rejects malformed buffers", function()
			expect(Pack.unpackMissiles(buffer.create(1))).toBe(nil)
			local b = buffer.create(10)
			buffer.writeu16(b, 0, 5)
			expect(Pack.unpackMissiles(b)).toBe(nil)
		end)
	end)

	describe("Signature", function()
		local jet = CFrame.new(0, Units.toStuds(3000), 0) -- facing -Z
		local behind = jet.Position + Vector3.new(0, 0, 500)
		local ahead = jet.Position + Vector3.new(0, 0, -500)
		it("rear-aspect seekers can't see a jet head-on; all-aspect can", function()
			expect(Signature.ir(jet, 1, false, ahead, true)).toBe(0)
			expect(Signature.ir(jet, 1, false, ahead, false) > 0).toBe(true)
		end)
		it("afterburner is much hotter, idle is cooler", function()
			local mil = Signature.ir(jet, 1, false, behind, true)
			expect(Signature.ir(jet, 1, true, behind, true)).toBeGreaterThan(mil * 2)
			expect(Signature.ir(jet, 0, false, behind, true)).toBeLessThan(mil * 0.5)
		end)
		it("a pulse-Doppler radar loses a target flying perpendicular below it (the notch)", function()
			local radar = { Range = 30000, Cone = 60, CanNotch = true }
			local radarCF = CFrame.lookAt(
				Vector3.new(0, Units.toStuds(5000), 0),
				Vector3.new(0, Units.toStuds(2000), -Units.toStuds(8000))
			)
			local target = Vector3.new(0, Units.toStuds(2000), -Units.toStuds(8000))
			local seen = Signature.radarDetects(radar, radarCF, target, Vector3.new(0, 0, 250)) -- flying away: big Doppler
			local notched, why = Signature.radarDetects(radar, radarCF, target, Vector3.new(250, 0, 0)) -- perpendicular
			expect(seen).toBe(true)
			expect(notched).toBe(false)
			expect(why).toBe("notch")
		end)
		it("a pulse radar can't look down into clutter, but sees a target above it", function()
			local radar = { Range = 30000, Cone = 60, CanNotch = false }
			local high = CFrame.lookAt(
				Vector3.new(0, Units.toStuds(5000), 0),
				Vector3.new(0, Units.toStuds(3000), -Units.toStuds(8000))
			)
			local _, why = Signature.radarDetects(
				radar,
				high,
				Vector3.new(0, Units.toStuds(3000), -Units.toStuds(8000)),
				Vector3.new(0, 0, 250)
			)
			expect(why).toBe("clutter")
			local low = CFrame.lookAt(
				Vector3.new(0, Units.toStuds(3000), 0),
				Vector3.new(0, Units.toStuds(5000), -Units.toStuds(8000))
			)
			expect(
				(
					Signature.radarDetects(
						radar,
						low,
						Vector3.new(0, Units.toStuds(5000), -Units.toStuds(8000)),
						Vector3.zero
					)
				)
			).toBe(true)
		end)
		it("out of range or outside the cone is not detected", function()
			local radar = { Range = 10000, Cone = 30, CanNotch = true }
			local cf = CFrame.new(0, Units.toStuds(5000), 0)
			expect(
				select(
					2,
					Signature.radarDetects(
						radar,
						cf,
						cf.Position + Vector3.new(0, 0, -Units.toStuds(15000)),
						Vector3.zero
					)
				)
			).toBe("range")
			expect(
				select(
					2,
					Signature.radarDetects(
						radar,
						cf,
						cf.Position + Vector3.new(Units.toStuds(5000), 0, 0),
						Vector3.zero
					)
				)
			).toBe("cone")
		end)
	end)

	describe("Guidance", function()
		local aim9 = WeaponData.getMissile("AIM9P") :: any

		local function chase(startRange: number, targetSpeed: number, targetTurn: boolean, spec: any): (boolean, number)
			local targetPos = Vector3.new(0, Units.toStuds(3000), 0)
			local targetVel = Vector3.new(0, 0, -targetSpeed)
			local missile =
				Guidance.launch(targetPos + Vector3.new(0, 0, Units.toStuds(startRange)), Vector3.new(0, 0, -250))
			local closest = math.huge
			for i = 1, 60 * 30 do
				local dt = 1 / 60
				if targetTurn and i > 30 then
					-- 6 G level turn
					local turnRate = 9.81 * 6 / targetVel.Magnitude
					targetVel = CFrame.fromAxisAngle(Vector3.yAxis, turnRate * dt) * targetVel
				end
				local nextTarget = targetPos + Units.velocityToStuds(targetVel) * dt
				local nextMissile = Guidance.step(missile, spec, dt, targetPos, targetVel)
				closest = math.min(
					closest,
					Guidance.closestApproach(missile.position, nextMissile.position, targetPos, nextTarget)
				)
				missile, targetPos = nextMissile, nextTarget
				if missile.velocity.Magnitude < 150 and missile.age > spec.MotorBurnTime then
					break
				end
			end
			return closest <= spec.ProximityFuse, closest
		end

		it("hits a non-manoeuvring target from 2 km behind", function()
			local hit, closest = chase(2000, 220, false, aim9)
			if not hit then
				error(`missed by {closest} m`, 0)
			end
		end)

		it("hits a target pulling 6 G from 1.5 km", function()
			local hit = chase(1500, 220, true, aim9)
			expect(hit).toBe(true)
		end)

		it("a long shot at a fleeing target runs out of energy and falls short", function()
			local hit = chase(5500, 300, false, aim9)
			expect(hit).toBe(false)
		end)

		it("loses guidance when the target leaves the gimbal", function()
			local m = Guidance.launch(Vector3.zero, Vector3.new(0, 0, -600))
			expect(Guidance.inGimbal(m, aim9, Vector3.new(0, 0, -100))).toBe(true)
			expect(Guidance.inGimbal(m, aim9, Vector3.new(100, 0, 0))).toBe(false)
			local _, guiding = Guidance.step(m, aim9, 1 / 60, Vector3.new(100, 0, 0), Vector3.zero)
			expect(guiding).toBe(false)
		end)

		it("turns less as it slows (energy-limited G)", function()
			local fast = Guidance.maxLateral(Guidance.launch(Vector3.zero, Vector3.new(0, 0, -800)), aim9)
			local slow = Guidance.maxLateral(Guidance.launch(Vector3.zero, Vector3.new(0, 0, -300)), aim9)
			expect(slow).toBeLessThan(fast * 0.3)
		end)

		it("IR lock needs the target in the seeker cone and (for rear-aspect) its tail", function()
			local target = CFrame.new(0, Units.toStuds(3000), -Units.toStuds(1500)) -- facing -Z, away from us
			local shooter = CFrame.lookAt(Vector3.new(0, Units.toStuds(3000), 0), target.Position)
			expect(Guidance.irLockable(aim9, shooter, target, 0.9, false)).toBe(true)
			local headOn = target * CFrame.Angles(0, math.pi, 0)
			expect(Guidance.irLockable(aim9, shooter, headOn, 0.9, false)).toBe(false)
			local offAxis = CFrame.lookAt(shooter.Position, shooter.Position + Vector3.new(1, 0, 0))
			expect(Guidance.irLockable(aim9, offAxis, target, 0.9, false)).toBe(false)
		end)

		it("launch zone shrinks against a fleeing target", function()
			local p, t = Vector3.zero, Vector3.new(0, 0, -100)
			local headOn = Guidance.launchZone(aim9, p, Vector3.new(0, 0, -250), t, Vector3.new(0, 0, 250))
			local fleeing = Guidance.launchZone(aim9, p, Vector3.new(0, 0, -250), t, Vector3.new(0, 0, -300))
			expect(fleeing).toBeLessThan(headOn)
			local _ = RAD
		end)
	end)
end
