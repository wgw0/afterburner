--!strict
-- MMK-05: parties (Shared/Party) and how the queue treats them (Shared/Queue).
return function(ctx)
	local describe, it, expect = ctx.describe, ctx.it, ctx.expect
	local Party = require(ctx.Shared.Party)
	local Queue = require(ctx.Shared.Queue)

	local T = 1000

	local function party(...: number)
		local s = Party.new()
		local ids = { ... }
		for i = 2, #ids do
			assert(Party.invite(s, ids[1], ids[i], T))
			assert(Party.accept(s, ids[i], ids[1], T))
		end
		return s
	end

	describe("inviting and joining", function()
		it("accepting makes a party led by the inviter", function()
			local s = Party.new()
			expect((Party.invite(s, 1, 2, T))).toBe(true)
			expect(Party.invitesFor(s, 2, T)[1]).toBe(1)
			expect(Party.accept(s, 2, 1, T)).toBe(1)
			expect(Party.leaderOf(s, 2)).toBe(1)
			expect(#Party.membersOf(s, 1)).toBe(2)
			expect(Party.membersOf(s, 1)[1]).toBe(1) -- leader first
		end)

		it("invites run out", function()
			local s = Party.new()
			Party.invite(s, 1, 2, T)
			expect(#Party.invitesFor(s, 2, T + Party.INVITE_TTL + 1)).toBe(0)
			expect((Party.accept(s, 2, 1, T + Party.INVITE_TTL + 1))).toBe(nil)
		end)

		it("only the leader invites, nobody already in a party is invited, and never past MAX", function()
			local s = party(1, 2)
			expect((Party.invite(s, 2, 3, T))).toBe(false) -- not the leader
			expect((Party.invite(s, 3, 2, T))).toBe(false) -- already in a party
			expect((Party.invite(s, 1, 1, T))).toBe(false)
			local full = party(1, 2, 3)
			expect(#Party.membersOf(full, 1)).toBe(Party.MAX)
			expect((Party.invite(full, 1, 4, T))).toBe(false)
		end)

		it("a party filled while an invite waited can't be joined", function()
			local s = party(1, 2)
			Party.invite(s, 1, 3, T)
			Party.invite(s, 1, 4, T)
			expect(Party.accept(s, 3, 1, T)).toBe(1)
			expect((Party.accept(s, 4, 1, T))).toBe(nil)
		end)

		it("joining a party drops your other invites", function()
			local s = Party.new()
			Party.invite(s, 1, 3, T)
			Party.invite(s, 2, 3, T)
			Party.accept(s, 3, 1, T)
			expect(#Party.invitesFor(s, 3, T)).toBe(0)
		end)
	end)

	describe("leaving", function()
		it("the rest carry on; a party of one is no party", function()
			local s = party(1, 2, 3)
			expect(Party.leave(s, 3)).toBe(1)
			expect(#Party.membersOf(s, 1)).toBe(2)
			expect(Party.leave(s, 2)).toBe(nil)
			expect(Party.leaderOf(s, 1)).toBe(nil)
		end)

		it("the longest-standing member takes over from a leader who leaves", function()
			local s = party(1, 2, 3)
			expect(Party.leave(s, 1)).toBe(2)
			expect(Party.leaderOf(s, 3)).toBe(2)
			expect(Party.membersOf(s, 3)[1]).toBe(2)
		end)

		it("only the leader removes someone", function()
			local s = party(1, 2, 3)
			expect((Party.kick(s, 2, 3))).toBe(false)
			expect((Party.kick(s, 1, 3))).toBe(true)
			expect(Party.leaderOf(s, 3)).toBe(nil)
		end)

		it("is put back together after a match, with whoever made it", function()
			local s = Party.new()
			expect(Party.restore(s, 1, { 1, 2, 3 })).toBe(1)
			expect(#Party.membersOf(s, 3)).toBe(3)
			local t = Party.new()
			expect(Party.restore(t, 1, { 1 })).toBe(nil) -- nobody else came back
		end)
	end)

	describe("teams", function()
		it("keep each party together and the sides as even as they can be", function()
			local teams = Party.splitTeams({ { 1, 2, 3 }, { 4 }, { 5, 6 } }, { "West", "East" })
			expect(teams[1]).toBe(teams[2])
			expect(teams[2]).toBe(teams[3])
			expect(teams[5]).toBe(teams[6])
			expect(teams[5] ~= teams[1]).toBe(true)
			expect(teams[4]).toBe(teams[5]) -- 3 against 3
		end)
	end)

	describe("queueing as a party", function()
		local function entry(userId: number, br: number, joinedAt: number, members: { number }?): any
			return { userId = userId, br = br, mode = "Any", joinedAt = joinedAt, jobId = "J", members = members }
		end

		it("a party takes a seat per member and comes in whole or not at all", function()
			local matches = Queue.form({
				entry(1, 3, 0, { 1, 2, 3 }),
				entry(4, 3, 1, { 4, 5, 6 }),
				entry(7, 3, 2),
			}, { now = 5 })
			expect(#matches).toBe(1)
			expect(matches[1].players).toBe(6)
			expect(#matches[1].entries).toBe(2) -- the solo pilot waits for the next one
		end)

		it("a party that doesn't fit the seats left is skipped, not split", function()
			local matches = Queue.form({
				entry(1, 3, 0, { 1, 2, 3 }),
				entry(4, 3, 1),
				entry(5, 3, 2),
				entry(6, 3, 3, { 6, 7, 8 }),
			}, { now = 100 })
			local first = matches[1]
			expect(first.players).toBe(5)
			for _, e in first.entries do
				expect(e.userId ~= 6).toBe(true)
			end
		end)

		it("everyone in an entry is listed", function()
			expect(#Queue.users(entry(1, 3, 0, { 1, 2 }))).toBe(2)
			expect(Queue.users(entry(9, 3, 0))[1]).toBe(9)
			expect(Queue.seats(entry(9, 3, 0))).toBe(1)
		end)
	end)
end
