--!strict
-- LIV-06: squadron rules (Shared/Squadron).
return function(ctx)
	local describe, it, expect = ctx.describe, ctx.it, ctx.expect
	local Leaderboards = require(ctx.Shared.Leaderboards)
	local PlayerData = require(ctx.Shared.PlayerData)
	local Squadron = require(ctx.Shared.Squadron)

	local function squad(open: boolean?): Squadron.Record
		return Squadron.new("abc", "Night Owls", "NOWL", 1, open ~= false, 100)
	end

	describe("names and tags", function()
		it("tidies names and refuses odd ones", function()
			expect(Squadron.cleanName("  Night   Owls ")).toBe("Night Owls")
			expect((Squadron.cleanName("NO"))).toBe(nil)
			expect((Squadron.cleanName("Owls!"))).toBe(nil)
			expect((Squadron.cleanName("1234"))).toBe(nil)
		end)

		it("tags are 2-4 letters or numbers, in capitals", function()
			expect(Squadron.cleanTag("ace")).toBe("ACE")
			expect(Squadron.cleanTag("x7")).toBe("X7")
			expect((Squadron.cleanTag("A"))).toBe(nil)
			expect((Squadron.cleanTag("TOOLONG"))).toBe(nil)
			expect((Squadron.cleanTag("A-B"))).toBe(nil)
		end)
	end)

	describe("membership", function()
		it("an open squadron takes anyone, an invite-only one needs an invite, never past MAX", function()
			local s = squad()
			expect((Squadron.join(s, 2, false, 101))).toBe(true)
			expect((Squadron.join(s, 2, false, 101))).toBe(false) -- already in
			local closed = squad(false)
			expect((Squadron.join(closed, 3, false, 101))).toBe(false)
			expect((Squadron.join(closed, 3, true, 101))).toBe(true)
			for userId = 10, 9 + Squadron.MAX_MEMBERS do
				Squadron.join(s, userId, true, 102)
			end
			expect(Squadron.count(s)).toBe(Squadron.MAX_MEMBERS)
		end)

		it("a leaving owner hands over to an officer first, else the longest-standing member", function()
			local s = squad()
			Squadron.join(s, 2, false, 101)
			Squadron.join(s, 3, false, 102)
			Squadron.setRole(s, 1, 3, "Officer")
			expect(Squadron.leave(s, 1)).toBe(true)
			expect(s.owner).toBe(3)
			expect(Squadron.roleOf(s, 3)).toBe("Owner")
			local t = squad()
			Squadron.join(t, 5, false, 103)
			Squadron.join(t, 4, false, 102)
			Squadron.leave(t, 1)
			expect(t.owner).toBe(4)
		end)

		it("the last one out disbands it", function()
			local s = squad()
			expect(Squadron.leave(s, 1)).toBe(false)
		end)

		it("only the owner sets roles; officers can remove members but not officers or the owner", function()
			local s = squad()
			Squadron.join(s, 2, false, 101)
			Squadron.join(s, 3, false, 102)
			expect((Squadron.setRole(s, 2, 3, "Officer"))).toBe(false)
			Squadron.setRole(s, 1, 2, "Officer")
			Squadron.join(s, 4, false, 103)
			Squadron.setRole(s, 1, 4, "Officer")
			expect((Squadron.kick(s, 2, 1))).toBe(false)
			expect((Squadron.kick(s, 2, 4))).toBe(false)
			expect((Squadron.kick(s, 2, 3))).toBe(true)
			expect((Squadron.kick(s, 1, 4))).toBe(true)
		end)

		it("handing over ownership makes the old owner an officer", function()
			local s = squad()
			Squadron.join(s, 2, false, 101)
			Squadron.setRole(s, 1, 2, "Owner")
			expect(s.owner).toBe(2)
			expect(Squadron.roleOf(s, 1)).toBe("Officer")
		end)

		it("a stored record is read back safely", function()
			expect(Squadron.clean({ id = "x" })).toBe(nil)
			local clean =
				Squadron.clean({ id = "x", tag = "AB", members = { ["5"] = { role = "Boss" }, bad = {} } }) :: any
			expect(clean.members["5"].role).toBe("Member")
			expect(clean.members.bad).toBe(nil)
		end)
	end)

	describe("weekly points", function()
		it("player kills and wins earn points; the board is weekly", function()
			expect(Squadron.points(3, true)).toBe(3 * Squadron.POINTS.kill + Squadron.POINTS.win)
			expect(Squadron.points(0, false)).toBe(0)
			local board = Leaderboards.get("SquadronWeek") :: any
			expect(board.squadron).toBe(true)
			local monday = 1794182400
			expect(
				Leaderboards.storeName("SquadronWeek", monday)
					~= Leaderboards.storeName("SquadronWeek", monday + 7 * 86400)
			).toBe(true)
			expect(Leaderboards.score(PlayerData.template(), "SquadronWeek", monday)).toBe(0)
		end)
	end)
end
