--!strict
-- Pilot level rewards (PRG-03 / the Career level track) and the newer achievements (LIV-02).

return function(ctx)
	local describe, it, expect = ctx.describe, ctx.it, ctx.expect
	local Achievements = require(ctx.Shared.Achievements)
	local Economy = require(ctx.Shared.Config.Economy)
	local LevelRewards = require(ctx.Shared.Config.LevelRewards)
	local PlayerData = require(ctx.Shared.PlayerData)
	local Progression = require(ctx.Shared.Progression)

	describe("milestones", function()
		it("are in level order, within the level range, and include the lineup slots", function()
			local last, slots = 0, 0
			for _, milestone in LevelRewards.MILESTONES do
				expect(milestone.Level >= last).toBe(true)
				expect(milestone.Level >= 2 and milestone.Level <= Economy.MAX_LEVEL).toBe(true)
				last = milestone.Level
				if milestone.Kind == "Slot" then
					slots += 1
				end
			end
			expect(slots).toBe(#Economy.LINEUP_SLOTS - 1)
		end)

		it("every title, skin and HUD colour named in a milestone is defined", function()
			local skins = {}
			for _, skin in LevelRewards.SKINS do
				skins[skin.Id] = skin.Level
			end
			for _, milestone in LevelRewards.MILESTONES do
				if milestone.Kind == "Title" then
					expect(LevelRewards.TITLES[milestone.Id :: string] ~= nil).toBe(true)
				elseif milestone.Kind == "Skin" then
					expect(skins[milestone.Id :: string]).toBe(milestone.Level)
				elseif milestone.Kind == "HUDColour" then
					expect(LevelRewards.HUD_COLOURS[milestone.Id :: string]).toBe(milestone.Level)
				end
			end
		end)

		it("groups by level for the track", function()
			local groups = LevelRewards.byLevel()
			local seen = {}
			for _, group in groups do
				expect(seen[group.Level]).toBe(nil)
				seen[group.Level] = true
				expect(#group.Rewards >= 1).toBe(true)
			end
		end)

		it("titles unlock with level; no title is always allowed", function()
			expect(LevelRewards.titleUnlocked("", 1)).toBe(true)
			expect(LevelRewards.titleUnlocked("Wingman", 2)).toBe(false)
			expect(LevelRewards.titleUnlocked("Wingman", 3)).toBe(true)
			expect(LevelRewards.titleUnlocked("AirMarshal", 50)).toBe(false)
			expect(LevelRewards.titleUnlocked("AirMarshal", 1, true)).toBe(true)
			expect(LevelRewards.titleUnlocked("Emperor", 100)).toBe(false)
		end)
	end)

	describe("paying milestones", function()
		it("pays Credits and Free RP once each, levels skipped included", function()
			local data = PlayerData.template()
			data.PilotLevel = 1
			local credits, rp = data.Credits, data.FreeRP
			expect(#Progression.claimLevelRewards(data)).toBe(0)
			-- Straight to level 12: the level 2 Credits and the level 12 Free RP
			data.PilotLevel = 12
			local paid = Progression.claimLevelRewards(data)
			expect(#paid).toBe(2)
			expect(data.Credits).toBe(credits + 1000)
			expect(data.FreeRP).toBe(rp + 3000)
			-- Not again
			expect(#Progression.claimLevelRewards(data)).toBe(0)
			expect(data.Credits).toBe(credits + 1000)
		end)

		it("levelling up through addXP pays them too", function()
			local data = PlayerData.template()
			local credits = data.Credits
			local xp = 0
			for level = 1, 2 do
				xp += Economy.xpToNext(level)
			end
			local gained = Progression.addXP(data, xp)
			expect(gained).toBe(2)
			expect(data.PilotLevel).toBe(3)
			expect(data.Credits).toBe(credits + 2 * Economy.LEVEL_CREDITS + 1000)
			expect(data.LevelRewardsClaimed).toBe(3)
		end)
	end)

	describe("level skins", function()
		it("can't be bought, and are owned from their level", function()
			local data = PlayerData.template()
			local skin = LevelRewards.SKINS[1]
			-- Whether or not its paint is installed yet, the rule is the level
			data.PilotLevel = skin.Level - 1
			local ok = Progression.canBuySkin(data, "F5E", skin.Id)
			expect(ok).toBe(false)
		end)
	end)

	describe("newer achievements", function()
		local function has(list: { string }, id: string): boolean
			return table.find(list, id) ~= nil
		end

		it("Fox One / Fox Three by missile class", function()
			expect(has(Achievements.earned({ kind = "Kill", weapon = "Radar", missileClass = "SARH" }), "FoxOne")).toBe(
				true
			)
			expect(has(Achievements.earned({ kind = "Kill", weapon = "Radar", missileClass = "ARH" }), "FoxThree")).toBe(
				true
			)
			expect(has(Achievements.earned({ kind = "Kill", weapon = "IR", missileClass = "IR_All" }), "FoxThree")).toBe(
				false
			)
		end)

		it("kills in a life and in quick succession", function()
			expect(has(Achievements.earned({ kind = "Kill", lifeKills = 2 }), "HatTrick")).toBe(false)
			expect(has(Achievements.earned({ kind = "Kill", lifeKills = 3 }), "HatTrick")).toBe(true)
			expect(has(Achievements.earned({ kind = "Kill", sinceLastKill = 8 }), "DoubleTrouble")).toBe(true)
			expect(has(Achievements.earned({ kind = "Kill", sinceLastKill = 12 }), "DoubleTrouble")).toBe(false)
			expect(has(Achievements.earned({ kind = "Kill" }), "DoubleTrouble")).toBe(false)
		end)

		it("match results", function()
			local flawless = Achievements.earned({ kind = "MatchFinished", survived = true, matchKills = 3 })
			expect(has(flawless, "Flawless")).toBe(true)
			expect(has(Achievements.earned({ kind = "MatchFinished", survived = false, matchKills = 5 }), "Flawless")).toBe(
				false
			)
			expect(has(Achievements.earned({ kind = "MatchFinished", matchAssists = 3 }), "TeamPlayer")).toBe(true)
			expect(has(Achievements.earned({ kind = "MatchFinished", firstFreeForAll = true }), "TopOfTheTable")).toBe(
				true
			)
			expect(has(Achievements.earned({ kind = "MissileDefeated", lifeDefeats = 3 }), "EscapeArtist")).toBe(true)
		end)

		it("career totals, at the end of a match or on joining", function()
			local career =
				Achievements.earned({ kind = "Career", matches = 50, totalKills = 100, ownedJets = 10, level = 25 })
			for _, id in { "Veteran", "Centurion", "Collector", "HighFlyer" } do
				expect(has(career, id)).toBe(true)
			end
			expect(#Achievements.earned({ kind = "Career", matches = 49, totalKills = 99, ownedJets = 9, level = 24 })).toBe(
				0
			)
			local visible = 0
			for _, def in Achievements.LIST do
				if not def.secret then
					visible += 1
				end
			end
			expect(visible).toBe(31)
			expect(table.find(Achievements.earned({ kind = "BridgeRun" }), "ThreadTheNeedle") ~= nil).toBe(true)
		end)
	end)
end
