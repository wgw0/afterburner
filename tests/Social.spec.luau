--!strict
-- The group and friends bonuses (Shared/Social, Config/Social; DEVELOPMENT.md §25.8): who gets them, that they
-- reach match rewards as their own lines (Credits and XP, never RP), and that nothing pays for likes or
-- favourites (docs/COMPLIANCE.md §8).
return function(ctx)
	local describe, it, expect = ctx.describe, ctx.it, ctx.expect
	local Config = require(ctx.Shared.Config.Social)
	local Economy = require(ctx.Shared.Config.Economy)
	local Progression = require(ctx.Shared.Progression)
	local Social = require(ctx.Shared.Social)

	-- Runs fn with a group id set, then puts Config back the way it was
	local function withGroup(fn: () -> ())
		local before = Config.GROUP_ID
		Config.GROUP_ID = 123456
		local ok, err = pcall(fn)
		Config.GROUP_ID = before
		if not ok then
			error(err, 0)
		end
	end

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
		it("the group bonus is off until Will gives the group id", function()
			expect(Config.GROUP_ID).toBe(nil)
			expect(Social.groupOn()).toBe(false)
			expect(#Social.bonuses(true, false)).toBe(0)
		end)

		it("both bonuses are small and pay only Credits and XP", function()
			for _, bonus in { Config.GROUP, Config.FRIENDS } :: { any } do
				expect(bonus.XP >= 1 and bonus.XP <= 1.25).toBe(true)
				expect(bonus.Credits >= 1 and bonus.Credits <= 1.25).toBe(true)
				expect(bonus.RP).toBe(nil)
			end
			expect(Social.percent(Config.FRIENDS)).toBe("+10%")
		end)

		it("nothing rewards likes, upvotes or favourites", function()
			for key in Config :: any do
				local name = string.lower(key)
				expect(string.find(name, "like") or string.find(name, "favo") or string.find(name, "vote")).toBe(nil)
			end
		end)
	end)

	describe("who gets them", function()
		it("the group bonus once there's a group and the player is in it", function()
			withGroup(function()
				expect(Social.groupOn()).toBe(true)
				local list = Social.bonuses(true, false)
				expect(#list).toBe(1)
				expect(list[1].Label).toBe(Social.GROUP_LABEL)
				expect(#Social.bonuses(false, false)).toBe(0)
				expect(#Social.bonuses(true, true)).toBe(2)
			end)
		end)

		it("the friends bonus: a friend here, or a party member here", function()
			local friends = { [Social.pairKey(1, 2)] = true }
			expect(Social.withFriends(1, { 1, 2, 3 }, friends, nil)).toBe(true)
			expect(Social.withFriends(2, { 1, 2 }, friends, nil)).toBe(true) -- friends both ways
			expect(Social.withFriends(3, { 1, 2, 3 }, friends, nil)).toBe(false)
			expect(Social.withFriends(1, { 1, 3 }, friends, nil)).toBe(false) -- the friend isn't here
			expect(Social.withFriends(3, { 1, 2, 3, 4 }, {}, { { 3, 4 } })).toBe(true)
			expect(Social.withFriends(3, { 1, 2, 3 }, {}, { { 3, 4 } })).toBe(false) -- party mate left
			expect(Social.withFriends(1, { 1 }, friends, { { 1 } })).toBe(false) -- yourself doesn't count
		end)
	end)

	describe("match rewards", function()
		it("a line each, +10% Credits and XP, RP untouched", function()
			withGroup(function()
				local plain = Progression.matchRewards(summary(nil), 0)
				local boosted = Progression.matchRewards(summary(Social.bonuses(true, true)), 0)
				local labels = {}
				for _, line in boosted.Lines do
					labels[line.Label] = line
				end
				expect(labels[Social.GROUP_LABEL] ~= nil).toBe(true)
				expect(labels[Social.FRIENDS_LABEL] ~= nil).toBe(true)
				expect(labels[Social.GROUP_LABEL].RP).toBe(0)
				local factor = Config.GROUP.Credits * Config.FRIENDS.Credits
				expect(boosted.Credits).toBe(math.floor(plain.Credits * factor + 0.5))
				expect(boosted.XP).toBe(math.floor(plain.XP * Config.GROUP.XP * Config.FRIENDS.XP + 0.5))
				expect(boosted.RP.F5E).toBe(plain.RP.F5E)
				expect(boosted.FreeRP).toBe(plain.FreeRP)
			end)
		end)

		it("no bonuses, no lines", function()
			local r = Progression.matchRewards(summary({}), 0)
			for _, line in r.Lines do
				expect(line.Label ~= Social.GROUP_LABEL and line.Label ~= Social.FRIENDS_LABEL).toBe(true)
			end
			local base = Economy.ACTIONS.Kill.Credits + Economy.ACTIONS.Participation.Credits
			expect(r.Credits).toBe(base)
		end)
	end)
end
