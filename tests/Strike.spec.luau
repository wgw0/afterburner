--!strict
-- Strike missions (MCH-07, MCH-08, AI-06): bomber flying, Strike Escort scoring and PvE waves (Shared/Strike).
return function(ctx)
	local describe, it, expect = ctx.describe, ctx.it, ctx.expect
	local Strike = require(ctx.Shared.Strike)
	local Units = require(ctx.Shared.Units)

	describe("bombers", function()
		it("fly level-ish straight at the target and decoy when a missile comes", function()
			local memory = {}
			local cruise = Units.toStuds(Strike.CRUISE_ALTITUDE)
			local d = Strike.bomberDecision(memory, Vector3.new(0, cruise, 0), Vector3.new(5000, 0, 0), 900, nil, 0)
			expect(d.aim.X > 0.95).toBe(true)
			expect(d.fire).toBe(false)
			expect(d.flare).toBe(false)
			local hit = Strike.bomberDecision(
				memory,
				Vector3.new(0, cruise, 0),
				Vector3.new(5000, 0, 0),
				900,
				{ kind = "Launch" },
				1
			)
			expect(hit.flare and hit.chaff).toBe(true)
		end)

		it("climb away from the ground", function()
			local d = Strike.bomberDecision({}, Vector3.new(0, 50, 0), Vector3.new(5000, 0, 0), 100, nil, 0)
			expect(d.aim.Y > 0.3).toBe(true)
		end)

		it("start on their own side and reach the target within its radius", function()
			local start = Strike.bomberStart("West", Vector3.new(3000, 0, 0), 5600, 1)
			expect(start.Position.X < 0).toBe(true)
			expect(start.LookVector.X > 0.9).toBe(true)
			expect(Strike.reached(Vector3.new(3000, 400, Strike.TARGET_RADIUS - 1), Vector3.new(3000, 0, 0))).toBe(true)
			expect(Strike.reached(Vector3.new(3000, 400, Strike.TARGET_RADIUS + 1), Vector3.new(3000, 0, 0))).toBe(
				false
			)
		end)
	end)

	describe("Strike Escort", function()
		it("launches a wave at once, then every WAVE_INTERVAL", function()
			local state = Strike.newEscort({ "West", "East" }, 0)
			expect(Strike.waveDue(state, 0)).toBe(true)
			expect(Strike.waveDue(state, 10)).toBe(false)
			expect(Strike.waveDue(state, Strike.WAVE_INTERVAL)).toBe(true)
			expect(state.wave).toBe(2)
		end)

		it("ends at the strike limit; the winner has most strikes, then kills", function()
			local state = Strike.newEscort({ "West", "East" }, 0)
			for _ = 1, Strike.STRIKE_LIMIT do
				Strike.strike(state, "East")
			end
			expect(Strike.escortEnded(state)).toBe(true)
			expect(Strike.escortWinner(state, { West = 50, East = 0 })).toBe("East")
			local level = Strike.newEscort({ "West", "East" }, 0)
			expect(Strike.escortWinner(level, { West = 3, East = 2 })).toBe("West")
			expect(Strike.escortWinner(level, { West = 2, East = 2 })).toBe(nil)
		end)
	end)

	describe("PvE waves", function()
		it("waves grow and sharpen", function()
			local first, last = Strike.waveSpec(1), Strike.waveSpec(Strike.WAVES)
			expect(last.fighters > first.fighters and last.bombers > first.bombers).toBe(true)
			expect(first.difficulty).toBe("Normal")
			expect(last.difficulty).toBe("Ace")
		end)

		it("a cleared wave breaks, then the next launches; clearing the last wins", function()
			local state = Strike.newPve(0)
			expect(Strike.stepPve(state, 0, Strike.WAVE_BREAK)).toBe("Launch")
			expect(state.wave).toBe(1)
			expect(Strike.stepPve(state, 3, 20)).toBe(nil)
			Strike.stepPve(state, 0, 30)
			expect(state.phase).toBe("Break")
			state.wave = Strike.WAVES
			state.phase = "Fight"
			Strike.stepPve(state, 0, 100)
			expect(state.phase).toBe("Won")
		end)

		it("the base falls after BASE_HITS strikes", function()
			local state = Strike.newPve(0)
			for _ = 1, Strike.BASE_HITS do
				Strike.baseHit(state, 5)
			end
			expect(state.phase).toBe("Lost")
		end)
	end)
end
