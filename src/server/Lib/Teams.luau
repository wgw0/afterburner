--!strict
-- Who is on which team (DEVELOPMENT.md §17, MCH-05). MatchService assigns teams in team modes; the combat,
-- missile, sensor and AI services ask here so teammates can't hurt, lock or target each other. Keyed by pilot
-- identity (a Player, or an AI pilot record). Outside a team mode nobody has a team and nobody is a friend.

local Teams = {}

local teamOf: { [any]: string } = {}

function Teams.set(identity: any, team: string?)
	teamOf[identity] = team
	if typeof(identity) == "Instance" and identity:IsA("Player") then
		identity:SetAttribute("Team", team or "")
	end
end

function Teams.of(identity: any): string?
	return if identity ~= nil then teamOf[identity] else nil
end

-- Same team (two different pilots). Nil on either side is never a friend.
function Teams.areFriends(a: any, b: any): boolean
	if a == nil or b == nil or a == b then
		return false
	end
	local team = teamOf[a]
	return team ~= nil and team == teamOf[b]
end

function Teams.clear()
	for identity in teamOf do
		Teams.set(identity, nil)
	end
end

return Teams
