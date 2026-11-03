--!strict
-- The friends bonus (Shared/Social, Config/Social; DEVELOPMENT.md §25.8): who gets it, that it reaches match
-- rewards as its own line (Credits and XP, never RP), and that nothing pays for likes or favourites
-- (docs/COMPLIANCE.md §8).
return function(ctx)
	local describe, it, expect = ctx.describe, ctx.it, ctx.expect
	local Config = require(ctx.Shared.Config.Social)
	local Economy = require(ctx.Shared.Config.Economy)
	local Progression = require(ctx.Shared.Progression)
	local Social = require(ctx.Shared.Social)

	local function summary(social: { Social.Bonus }?): Progression.MatchSummary
		return {
			Events = { { Kind = "Kill", Airframe = "F5E", Victim = "p1" } },
			LastAirframe = "F5E",
			Survived = false,
			Won = false,
			Afk = false,
			Day = 1,
			Social = social,
		}
	end

	describe("config", function()
		it("the bonus is small and pays only Credits and XP", function()
			local bonus = Config.FRIENDS :: any
			expect(bonus.XP >= 1 and bonus.XP <= 1.25).toBe(true)
			expect(bonus.Credits >= 1 and bonus.Credits <= 1.25).toBe(true)
			expect(bonus.RP).toBe(nil)
			expect(Social.percent(Config.FRIENDS)).toBe("+10%")
		end)

		it("nothing rewards likes, upvotes, favourites or group joins", function()
			for key in Config :: any do
				local name = string.lower(key)
				for _, word in { "like", "favo", "vote", "group" } do
					expect(string.find(name, word)).toBe(nil)
				end
			end
		end)
	end)

	describe("who gets it", function()
		it("a friend here, or a party member here", function()
			local friends = { [Social.pairKey(1, 2)] = true }
			expect(Social.withFriends(1, { 1, 2, 3 }, friends, nil)).toBe(true)
			expect(Social.withFriends(2, { 1, 2 }, friends, nil)).toBe(true) -- friends both ways
			expect(Social.withFriends(3, { 1, 2, 3 }, friends, nil)).toBe(false)
			expect(Social.withFriends(1, { 1, 3 }, friends, nil)).toBe(false) -- the friend isn't here
			expect(Social.withFriends(3, { 1, 2, 3, 4 }, {}, { { 3, 4 } })).toBe(true)
			expect(Social.withFriends(3, { 1, 2, 3 }, {}, { { 3, 4 } })).toBe(false) -- party mate left
			expect(Social.withFriends(1, { 1 }, friends, { { 1 } })).toBe(false) -- yourself doesn't count
		end)

		it("the bonus list: one entry with friends, none without", function()
			expect(#Social.bonuses(false)).toBe(0)
			local list = Social.bonuses(true)
			expect(#list).toBe(1)
			expect(list[1].Label).toBe(Social.FRIENDS_LABEL)
		end)
	end)

	describe("match rewards", function()
		it("its own line, +10% Credits and XP, RP untouched", function()
			local plain = Progression.matchRewards(summary(nil), 0)
			local boosted = Progression.matchRewards(summary(Social.bonuses(true)), 0)
			local found
			for _, line in boosted.Lines do
				if line.Label == Social.FRIENDS_LABEL then
					found = line
				end
			end
			expect(found ~= nil).toBe(true)
			expect(found.RP).toBe(0)
			expect(boosted.Credits).toBe(math.floor(plain.Credits * Config.FRIENDS.Credits + 0.5))
			expect(boosted.XP).toBe(math.floor(plain.XP * Config.FRIENDS.XP + 0.5))
			expect(boosted.RP.F5E).toBe(plain.RP.F5E)
			expect(boosted.FreeRP).toBe(plain.FreeRP)
		end)

		it("no bonus, no line", function()
			local r = Progression.matchRewards(summary({}), 0)
			for _, line in r.Lines do
				expect(line.Label ~= Social.FRIENDS_LABEL).toBe(true)
			end
			expect(r.Credits).toBe(Economy.ACTIONS.Kill.Credits + Economy.ACTIONS.Participation.Credits)
		end)
	end)
end
