--!strict
-- Acceptance tests for the flight model (DEVELOPMENT.md §6.7).
return function(ctx)
	local describe, it, expect = ctx.describe, ctx.it, ctx.expect
	local FlightModel = require(ctx.Shared.FlightModel)
	local AircraftData = require(ctx.Shared.AircraftData)
	local Units = require(ctx.Shared.Units)

	local F5E = AircraftData.get("F5E") :: any
	local MiG = AircraftData.get("MiG21bis") :: any
	local RAD = math.pi / 180

	local function input(overrides: { [string]: any }?): any
		local base = { pitch = 0, roll = 0, yaw = 0, throttle = 0.8, afterburner = false, protections = true }
		for k, v in overrides or {} do
			base[k] = v
		end
		return base
	end

	local function levelState(airframe: any, altitudeMetres: number, speed: number): any
		local cf = CFrame.new(0, Units.toStuds(altitudeMetres), 0)
		return FlightModel.newState(cf, speed, airframe)
	end

	local function fly(state: any, airframe: any, inp: any, seconds: number, dt: number?): any
		local h = dt or 1 / 60
		for _ = 1, math.round(seconds / h) do
			state = FlightModel.step(state, inp, airframe, h)
		end
		return state
	end

	local function isFinite(x: number): boolean
		return x == x and x ~= math.huge and x ~= -math.huge
	end

	describe("level flight", function()
		it("holds altitude within 2% over 10 s with neutral stick", function()
			local s0 = levelState(F5E, 3000, 220)
			local s = fly(s0, F5E, input(), 10)
			expect(math.abs(s.altitude - s0.altitude) / s0.altitude).toBeLessThan(0.02)
		end)
		it("stays wings level and finite", function()
			local s = fly(levelState(MiG, 3000, 220), MiG, input(), 10)
			expect(isFinite(s.velocity.Magnitude)).toBe(true)
			expect(math.abs(s.cframe.RightVector.Y)).toBeLessThan(0.01)
		end)
	end)

	describe("energy", function()
		it("a max-G pull bleeds speed even in afterburner", function()
			local s0 = levelState(F5E, 3000, 220)
			local s = fly(s0, F5E, input({ pitch = 1, throttle = 1, afterburner = true }), 5)
			expect(s.speed).toBeLessThan(s0.speed)
		end)
		it("diving in afterburner gains speed", function()
			local cf = CFrame.new(0, Units.toStuds(6000), 0) * CFrame.Angles(-45 * RAD, 0, 0)
			local s0 = FlightModel.newState(cf, 200, F5E)
			local s = fly(s0, F5E, input({ throttle = 1, afterburner = true }), 3)
			expect(s.speed).toBeGreaterThan(s0.speed + 10)
		end)
		it("the MiG-21 bleeds more speed than the F-5E in the same hard turn", function()
			local function bleed(airframe: any): number
				local s0 = levelState(airframe, 3000, 200)
				local s = fly(s0, airframe, input({ pitch = 1, throttle = 1, afterburner = true }), 6)
				return (s0.speed - s.speed) / s0.speed
			end
			expect(bleed(MiG)).toBeGreaterThan(bleed(F5E))
		end)
		it("the F-5E out-sustains the MiG-21 at Mach 0.6", function()
			local speed = 0.6 * 328
			expect(FlightModel.maxSustainedTurnRate(F5E, speed, 3000)).toBeGreaterThan(
				FlightModel.maxSustainedTurnRate(MiG, speed, 3000)
			)
		end)
	end)

	describe("turn performance", function()
		it("F-5E corner speed is in a believable range (300-450 kt at sea level)", function()
			local knots = Units.knots(FlightModel.cornerSpeed(F5E, 0))
			expect(knots > 300 and knots < 450).toBe(true)
		end)
		it("pulls close to its G limit above corner speed", function()
			local s = fly(levelState(F5E, 1000, 260), F5E, input({ pitch = 1, throttle = 1, afterburner = true }), 1.5)
			expect(s.gLoad > F5E.MaxG * 0.85 and s.gLoad < F5E.MaxG * 1.08).toBe(true)
		end)
		it("full roll input reaches most of the max roll rate within 1 s", function()
			local s = fly(levelState(F5E, 3000, 220), F5E, input({ roll = 1 }), 1)
			expect(s.rollRate).toBeGreaterThan(F5E.MaxRollRate * RAD * 0.8)
		end)
	end)

	describe("stall", function()
		it("lift falls past the critical angle", function()
			local peak = FlightModel.liftCoefficient(F5E.CriticalAoA * RAD, F5E)
			local past, stalled = FlightModel.liftCoefficient((F5E.CriticalAoA + 15) * RAD, F5E)
			expect(past).toBeLessThan(peak)
			expect(stalled).toBe(true)
		end)
		it("pulling hard when slow with protections off stalls the jet", function()
			local s = levelState(F5E, 3000, 90)
			local sawStall = false
			for _ = 1, 180 do
				s = FlightModel.step(s, input({ pitch = 1, protections = false }), F5E, 1 / 60)
				sawStall = sawStall or s.stalled
			end
			expect(sawStall).toBe(true)
		end)
		it("the AoA limiter keeps the jet out of the stall", function()
			local s = levelState(F5E, 3000, 90)
			local maxAoa = 0
			for _ = 1, 300 do
				s = FlightModel.step(s, input({ pitch = 1, protections = true }), F5E, 1 / 60)
				maxAoa = math.max(maxAoa, s.aoa)
			end
			expect(maxAoa).toBeLessThan(F5E.CriticalAoA * RAD)
		end)
	end)

	describe("fuel", function()
		it("no fuel means no thrust", function()
			local s = levelState(F5E, 3000, 220)
			s.fuel = 0
			local forces = FlightModel.computeForces(s, input({ throttle = 1, afterburner = true }), F5E)
			expect(forces.thrust.Magnitude).toBe(0)
		end)
		it("afterburner burns fuel faster", function()
			local dry = fly(levelState(F5E, 3000, 220), F5E, input({ throttle = 1 }), 5)
			local wet = fly(levelState(F5E, 3000, 220), F5E, input({ throttle = 1, afterburner = true }), 5)
			expect(wet.fuel).toBeLessThan(dry.fuel)
		end)
	end)

	describe("supercruise and wave drag (FLT-07)", function()
		it("the F-5E cannot pass Mach 1 on dry thrust at 9,000 m", function()
			local s = fly(levelState(F5E, 9000, 240), F5E, input({ throttle = 1 }), 60, 1 / 30)
			expect(s.mach).toBeLessThan(1)
		end)
		it("the MiG-21 goes supersonic in afterburner at 9,000 m", function()
			local s = fly(levelState(MiG, 9000, 260), MiG, input({ throttle = 1, afterburner = true }), 90, 1 / 30)
			expect(s.mach).toBeGreaterThan(1.05)
		end)
		it("wave drag peaks around Mach 1", function()
			expect(FlightModel.waveDrag(0.7)).toBe(0)
			expect(FlightModel.waveDrag(1.05)).toBeGreaterThan(FlightModel.waveDrag(0.9))
			expect(FlightModel.waveDrag(1.05)).toBeGreaterThan(FlightModel.waveDrag(1.8))
		end)
	end)

	describe("pilot G tolerance", function()
		it("stress builds above the onset and decays below it", function()
			local s = levelState(F5E, 3000, 220)
			s.gLoad = 1
			-- A strong, high-G variant so it can hold 9 G for the test
			local strong = table.clone(F5E)
			strong.MaxG = 9
			strong.MaxThrust = 200000
			local pulled = fly(s, strong, input({ pitch = 1, throttle = 1, afterburner = true, protections = true }), 4)
			expect(pulled.gStress).toBeGreaterThan(0.5)
			local relaxed = fly(pulled, strong, input({ throttle = 1 }), 4)
			expect(relaxed.gStress).toBeLessThan(pulled.gStress)
		end)
	end)

	describe("numerics", function()
		it("is deterministic", function()
			local a = fly(levelState(F5E, 3000, 220), F5E, input({ pitch = 0.6, roll = 0.3 }), 4)
			local b = fly(levelState(F5E, 3000, 220), F5E, input({ pitch = 0.6, roll = 0.3 }), 4)
			expect(a.cframe == b.cframe).toBe(true)
			expect(a.velocity == b.velocity).toBe(true)
		end)
		it("is stable at 20 FPS (sub-stepping) and agrees with 60 FPS", function()
			local inp = input({ pitch = 0.5, roll = 0.2, throttle = 1 })
			local slow = fly(levelState(F5E, 3000, 220), F5E, inp, 3, 1 / 20)
			local fast = fly(levelState(F5E, 3000, 220), F5E, inp, 3, 1 / 60)
			expect(isFinite(slow.speed)).toBe(true)
			expect(math.abs(slow.speed - fast.speed)).toBeLessThan(2)
			expect((slow.cframe.Position - fast.cframe.Position).Magnitude).toBeLessThan(20)
		end)
		it("does not mutate the input state", function()
			local s0 = levelState(F5E, 3000, 220)
			local before = s0.cframe
			FlightModel.step(s0, input({ pitch = 1 }), F5E, 0.5)
			expect(s0.cframe == before).toBe(true)
		end)
	end)
end
