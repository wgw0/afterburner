--!strict
return function(ctx)
	local describe, it, expect = ctx.describe, ctx.it, ctx.expect
	local FlightModel = require(ctx.Shared.FlightModel)
	local Instructor = require(ctx.Shared.Instructor)
	local AircraftData = require(ctx.Shared.AircraftData)
	local Units = require(ctx.Shared.Units)
	local Flight = require(ctx.Shared.Config.Flight)

	local F5E = AircraftData.get("F5E") :: any
	local RAD = math.pi / 180

	local function level(): any
		return FlightModel.newState(CFrame.new(0, Units.toStuds(3000), 0), 220, F5E)
	end

	-- Direction rotated from the jet's nose by yaw (right +) and pitch (up +), in degrees.
	local function aimFrom(cf: CFrame, yawDeg: number, pitchDeg: number): Vector3
		return (cf.Rotation * CFrame.Angles(0, -yawDeg * RAD, 0) * CFrame.Angles(pitchDeg * RAD, 0, 0)).LookVector
	end

	describe("open loop", function()
		it("aim dead ahead gives near-neutral inputs", function()
			local s = level()
			local c = Instructor.compute(s, s.cframe.LookVector, F5E)
			expect(math.abs(c.pitch) < 0.05 and math.abs(c.roll) < 0.05 and math.abs(c.yaw) < 0.05).toBe(true)
		end)
		it("aim to the right rolls right", function()
			local s = level()
			expect(Instructor.compute(s, aimFrom(s.cframe, 90, 0), F5E).roll).toBeGreaterThan(0.5)
		end)
		it("aim to the left rolls left", function()
			local s = level()
			expect(Instructor.compute(s, aimFrom(s.cframe, -90, 0), F5E).roll).toBeLessThan(-0.5)
		end)
		it("aim above pulls without rolling", function()
			local s = level()
			local c = Instructor.compute(s, aimFrom(s.cframe, 0, 30), F5E)
			expect(c.pitch).toBeGreaterThan(0.3)
			expect(math.abs(c.roll)).toBeLessThan(0.1)
		end)
		it("a small offset below pushes rather than rolling inverted", function()
			local s = level()
			local c = Instructor.compute(s, aimFrom(s.cframe, 0, -8), F5E)
			expect(c.pitch).toBeLessThan(0)
			expect(math.abs(c.roll)).toBeLessThan(0.3)
		end)
		it("caps G at the safe limit unless the pilot overrides", function()
			local s = level()
			local aim = aimFrom(s.cframe, 0, 60)
			local safe = (Flight.INSTRUCTOR_SAFE_G - 1) / (F5E.MaxG - 1)
			expect(Instructor.compute(s, aim, F5E).pitch <= safe + 1e-9).toBe(true)
			expect(Instructor.compute(s, aim, F5E, { allowOverG = true }).pitch).toBeGreaterThan(safe)
		end)
	end)

	describe("closed loop", function()
		local function run(aim: Vector3, seconds: number): ({ number }, any)
			local s = level()
			local offs = {}
			for i = 1, math.round(seconds * 60) do
				local c = Instructor.compute(s, aim, F5E, { throttle = 1 })
				s = FlightModel.step(s, c, F5E, 1 / 60)
				if i % 6 == 0 then
					-- The instructor flies the flight path (velocity) onto the aim; the nose sits AoA above it.
					local pathOff = math.acos(math.clamp(s.velocity.Unit:Dot(aim), -1, 1))
					table.insert(offs, pathOff / RAD)
				end
			end
			return offs, s
		end

		it("turns onto a target 90° to the right and settles without oscillating", function()
			local aim = aimFrom(level().cframe, 90, 0)
			local offs, s = run(aim, 20)
			expect(offs[#offs]).toBeLessThan(3)
			local reached = false
			for _, off in offs do
				if off < 5 then
					reached = true
				elseif reached then
					expect(off).toBeLessThan(8) -- no big overshoot once on target
				end
			end
			expect(s.speed == s.speed).toBe(true)
		end)

		it("turns onto a target behind and above, then holds it steadily", function()
			local aim = aimFrom(level().cframe, 150, 20)
			local offs = run(aim, 30)
			expect(offs[#offs]).toBeLessThan(3)
			-- Last 10 s: no wandering (this caught a roll wobble when errors were measured from the nose).
			for i = #offs - 100, #offs do
				expect(offs[i]).toBeLessThan(3)
			end
		end)

		it("flying straight ahead keeps the wings level and the altitude steady", function()
			local s0 = level()
			local _, s = run(s0.cframe.LookVector, 10)
			expect(math.abs(Instructor.bankAngle(s.cframe))).toBeLessThan(2 * RAD)
			expect(math.abs(s.altitude - s0.altitude)).toBeLessThan(15) -- metres, over 10 s
		end)

		it("holds a level aim for 30 s without drifting off altitude", function()
			local s0 = level()
			local _, s = run(s0.cframe.LookVector, 30)
			expect(math.abs(s.altitude - s0.altitude)).toBeLessThan(20)
			expect(math.abs(s.velocity.Unit.Y)).toBeLessThan(0.01)
		end)
	end)
end
