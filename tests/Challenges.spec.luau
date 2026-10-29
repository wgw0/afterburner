--!strict
-- Daily and weekly challenges (LIV-01) and achievements (LIV-02).

return function(ctx)
	local describe, it, expect = ctx.describe, ctx.it, ctx.expect
	local Achievements = require(ctx.Shared.Achievements)
	local Challenges = require(ctx.Shared.Challenges)

	local DAY = 86400
	local MONDAY = 20038 * DAY -- Monday 11 November 2024, 00:00 UTC

	describe("the pools", function()
		it("every challenge has a unique id, a known event, a target and a reward", function()
			local seen = {}
			local events =
				{ Kill = true, Assist = true, Win = true, MatchFinished = true, Capture = true, MissileDefeated = true }
			for _, pool in { Challenges.DAILY_POOL, Challenges.WEEKLY_POOL } do
				for _, def in pool do
					expect(seen[def.id]).toBe(nil)
					seen[def.id] = true
					expect(events[def.event]).toBe(true)
					expect(def.target >= 1).toBe(true)
					expect(def.credits > 0 and def.xp > 0).toBe(true)
				end
			end
		end)
	end)

	describe("days and weeks", function()
		it("a week starts on Monday at 00:00 UTC", function()
			local week = Challenges.week(MONDAY)
			expect(Challenges.week(MONDAY - 1)).toBe(week - 1)
			expect(Challenges.week(MONDAY + 7 * DAY - 1)).toBe(week)
			expect(Challenges.week(MONDAY + 7 * DAY)).toBe(week + 1)
		end)

		it("counts down to the next resets", function()
			local untilDay, untilWeek = Challenges.untilReset(MONDAY + 3600)
			expect(untilDay).toBe(DAY - 3600)
			expect(untilWeek).toBe(7 * DAY - 3600)
		end)

		it("everyone gets the same 3 dailies on a day, different from the next day's", function()
			local day = Challenges.day(MONDAY)
			local a, b = Challenges.dailyFor(day), Challenges.dailyFor(day)
			expect(#a).toBe(Challenges.DAILY_COUNT)
			expect(table.concat(a, ",")).toBe(table.concat(b, ","))
			local differs = false
			for offset = 1, 5 do
				if table.concat(Challenges.dailyFor(day + offset), ",") ~= table.concat(a, ",") then
					differs = true
				end
			end
			expect(differs).toBe(true)
			-- no repeats within a day
			expect(a[1] ~= a[2] and a[2] ~= a[3] and a[1] ~= a[3]).toBe(true)
		end)
	end)

	describe("refreshing", function()
		it("a new day brings new dailies and the reroll back; the weekly carries on", function()
			local state = Challenges.newState()
			expect(Challenges.refresh(state, MONDAY)).toBe(true)
			expect(#state.Daily).toBe(Challenges.DAILY_COUNT)
			expect(#state.Weekly).toBe(Challenges.WEEKLY_COUNT)
			state.Weekly[1].Progress = 4
			state.Rerolls = 1
			expect(Challenges.refresh(state, MONDAY + 100)).toBe(false)
			Challenges.refresh(state, MONDAY + DAY)
			expect(state.Rerolls).toBe(0)
			expect(state.Weekly[1].Progress).toBe(4)
			Challenges.refresh(state, MONDAY + 7 * DAY)
			expect(state.Weekly[1].Progress).toBe(0)
		end)
	end)

	describe("progress", function()
		it("an event counts only towards challenges it fits", function()
			local state = Challenges.newState()
			Challenges.refresh(state, MONDAY)
			state.Daily = {
				{ Id = "IRKills", Progress = 0, Done = false },
				{ Id = "GunKills", Progress = 0, Done = false },
				{ Id = "LowTierKills", Progress = 0, Done = false },
			}
			Challenges.record(state, { kind = "Kill", weapon = "IR", tier = 4 }, MONDAY)
			expect(state.Daily[1].Progress).toBe(1)
			expect(state.Daily[2].Progress).toBe(0)
			expect(state.Daily[3].Progress).toBe(0) -- tier 4 is above Tier II
			Challenges.record(state, { kind = "Kill", weapon = "Gun", tier = 2 }, MONDAY)
			expect(state.Daily[2].Progress).toBe(1)
			expect(state.Daily[3].Progress).toBe(1)
		end)

		it("completes at the target, once", function()
			local state = Challenges.newState()
			Challenges.refresh(state, MONDAY)
			state.Daily = { { Id = "IRKills", Progress = 0, Done = false } }
			state.Weekly = {}
			expect(#Challenges.record(state, { kind = "Kill", weapon = "IR" }, MONDAY)).toBe(0)
			local done = Challenges.record(state, { kind = "Kill", weapon = "IR" }, MONDAY)
			expect(#done).toBe(1)
			expect(done[1].id).toBe("IRKills")
			expect(state.Daily[1].Done).toBe(true)
			expect(#Challenges.record(state, { kind = "Kill", weapon = "IR" }, MONDAY)).toBe(0)
			expect(state.Daily[1].Progress).toBe(2)
		end)

		it("mode and survival filters", function()
			local team = Challenges.get("TeamWin") :: any
			expect(Challenges.matches(team, { kind = "Win", mode = "TeamDeathmatch" })).toBe(true)
			expect(Challenges.matches(team, { kind = "Win", mode = "Dogfight" })).toBe(false)
			local survivor = Challenges.get("Survivor") :: any
			expect(Challenges.matches(survivor, { kind = "MatchFinished", survived = true })).toBe(true)
			expect(Challenges.matches(survivor, { kind = "MatchFinished", survived = false })).toBe(false)
		end)

		it("weapon classes", function()
			expect(Challenges.weaponClass(nil)).toBe("Gun")
			expect(Challenges.weaponClass("IR_Rear")).toBe("IR")
			expect(Challenges.weaponClass("IR_Adv")).toBe("IR")
			expect(Challenges.weaponClass("SARH")).toBe("Radar")
			expect(Challenges.weaponClass("ARH")).toBe("Radar")
		end)
	end)

	describe("rerolls", function()
		it("one a day, only on unfinished dailies, never to one already on the list", function()
			local state = Challenges.newState()
			Challenges.refresh(state, MONDAY)
			local before = { state.Daily[1].Id, state.Daily[2].Id, state.Daily[3].Id }
			local ok = Challenges.reroll(state, 2, MONDAY)
			expect(ok).toBe(true)
			expect(state.Daily[2].Id ~= before[2]).toBe(true)
			expect(state.Daily[2].Id ~= before[1] and state.Daily[2].Id ~= before[3]).toBe(true)
			local again, why = Challenges.reroll(state, 1, MONDAY)
			expect(again).toBe(false)
			expect(why).toBe("No rerolls left today")
			-- the next day there's a reroll again, but not for a finished one
			Challenges.refresh(state, MONDAY + DAY)
			state.Daily[1].Done = true
			expect((Challenges.reroll(state, 1, MONDAY + DAY))).toBe(false)
			expect((Challenges.reroll(state, 9, MONDAY + DAY))).toBe(false)
		end)
	end)

	describe("achievements", function()
		it("every achievement has a unique id and a known rarity", function()
			local seen = {}
			for _, def in Achievements.LIST do
				expect(seen[def.id]).toBe(nil)
				seen[def.id] = true
				expect(table.find(Achievements.RARITIES, def.rarity) ~= nil).toBe(true)
			end
		end)

		local function has(list: { string }, id: string): boolean
			return table.find(list, id) ~= nil
		end

		it("kills", function()
			local first = Achievements.earned({ kind = "Kill", weapon = "IR", lifeKills = 1 })
			expect(has(first, "FirstBlood")).toBe(true)
			expect(has(first, "GunsOnly")).toBe(false)
			expect(has(Achievements.earned({ kind = "Kill", weapon = "Gun", lifeKills = 1 }), "GunsOnly")).toBe(true)
			expect(has(Achievements.earned({ kind = "Kill", weapon = "IR", lifeKills = 4 }), "AceInADay")).toBe(false)
			expect(has(Achievements.earned({ kind = "Kill", weapon = "IR", lifeKills = 5 }), "AceInADay")).toBe(true)
		end)

		it("wins, missiles, zones, matches and the Tempest", function()
			expect(has(Achievements.earned({ kind = "Win", hitThisMatch = true }), "Untouchable")).toBe(false)
			local clean = Achievements.earned({ kind = "Win", hitThisMatch = false })
			expect(has(clean, "Untouchable") and has(clean, "Victor")).toBe(true)
			expect(has(Achievements.earned({ kind = "MissileDefeated", weapon = "IR" }), "Notched")).toBe(false)
			expect(has(Achievements.earned({ kind = "MissileDefeated", weapon = "Radar" }), "Notched")).toBe(true)
			expect(has(Achievements.earned({ kind = "Capture" }), "ZoneHunter")).toBe(true)
			expect(#Achievements.earned({ kind = "MatchFinished", matches = 49 })).toBe(0)
			expect(has(Achievements.earned({ kind = "MatchFinished", matches = 50 }), "Veteran")).toBe(true)
			expect(has(Achievements.earned({ kind = "Spawn", airframe = "Tempest" }), "TestPilot")).toBe(true)
			expect(#Achievements.earned({ kind = "Spawn", airframe = "F5E" })).toBe(0)
		end)
	end)
end
