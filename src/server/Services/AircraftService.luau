--!strict
-- Owns every jet in the world (DEVELOPMENT.md §10): spawning, network ownership, telemetry, despawn.
-- Phase 1: one place, airborne spawns over the test range, no characters.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AircraftData = require(Shared.AircraftData)
local Contract = require(Shared.AircraftModelContract)
local Flight = require(Shared.Config.Flight)
local Net = require(Shared.Net)
local Signal = require(Shared.Util.Signal)
local Units = require(Shared.Units)
local Validate = require(Shared.Util.Validate)

export type Jet = {
	id: number,
	model: Model,
	root: BasePart,
	airframeId: string,
	pilot: Player?,
	spawnTime: number,
}

local AircraftService = {
	Priority = 20,
	JetSpawned = Signal.new(),
	JetDestroyed = Signal.new(), -- (jet, cause)
}

local jets: { [number]: Jet } = {}
local jetByPlayer: { [Player]: Jet } = {}
local nextId = 0
local jetsFolder: Folder

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

function AircraftService:GetJet(player: Player): Jet?
	return jetByPlayer[player]
end

function AircraftService:GetJets(): { [number]: Jet }
	return jets
end

-- With streaming on and no characters, the server streams around each player's ReplicationFocus.
-- Without a jet, that's the test range, so the menu backdrop is loaded.
local function idleFocus(): BasePart?
	local range = workspace:FindFirstChild("TestRange")
	local strip = range and range:FindFirstChild("Runway") and range.Runway:FindFirstChild("Strip")
	return if strip and strip:IsA("BasePart") then strip else nil
end

function AircraftService:Despawn(jet: Jet, cause: string)
	if jets[jet.id] == nil then
		return
	end
	jets[jet.id] = nil
	if jet.pilot and jetByPlayer[jet.pilot] == jet then
		jetByPlayer[jet.pilot] = nil
	end
	if jet.pilot and jet.pilot.Parent then
		jet.pilot.ReplicationFocus = idleFocus()
	end
	self.JetDestroyed:Fire(jet, cause)
	jet.model:Destroy()
end

function AircraftService:Spawn(pilot: Player, airframeId: string, cframe: CFrame?): Jet?
	local airframe = AircraftData.get(airframeId)
	local template = modelFor(airframeId)
	if not (airframe and template) then
		return nil
	end

	local existing = jetByPlayer[pilot]
	if existing then
		self:Despawn(existing, "Respawn")
	end

	nextId += 1
	local id = nextId
	local startCFrame = cframe or spawnCFrame(id)
	local startVelocity = startCFrame.LookVector * Units.velocityToStuds(Flight.SPAWN_SPEED)

	local model = template:Clone()
	model.Name = `{airframeId}_{pilot.Name}`
	model:SetAttribute("JetId", id)
	model:SetAttribute("AirframeId", airframeId)
	model:SetAttribute("PilotUserId", pilot.UserId)
	model:SetAttribute("Team", "")
	model:SetAttribute("IsAI", false)
	model:SetAttribute("Throttle", 0.8)
	model:SetAttribute("Afterburner", false)
	model:SetAttribute("GLoad", 1)
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent

	local root = model.PrimaryPart :: BasePart
	local attachment = Instance.new("Attachment")
	attachment.Name = "PhysicsAttachment"
	attachment.Parent = root

	-- The pilot's client drives these every frame (FlightController). Unlimited force/torque so the
	-- flight model, not Roblox gravity, decides the motion.
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
	pilot.ReplicationFocus = root

	local jet: Jet = {
		id = id,
		model = model,
		root = root,
		airframeId = airframeId,
		pilot = pilot,
		spawnTime = os.clock(),
	}
	jets[id] = jet
	jetByPlayer[pilot] = jet
	self.JetSpawned:Fire(jet)
	return jet
end

function AircraftService:Init()
	-- Battle places fly jets, not characters (§10.1).
	Players.CharacterAutoLoads = false

	jetsFolder = Instance.new("Folder")
	jetsFolder.Name = "Jets"
	jetsFolder.Parent = workspace

	-- Every airframe needs a valid model; fail loudly at boot rather than when someone spawns.
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
	end
	if #problems > 0 then
		error("[AircraftService] Aircraft model problems:\n  " .. table.concat(problems, "\n  "), 0)
	end

	Net.Server.on("RequestSpawn", function(player: Player, airframeId: string)
		if AircraftData.get(airframeId) == nil then
			return
		end
		self:Spawn(player, airframeId)
	end)

	Net.Server.on("ReportCrash", function(player: Player)
		-- Phase 1 trusts the pilot; Phase 2 (AIR-02) verifies crashes on the server.
		local jet = jetByPlayer[player]
		if jet then
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

return AircraftService
