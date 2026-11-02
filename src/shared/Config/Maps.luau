--!strict
-- The maps (MAP-05). Every map is its own place in the experience (Roblox terrain belongs to a whole
-- place), running the same code; the place says which map it is with the workspace's "Map" attribute (set
-- by the map's builder, e.g. tools/DesertBuilder). Config/Places says which place holds which map, and the
-- matchmaker picks one at random for every match it forms (Will).
--   edge: the world past the terrain (WorldEdge / WorldEdgeController): whether there's sea, and colours.

export type Map = {
	Id: string,
	DisplayName: string,
	edge: { sea: boolean, land: Color3, seaColour: Color3, plainHeight: number },
}

local Maps = {}

Maps.LIST = table.freeze({
	Strait = table.freeze({
		Id = "Strait",
		DisplayName = "The Strait",
		edge = {
			sea = true,
			land = Color3.fromRGB(98, 122, 56),
			seaColour = Color3.fromRGB(34, 92, 104),
			plainHeight = 6.72,
		},
	}),
	Desert = table.freeze({
		Id = "Desert",
		DisplayName = "Desert Range",
		-- Endless flat desert past the edges, no sea
		edge = {
			sea = false,
			land = Color3.fromRGB(196, 150, 100),
			seaColour = Color3.fromRGB(196, 150, 100),
			plainHeight = 24,
		},
	}),
}) :: { [string]: any }

Maps.DEFAULT = "Strait"

function Maps.get(id: any): any?
	return if type(id) == "string" then Maps.LIST[id] else nil
end

-- The map this place is (the workspace's "Map" attribute; the Strait if it has none).
function Maps.current(): any
	local id = workspace:GetAttribute("Map")
	return Maps.get(id) or Maps.LIST[Maps.DEFAULT]
end

return Maps
