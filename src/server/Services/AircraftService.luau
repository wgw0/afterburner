--!strict
-- Owns every jet in the world (DEVELOPMENT.md §10): spawning, network ownership, telemetry, crash and
-- collision detection, despawn. Jets are flown by a player (who owns the physics) or by the server
-- (AI and test drones, pilot = nil).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AircraftData = require(Shared.AircraftData)
local Contract = require(Shared.AircraftModelContract)
local Flight = require(Shared.Config.Flight)
local Net = require(Shared.Net)
local Signal = require(Shared.Util.Signal)
local Units = require(Shared.Units)
local Validate = require(Shared.Util.Validate)
local WeaponData = require(Shared.WeaponData)

export type Jet = {
	id: number,
	model: Model,
	root: BasePart,
	airframeId: string,
	pilot: Player?, -- nil for AI / drones
	name: string, -- shown in the kill feed
	spawnTime: number,
	lastPosition: Vector3,
}

export type SpawnOptions = {
	name: string?, -- AI display name
	speed: number?, -- real m/s, default Flight.SPAWN_SPEED
}

local CRASH_GRACE = 1.0 -- seconds after spawn before crash checks apply
local COLLISION_DISTANCE = 16 -- studs between roots counts as a mid-air collision
local CRASH_REPORT_RANGE = 150 -- studs: a reported crash must be this close to the ground

local AircraftService = {
	Priority = 20,
	JetSpawned = Signal.new(), -- (jet)
	JetDestroyed = Signal.new(), -- (jet, cause, position)
}

local jets: { [number]: Jet } = {}
local jetByPlayer: { [Player]: Jet } = {}
local nextId = 0
local jetsFolder: Folder
local worldParams: RaycastParams

local function modelFor(airframeId: string): Model?
	local airframe = AircraftData.get(airframeId)
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local folder = assets and assets:FindFirstChild("Aircraft")
	local model = airframe and folder and folder:FindFirstChild(airframe.ModelName)
	return if model and model:IsA("Model") then model else nil
end

local function spawnCFrame(id: number): CFrame
	-- Spread spawns around a ring so simultaneous spawns never overlap, all heading toward the test range.
	local angle = (id * 137.5) % 360
	local offset = CFrame.Angles(0, math.rad(angle), 0) * Vector3.new(0, 0, 2500)
	local position = Vector3.new(0, Flight.SPAWN_ALTITUDE_STUDS, 0) + offset
	return CFrame.lookAt(position, Vector3.new(0, Flight.SPAWN_ALTITUDE_STUDS, 0))
end

-- With streaming on and no characters, the server streams around each player's ReplicationFocus.
-- Without a jet, that's the test range, so the menu backdrop is loaded.
local function idleFocus(): BasePart?
	local range = workspace:FindFirstChild("TestRange")
	local strip = range and range:FindFirstChild("Runway") and range.Runway:FindFirstChild("Strip")
	return if strip and strip:IsA("BasePart") then strip else nil
end

function AircraftService:GetJet(player: Player): Jet?
	return jetByPlayer[player]
end

function AircraftService:GetJetById(id: number): Jet?
	return jets[id]
end

function AircraftService:GetJets(): { [number]: Jet }
	return jets
end

-- Removes a jet. cause: "Shot" | "Crash" | "Collision" | "Respawn" | "PilotLeft" | "Despawn"
function AircraftService:Despawn(jet: Jet, cause: string)
	if jets[jet.id] == nil then
		return
	end
	jets[jet.id] = nil
	local position = jet.root.Position
	if jet.pilot and jetByPlayer[jet.pilot] == jet then
		jetByPlayer[jet.pilot] = nil
	end
	if jet.pilot and jet.pilot.Parent then
		jet.pilot.ReplicationFocus = idleFocus()
	end
	self.JetDestroyed:Fire(jet, cause, position)
	jet.model:Destroy()
end

function AircraftService:Spawn(pilot: Player?, airframeId: string, cframe: CFrame?, options: SpawnOptions?): Jet?
	local airframe = AircraftData.get(airframeId)
	local template = modelFor(airframeId)
	if not (airframe and template) then
		return nil
	end

	if pilot then
		local existing = jetByPlayer[pilot]
		if existing then
			self:Despawn(existing, "Respawn")
		end
	end

	nextId += 1
	local id = nextId
	local startCFrame = cframe or spawnCFrame(id)
	local speed = (options and options.speed) or Flight.SPAWN_SPEED
	local startVelocity = startCFrame.LookVector * Units.velocityToStuds(speed)
	local name = if pilot then pilot.Name else (options and options.name) or `AI-{id}`

	local model = template:Clone()
	model.Name = `{airframeId}_{name}`
	model:SetAttribute("JetId", id)
	model:SetAttribute("AirframeId", airframeId)
	model:SetAttribute("PilotUserId", if pilot then pilot.UserId else 0)
	model:SetAttribute("PilotName", name)
	model:SetAttribute("Team", "")
	model:SetAttribute("IsAI", pilot == nil)
	model:SetAttribute("Throttle", 0.8)
	model:SetAttribute("Afterburner", false)
	model:SetAttribute("GLoad", 1)
	model:SetAttribute("Gun", airframe.Gun)
	local gun = WeaponData.get(airframe.Gun)
	model:SetAttribute("Ammo", if gun then gun.Ammo else 0)
	model:SetAttribute("GunHeat", 0)
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent

	local root = model.PrimaryPart :: BasePart
	local attachment = Instance.new("Attachment")
	attachment.Name = "PhysicsAttachment"
	attachment.Parent = root

	-- Whoever owns the physics drives these every frame (the pilot's FlightController, or the server for
	-- AI). Unlimited force/torque so the flight model, not Roblox gravity, decides the motion.
	local linear = Instance.new("LinearVelocity")
	linear.Name = "FlightLinear"
	linear.Attachment0 = attachment
	linear.RelativeTo = Enum.ActuatorRelativeTo.World
	linear.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	linear.MaxForce = math.huge
	linear.VectorVelocity = startVelocity
	linear.Parent = root

	local angular = Instance.new("AngularVelocity")
	angular.Name = "FlightAngular"
	angular.Attachment0 = attachment
	angular.RelativeTo = Enum.ActuatorRelativeTo.World
	angular.MaxTorque = math.huge
	angular.AngularVelocity = Vector3.zero
	angular.Parent = root

	model:PivotTo(startCFrame)
	root.AssemblyLinearVelocity = startVelocity
	model.Parent = jetsFolder
	root:SetNetworkOwner(pilot)
	if pilot then
		pilot.ReplicationFocus = root
	end

	local jet: Jet = {
		id = id,
		model = model,
		root = root,
		airframeId = airframeId,
		pilot = pilot,
		name = name,
		spawnTime = os.clock(),
		lastPosition = root.Position,
	}
	jets[id] = jet
	if pilot then
		jetByPlayer[pilot] = jet
	end
	self.JetSpawned:Fire(jet)
	return jet
end

-- Is there terrain or map geometry within `range` studs below or ahead of the jet?
local function nearGround(jet: Jet, range: number): boolean
	local position = jet.root.Position
	if workspace:Raycast(position, Vector3.new(0, -range, 0), worldParams) then
		return true
	end
	local velocity = jet.root.AssemblyLinearVelocity
	if velocity.Magnitude > 1 then
		return workspace:Raycast(position, velocity.Unit * range, worldParams) ~= nil
	end
	return false
end

-- Server-side crash and mid-air collision checks (AIR-02). The pilot's client also stops the jet on
-- impact and reports it, but the server decides.
local function checkCollisions()
	local now = os.clock()
	local live = {}
	for _, jet in jets do
		if now - jet.spawnTime >= CRASH_GRACE then
			table.insert(live, jet)
		end
	end

	for _, jet in live do
		local position = jet.root.Position
		local travel = position - jet.lastPosition
		jet.lastPosition = position
		local length = travel.Magnitude
		if length > 0.01 and length < 2000 then
			-- The path since last tick, extended a little ahead for the nose.
			local hit = workspace:Raycast(position - travel, travel + travel.Unit * 6, worldParams)
			if hit then
				AircraftService:Despawn(jet, "Crash")
			end
		end
	end

	for i = 1, #live do
		local a = live[i]
		if jets[a.id] == nil then
			continue
		end
		for j = i + 1, #live do
			local b = live[j]
			if jets[b.id] ~= nil and (a.root.Position - b.root.Position).Magnitude < COLLISION_DISTANCE then
				AircraftService:Despawn(a, "Collision")
				AircraftService:Despawn(b, "Collision")
				break
			end
		end
	end
end

function AircraftService:Init()
	-- Battle places fly jets, not characters (§10.1).
	Players.CharacterAutoLoads = false

	jetsFolder = Instance.new("Folder")
	jetsFolder.Name = "Jets"
	jetsFolder.Parent = workspace

	worldParams = RaycastParams.new()
	worldParams.FilterType = Enum.RaycastFilterType.Exclude
	worldParams.FilterDescendantsInstances = { jetsFolder }
	worldParams.IgnoreWater = false

	-- Every airframe needs a valid model and a known gun; fail loudly at boot, not when someone spawns.
	local problems = {}
	for id, airframe in AircraftData.getAll() do
		local model = modelFor(id)
		if not model then
			table.insert(problems, `{id}: no model named {airframe.ModelName} in ReplicatedStorage.Assets.Aircraft`)
		else
			for _, problem in Contract.validate(model) do
				table.insert(problems, problem)
			end
		end
		if WeaponData.get(airframe.Gun) == nil then
			table.insert(problems, `{id}: unknown gun {airframe.Gun}`)
		end
	end
	if #problems > 0 then
		error("[AircraftService] Aircraft problems:\n  " .. table.concat(problems, "\n  "), 0)
	end

	Net.Server.on("RequestSpawn", function(player: Player, airframeId: string)
		if AircraftData.get(airframeId) == nil then
			return
		end
		self:Spawn(player, airframeId)
	end)

	Net.Server.on("ReportCrash", function(player: Player)
		-- The pilot stops the jet the moment it hits; accept it only if the jet really is at the ground.
		local jet = jetByPlayer[player]
		if jet and nearGround(jet, CRASH_REPORT_RANGE) then
			self:Despawn(jet, "Crash")
		end
	end)

	Net.Server.on("FlightTelemetry", function(player: Player, throttle: number, afterburner: boolean, gLoad: number)
		local jet = jetByPlayer[player]
		if not jet or not Validate.inRange(throttle, 0, 1) or not Validate.inRange(gLoad, -20, 20) then
			return
		end
		jet.model:SetAttribute("Throttle", math.round(throttle * 100) / 100)
		jet.model:SetAttribute("Afterburner", afterburner)
		jet.model:SetAttribute("GLoad", math.round(gLoad * 10) / 10)
	end)

	local function onPlayerAdded(player: Player)
		player.ReplicationFocus = idleFocus()
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		local jet = jetByPlayer[player]
		if jet then
			self:Despawn(jet, "PilotLeft")
		end
	end)
end

function AircraftService:Start()
	RunService.Heartbeat:Connect(function()
		debug.profilebegin("AircraftService.collisions")
		checkCollisions()
		debug.profileend()
	end)
end

return AircraftService
