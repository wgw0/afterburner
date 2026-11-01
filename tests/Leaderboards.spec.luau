--!strict
-- LIV-05 / DAT-04: leaderboard boards, stores and scores (Shared/Leaderboards).
return function(ctx)
	local describe, it, expect = ctx.describe, ctx.it, ctx.expect
	local Leaderboards = require(ctx.Shared.Leaderboards)
	local PlayerData = require(ctx.Shared.PlayerData)
	local Progression = require(ctx.Shared.Progression)
	local Seasons = require(ctx.Shared.Config.Seasons)

	local MONDAY = 1794182400 -- Monday 9 November 2026, 00:00 UTC (Season 1 starts)

	describe("stores", function()
		it("weekly boards get a new store every Monday at 00:00 UTC", function()
			local a = Leaderboards.storeName("KillsWeek", MONDAY)
			expect(Leaderboards.storeName("KillsWeek", MONDAY + 7 * 86400 - 1)).toBe(a)
			expect(Leaderboards.storeName("KillsWeek", MONDAY - 1) ~= a).toBe(true)
			expect(Leaderboards.storeName("KillsWeek", MONDAY + 7 * 86400) ~= a).toBe(true)
		end)

		it("the season board is per season, and there's none between seasons", function()
			local s1 = Seasons.LIST[1]
			expect(Leaderboards.storeName("Season", s1.Start + 10)).toBe(`LB_Season_{s1.Id}`)
			expect(Leaderboards.storeName("Season", s1.Start - 10)).toBe(nil)
			expect(Leaderboards.storeName("KillsAll", 0)).toBe("LB_KillsAll")
		end)
	end)

	describe("scores", function()
		it("a scored match adds its kills and win to this week, and to all-time kills", function()
			local data = PlayerData.template()
			local summary = {
				Events = {
					{ Kind = "Kill", Airframe = "F5E", Victim = "a", VictimAI = true },
					{ Kind = "Kill", Airframe = "F5E", Victim = "b", VictimAI = false },
					{ Kind = "Assist", Airframe = "F5E", Victim = "c" },
				},
				Won = true,
				Afk = false,
				Survived = true,
				Day = 0,
			}
			local rewards = { XP = 0, Credits = 0, FreeRP = 0, RP = {} }
			Progression.applyRewards(data, rewards :: any, summary :: any)
			local now = os.time()
			expect(Leaderboards.score(data, "KillsWeek", now)).toBe(2)
			expect(Leaderboards.score(data, "WinsWeek", now)).toBe(1)
			expect(Leaderboards.score(data, "KillsAll", now)).toBe(2)
		end)

		it("last week's counts don't count this week, and a new week starts from zero", function()
			local data = PlayerData.template()
			Leaderboards.record(data, 5, true, MONDAY)
			expect(Leaderboards.score(data, "KillsWeek", MONDAY + 7 * 86400)).toBe(0)
			Leaderboards.record(data, 1, false, MONDAY + 7 * 86400)
			expect(Leaderboards.score(data, "KillsWeek", MONDAY + 7 * 86400)).toBe(1)
			expect(Leaderboards.score(data, "WinsWeek", MONDAY + 7 * 86400)).toBe(0)
		end)

		it("an AFK player's win doesn't count", function()
			local data = PlayerData.template()
			local summary = { Events = {}, Won = true, Afk = true, Survived = true, Day = 0 }
			Progression.applyRewards(data, { XP = 0, Credits = 0, FreeRP = 0, RP = {} } :: any, summary :: any)
			expect(Leaderboards.score(data, "WinsWeek", os.time())).toBe(0)
		end)

		it("season XP counts only for the season running", function()
			local data = PlayerData.template()
			local s1 = Seasons.LIST[1]
			data.Season = { Id = s1.Id, XP = 4321, Premium = false, FreeClaimed = 0, PremiumClaimed = 0 }
			expect(Leaderboards.score(data, "Season", s1.Start + 10)).toBe(4321)
			expect(Leaderboards.score(data, "Season", s1.End + 10)).toBe(0)
		end)
	end)
end
