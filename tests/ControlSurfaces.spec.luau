--!strict
-- Control surfaces move the right way: stick and body rates -> deflections -> hinge rotations.

return function(ctx)
	local describe, it, expect = ctx.describe, ctx.it, ctx.expect
	local ControlSurfaces = require(ctx.Shared.ControlSurfaces)
	local AircraftData = require(ctx.Shared.AircraftData)

	local airframe = AircraftData.get("F5E")
	local level = CFrame.new()
	local forward = Vector3.new(0, 0, -200) -- 200 m/s straight ahead

	-- Where a point at `offset` from the hinge ends up after the surface deflects
	local function moved(control: string, axis: Vector3, deflection: number, offset: Vector3): Vector3
		return CFrame.fromAxisAngle(axis, ControlSurfaces.hingeAngle(control, axis, deflection)) * offset
	end

	describe("commands from motion", function()
		it("reads nose-up pitch, right roll and nose-right sideslip as positive", function()
			local pitch = ControlSurfaces.fromMotion(level, Vector3.new(0.2, 0, 0), forward, airframe)
			local roll = ControlSurfaces.fromMotion(level, Vector3.new(0, 0, -0.5), forward, airframe)
			-- Flight path to the left of the nose: the nose is yawed right
			local yaw = ControlSurfaces.fromMotion(level, Vector3.zero, Vector3.new(-10, 0, -200), airframe)
			expect(pitch.pitch > 0).toBe(true)
			expect(roll.roll > 0).toBe(true)
			expect(yaw.yaw > 0).toBe(true)
		end)

		it("keeps the rudder central in a coordinated turn", function()
			-- Banked 70° and turning hard: large body yaw rate, no sideslip
			local banked = CFrame.Angles(0, 0, math.rad(-70))
			local turn = Vector3.new(0, 0.3, 0) -- world yaw rate
			local c = ControlSurfaces.fromMotion(banked, turn, banked.LookVector * 200, airframe)
			expect(math.abs(c.yaw) < 1e-6).toBe(true)
		end)

		it("keeps commands within -1..1", function()
			local c = ControlSurfaces.fromMotion(level, Vector3.new(5, 5, 5), forward, airframe)
			expect(math.abs(c.pitch) <= 1 and math.abs(c.roll) <= 1 and math.abs(c.yaw) <= 1).toBe(true)
		end)

		it("works in the jet's own frame, not the world's", function()
			local banked = CFrame.Angles(0, 0, math.rad(90)) -- rolled 90°: pitching now turns about world Y
			local c =
				ControlSurfaces.fromMotion(banked, banked:VectorToWorldSpace(Vector3.new(0.2, 0, 0)), forward, airframe)
			expect(c.pitch > 0).toBe(true)
			expect(math.abs(c.yaw) < 1e-6).toBe(true)
		end)
	end)

	describe("manoeuvring flaps", function()
		it("are out at high angle of attack and low speed, in when fast", function()
			expect(ControlSurfaces.flapFraction(15, 150)).toBe(1)
			expect(ControlSurfaces.flapFraction(15, 320)).toBe(0)
			expect(ControlSurfaces.flapFraction(0, 150)).toBe(0)
		end)

		it("angle of attack is positive with the nose above the flight path", function()
			local noseUp = CFrame.Angles(math.rad(10), 0, 0)
			expect(ControlSurfaces.angleOfAttack(noseUp, forward) > 9).toBe(true)
		end)
	end)

	describe("deflections", function()
		local right = { pitch = 0, roll = 1, yaw = 0, flap = 0 }
		it("roll right raises the right aileron and lowers the left", function()
			expect(ControlSurfaces.deflection("AileronR", right, -20, 20)).toBe(-20)
			expect(ControlSurfaces.deflection("AileronL", right, -20, 20)).toBe(20)
		end)

		it("nose up raises the stabilator trailing edge, within its limits", function()
			expect(ControlSurfaces.deflection("Stabilator", { pitch = 1, roll = 0, yaw = 0, flap = 0 }, -20, 15)).toBe(
				-20
			)
			expect(ControlSurfaces.deflection("Stabilator", { pitch = -1, roll = 0, yaw = 0, flap = 0 }, -20, 15)).toBe(
				15
			)
		end)

		it("elevons mix pitch and roll", function()
			local up = { pitch = 1, roll = 0, yaw = 0, flap = 0 }
			expect(ControlSurfaces.deflection("ElevonL", up, -20, 20)).toBe(-15)
			expect(ControlSurfaces.deflection("ElevonR", up, -20, 20)).toBe(-15)
			expect(ControlSurfaces.deflection("ElevonR", right, -20, 20)).toBe(-15)
			expect(ControlSurfaces.deflection("ElevonL", right, -20, 20)).toBe(15)
			-- Full nose up and full right roll: the right elevon is at its limit, the left one is level
			local both = { pitch = 1, roll = 1, yaw = 0, flap = 0 }
			expect(ControlSurfaces.deflection("ElevonR", both, -20, 20)).toBe(-20)
			expect(ControlSurfaces.deflection("ElevonL", both, -20, 20)).toBe(0)
		end)

		it("flaps follow the flap command up to their maximum", function()
			expect(ControlSurfaces.deflection("Flap", { pitch = 0, roll = 0, yaw = 0, flap = 0.5 }, 0, 30)).toBe(15)
		end)
	end)

	describe("hinge rotations", function()
		local aft, ahead = Vector3.new(0, 0, 1), Vector3.new(0, 0, -1)
		it("trailing edge down is down on both wings (mirrored hinge axes)", function()
			expect(moved("AileronR", Vector3.new(1, 0, 0), 10, aft).Y < 0).toBe(true)
			expect(moved("AileronL", Vector3.new(-1, 0, 0), 10, aft).Y < 0).toBe(true)
		end)

		it("a drooping leading-edge flap moves its leading edge down", function()
			expect(moved("LEFlap", Vector3.new(1, 0, 0), 10, ahead).Y < 0).toBe(true)
			expect(moved("LEFlap", Vector3.new(-1, 0, 0), 10, ahead).Y < 0).toBe(true)
		end)

		it("a positive rudder deflection swings the trailing edge right", function()
			expect(moved("Rudder", Vector3.new(0, 1, 0.4).Unit, 10, aft).X > 0).toBe(true)
		end)
	end)
end
