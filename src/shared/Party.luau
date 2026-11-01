--!strict
-- Parties (MMK-05; DEVELOPMENT.md §25.3): up to MAX pilots on one lobby server who queue as one and fly
-- on the same team. Pure: PartyService keeps one State per lobby server and the tests drive it directly.
--   A solo pilot (or a party's leader) invites someone who isn't in a party; the invite lasts INVITE_TTL
--   seconds. Accepting makes a party (the inviter leads) or joins theirs, if there's room.
--   Leaving: the rest carry on; if the leader leaves, the longest-standing member leads; a party of one is no
--   party. The leader can remove a member.

local Party = {}

Party.MAX = 3 -- so two parties always fit a 6-pilot match
Party.INVITE_TTL = 60

export type Group = { leader: number, members: { number } } -- members in joining order, leader first

export type State = {
	parties: { [number]: Group }, -- by leader
	of: { [number]: number }, -- member (leader too) → leader
	invites: { [number]: { [number]: number } }, -- invitee → { inviter → expires }
}

function Party.new(): State
	return { parties = {}, of = {}, invites = {} }
end

-- The leader of the player's party, or nil if they're on their own.
function Party.leaderOf(s: State, userId: number): number?
	return s.of[userId]
end

-- Everyone in the player's party, leader first ({ userId } on their own).
function Party.membersOf(s: State, userId: number): { number }
	local leader = s.of[userId]
	if not leader then
		return { userId }
	end
	return table.clone(s.parties[leader].members)
end

-- The invites waiting for a player that haven't run out: { inviter }, oldest first.
function Party.invitesFor(s: State, userId: number, now: number): { number }
	local list = {}
	for from, expires in s.invites[userId] or {} do
		if expires > now then
			table.insert(list, from)
		end
	end
	table.sort(list, function(a, b)
		return (s.invites[userId] :: any)[a] < (s.invites[userId] :: any)[b]
	end)
	return list
end

function Party.invite(s: State, from: number, to: number, now: number): (boolean, string?)
	if from == to then
		return false, "You can't invite yourself"
	end
	local leader = s.of[from]
	if leader and leader ~= from then
		return false, "Only your party's leader can invite"
	elseif s.of[to] then
		return false, "They're already in a party"
	elseif #Party.membersOf(s, from) >= Party.MAX then
		return false, `A party is at most {Party.MAX} pilots`
	end
	local pending = s.invites[to] and s.invites[to][from]
	if pending and pending > now then
		return false, "Already invited"
	end
	s.invites[to] = s.invites[to] or {}
	s.invites[to][from] = now + Party.INVITE_TTL
	return true, nil
end

local function forget(s: State, to: number, from: number)
	local list = s.invites[to]
	if list then
		list[from] = nil
		if next(list) == nil then
			s.invites[to] = nil
		end
	end
end

function Party.decline(s: State, to: number, from: number)
	forget(s, to, from)
end

-- Accepts an invite. Returns the party's leader, or nil and why not.
function Party.accept(s: State, to: number, from: number, now: number): (number?, string?)
	local expires = s.invites[to] and s.invites[to][from]
	forget(s, to, from)
	if not expires or expires <= now then
		return nil, "That invite has run out"
	elseif s.of[to] then
		return nil, "Leave your party first"
	end
	local leader = s.of[from]
	if leader and leader ~= from then
		return nil, "They're in someone else's party now"
	end
	local group = s.parties[from]
	if not group then
		group = { leader = from, members = { from } }
		s.parties[from] = group
		s.of[from] = from
	end
	if #group.members >= Party.MAX then
		return nil, "That party is full"
	end
	table.insert(group.members, to)
	s.of[to] = from
	s.invites[to] = nil -- one party at a time: the rest of their invites go
	return from, nil
end

-- Takes a player out of their party. Returns the party's leader afterwards (nil if it broke up or they
-- were on their own).
function Party.leave(s: State, userId: number): number?
	local leader = s.of[userId]
	if not leader then
		return nil
	end
	local group = s.parties[leader]
	s.of[userId] = nil
	local i = table.find(group.members, userId)
	if i then
		table.remove(group.members, i)
	end
	s.parties[leader] = nil
	if #group.members <= 1 then
		for _, member in group.members do
			s.of[member] = nil
		end
		return nil
	end
	group.leader = group.members[1]
	s.parties[group.leader] = group
	for _, member in group.members do
		s.of[member] = group.leader
	end
	return group.leader
end

function Party.kick(s: State, leader: number, target: number): (boolean, string?)
	if s.of[leader] ~= leader then
		return false, "Only the leader can remove someone"
	elseif target == leader or s.of[target] ~= leader then
		return false, "They're not in your party"
	end
	Party.leave(s, target)
	return true, nil
end

-- Puts a party back together (after a match brought everyone back to the same lobby). Only players on
-- their own are added; returns the leader, or nil if fewer than two could be.
function Party.restore(s: State, leader: number, members: { number }): number?
	local free = {}
	for _, userId in members do
		if not s.of[userId] and not table.find(free, userId) then
			table.insert(free, userId)
		end
	end
	if #free < 2 or free[1] ~= leader then
		return nil
	end
	while #free > Party.MAX do
		table.remove(free)
	end
	s.parties[leader] = { leader = leader, members = free }
	for _, userId in free do
		s.of[userId] = leader
	end
	return leader
end

-- Splits a match's groups (parties, and solo pilots as groups of one) over the teams so each group stays
-- together and the teams are as even as can be: biggest groups first, each onto the smaller team. Returns
-- { [userId] = team }.
function Party.splitTeams(groups: { { number } }, teams: { string }): { [number]: string }
	local sorted = table.clone(groups)
	table.sort(sorted, function(a, b)
		if #a ~= #b then
			return #a > #b
		end
		return a[1] < b[1]
	end)
	local counts: { [string]: number } = {}
	for _, team in teams do
		counts[team] = 0
	end
	local out = {}
	for _, group in sorted do
		local best = teams[1]
		for _, team in teams do
			if counts[team] < counts[best] then
				best = team
			end
		end
		counts[best] += #group
		for _, userId in group do
			out[userId] = best
		end
	end
	return out
end

return Party
