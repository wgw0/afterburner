--!strict
-- The research graph (DESIGN §6, DEVELOPMENT.md §23.3). Phase 5 covers Tiers I–III.
--   Requires: research needs RP earned in one of these jets (any branch, same or lower tier), topped
--     up from the free RP pool. Owning a prerequisite is what makes a node researchable.
--   RP / Credits: research cost (RP) and purchase cost once researched (Credits).
-- Starter jets (Economy.STARTERS) are owned by every account and have no costs.

export type Node = {
	Id: string, -- AircraftData id
	Tier: number,
	Branch: "NATO" | "East" | "Europe",
	Requires: { string },
	RP: number,
	Credits: number,
}

local TIER_I = { "F5E", "MiG21bis", "MirageIII" }
local TIER_II = { "F4E", "MiG23MLD", "MirageF1" }

local NODES: { Node } = {
	{ Id = "F5E", Tier = 1, Branch = "NATO", Requires = {}, RP = 0, Credits = 0 },
	{ Id = "MiG21bis", Tier = 1, Branch = "East", Requires = {}, RP = 0, Credits = 0 },
	{ Id = "MirageIII", Tier = 1, Branch = "Europe", Requires = { "F5E", "MiG21bis" }, RP = 300, Credits = 800 },
	{ Id = "F4E", Tier = 2, Branch = "NATO", Requires = TIER_I, RP = 1600, Credits = 2900 },
	{ Id = "MiG23MLD", Tier = 2, Branch = "East", Requires = TIER_I, RP = 1600, Credits = 2900 },
	{ Id = "MirageF1", Tier = 2, Branch = "Europe", Requires = TIER_I, RP = 1600, Credits = 2900 },
	{ Id = "F16A", Tier = 3, Branch = "NATO", Requires = TIER_II, RP = 7500, Credits = 12500 },
	{ Id = "MiG29A", Tier = 3, Branch = "East", Requires = TIER_II, RP = 7500, Credits = 12500 },
}

local byId: { [string]: Node } = {}
for _, node in NODES do
	byId[node.Id] = node
	if not table.isfrozen(node.Requires) then
		table.freeze(node.Requires) -- shared by several nodes
	end
	table.freeze(node)
end

local TechTree = {}

TechTree.NODES = table.freeze(NODES)
TechTree.BRANCHES = table.freeze({ "NATO", "East", "Europe" })
TechTree.MAX_TIER = 3

function TechTree.get(id: string): Node?
	return byId[id]
end

-- Nodes of one branch, by tier.
function TechTree.branch(branch: string): { Node }
	local list = {}
	for _, node in NODES do
		if node.Branch == branch then
			table.insert(list, node)
		end
	end
	table.sort(list, function(a, b)
		return a.Tier < b.Tier
	end)
	return list
end

return TechTree
