--!strict
-- Owns every jet in the world (DEVELOPMENT.md §10): spawning, network ownership, telemetry, crash and
-- collision detection, out-of-bounds (AIR-04), despawn. Jets are flown by a player (who owns the physics)
-- or by the server (AI and test drones, pilot = nil).
--
-- Every jet has an `identity`: the Player, or an AI pilot record ({ Name, UserId = 0, IsAI = true }).
-- Kill credit and match scores are keyed by identity, so AI pilots can score and be scored against.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AircraftData = require(Shared.AircraftData)
local Contract = require(Shared.AircraftModelContract)
local Flight = require(Shared.Config.Flight)
local Scale = require(Shared.Config.Scale)
local Net = require(Shared.Net)
local Signal = require(Shared.Util.Signal)
local Skins = require(Shared.Skins)
local Units = require(Shared.Units)
local Validate = require(Shared.Util.Validate)
local WeaponData = require(Shared.WeaponData)
local Teams = require(ServerScriptService.Server.Lib.Teams)

export type Jet = {
	id: number,
	model: Model,
	root: BasePart,
	airframeId: string,
	pilot: Player?, -- nil for AI / drones
	identity: any, -- the Player, or an AI pilot record (kill credit and scores key on this)
	name: string, -- shown in the kill feed
	spawnTime: number,
	lastPosition: Vector3,
	lastProbes: { [string]: Vector3 }, -- extremities last tick, for the crash check
	outSince: number?, -- when it left the play area (AIR-04)
}

export type SpawnOptions = {
	name: string?, -- AI display name
	speed: number?, -- real m/s, default Flight.SPAWN_SPEED
	identity: any?, -- AI pilot record (players are their own identity)
	modules: string?, -- fitted modules as a comma list (players get theirs from modulesFor)
}

local CRASH_GRACE = 1.0 -- seconds after spawn before crash checks apply
local COLLISION_DISTANCE = 4.5 -- studs between roots counts as a mid-air collision
local CRASH_REPORT_RANGE = 42 -- studs: a reported crash must be this close to the ground
local OUT_OF_BOUNDS_SECONDS = 10 -- outside the play area this long and the jet is lost
-- Extremities (Root attachments) whose paths are checked too, so a wingtip clipping a hill in a bank or
-- the nose or tail striking first counts as a crash, not only the centre of mass hitting.
local CRASH_PROBES = { "GunMuzzle", "WingtipL", "WingtipR", "Nozzle1" }

local AircraftService = {
	Priority = 20,
	JetSpawned = Signal.new(), -- (jet)
	JetDestroyed = Signal.new(), -- (jet, cause, position)
	-- Set by MatchService: decides whether a player may spawn and where. nil = always, default spawn.
	spawnGate = nil :: ((Player, string) -> (boolean, CFrame?))?,
	-- Set by ProgressionService: the modules a player has fitted to a jet, as a comma list.
	modulesFor = nil :: ((Player, string) -> string)?,
	-- Set by ProgressionService: the skin a player's jet spawns in.
	skinFor = nil :: ((Player, string) -> string?)?,
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
	local offset = CFrame.Angles(0, math.rad(angle), 0) * Vector3.new(0, 0, 700)
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

-- Removes a jet. cause: "Shot" | "Crash" | "Collision" | "OutOfBounds" | "Respawn" | "PilotLeft" | "Despawn"
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
	-- Fitted upgrade modules (Progression.airframeForModel applies them wherever the airframe is used)
	local modules = (options and options.modules)
		or (pilot and self.modulesFor and self.modulesFor(pilot, airframeId))
		or ""
	model:SetAttribute("Modules", modules)
	-- Paint: the pilot's chosen skin; AI jets get a random one, for a varied sky
	local skin = pilot and self.skinFor and self.skinFor(pilot, airframeId)
	if not pilot then
		local choices = Skins.list(airframeId)
		skin = if #choices > 0 then choices[math.random(#choices)].Id else nil
	end
	if skin then
		Skins.apply(model, airframeId, skin)
	end
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
		identity = if pilot then pilot else (options and options.identity) or { Name = name, UserId = 0, IsAI = true },
		name = name,
		spawnTime = os.clock(),
		lastPosition = root.Position,
		lastProbes = {},
	}
	jets[id] = jet
	model:SetAttribute("Team", Teams.of(jet.identity) or "") -- team modes (MCH-05); "" = no team
	-- A belly landing at a shallow angle can slide the hull along the ground without the centre's path
	-- ever crossing it, so the hull touching the map is a crash too.
	local hull = model:FindFirstChild("Hull")
	if hull and hull:IsA("BasePart") then
		hull.Touched:Connect(function(other: BasePart)
			if jets[id] == jet and os.clock() - jet.spawnTime >= CRASH_GRACE then
				if other.CanCollide and not other:IsDescendantOf(jetsFolder) then
					self:Despawn(jet, "Crash")
				end
			end
		end)
	end
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

	local serverNow = workspace:GetServerTimeNow()
	for _, jet in live do
		local position = jet.root.Position
		-- Out of bounds (AIR-04): outside the square play area or above the ceiling for too long
		local outside = math.max(math.abs(position.X), math.abs(position.Z)) > Scale.MAP_HALF_EXTENT
			or position.Y > Scale.CEILING
		if outside then
			if not jet.outSince then
				jet.outSince = now
				jet.model:SetAttribute("OutOfBoundsAt", serverNow + OUT_OF_BOUNDS_SECONDS)
			elseif now - jet.outSince >= OUT_OF_BOUNDS_SECONDS then
				AircraftService:Despawn(jet, "OutOfBounds")
				continue
			end
		elseif jet.outSince then
			jet.outSince = nil
			jet.model:SetAttribute("OutOfBoundsAt", nil)
		end
		local travel = position - jet.lastPosition
		jet.lastPosition = position
		local length = travel.Magnitude
		local crashed = false
		if length > 0.01 and length < 560 then
			-- The path since last tick, extended a little ahead for the nose.
			crashed = workspace:Raycast(position - travel, travel + travel.Unit * 1.7, worldParams) ~= nil
		end
		for _, name in CRASH_PROBES do
			local probe = jet.root:FindFirstChild(name)
			if not (probe and probe:IsA("Attachment")) then
				continue
			end
			local here = probe.WorldPosition
			local last = jet.lastProbes[name]
			jet.lastProbes[name] = here
			local step = if last then here - last else Vector3.zero
			if not crashed and step.Magnitude > 0.01 and step.Magnitude < 560 then
				crashed = workspace:Raycast(last :: Vector3, step, worldParams) ~= nil
			end
		end
		if crashed then
			AircraftService:Despawn(jet, "Crash")
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
		local cframe: CFrame? = nil
		if self.spawnGate then
			local allowed, at = self.spawnGate(player, airframeId)
			if not allowed then
				return
			end
			cframe = at
		end
		self:Spawn(player, airframeId, cframe)
	end)

	Net.Server.on("ReportCrash", function(player: Player)
		-- The pilot stops the jet the moment it hits; accept it only if the jet really is at the ground.
		local jet = jetByPlayer[player]
		if jet and nearGround(jet, CRASH_REPORT_RANGE) then
			self:Despawn(jet, "Crash")
		end
	end)

	-- Back to the hangar. A quiet despawn, unless someone damaged the jet recently: then they get the kill
	-- (DamageModel.resolveCredit), so leaving can't dodge one.
	Net.Server.on("ReturnToHangar", function(player: Player)
		local jet = jetByPlayer[player]
		if jet then
			self:Despawn(jet, "Despawn")
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
