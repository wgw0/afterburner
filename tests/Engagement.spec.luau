--!strict
-- Engagement simulator: a real target jet (FlightModel + Instructor) defending against a real missile
-- (Guidance + IR seeker + flares), many seeds per scenario. Proves the countermeasure design goals
-- (DEVELOPMENT.md §15 acceptance): defending properly usually works; doing it wrong usually doesn't.
return function(ctx)
	local describe, it, expect = ctx.describe, ctx.it, ctx.expect
	local AircraftData = require(ctx.Shared.AircraftData)
	local WeaponData = require(ctx.Shared.WeaponData)
	local FlightModel = require(ctx.Shared.FlightModel)
	local Instructor = require(ctx.Shared.Instructor)
	local Guidance = require(ctx.Shared.Guidance)
	local Countermeasures = require(ctx.Shared.Countermeasures)
	local Signature = require(ctx.Shared.Signature)
	local Units = require(ctx.Shared.Units)

	local F5E = AircraftData.get("F5E") :: any
	local DT = 1 / 60

	export type Scenario = {
		throttle: number,
		afterburner: boolean,
		breakTurn: boolean,
		flareInterval: number?, -- seconds between flares (nil = none)
		reaction: number, -- seconds after launch before the target reacts
	}

	-- Returns true if the missile hits.
	local function engage(missileId: string, scenario: Scenario, seed: number, range: number): boolean
		local spec = WeaponData.getMissile(missileId) :: any
		local rearOnly = spec.Class == "IR_Rear"
		local start = CFrame.new(0, Units.toStuds(3000), 0)
		local target = FlightModel.newState(start, 230, F5E)
		local missile =
			Guidance.launch(start.Position + Vector3.new(0, 0, Units.toStuds(range)), Vector3.new(0, 0, -260))
		local seeker = Guidance.newIRSeeker(1, seed)
		local flares = {}
		local nextFlareId, flareTimer = seed * 100, 0
		local breakDir = Vector3.new(1, -0.15, 0).Unit -- a hard, slightly descending break to the right

		for _ = 1, math.floor(spec.Lifetime / DT) do
			local reacting = missile.age >= scenario.reaction
			local aim = if reacting and scenario.breakTurn then breakDir else start.LookVector
			local input = Instructor.compute(target, aim, F5E, {
				allowOverG = reacting and scenario.breakTurn,
				throttle = if reacting then scenario.throttle else 0.85,
				afterburner = reacting and scenario.afterburner,
			})
			local nextTarget = FlightModel.step(target, input, F5E, DT)

			if reacting and scenario.flareInterval then
				flareTimer -= DT
				if flareTimer <= 0 then
					flareTimer = scenario.flareInterval
					nextFlareId += 1
					table.insert(
						flares,
						Countermeasures.newFlare(
							nextFlareId,
							target.cframe * CFrame.new(0, -0.56, 4.2),
							target.velocity
						)
					)
				end
			end
			for i, flare in flares do
				flares[i] = Countermeasures.stepFlare(flare, DT)
			end

			local sources = {
				{
					id = 1,
					position = target.cframe.Position,
					velocity = target.velocity,
					heat = Signature.ir(target.cframe, input.throttle, input.afterburner, missile.position, rearOnly),
				},
			}
			for _, flare in flares do
				table.insert(sources, {
					id = `flare:{flare.id}`,
					position = flare.position,
					velocity = flare.velocity,
					heat = Countermeasures.flareHeat(flare),
				})
			end
			local tracked = Guidance.updateIRSeeker(seeker, missile, spec, sources)
			local nextMissile =
				Guidance.step(missile, spec, DT, tracked and tracked.position, tracked and tracked.velocity)
			local miss = Guidance.closestApproach(
				missile.position,
				nextMissile.position,
				target.cframe.Position,
				nextTarget.cframe.Position
			)
			if miss <= spec.ProximityFuse and nextMissile.travelled >= spec.MinRange then
				return true
			end
			missile, target = nextMissile, nextTarget
			if missile.age > spec.MotorBurnTime and missile.velocity.Magnitude < spec.MinSpeed * 0.6 then
				return false
			end
		end
		return false
	end

	local function hitRate(missileId: string, scenario: Scenario, runs: number, range: number): number
		local hits = 0
		for seed = 1, runs do
			if engage(missileId, scenario, seed, range) then
				hits += 1
			end
		end
		return hits / runs
	end

	local RUNS = 40

	describe("AIM-9P vs a defending F-5E from 1.8 km behind", function()
		it("an unaware target is hit nearly every time", function()
			local rate =
				hitRate("AIM9P", { throttle = 0.85, afterburner = false, breakTurn = false, reaction = 99 }, RUNS, 1800)
			print(`[Engagement] no defence: {math.round(rate * 100)}% hit`)
			expect(rate >= 0.9).toBe(true)
		end)

		it("afterburner and flying straight while flaring mostly fails", function()
			local rate = hitRate(
				"AIM9P",
				{ throttle = 1, afterburner = true, breakTurn = false, flareInterval = 0.5, reaction = 0.5 },
				RUNS,
				1800
			)
			print(`[Engagement] AB straight + flares: {math.round((1 - rate) * 100)}% defeated`)
			expect(rate >= 0.5).toBe(true)
		end)

		it("throttle back, break hard and flare defeats it most of the time (target 70-85%)", function()
			local rate = hitRate(
				"AIM9P",
				{ throttle = 0, afterburner = false, breakTurn = true, flareInterval = 0.4, reaction = 0.5 },
				RUNS,
				1800
			)
			local defeated = 1 - rate
			print(`[Engagement] idle + break + flares: {math.round(defeated * 100)}% defeated`)
			expect(defeated >= 0.65 and defeated <= 0.92).toBe(true)
		end)
	end)
end
