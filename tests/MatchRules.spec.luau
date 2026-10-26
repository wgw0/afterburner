--!strict
-- Match rules, movement anti-cheat limits and the lesson runner (MCH-01/03, SEC-01, TUT-01).
return function(ctx)
	local describe, it, expect = ctx.describe, ctx.it, ctx.expect
	local MatchRules = require(ctx.Shared.MatchRules)
	local MovementCheck = require(ctx.Shared.MovementCheck)
	local LessonRunner = require(ctx.Shared.LessonRunner)
	local FlightModel = require(ctx.Shared.FlightModel)
	local AircraftData = require(ctx.Shared.AircraftData)
	local Units = require(ctx.Shared.Units)

	describe("MatchRules", function()
		local dogfight = MatchRules.MODES.Dogfight

		local function scores()
			return {
				a = MatchRules.newScore("Alice", false, 1),
				b = MatchRules.newScore("Bob", false, 2),
				c = MatchRules.newScore("AI-3", true, 0),
			}
		end

		it("a kill scores for the killer, a death for the victim, assists for helpers", function()
			local s = scores()
			MatchRules.recordKill(s, "b", "a", { "c" }, false)
			expect(s.a.kills).toBe(1)
			expect(s.a.score).toBe(MatchRules.POINTS.Kill)
			expect(s.b.deaths).toBe(1)
			expect(s.c.assists).toBe(1)
			expect(s.c.score).toBe(MatchRules.POINTS.Assist)
		end)
		it("a crash with nobody's damage is just a death", function()
			local s = scores()
			MatchRules.recordKill(s, "b", nil, {}, false)
			expect(s.b.deaths).toBe(1)
			expect(s.a.kills + s.c.kills).toBe(0)
		end)
		it("ranking orders by score, then kills, then fewest deaths", function()
			local s = scores()
			MatchRules.recordKill(s, "b", "a", {}, false)
			MatchRules.recordKill(s, "a", "c", {}, false)
			MatchRules.recordKill(s, "b", "c", {}, false)
			local ranked = MatchRules.ranking(s)
			expect(ranked[1].name).toBe("AI-3")
			expect(ranked[2].name).toBe("Alice")
		end)
		it("the match ends at the score limit or the time limit", function()
			local s = scores()
			expect((MatchRules.checkEnd(dogfight, s, 10))).toBe(false)
			s.a.kills = dogfight.ScoreLimit
			expect(select(2, MatchRules.checkEnd(dogfight, s, 10))).toBe("ScoreLimit")
			expect(select(2, MatchRules.checkEnd(dogfight, scores(), dogfight.TimeLimit))).toBe("TimeLimit")
			expect((MatchRules.checkEnd(MatchRules.MODES.FreeFlight, scores(), 99999))).toBe(false)
		end)
		it("timer respawns wait the delay", function()
			local ok, wait = MatchRules.canSpawn(dogfight, { diedAt = 100, livesUsed = 1 }, 102)
			expect(ok).toBe(false)
			expect(wait).toBeCloseTo(dogfight.Respawn.Delay - 2, 1e-9)
			expect((MatchRules.canSpawn(dogfight, { diedAt = 100, livesUsed = 1 }, 106))).toBe(true)
		end)
		it("lives respawns run out", function()
			local lives = table.clone(dogfight) :: any
			lives.Respawn = { Type = "Lives", Lives = 2, Delay = 0 }
			expect((MatchRules.canSpawn(lives, { diedAt = nil, livesUsed = 1 }, 0))).toBe(true)
			local ok, _, left = MatchRules.canSpawn(lives, { diedAt = nil, livesUsed = 2 }, 0)
			expect(ok).toBe(false)
			expect(left).toBe(0)
		end)
	end)

	describe("MovementCheck", function()
		local F5E = AircraftData.get("F5E") :: any
		local limits = MovementCheck.limits(F5E)

		local function sampleFlight(inputFn: (number) -> any, seconds: number): (boolean, string?)
			local state = FlightModel.newState(CFrame.new(0, Units.toStuds(3000), 0), 230, F5E)
			local previous = nil
			local t = 0
			for i = 1, math.round(seconds * 60) do
				state = FlightModel.step(state, inputFn(t), F5E, 1 / 60)
				t += 1 / 60
				if i % 6 == 0 then
					local sample =
						{ time = t, position = state.cframe.Position, velocity = Units.velocityToStuds(state.velocity) }
					if previous then
						local ok, reason = MovementCheck.evaluate(previous, sample, limits)
						if not ok then
							return false, reason
						end
					end
					previous = sample
				end
			end
			return true, nil
		end

		it("never flags honest flying: max-G pulls, rolls, afterburner dives", function()
			local ok, reason = sampleFlight(function(t)
				local phase = math.floor(t / 4) % 3
				return {
					pitch = if phase == 0 then 1 elseif phase == 1 then -1 else 0.4,
					roll = if phase == 2 then 1 else 0,
					yaw = 0,
					throttle = 1,
					afterburner = true,
					protections = false,
				}
			end, 60)
			if not ok then
				error(`honest flight flagged: {reason}`, 0)
			end
		end)
		it("flags a speed hack", function()
			local a = { time = 0, position = Vector3.zero, velocity = Vector3.new(0, 0, -300) }
			local b = {
				time = 0.1,
				position = Vector3.new(0, 0, -30),
				velocity = Vector3.new(0, 0, -Units.velocityToStuds(2000)),
			}
			expect(select(2, MovementCheck.evaluate(a, b, limits))).toBe("speed")
		end)
		it("flags a teleport", function()
			local a = { time = 0, position = Vector3.zero, velocity = Vector3.new(0, 0, -300) }
			local b = { time = 0.1, position = Vector3.new(5000, 0, 0), velocity = Vector3.new(0, 0, -300) }
			expect(select(2, MovementCheck.evaluate(a, b, limits))).toBe("teleport")
		end)
		it("flags impossible acceleration", function()
			local a = { time = 0, position = Vector3.zero, velocity = Vector3.new(0, 0, -300) }
			local b = { time = 0.1, position = Vector3.new(0, 0, -30), velocity = Vector3.new(0, 0, 300) }
			expect(select(2, MovementCheck.evaluate(a, b, limits))).toBe("acceleration")
		end)
		it("a sudden stop (crashing) is not flagged", function()
			local a = { time = 0, position = Vector3.zero, velocity = Vector3.new(0, 0, -300) }
			local b = { time = 0.1, position = Vector3.new(0, 0, -20), velocity = Vector3.zero }
			expect((MovementCheck.evaluate(a, b, limits))).toBe(true)
		end)
		it("three strikes resets, three resets kicks; old strikes expire", function()
			local s = MovementCheck.newStrikes()
			expect(MovementCheck.strike(s, 0)).toBe("none")
			expect(MovementCheck.strike(s, 20)).toBe("none") -- the first one expired
			expect(MovementCheck.strike(s, 21)).toBe("none")
			expect(MovementCheck.strike(s, 22)).toBe("reset")
			MovementCheck.strike(s, 30)
			MovementCheck.strike(s, 30)
			expect(MovementCheck.strike(s, 30)).toBe("reset")
			MovementCheck.strike(s, 40)
			MovementCheck.strike(s, 40)
			expect(MovementCheck.strike(s, 40)).toBe("kick")
		end)
	end)

	describe("LessonRunner", function()
		it("advances through steps as their checks pass, then finishes", function()
			local entered = 0
			local lesson = {
				id = "test",
				title = "Test",
				steps = {
					{
						text = "one",
						check = function(c)
							return c.x > 1
						end,
						enter = function()
							entered += 1
						end,
					},
					{
						text = "two",
						check = function(c)
							return c.x > 2
						end,
					},
				},
			}
			local runner = LessonRunner.new(lesson)
			expect(runner:update({ x = 0 })).toBe(false)
			expect((runner:current() :: any).text).toBe("one")
			runner:update({ x = 1.5 })
			expect((runner:current() :: any).text).toBe("two")
			expect(runner:update({ x = 3 })).toBe(true)
			expect(runner.done).toBe(true)
			expect(entered).toBe(1)
		end)
	end)
end
