--!strict
-- Map warm-up (MAP-04). With streaming on, a client only gets the map around its ReplicationFocus: the
-- runway while on the menu, the jet once flying. So while a player sits in the hangar, ask the engine to
-- stream the rest in around them: the spawn points first (where they'll appear), then the airbases, then
-- a grid over the whole map. With Workspace.StreamOutBehavior = LowMemory (set in Studio; scripts can't),
-- what's loaded stays loaded unless the device runs short of memory, so spawning doesn't start in a void.
-- The client sets the pace: it reports its frame rate (StreamingController), and each area waits until
-- that is back to normal for the machine. Sending everything at once held a client at ~10 fps for over
-- a minute while it built the terrain; a fixed pause between areas wasted a fast machine's headroom.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Scale = require(Shared.Config.Scale)

local GRID = 3500 -- each request only guarantees StreamingMinRadius (2048) around its point, so the grid is tight
local TIMEOUT = 15 -- seconds to wait on each area
local SMOOTH = 0.8 -- an area goes once the frame rate is back to this share of the machine's best...
local SMOOTH_FPS = 55 -- ...or this high
local MAX_WAIT = 3 -- seconds to hold an area for a client that's busy (or not reporting)
-- Off: building terrain meshes for the whole map kept a client at ~12 fps for minutes, however it was
-- paced. Only the spawn areas warm up; the rest streams in around the jet as it flies, LowMemory keeps
-- it, and WorldEdgeController's underlay stands in for anything not there yet.
local WARM_WHOLE_MAP = false

local StreamingService = {
	Priority = 90,
}

type Pace = { fps: number, best: number }
local pace: { [Player]: Pace } = {}

-- Where a player can appear: the spawn points and the airbases. Loaded first.
local function spawnAreas(): { Vector3 }
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
	return list
end

-- The rest of the map, nearest the middle first.
local function grid(): { Vector3 }
	local list = {}
	local half = Scale.MAP_HALF_EXTENT
	for x = -half + GRID / 2, half, GRID do
		for z = -half + GRID / 2, half, GRID do
			table.insert(list, Vector3.new(x, 0, z))
		end
	end
	table.sort(list, function(a, b)
		return a.Magnitude < b.Magnitude
	end)
	return list
end

-- Waits until the client is drawing smoothly again (or MAX_WAIT has passed).
local function settle(player: Player)
	local started = os.clock()
	repeat
		task.wait(0.1)
		local p = pace[player]
		if p and (p.fps >= SMOOTH_FPS or p.fps >= p.best * SMOOTH) then
			return
		end
	until os.clock() - started >= MAX_WAIT
end

local function warm(player: Player)
	local areas = spawnAreas()
	if WARM_WHOLE_MAP then
		for _, position in grid() do
			table.insert(areas, position)
		end
	end
	for _, position in areas do
		settle(player)
		if player.Parent ~= Players then
			return
		end
		pcall(player.RequestStreamAroundAsync, player, position, TIMEOUT)
	end
end

function StreamingService:Start()
	Net.Server.on("StreamPace", function(player: Player, fps: number)
		fps = math.clamp(fps, 0, 1000)
		local p = pace[player]
		if p then
			p.fps = fps
			p.best = math.max(p.best * 0.995, fps) -- the best slowly fades, in case the machine settles lower
		else
			pace[player] = { fps = fps, best = fps }
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		pace[player] = nil
	end)
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
