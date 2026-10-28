--!strict
-- The research graph (DESIGN §6, DEVELOPMENT.md §23.3). Tiers I–VI so far.
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
local TIER_III = { "F16A", "F14A", "MiG29A", "Mirage2000C" }
local TIER_IV = { "F15C", "FA18C", "Su27S", "TornadoF3" }
local TIER_V = { "F16C", "F15E", "Su30SM", "MiG29SMT", "GripenC" }

local NODES: { Node } = {
	{ Id = "F5E", Tier = 1, Branch = "NATO", Requires = {}, RP = 0, Credits = 0 },
	{ Id = "MiG21bis", Tier = 1, Branch = "East", Requires = {}, RP = 0, Credits = 0 },
	{ Id = "MirageIII", Tier = 1, Branch = "Europe", Requires = { "F5E", "MiG21bis" }, RP = 300, Credits = 800 },
	{ Id = "F4E", Tier = 2, Branch = "NATO", Requires = TIER_I, RP = 1600, Credits = 2900 },
	{ Id = "MiG23MLD", Tier = 2, Branch = "East", Requires = TIER_I, RP = 1600, Credits = 2900 },
	{ Id = "MirageF1", Tier = 2, Branch = "Europe", Requires = TIER_I, RP = 1600, Credits = 2900 },
	{ Id = "F16A", Tier = 3, Branch = "NATO", Requires = TIER_II, RP = 7500, Credits = 12500 },
	{ Id = "MiG29A", Tier = 3, Branch = "East", Requires = TIER_II, RP = 7500, Credits = 12500 },
	-- The F-14A follows the F-16A in its branch: the Phoenix makes it the strongest Tier III jet
	{ Id = "F14A", Tier = 3, Branch = "NATO", Requires = { "F16A", "MiG29A" }, RP = 9500, Credits = 15500 },
	{ Id = "Mirage2000C", Tier = 3, Branch = "Europe", Requires = TIER_II, RP = 7500, Credits = 12500 },
	{ Id = "F15C", Tier = 4, Branch = "NATO", Requires = TIER_III, RP = 22000, Credits = 38000 },
	-- The F/A-18C is the cheaper NATO Tier IV jet; the Eagle and Flanker are the benchmarks
	{ Id = "FA18C", Tier = 4, Branch = "NATO", Requires = TIER_III, RP = 19000, Credits = 33000 },
	{ Id = "Su27S", Tier = 4, Branch = "East", Requires = TIER_III, RP = 22000, Credits = 38000 },
	{ Id = "TornadoF3", Tier = 4, Branch = "Europe", Requires = TIER_III, RP = 19000, Credits = 33000 },
	{ Id = "F16C", Tier = 5, Branch = "NATO", Requires = TIER_IV, RP = 45000, Credits = 75000 },
	{ Id = "F15E", Tier = 5, Branch = "NATO", Requires = TIER_IV, RP = 42000, Credits = 70000 },
	{ Id = "Su30SM", Tier = 5, Branch = "East", Requires = TIER_IV, RP = 48000, Credits = 80000 },
	{ Id = "MiG29SMT", Tier = 5, Branch = "East", Requires = TIER_IV, RP = 42000, Credits = 70000 },
	{ Id = "GripenC", Tier = 5, Branch = "Europe", Requires = TIER_IV, RP = 42000, Credits = 70000 },
	{ Id = "FA18E", Tier = 6, Branch = "NATO", Requires = TIER_V, RP = 80000, Credits = 130000 },
	{ Id = "Su35S", Tier = 6, Branch = "East", Requires = TIER_V, RP = 90000, Credits = 145000 },
	{ Id = "Typhoon", Tier = 6, Branch = "Europe", Requires = TIER_V, RP = 90000, Credits = 145000 },
	{ Id = "RafaleC", Tier = 6, Branch = "Europe", Requires = TIER_V, RP = 85000, Credits = 138000 },
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
TechTree.MAX_TIER = 6

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
