--!strict
-- Team names and colours for team modes (DEVELOPMENT.md §17, MCH-05). The ids match the Team attribute on
-- the map's SpawnPoints: West spawns over the west coast, East over the east.

return table.freeze({
	West = table.freeze({ DisplayName = "West", Colour = Color3.fromRGB(90, 165, 255) }),
	East = table.freeze({ DisplayName = "East", Colour = Color3.fromRGB(255, 95, 85) }),
})
