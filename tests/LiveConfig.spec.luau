--!strict
-- Live config (OPS-01): what can be set, and the event multipliers on match rewards.

return function(ctx)
	local describe, it, expect = ctx.describe, ctx.it, ctx.expect
	local AircraftData = require(ctx.Shared.AircraftData)
	local LiveConfig = require(ctx.Shared.LiveConfig)
	local Progression = require(ctx.Shared.Progression)

	describe("validation", function()
		it("only known keys", function()
			expect((LiveConfig.validate("economy.xp", 2))).toBe(true)
			expect((LiveConfig.validate("economy.gems", 2))).toBe(false)
			expect((LiveConfig.validate("br.NotAJet", 5))).toBe(false)
			expect((LiveConfig.validate("br.F16A", 5))).toBe(true)
		end)

		it("numbers in range, rounded to two places", function()
			local ok, value = LiveConfig.validate("economy.credits", "1.256")
			expect(ok).toBe(true)
			expect(value).toBe(1.26)
			expect((LiveConfig.validate("economy.xp", 5))).toBe(false)
			expect((LiveConfig.validate("economy.xp", 0.1))).toBe(false)
			expect((LiveConfig.validate("br.F16A", 0))).toBe(false)
			expect((LiveConfig.validate("br.F16A", "fast"))).toBe(false)
		end)

		it("text up to its limit", function()
			expect((LiveConfig.validate("event", "Double XP weekend"))).toBe(true)
			expect((LiveConfig.validate("motd", string.rep("a", 161)))).toBe(false)
			expect((LiveConfig.validate("event", 5))).toBe(false)
		end)

		it("with no override, keys have their defaults and a jet its own BR", function()
			expect(LiveConfig.get("economy.xp")).toBe(1)
			expect(LiveConfig.get("motd")).toBe("")
			expect(LiveConfig.battleRating("F16A")).toBe((AircraftData.get("F16A") :: any).BattleRating)
			expect(LiveConfig.battleRating("NotAJet")).toBe(nil)
			expect(LiveConfig.attributeName("br.F16A")).toBe("LC_br_F16A")
		end)
	end)

	describe("event multipliers", function()
		local function summary(boost: any): any
			return {
				Events = { { Kind = "Kill", Airframe = "F5E", Victim = "a", VictimAI = false } },
				LastAirframe = "F5E",
				Survived = false,
				Won = false,
				Afk = false,
				Day = 1,
				Boost = boost,
			}
		end

		it("double XP doubles XP only, with its own line", function()
			local plain = Progression.matchRewards(summary(nil), 0)
			local boosted =
				Progression.matchRewards(summary({ XP = 2, Credits = 1, RP = 1, Label = "Double XP weekend" }), 0)
			expect(boosted.XP).toBe(plain.XP * 2)
			expect(boosted.Credits).toBe(plain.Credits)
			local line = boosted.Lines[#boosted.Lines]
			expect(line.Label).toBe("Double XP weekend")
			expect(line.XP).toBe(plain.XP)
		end)

		it("multipliers of 1 add nothing", function()
			local plain = Progression.matchRewards(summary(nil), 0)
			local same = Progression.matchRewards(summary({ XP = 1, Credits = 1, RP = 1, Label = "x" }), 0)
			expect(#same.Lines).toBe(#plain.Lines)
			expect(same.XP).toBe(plain.XP)
		end)
	end)
end
