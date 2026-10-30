--!strict
-- FLT-08: swing wings (FlightModel.sweep / FlightModel.swept, airframe VariableGeometry).
return function(ctx)
	local describe, it, expect = ctx.describe, ctx.it, ctx.expect
	local AircraftData = require(ctx.Shared.AircraftData)
	local Atmosphere = require(ctx.Shared.Atmosphere)
	local FlightModel = require(ctx.Shared.FlightModel)
	local Units = require(ctx.Shared.Units)

	local F14A = AircraftData.get("F14A") :: any
	local F15C = AircraftData.get("F15C") :: any

	-- The F-14A with its wings fixed at the mid-sweep values (as it flew before FLT-08)
	local fixed = table.clone(F14A)
	fixed.VariableGeometry = nil

	local function near(a: number, b: number): boolean
		return math.abs(a - b) < 1e-6
	end

	describe("the sweep schedule", function()
		it("the swing-wing jets are the F-14A, MiG-23MLD and Tornado F3", function()
			local ids = {}
			for id, airframe in AircraftData.getAll() do
				if (airframe :: any).VariableGeometry then
					table.insert(ids, id)
				end
			end
			table.sort(ids)
			expect(table.concat(ids, ",")).toBe("F14A,MiG23MLD,TornadoF3")
		end)

		it("forward when slow, fully back when fast, in between on the schedule", function()
			expect(FlightModel.sweep(F14A, 0.3)).toBe(20)
			expect(FlightModel.sweep(F14A, 0.6)).toBe(20)
			expect(near(FlightModel.sweep(F14A, 0.825) :: number, 42.5)).toBe(true)
			expect(FlightModel.sweep(F14A, 1.05)).toBe(68)
			expect(FlightModel.sweep(F14A, 2.0)).toBe(68)
			expect(FlightModel.sweep(F15C, 0.8)).toBe(nil)
		end)
	end)

	describe("swept coefficients", function()
		it("blend from the wings-forward to the wings-back values", function()
			local slow, fast = FlightModel.swept(F14A, 0.4), FlightModel.swept(F14A, 1.5)
			expect(slow.CLMax).toBe(F14A.VariableGeometry.Forward.CLMax)
			expect(fast.CLMax).toBe(F14A.VariableGeometry.Back.CLMax)
			expect(fast.CD0 < slow.CD0).toBe(true)
			expect(fast.InducedK > slow.InducedK).toBe(true)
			expect(slow.VariableGeometry).toBe(nil)
			expect(slow.Sweep).toBe(20)
		end)

		it("are cached per degree, and other jets pass straight through", function()
			expect(FlightModel.swept(F14A, 0.4)).toBe(FlightModel.swept(F14A, 0.45))
			expect(FlightModel.swept(F15C, 0.9)).toBe(F15C)
		end)
	end)

	describe("flying", function()
		it("turns harder slow than the fixed-wing version (wings forward)", function()
			local speed, altitude = 170, 3000
			local swing = FlightModel.maxSustainedTurnRate(F14A, speed, altitude)
			local mid = FlightModel.maxSustainedTurnRate(fixed, speed, altitude)
			print(
				`[SwingWings] F-14A sustained turn at 170 m/s: {math.round(math.deg(swing) * 10) / 10}°/s swing, {math.round(
					math.deg(mid) * 10
				) / 10}°/s fixed`
			)
			expect(swing > mid).toBe(true)
		end)

		it("has less drag fast than the fixed-wing version (wings back)", function()
			local altitude = 9000
			local speed = 1.3 * Atmosphere.speedOfSound(altitude)
			local cf = CFrame.new(0, Units.toStuds(altitude), 0)
			local input = { throttle = 1, afterburner = true, pitch = 0, roll = 0, yaw = 0, protections = true }
			local swing = FlightModel.computeForces(FlightModel.newState(cf, speed, F14A), input :: any, F14A)
			local mid = FlightModel.computeForces(FlightModel.newState(cf, speed, fixed), input :: any, fixed)
			expect(swing.drag.Magnitude < mid.drag.Magnitude).toBe(true)
		end)

		it("a step flies with the swept values (the same as stepping the swept copy)", function()
			local cf = CFrame.new(0, Units.toStuds(5000), 0)
			local state = FlightModel.newState(cf, 300, F14A)
			local input = { throttle = 0.9, afterburner = false, pitch = 0.4, roll = 0, yaw = 0, protections = true }
			local a = FlightModel.step(state, input :: any, F14A, 1 / 60)
			local b = FlightModel.step(state, input :: any, FlightModel.swept(F14A, state.mach), 1 / 60)
			expect((a.velocity - b.velocity).Magnitude < 1e-9).toBe(true)
		end)
	end)
end
