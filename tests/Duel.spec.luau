--!strict
-- Duels (MCH-09): rounds, ratings and ranks (Shared/Duel).
return function(ctx)
	local describe, it, expect = ctx.describe, ctx.it, ctx.expect
	local Duel = require(ctx.Shared.Duel)

	local function fresh()
		local state = Duel.newState(0)
		Duel.seat(state, "A")
		Duel.seat(state, "B")
		return state
	end

	describe("rounds", function()
		it("seats two pilots and no more", function()
			local state = fresh()
			expect(Duel.seat(state, "C")).toBe(nil)
			expect(Duel.seat(state, "A")).toBe(1)
		end)

		it("waits out the intermission, then starts a round with both alive", function()
			local state = Duel.newState(0)
			Duel.seat(state, "A")
			expect(Duel.step(state, 10)).toBe(nil) -- only one pilot
			Duel.seat(state, "B")
			expect(Duel.step(state, 10)).toBe("Start")
			Duel.startRound(state, 10)
			expect(state.round).toBe(1)
			expect(state.alive.A and state.alive.B).toBe(true)
		end)

		it("the last one flying wins the round", function()
			local state = fresh()
			Duel.startRound(state, 0)
			Duel.down(state, "B", 5)
			expect(state.phase).toBe("Deciding")
			Duel.step(state, 5 + Duel.GRACE)
			expect(state.wins.A).toBe(1)
			expect(state.phase).toBe("Intermission")
			expect((state.lastRound :: any).winner).toBe("A")
		end)

		it("both down at once, or the clock running out, is a drawn round", function()
			local state = fresh()
			Duel.startRound(state, 0)
			Duel.down(state, "A", 5)
			Duel.down(state, "B", 6) -- within the grace: B's missile was already on its way, or a trade
			expect(state.phase).toBe("Intermission")
			expect((state.lastRound :: any).reason).toBe("Both down")
			expect(state.wins.A + state.wins.B).toBe(0)
			Duel.startRound(state, 10)
			Duel.step(state, 10 + Duel.ROUND_TIME)
			expect((state.lastRound :: any).winner).toBe(nil)
			expect((state.lastRound :: any).reason).toBe("Time")
		end)

		it("first to three round wins takes the duel", function()
			local state = fresh()
			for i = 1, 3 do
				Duel.startRound(state, i * 10)
				Duel.down(state, "B", i * 10 + 1)
				Duel.step(state, i * 10 + 1 + Duel.GRACE)
			end
			expect(state.phase).toBe("Over")
			expect(Duel.matchResult(state)).toBe("A")
		end)

		it("level after the last round is a draw", function()
			local state = fresh()
			state.round = Duel.MAX_ROUNDS - 1
			state.wins.A, state.wins.B = 2, 2
			Duel.startRound(state, 0)
			Duel.step(state, Duel.ROUND_TIME)
			expect(Duel.matchResult(state)).toBe("Draw")
		end)

		it("leaving hands the other pilot the duel", function()
			local state = fresh()
			Duel.startRound(state, 0)
			expect(Duel.forfeit(state, "A", 3)).toBe("B")
			expect(Duel.matchResult(state)).toBe("B")
		end)

		it("start positions are opposite corners, level, heading due east and west away from their side", function()
			local pair = Duel.spawnPair(Vector3.zero, 300)
			local a, b = pair[1].Position, pair[2].Position
			expect(math.abs((b.X - a.X) - Duel.SEPARATION) < 1e-3).toBe(true)
			expect(math.abs((a.Z - b.Z) - Duel.OFFSET) < 1e-3).toBe(true) -- seat 1 south (+Z), seat 2 north
			expect(pair[1].LookVector:Dot(Vector3.xAxis) > 0.999).toBe(true) -- west side heads east
			expect(pair[2].LookVector:Dot(-Vector3.xAxis) > 0.999).toBe(true) -- east side heads west
			-- Not pointed at each other
			expect(pair[1].LookVector:Dot((b - a).Unit) < 0.95).toBe(true)
			expect(a.Y).toBe(300)
			expect(b.Y).toBe(300)
		end)
	end)

	describe("ratings", function()
		it("an even match moves K/2 for a win and back for a loss", function()
			expect(Duel.change(1000, 1000, 1, 20)).toBe(Duel.K / 2)
			expect(Duel.change(1000, 1000, 0, 20)).toBe(-Duel.K / 2)
			expect(Duel.change(1000, 1000, 0.5, 20)).toBe(0)
		end)

		it("beating a stronger pilot earns more than beating a weaker one", function()
			expect(Duel.change(1000, 1300, 1, 20) > Duel.change(1000, 700, 1, 20)).toBe(true)
		end)

		it("a win always gains and a loss always costs at least a point", function()
			expect(Duel.change(2000, 800, 1, 20)).toBe(1)
			expect(Duel.change(800, 2000, 0, 20)).toBe(-1)
		end)

		it("new pilots move faster for their first duels", function()
			expect(Duel.change(1000, 1000, 1, 0) > Duel.change(1000, 1000, 1, 50)).toBe(true)
		end)

		it("ranked duels move the rating; casual ones only count", function()
			local data = {}
			expect(Duel.apply(data, 1000, 1, false)).toBe(0)
			expect(data.Duel.Rating).toBe(Duel.START_RATING)
			expect(data.Duel.Won).toBe(1)
			local delta = Duel.apply(data, 1000, 1, true)
			expect(delta > 0 and data.Duel.Rating == Duel.START_RATING + delta).toBe(true)
			expect(data.Duel.Peak).toBe(data.Duel.Rating)
		end)

		it("reaching a rank the first time gives its title and Credits, once", function()
			local data: any = { Credits = 0 }
			Duel.record(data).Rating = 1090
			local _, reached = Duel.apply(data, 1500, 1, true)
			expect(#reached).toBe(1)
			expect(reached[1].id).toBe("Silver")
			expect(data.Titles.DuelistSilver).toBe(true)
			expect(data.Credits).toBe(Duel.RANK_CREDITS.Silver)
			Duel.record(data).Rating = 1000 -- drop back down, then climb again: nothing twice
			local _, again = Duel.apply(data, 2000, 1, true)
			expect(#again).toBe(0)
			expect(data.Credits).toBe(Duel.RANK_CREDITS.Silver)
		end)

		it("ranks follow the rating, with the next one to aim for", function()
			expect(Duel.rankFor(Duel.START_RATING).id).toBe("Bronze")
			expect(Duel.rankFor(1250).id).toBe("Gold")
			expect(Duel.rankFor(5000).id).toBe("Ace")
			expect((Duel.nextRank(1000) :: any).id).toBe("Silver")
			expect(Duel.nextRank(5000)).toBe(nil)
		end)

		it("the rating spread loosens with the wait", function()
			expect(Duel.ratingSpread(0)).toBe(150)
			expect(Duel.ratingSpread(15) > 150 and Duel.ratingSpread(15) < 300).toBe(true)
			expect(Duel.ratingSpread(600)).toBe(600)
		end)
	end)
end
