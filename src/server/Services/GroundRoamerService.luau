--!strict
-- The Ground Roamer (DEVELOPMENT.md §36): a 4x4 players can take out from the menu to explore the map from the
-- ground. One per player. The server clones it from ServerStorage.Vehicles.GroundRoamer (built in Studio by
-- tools/GroundRoamerBuilder.luau), puts it on the ground at an airbase apron or on the island, dresses it in the
-- chosen skin and hands its physics to the driver; the driver's DriveController drives it. It is put away when
-- the driver asks, takes off in a jet, leaves, or it goes somewhere it shouldn't (the driver owns its physics).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config.GroundRoamer)
local Net = require(Shared.Net)

local AircraftService = require(script.Parent.AircraftService)

local CHECK_INTERVAL = 1 -- seconds between sanity checks
local LOWEST = -200 -- studs: below this it has fallen out of the world

local GroundRoamerService = {
	Priority = 60,
}

local vehicles: { [Player]: Model } = {}
local folder: Folder

local function despawn(player: Player)
	local model = vehicles[player]
	vehicles[player] = nil
	if model then
		model:Destroy()
	end
end

local function template(): Model?
	local store = ServerStorage:FindFirstChild("Vehicles")
	local model = store and store:FindFirstChild(Config.ModelName)
	return if model and model:IsA("Model") then model else nil
end

-- The ground's height under (x, z), ignoring vehicles and jets.
local function groundY(x: number, z: number): number?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { folder, workspace:FindFirstChild("Jets") :: Instance }
	local hit = workspace:Raycast(Vector3.new(x, 2000, z), Vector3.new(0, -4000, 0), params)
	return hit and hit.Position.Y
end

-- Each part records its texture set (Body, Canvas, Details, Glass, Decals); the template keeps one
-- SurfaceAppearance per set and skin under Skins/<skin>/<set>.
local function dress(model: Model, skin: string)
	local skins = model:FindFirstChild("Skins")
	local chosen = skins and (skins:FindFirstChild(skin) or skins:FindFirstChild(Config.DefaultSkin))
	for _, part in model:GetDescendants() do
		if part:IsA("MeshPart") then
			local set = part:GetAttribute("TextureSet")
			local appearance = chosen and set and chosen:FindFirstChild(set :: string)
			if appearance and not part:FindFirstChildOfClass("SurfaceAppearance") then
				appearance:Clone().Parent = part
			end
		end
	end
	if skins then
		skins:Destroy()
	end
end

local function spawn(player: Player, skin: string?): (boolean, string?)
	if not Config.Enabled then
		return false, "The Ground Roamer is off"
	end
	if AircraftService:GetJet(player) then
		return false, "You're flying: land in the menu first"
	end
	local source = template()
	if not source then
		return false, "The Ground Roamer isn't installed on this server yet"
	end
	despawn(player)
	local choice = if skin and table.find(Config.Skins, skin) then skin else Config.DefaultSkin
	local spot = Config.SpawnSpots[math.random(#Config.SpawnSpots)]
	local y = groundY(spot.x, spot.z) or 10

	local model = source:Clone()
	model.Name = `{Config.ModelName}_{player.UserId}`
	dress(model, choice)
	model:PivotTo(CFrame.new(spot.x, y + 0.3, spot.z) * CFrame.Angles(0, spot.yaw, 0))
	model:SetAttribute("OwnerUserId", player.UserId)
	model:SetAttribute("Skin", choice)
	model.Parent = folder
	local root = model.PrimaryPart
	if root then
		root:SetNetworkOwner(player)
	end
	vehicles[player] = model
	return true, spot.name
end

function GroundRoamerService:GetVehicle(player: Player): Model?
	return vehicles[player]
end

function GroundRoamerService:Init()
	folder = Instance.new("Folder")
	folder.Name = "Vehicles"
	folder.Parent = workspace
end

function GroundRoamerService:Start()
	Net.Server.handle("RequestGroundRoamer", function(player: Player, takeOut: boolean, skin: string?)
		if takeOut then
			return spawn(player, skin)
		end
		despawn(player)
		return true, nil
	end)
	Players.PlayerRemoving:Connect(despawn)
	AircraftService.JetSpawned:Connect(function(jet)
		if jet.pilot then
			despawn(jet.pilot)
		end
	end)

	-- Sanity: the driver owns the physics, so a vehicle that's far too fast or has fallen out of the world goes
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < CHECK_INTERVAL then
			return
		end
		elapsed = 0
		for player, model in vehicles do
			local root = model.PrimaryPart
			if
				not (root and root.Parent)
				or root.AssemblyLinearVelocity.Magnitude > Config.MaxSpeed
				or root.Position.Y < LOWEST
			then
				despawn(player)
			end
		end
	end)
end

return GroundRoamerService
