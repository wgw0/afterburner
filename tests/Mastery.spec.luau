--!strict
-- Aircraft mastery (PRG-07).

return function(ctx)
	local describe, it, expect = ctx.describe, ctx.it, ctx.expect
	local Mastery = require(ctx.Shared.Mastery)
	local LevelRewards = require(ctx.Shared.Config.LevelRewards)
	local PlayerData = require(ctx.Shared.PlayerData)

	local function kill(airframe: string, victim: string): any
		return { Kind = "Kill", Airframe = airframe, Victim = victim, VictimAI = true }
	end

	describe("stars", function()
		it("follow the kill thresholds", function()
			expect(Mastery.stars(0)).toBe(0)
			expect(Mastery.stars(4)).toBe(0)
			expect(Mastery.stars(5)).toBe(1)
			expect(Mastery.stars(39)).toBe(2)
			expect(Mastery.stars(150)).toBe(5)
			expect(Mastery.stars(9999)).toBe(5)
		end)

		it("progress counts from the last star to the next", function()
			local into, needed = Mastery.progress(20)
			expect(into).toBe(5)
			expect(needed).toBe(25)
			expect((Mastery.progress(150))).toBe(nil)
			expect(Mastery.starText(2)).toBe("★★☆☆☆")
		end)
	end)

	describe("counting kills", function()
		it("counts kills per jet, the same victim only up to the full-reward limit", function()
			local events = {
				kill("F5E", "a"),
				kill("F5E", "a"),
				kill("F5E", "a"),
				kill("F5E", "a"),
				kill("MiG21bis", "b"),
				{ Kind = "Assist", Airframe = "F5E" },
			}
			local perJet = Mastery.countKills(events)
			expect(perJet.F5E).toBe(3)
			expect(perJet.MiG21bis).toBe(1)
		end)
	end)

	describe("record", function()
		it("adds kills, pays each star reached once, and gives the title at 5 stars", function()
			local data = PlayerData.template()
			data.Credits = 0
			data.Aircraft.F5E.Mastery = 3
			local events = {}
			for i = 1, 3 do
				table.insert(events, kill("F5E", `v{i}`))
			end
			local gains = Mastery.record(data, events)
			expect(data.Aircraft.F5E.Mastery).toBe(6)
			expect(#gains).toBe(1)
			expect(gains[1].Stars).toBe(1)
			expect(data.Credits).toBe(Mastery.CREDITS[1])

			data.Aircraft.F5E.Mastery = 148
			local more = Mastery.record(data, { kill("F5E", "x"), kill("F5E", "y") })
			expect(#more).toBe(1)
			expect(more[1].Stars).toBe(5)
			expect(more[1].Title).toBe("Mastery:F5E")
			expect(data.Titles["Mastery:F5E"]).toBe(true)
		end)

		it("ignores jets not in the save", function()
			local data = PlayerData.template()
			local gains = Mastery.record(data, { kill("NotAJet", "a") })
			expect(#gains).toBe(0)
		end)
	end)

	describe("titles", function()
		it("names mastery titles, and they can be worn once earned", function()
			expect(LevelRewards.titleName("Mastery:F14A")).toBe("Tomcat Ace")
			expect(LevelRewards.titleName("Mastery:Nope")).toBe(nil)
			expect(LevelRewards.titleUnlocked("Mastery:F14A", 1, false, {})).toBe(false)
			expect(LevelRewards.titleUnlocked("Mastery:F14A", 1, false, { ["Mastery:F14A"] = true })).toBe(true)
			expect(LevelRewards.titleUnlocked("Mastery:Nope", 1, false, { ["Mastery:Nope"] = true })).toBe(false)
		end)
	end)
end
