--!strict
-- Achievement rewards and ranked series (Shared/Achievements; Will: always something new to earn).
return function(ctx)
	local describe, it, expect = ctx.describe, ctx.it, ctx.expect
	local Achievements = require(ctx.Shared.Achievements)
	local PlayerData = require(ctx.Shared.PlayerData)
	local Progression = require(ctx.Shared.Progression)

	local function has(list: { string }, id: string): boolean
		return table.find(list, id) ~= nil
	end

	describe("rewards", function()
		it("every achievement pays, and rarer ones pay more", function()
			local last = 0
			for _, rarity in Achievements.RARITIES do
				local reward = Achievements.REWARDS[rarity]
				expect(reward ~= nil and reward.credits > last).toBe(true)
				last = reward.credits
			end
			for _, def in Achievements.LIST do
				expect(Achievements.reward(def).credits > 0).toBe(true)
			end
		end)
	end)

	describe("series", function()
		it("every series has rising targets, a level per target, and gets rarer as it climbs", function()
			for _, series in Achievements.SERIES do
				local levels = Achievements.seriesLevels(series.id)
				expect(#levels).toBe(#series.levels)
				for i = 2, #levels do
					expect(levels[i].target > levels[i - 1].target).toBe(true)
					local a = table.find(Achievements.RARITIES, levels[i - 1].rarity) :: number
					local b = table.find(Achievements.RARITIES, levels[i].rarity) :: number
					expect(b >= a).toBe(true)
				end
				expect(levels[#levels].rarity).toBe("Legendary")
			end
		end)

		it("ids are unique across every achievement", function()
			local seen = {}
			for _, def in Achievements.LIST do
				expect(seen[def.id]).toBe(nil)
				seen[def.id] = true
			end
		end)

		it("a career reaching a target earns that level and the ones below it", function()
			local earned = Achievements.earned({ kind = "Career", totalKills = 60 })
			expect(has(earned, "Hunter1") and has(earned, "Hunter2") and has(earned, "Hunter3")).toBe(true)
			expect(has(earned, "Hunter4")).toBe(false)
			local tiers = Achievements.earned({ kind = "Career", topTier = 3 })
			expect(has(tiers, "Promotion1") and has(tiers, "Promotion2")).toBe(true)
			expect(has(tiers, "Promotion3")).toBe(false)
		end)

		it("matches count assists, missiles defeated and captures for the series", function()
			local data = PlayerData.template()
			local summary = {
				Events = {
					{ Kind = "Assist", Airframe = "F5E" },
					{ Kind = "MissileDefeated", Airframe = "F5E" },
					{ Kind = "ZoneCaptured", Airframe = "F5E" },
				},
				Won = true,
				Afk = false,
				Survived = true,
				Day = 0,
			}
			Progression.applyRewards(data, { XP = 0, Credits = 0, FreeRP = 0, RP = {} } :: any, summary :: any)
			local career = Achievements.career(data)
			expect(career.assists).toBe(1)
			expect(career.missilesDefeated).toBe(1)
			expect(career.captures).toBe(1)
			expect(career.wins).toBe(1)
			expect(career.topTier).toBe(1)
		end)

		it("full access earns no hangar series", function()
			local data = PlayerData.template()
			data.Flags.AllUnlocked = true
			local career = Achievements.career(data)
			expect(career.ownedJets).toBe(0)
			expect(career.topTier).toBe(1)
			expect(career.modulesFitted).toBe(0)
		end)
	end)
end
