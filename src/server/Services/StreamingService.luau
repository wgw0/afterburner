--!strict
-- Map warm-up (MAP-04). With streaming on, a client only gets the map around its ReplicationFocus: the
-- runway while on the menu, the jet once flying. So while a player sits in the hangar, ask the engine to
-- stream the rest in around them: the spawn points first (where they'll appear), then the airbases, then
-- a grid over the whole map. With Workspace.StreamOutBehavior = LowMemory (set in Studio; scripts can't),
-- what's loaded stays loaded unless the device runs short of memory, so spawning doesn't start in a void.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Scale = require(Shared.Config.Scale)

local GRID = 3500 -- each request only guarantees StreamingMinRadius (2048) around its point, so the grid is tight
local TIMEOUT = 15 -- seconds to wait on each area

local StreamingService = {
	Priority = 90,
}

local function points(): { Vector3 }
	local list = {}
	for _, part in CollectionService:GetTagged("SpawnPoint") do
		if part:IsA("BasePart") then
			table.insert(list, part.Position)
		end
	end
	local map = workspace:FindFirstChild("Map")
	for _, name in { "AirbaseWest", "AirbaseEast" } do
		local base = map and map:FindFirstChild(name)
		if base and base:IsA("Model") then
			table.insert(list, (base:GetBoundingBox()).Position)
		end
	end
	local half = Scale.MAP_HALF_EXTENT
	for x = -half + GRID / 2, half, GRID do
		for z = -half + GRID / 2, half, GRID do
			table.insert(list, Vector3.new(x, 0, z))
		end
	end
	return list
end

local function warm(player: Player)
	for _, position in points() do
		if player.Parent ~= Players then
			return
		end
		pcall(player.RequestStreamAroundAsync, player, position, TIMEOUT)
	end
end

function StreamingService:Start()
	if not workspace.StreamingEnabled then
		return
	end
	Players.PlayerAdded:Connect(function(player)
		task.spawn(warm, player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(warm, player)
	end
end

return StreamingService
