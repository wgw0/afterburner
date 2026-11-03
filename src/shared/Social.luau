--!strict
-- The friends bonus (DEVELOPMENT.md §25.8; numbers in Config/Social). Pure: SocialService checks Roblox
-- (IsFriendsWith) and sets the player attribute below; Progression.matchRewards pays the bonus as its own line;
-- the hangar chip and the results screen read the attribute.

local Config = require(script.Parent.Config.Social)

local Social = {}

Social.FRIENDS_ATTRIBUTE = "FriendsBonus" -- true: a friend or party member is here (match) / a party (lobby)
Social.FRIENDS_LABEL = "Flying with friends"

export type Bonus = { Label: string, XP: number, Credits: number }

-- "+10%" for a bonus's Credits (the chip and hints; XP is the same).
function Social.percent(bonus: { Credits: number }): string
	return `+{math.round((bonus.Credits - 1) * 100)}%`
end

-- The bonuses a player gets on a match (just the friends bonus, when they flew with friends).
function Social.bonuses(withFriends: boolean): { Bonus }
	if not withFriends then
		return {}
	end
	return { { Label = Social.FRIENDS_LABEL, XP = Config.FRIENDS.XP, Credits = Config.FRIENDS.Credits } }
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
