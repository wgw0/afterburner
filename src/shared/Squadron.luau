--!strict
-- Squadrons (LIV-06; DESIGN §7.6, DEVELOPMENT.md §26.4): player groups with a shared tag shown before their
-- names, a weekly goal and a leaderboard. Pure rules for a squadron record; SquadronService keeps the
-- records in the Squadrons DataStore (s:<id>, and tag:<TAG> → id) and each member's save holds its id.
--   Creating costs COST Credits; the name and tag go through Roblox's text filter (refused if it changes them).
--   Open squadrons can be joined by tag; closed ones by an owner's or officer's invite (same server).
--   Roles: Owner (one), Officer, Member. If the owner leaves, the longest-standing officer (else member)
--   takes over; the last one out disbands it.
--   Each week (Monday 00:00 UTC) members' scored matches earn points (POINTS); at GOAL points every member
--   can claim REWARD Credits once that week.

local Squadron = {}

Squadron.NAME_MIN, Squadron.NAME_MAX = 3, 24
Squadron.TAG_MIN, Squadron.TAG_MAX = 2, 4
Squadron.MAX_MEMBERS = 30
Squadron.COST = 10000 -- Credits to create one
Squadron.POINTS = table.freeze({ kill = 1, win = 3 }) -- per player shot down, per win
Squadron.GOAL = 100 -- weekly points for the squadron reward
Squadron.REWARD = 5000 -- Credits each member can claim once a week at the goal
Squadron.ROLES = table.freeze({ "Owner", "Officer", "Member" })

export type Member = { role: string, joined: number }
export type Record = {
	id: string,
	name: string,
	tag: string,
	owner: number,
	open: boolean,
	created: number,
	members: { [string]: Member }, -- by tostring(userId) (the record is stored as JSON)
}

-- A typed name tidied (trimmed, single spaces): letters, digits, spaces, - and ' only. Returns it, or nil and why.
function Squadron.cleanName(text: any): (string?, string?)
	if type(text) ~= "string" then
		return nil, "Give it a name"
	end
	local tidy = string.gsub(string.gsub(string.gsub(text, "^%s+", ""), "%s+$", ""), "%s+", " ")
	if #tidy < Squadron.NAME_MIN or #tidy > Squadron.NAME_MAX then
		return nil, `A name is {Squadron.NAME_MIN}–{Squadron.NAME_MAX} characters`
	elseif string.find(tidy, "[^%w %-']") then
		return nil, "Letters, numbers, spaces, - and ' only"
	elseif not string.find(tidy, "%a") then
		return nil, "The name needs a letter"
	end
	return tidy, nil
end

-- A typed tag in capitals: 2–4 letters or digits. Returns it, or nil and why.
function Squadron.cleanTag(text: any): (string?, string?)
	if type(text) ~= "string" then
		return nil, "Give it a tag"
	end
	local tag = string.upper(string.gsub(text, "%s", ""))
	if #tag < Squadron.TAG_MIN or #tag > Squadron.TAG_MAX then
		return nil, `A tag is {Squadron.TAG_MIN}–{Squadron.TAG_MAX} letters or numbers`
	elseif string.find(tag, "[^%u%d]") then
		return nil, "A tag is letters and numbers only"
	end
	return tag, nil
end

function Squadron.new(id: string, name: string, tag: string, owner: number, open: boolean, now: number): Record
	return {
		id = id,
		name = name,
		tag = tag,
		owner = owner,
		open = open,
		created = now,
		members = { [tostring(owner)] = { role = "Owner", joined = now } },
	}
end

function Squadron.count(record: Record): number
	local n = 0
	for _ in record.members do
		n += 1
	end
	return n
end

function Squadron.roleOf(record: Record, userId: number): string?
	local member = record.members[tostring(userId)]
	return member and member.role
end

-- Owners and officers invite, remove members and open or close the squadron.
function Squadron.canManage(record: Record, userId: number): boolean
	local role = Squadron.roleOf(record, userId)
	return role == "Owner" or role == "Officer"
end

-- Adds a member. invited: an officer invited them (needed for a closed squadron).
function Squadron.join(record: Record, userId: number, invited: boolean, now: number): (boolean, string?)
	if record.members[tostring(userId)] then
		return false, "You're already in it"
	elseif not record.open and not invited then
		return false, "That squadron is invite-only"
	elseif Squadron.count(record) >= Squadron.MAX_MEMBERS then
		return false, `That squadron is full ({Squadron.MAX_MEMBERS})`
	end
	record.members[tostring(userId)] = { role = "Member", joined = now }
	return true, nil
end

-- Takes a member out. Returns false if the squadron is now empty (disband it); a leaving owner hands over to
-- the longest-standing officer, else the longest-standing member.
function Squadron.leave(record: Record, userId: number): boolean
	local key = tostring(userId)
	local leaving = record.members[key]
	if not leaving then
		return Squadron.count(record) > 0
	end
	record.members[key] = nil
	if Squadron.count(record) == 0 then
		return false
	end
	if leaving.role == "Owner" then
		local best, bestKey = nil, nil
		for k, member in record.members do
			local better = best == nil
				or (member.role == "Officer" and best.role ~= "Officer")
				or (member.role == best.role and member.joined < best.joined)
			if better then
				best, bestKey = member, k
			end
		end
		(best :: Member).role = "Owner"
		record.owner = tonumber(bestKey) :: number
	end
	return true
end

-- The owner makes a member an officer or back ("Officer" | "Member"), or hands over ownership ("Owner").
function Squadron.setRole(record: Record, actor: number, target: number, role: string): (boolean, string?)
	if Squadron.roleOf(record, actor) ~= "Owner" then
		return false, "Only the owner can do that"
	elseif actor == target or not record.members[tostring(target)] then
		return false, "They're not in the squadron"
	elseif not table.find(Squadron.ROLES, role) then
		return false, "Unknown role"
	end
	if role == "Owner" then
		record.members[tostring(actor)].role = "Officer"
		record.owner = target
	end
	record.members[tostring(target)].role = role
	return true, nil
end

-- An owner or officer removes a member (officers can't remove the owner or other officers).
function Squadron.kick(record: Record, actor: number, target: number): (boolean, string?)
	local mine, theirs = Squadron.roleOf(record, actor), Squadron.roleOf(record, target)
	if not Squadron.canManage(record, actor) then
		return false, "Only the owner and officers can do that"
	elseif not theirs or actor == target then
		return false, "They're not in the squadron"
	elseif theirs == "Owner" or (theirs == "Officer" and mine ~= "Owner") then
		return false, "You can't remove them"
	end
	record.members[tostring(target)] = nil
	return true, nil
end

-- Points a member's scored match earns the squadron.
function Squadron.points(playerKills: number, won: boolean): number
	return playerKills * Squadron.POINTS.kill + (if won then Squadron.POINTS.win else 0)
end

-- A record read back from the store with anything odd removed, or nil if it isn't a squadron.
function Squadron.clean(raw: any): Record?
	if
		type(raw) ~= "table"
		or type(raw.id) ~= "string"
		or type(raw.tag) ~= "string"
		or type(raw.members) ~= "table"
	then
		return nil
	end
	local members = {}
	for key, member in raw.members do
		if type(key) == "string" and tonumber(key) and type(member) == "table" then
			members[key] = {
				role = if table.find(Squadron.ROLES, member.role) then member.role else "Member",
				joined = tonumber(member.joined) or 0,
			}
		end
	end
	return {
		id = raw.id,
		name = if type(raw.name) == "string" then raw.name else raw.tag,
		tag = raw.tag,
		owner = tonumber(raw.owner) or 0,
		open = raw.open == true,
		created = tonumber(raw.created) or 0,
		members = members,
	}
end

return Squadron
