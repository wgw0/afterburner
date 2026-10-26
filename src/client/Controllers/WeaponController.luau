--!strict
-- Guns on the client (DEVELOPMENT.md §11, GUN-02/05).
--   Left mouse fires the gun. Missiles (Phase 3): R cycles missile type, Space fires it at your radar
--   lock (radar missiles) or what the heat-seeker sees (IR), T locks/unlocks the radar contact nearest
--   your nose, F drops a flare, C drops chaff. The server checks every launch.
--   Gun: The client only tells the server "trigger down/up" plus a spread seed; the server
--   fires and scores the real rounds.
--   Tracers: every client simulates the same rounds from the same seed with Ballistics, so the shooter
--   and everyone watching see matching streams without each round being sent over the network.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AircraftData = require(Shared.AircraftData)
local Ballistics = require(Shared.Ballistics)
local Net = require(Shared.Net)
local Pool = require(Shared.Util.Pool)
local Signal = require(Shared.Util.Signal)
local Units = require(Shared.Units)
local WeaponData = require(Shared.WeaponData)

local FlightController = require(script.Parent.FlightController)
local InputController = require(script.Parent.InputController)
local SensorController = require(script.Parent.SensorController)

local TRACER_EVERY = 2 -- draw every Nth round (real belts mix tracer and ball rounds)
local TRACER_COLOUR = Color3.fromRGB(255, 214, 120)

type Stream = {
	model: Model,
	gun: WeaponData.Gun,
	seed: number,
	index: number,
	timer: number,
	firing: boolean,
	rounds: { { round: Ballistics.Round, part: BasePart? } },
}

local WeaponController = {
	Priority = 35,
	triggerDown = false,
	Fired = Signal.new(), -- (isStart) for audio/effects
	Impact = Signal.new(), -- (position, material) where a tracer hit the world
}

local streams: { [Model]: Stream } = {}
local tracerPool: any
local tracerFolder: Folder
local worldParams: RaycastParams
local localPlayer = Players.LocalPlayer

local function makeTracer(): BasePart
	local p = Instance.new("Part")
	p.Name = "Tracer"
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = TRACER_COLOUR
	p.Size = Vector3.new(0.18, 0.18, 6)
	return p
end

local function streamFor(model: Model): Stream?
	local existing = streams[model]
	if existing then
		return existing
	end
	local gun = WeaponData.get(model:GetAttribute("Gun") :: string)
	if not gun then
		return nil
	end
	local stream: Stream = { model = model, gun = gun, seed = 0, index = 0, timer = 0, firing = false, rounds = {} }
	streams[model] = stream
	return stream
end

local function startStream(model: Model, seed: number)
	local stream = streamFor(model)
	if stream then
		stream.seed, stream.index, stream.timer, stream.firing = seed, 0, 0, true
	end
end

local function stopStream(model: Model)
	local stream = streams[model]
	if stream then
		stream.firing = false
	end
end

local function setTrigger(down: boolean)
	local self = WeaponController
	local jet = FlightController.jet
	if down == self.triggerDown then
		return
	end
	if down and not jet then
		return
	end
	self.triggerDown = down
	if down then
		if (jet :: Model):GetAttribute("Ammo") == 0 or (jet :: Model):GetAttribute("GunJammed") then
			self.triggerDown = false
			return
		end
		local seed = math.random(1, 2 ^ 30)
		Net.Client.fire("GunFire", true, workspace:GetServerTimeNow(), seed)
		startStream(jet :: Model, seed)
	else
		Net.Client.fire("GunFire", false, workspace:GetServerTimeNow(), 0)
		if jet then
			stopStream(jet)
		end
	end
	self.Fired:Fire(down)
end

local function update(dt: number)
	debug.profilebegin("WeaponController.tracers")
	-- Stop our own stream if the gun runs dry or jams (the server stops firing at the same point).
	local jet = FlightController.jet
	if WeaponController.triggerDown and jet and (jet:GetAttribute("Ammo") == 0 or jet:GetAttribute("GunJammed")) then
		setTrigger(false)
	end

	for model, stream in streams do
		local root = model.PrimaryPart
		local alive = root ~= nil and model:IsDescendantOf(workspace)
		-- Fire new rounds at the gun's rate
		if stream.firing and alive and root then
			local interval = Ballistics.interval(stream.gun)
			stream.timer += dt
			local muzzle = root:FindFirstChild("GunMuzzle") :: Attachment?
			local muzzleCF = if muzzle then muzzle.WorldCFrame else root.CFrame
			local velocity = Units.velocityFromStuds(root.AssemblyLinearVelocity)
			while stream.timer >= interval do
				stream.timer -= interval
				local round = Ballistics.fire(muzzleCF, velocity, stream.gun, stream.seed, stream.index)
				local part = if stream.index % TRACER_EVERY == 0 then tracerPool:Get() else nil
				if part then
					part.Parent = tracerFolder
				end
				table.insert(stream.rounds, { round = round, part = part })
				stream.index += 1
			end
		end
		-- Fly rounds, draw tracers, end them on impact or at the end of their life
		local survivors = {}
		for _, entry in stream.rounds do
			local nextRound = Ballistics.step(entry.round, dt, stream.gun.Drag)
			local from, to = entry.round.position, nextRound.position
			local hit = workspace:Raycast(from, to - from, worldParams)
			if hit or nextRound.age >= stream.gun.Lifetime then
				if hit and entry.part then
					WeaponController.Impact:Fire(hit.Position, hit.Material)
				end
				if entry.part then
					tracerPool:Release(entry.part)
				end
			else
				if entry.part then
					local length = math.clamp((to - from).Magnitude * 1.5, 2, 30)
					entry.part.Size = Vector3.new(0.18, 0.18, length)
					entry.part.CFrame = CFrame.lookAt(to, to + (to - from))
				end
				entry.round = nextRound
				table.insert(survivors, entry)
			end
		end
		stream.rounds = survivors
		if not stream.firing and #survivors == 0 and not alive then
			streams[model] = nil
		end
	end
	debug.profileend()
end

local function cycleMissile()
	local jet = FlightController.jet
	if not jet then
		return
	end
	local airframe = AircraftData.get(jet:GetAttribute("AirframeId") :: string) :: any
	local slots = airframe and airframe.Missiles or {}
	if #slots == 0 then
		return
	end
	local current = jet:GetAttribute("SelectedMissile")
	local index = 1
	for i, slot in slots do
		if slot.Weapon == current then
			index = i % #slots + 1
		end
	end
	Net.Client.fire("SelectWeapon", index)
end

local function fireMissile()
	local missile = SensorController:SelectedMissile()
	if not missile then
		return
	end
	local target = 0
	if WeaponData.isRadar(missile) then
		target = SensorController.lockId
		if target == 0 then
			return -- radar missiles need a lock
		end
	elseif SensorController.irLocked then
		target = SensorController.irTargetId
	end
	Net.Client.fire("MissileFire", target)
end

-- Lock the radar contact nearest the nose, or unlock if already locked.
local function toggleLock()
	local root = FlightController.root
	if not root then
		return
	end
	if SensorController.lockId ~= 0 or SensorController.acquiringId ~= 0 then
		SensorController:CancelRadarLock()
		return
	end
	local best, bestDot = 0, -2
	for id, contact in SensorController.contacts do
		if contact.onRadar then
			local dot = root.CFrame.LookVector:Dot((contact.position - root.Position).Unit)
			if dot > bestDot then
				best, bestDot = id, dot
			end
		end
	end
	if best ~= 0 then
		SensorController:StartRadarLock(best)
	end
end

-- Public actions (touch buttons, tutorial)
function WeaponController:SetTrigger(down: boolean)
	setTrigger(down)
end

function WeaponController:FireMissile()
	fireMissile()
end

function WeaponController:ToggleLock()
	toggleLock()
end

function WeaponController:CycleMissile()
	cycleMissile()
end

function WeaponController:IsFiring(model: Model): boolean
	local stream = streams[model]
	return stream ~= nil and stream.firing
end

function WeaponController:Init()
	tracerFolder = Instance.new("Folder")
	tracerFolder.Name = "AfterburnerTracers"
	tracerFolder.Parent = workspace
	tracerPool = Pool.new(makeTracer, 60)
	worldParams = RaycastParams.new()
	worldParams.FilterType = Enum.RaycastFilterType.Exclude
	worldParams.FilterDescendantsInstances = { workspace:WaitForChild("Jets"), tracerFolder }

	UserInputService.InputBegan:Connect(function(input, processed)
		if input.UserInputType == Enum.UserInputType.MouseButton1 and not processed and not InputController.uiOpen then
			setTrigger(true)
		end
	end)
	-- Keyboard and gamepad (INP-03): A gun (hold), X missile, Y lock, B flare, D-pad down chaff,
	-- D-pad up cycle missile.
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or InputController.uiOpen or not FlightController.jet then
			return
		end
		local key = input.KeyCode
		if key == Enum.KeyCode.ButtonA then
			setTrigger(true)
		elseif key == Enum.KeyCode.R or key == Enum.KeyCode.DPadUp then
			cycleMissile()
		elseif key == Enum.KeyCode.Space or key == Enum.KeyCode.ButtonX then
			fireMissile()
		elseif key == Enum.KeyCode.T or key == Enum.KeyCode.ButtonY then
			toggleLock()
		elseif key == Enum.KeyCode.F or key == Enum.KeyCode.ButtonB then
			Net.Client.fire("CountermeasureDeploy", "Flare")
		elseif key == Enum.KeyCode.C or key == Enum.KeyCode.DPadDown then
			Net.Client.fire("CountermeasureDeploy", "Chaff")
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.KeyCode == Enum.KeyCode.ButtonA then
			setTrigger(false)
		end
	end)
	FlightController.JetChanged:Connect(function()
		self.triggerDown = false
	end)

	-- Other jets' tracers
	Net.Client.on("GunFireFx", function(jetId: number, isStart: boolean, seed: number, _serverTime: number)
		for _, model in workspace.Jets:GetChildren() do
			if model:IsA("Model") and model:GetAttribute("JetId") == jetId then
				if model:GetAttribute("PilotUserId") == localPlayer.UserId then
					return -- our own stream is already running locally
				end
				if isStart then
					startStream(model, seed)
				else
					stopStream(model)
				end
				return
			end
		end
	end)
end

function WeaponController:Start()
	RunService.RenderStepped:Connect(update)
end

return WeaponController
