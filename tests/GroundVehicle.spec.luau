--!strict
-- The Ground Roamer's handling (DEVELOPMENT.md §36): Shared/GroundVehicle driving a simple rigid body (a
-- 1,500 kg box with its centre of mass 0.6 m up, as the template's ballast sets it) on a flat or tilted plane.
return function(ctx)
	local describe, it, expect = ctx.describe, ctx.it, ctx.expect
	local GroundVehicle = require(ctx.Shared.GroundVehicle)
	local config = require(ctx.Shared.Config.GroundRoamer) :: any

	local MASS = 1500
	local SIZE = Vector3.new(1.6, 1.0, 3.4)
	local INERTIA = Vector3.new(
		MASS / 12 * (SIZE.Y ^ 2 + SIZE.Z ^ 2),
		MASS / 12 * (SIZE.X ^ 2 + SIZE.Z ^ 2),
		MASS / 12 * (SIZE.X ^ 2 + SIZE.Y ^ 2)
	)
	local COM_UP = 0.6

	local function plane(slope: number)
		local n = Vector3.new(0, math.cos(slope), math.sin(slope))
		return function(origin: Vector3, dir: Vector3): (Vector3?, Vector3?)
			local denom = dir:Dot(n)
			if math.abs(denom) < 1e-9 then
				return nil, nil
			end
			local t = -origin:Dot(n) / denom
			if t < 0 or t > 1 then
				return nil, nil
			end
			return origin + dir * t, n
		end
	end

	-- Runs the vehicle for `seconds`; inputFn(lastStep) gives the input. Returns the pivot, the last step and the
	-- largest roll (degrees).
	local function drive(seconds: number, inputFn: (any) -> any, slope: number?, startSpeed: number?)
		local s = slope or 0
		local ground = plane(s)
		local up0 = Vector3.new(0, math.cos(s), math.sin(s))
		local cf = CFrame.fromMatrix(up0 * 0.02, Vector3.xAxis, up0)
		local v = cf.LookVector * (startSpeed or 0)
		local w = Vector3.zero
		local state = GroundVehicle.newState(config)
		local dt = 1 / 120
		local out: any = nil
		local maxRoll = 0
		for _ = 1, math.round(seconds / dt) do
			local com = cf:PointToWorldSpace(Vector3.new(0, COM_UP, 0))
			local body = { cframe = cf, velocity = v, angularVelocity = w, centreOfMass = com, mass = MASS }
			out = GroundVehicle.step(config, state, body, inputFn(out), ground, dt)
			local force = Vector3.new(0, -config.Gravity * MASS, 0)
			local torque = Vector3.zero
			for _, f in out.forces do
				force += f.force
				torque += (f.position - com):Cross(f.force)
			end
			v += force / MASS * dt
			local tb = cf:VectorToObjectSpace(torque)
			local wb = cf:VectorToObjectSpace(w)
				+ Vector3.new(tb.X / INERTIA.X, tb.Y / INERTIA.Y, tb.Z / INERTIA.Z) * dt
			w = cf:VectorToWorldSpace(wb)
			local rot = cf.Rotation
			if w.Magnitude > 1e-9 then
				rot = CFrame.fromAxisAngle(w.Unit, w.Magnitude * dt) * rot
			end
			cf = CFrame.new(com + v * dt) * rot * CFrame.new(0, -COM_UP, 0)
			maxRoll = math.max(maxRoll, math.deg(math.acos(math.clamp(cf.UpVector:Dot(up0), -1, 1))))
		end
		return cf, out, maxRoll
	end

	local function hold(throttle: number, steer: number, handbrake: boolean?)
		return function()
			return { throttle = throttle, steer = steer, handbrake = handbrake == true }
		end
	end

	describe("GroundVehicle", function()
		it("settles at its rest height on all four wheels", function()
			local cf, out = drive(4, hold(0, 0))
			expect(math.abs(cf.Position.Y) < 0.05).toBe(true)
			expect(out.grounded).toBe(4)
		end)

		it("reaches most of its top speed and no more", function()
			local _, out = drive(30, hold(1, 0))
			expect(out.speed > config.TopSpeed * 0.85).toBe(true)
			expect(out.speed < config.TopSpeed * 1.02).toBe(true)
		end)

		it("brakes to a stop from 25 m/s", function()
			local _, out = drive(6, function(last)
				return { throttle = if last and last.speed < 0.5 then 0 else -1, steer = 0, handbrake = false }
			end, 0, 25)
			expect(math.abs(out.speed) < 1).toBe(true)
		end)

		it("turns the way it's steered", function()
			local cf = drive(1, hold(0.5, 1), 0, 15)
			expect(cf.LookVector.X > 0.2).toBe(true) -- started facing -z; steering right turns it towards +x
		end)

		it("doesn't roll over in a full-lock turn at 15 m/s", function()
			local _, _, maxRoll = drive(5, hold(0.5, 1), 0, 15)
			expect(maxRoll < 25).toBe(true)
		end)

		it("holds on a 15-degree slope with the handbrake", function()
			local start = drive(0.01, hold(0, 0, true), math.rad(15))
			local finish = drive(5, hold(0, 0, true), math.rad(15))
			expect((finish.Position - start.Position).Magnitude < 0.5).toBe(true)
		end)

		it("limits the steering lock at speed", function()
			expect(GroundVehicle.steerLimit(config, 0)).toBe(config.MaxSteer)
			expect(math.abs(GroundVehicle.steerLimit(config, config.TopSpeed) - config.MinSteer) < 1e-9).toBe(true)
		end)
	end)
end
