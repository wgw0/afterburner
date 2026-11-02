--!strict
-- Aircraft mastery (PRG-07).

return function(ctx)
	local describe, it, expect = ctx.describe, ctx.it, ctx.expect
	local Mastery = require(ctx.Shared.Mastery)
	local LevelRewards = require(ctx.Shared.Config.LevelRewards)
	local PlayerData = require(ctx.Shared.PlayerData)
	local Progression = require(ctx.Shared.Progression)
	local Skins = require(ctx.Shared.Skins)

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

	describe("rewards", function()
		it("unlock the charm at 3 stars and the Ace Mastery livery at 4", function()
			expect(Mastery.unlockText(Mastery.TRINKET_STARS)).toBe("Gold wings charm in the cockpit")
			expect(Mastery.unlockText(Mastery.CAMO_STARS)).toBe("Ace Mastery livery")
			expect(Mastery.unlockText(1)).toBe(nil)
		end)

		it("the livery is owned from 4 stars on that jet, and never sold", function()
			-- Stand in for the installed paint if this place doesn't have it
			local ReplicatedStorage = game:GetService("ReplicatedStorage")
			local assets = ReplicatedStorage:FindFirstChild("Assets") or Instance.new("Folder")
			assets.Name = "Assets"
			assets.Parent = ReplicatedStorage
			local skins = assets:FindFirstChild("Skins") or Instance.new("Folder")
			skins.Name = "Skins"
			skins.Parent = assets
			local jet = skins:FindFirstChild("F5E") or Instance.new("Folder")
			jet.Name = "F5E"
			jet.Parent = skins
			local made = nil
			if not jet:FindFirstChild(Mastery.CAMO_ID) then
				made = Instance.new("Folder")
				made.Name = Mastery.CAMO_ID
				made.Parent = jet
			end

			local skin = Skins.get("F5E", Mastery.CAMO_ID)
			expect(skin ~= nil).toBe(true)
			expect(Skins.wingsPrice(skin :: any)).toBe(nil)
			local data = PlayerData.template()
			data.Aircraft.F5E.Mastery = Mastery.STARS[Mastery.CAMO_STARS] - 1
			expect(Progression.ownsSkin(data, "F5E", Mastery.CAMO_ID)).toBe(false)
			local ok, reason = Progression.canBuySkin(data, "F5E", Mastery.CAMO_ID)
			expect(ok).toBe(false)
			expect(reason).toBe("Unlocks at 4★ mastery in this jet")
			data.Aircraft.F5E.Mastery += 1
			expect(Progression.ownsSkin(data, "F5E", Mastery.CAMO_ID)).toBe(true)
			if made then
				made:Destroy()
			end
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
