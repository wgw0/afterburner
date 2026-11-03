--!strict
-- The group and friends bonuses (DEVELOPMENT.md §25.8; numbers in Config/Social). Pure: SocialService checks
-- Roblox (IsInGroupAsync, IsFriendsWith) and sets the player attributes below; Progression.matchRewards pays the
-- bonuses as their own lines; the hangar chip and the results screen read the attributes.

local Config = require(script.Parent.Config.Social)

local Social = {}

Social.GROUP_ATTRIBUTE = "GroupBonus" -- true: in the group (only set while Config GROUP_ID is)
Social.FRIENDS_ATTRIBUTE = "FriendsBonus" -- true: a friend or party member is here (match) / a party (lobby)

Social.GROUP_LABEL = "Group bonus"
Social.FRIENDS_LABEL = "Flying with friends"

export type Bonus = { Label: string, XP: number, Credits: number }

-- Is there a group to join? (Config GROUP_ID set)
function Social.groupOn(): boolean
	return Config.GROUP_ID ~= nil
end

-- "+10%" for a bonus's Credits (the chip and hints; XP is the same).
function Social.percent(bonus: { Credits: number }): string
	return `+{math.round((bonus.Credits - 1) * 100)}%`
end

-- The bonuses a player gets on a match: the group's (only while there's a group) and the friends'.
function Social.bonuses(inGroup: boolean, withFriends: boolean): { Bonus }
	local list = {}
	if inGroup and Social.groupOn() then
		table.insert(list, { Label = Social.GROUP_LABEL, XP = Config.GROUP.XP, Credits = Config.GROUP.Credits })
	end
	if withFriends then
		table.insert(list, { Label = Social.FRIENDS_LABEL, XP = Config.FRIENDS.XP, Credits = Config.FRIENDS.Credits })
	end
	return list
end

-- Is anyone in `present` (UserIds on this server, the player too) a friend or party member of userId?
-- friends: pairs known to be friends ("a:b", smaller id first). parties: the match's parties ({ userId } each).
function Social.withFriends(
	userId: number,
	present: { number },
	friends: { [string]: boolean },
	parties: { { number } }?
): boolean
	for _, other in present do
		if other ~= userId then
			if friends[Social.pairKey(userId, other)] then
				return true
			end
			for _, party in parties or {} do
				if table.find(party, userId) and table.find(party, other) then
					return true
				end
			end
		end
	end
	return false
end

function Social.pairKey(a: number, b: number): string
	return if a < b then `{a}:{b}` else `{b}:{a}`
end

return Social
