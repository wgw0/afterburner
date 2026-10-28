--!strict
-- Draws missiles, flares and chaff (DEVELOPMENT.md §13.3, MSL-04; FX-03).
--   Missiles: spawned on MissileSpawned, moved from packed MissileState updates (~15 Hz) with a 100 ms
--   interpolation buffer and short extrapolation if packets are late. The motor flame shows only while
--   it burns, then just the smoke trail fades: you can see when a missile has run out of energy.
--   Flares and chaff: simulated locally from the server's spawn event with the same physics.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Countermeasures = require(Shared.Countermeasures)
local Net = require(Shared.Net)
local Pack = require(Shared.Net.Pack)
local Units = require(Shared.Units)

local INTERP_DELAY = 0.1
local MAX_EXTRAPOLATE = 0.2
local CHAFF_LIFETIME = 4
-- A missile is drawn INTERP_DELAY in the past while the jet that fired it is drawn now, so at launch it
-- would appear tens of metres behind its rail. A new missile is drawn in the present instead
-- (extrapolated from its launch velocity), starting on the rail as this client sees the launcher, and
-- eases back to the interpolated track over LAUNCH_BLEND seconds.
local LAUNCH_BLEND = 1.0

type Snapshot = { time: number, position: Vector3, velocity: Vector3, burning: boolean }
type MissileView = {
	part: BasePart,
	trail: Trail,
	flame: PointLight,
	snapshots: { Snapshot },
	ownerJetId: number,
	born: number, -- os.clock() when it appeared
	railOffset: Vector3?, -- from its drawn launch point to the launcher's rail, faded out over LAUNCH_BLEND
	railChecked: boolean,
}
type FlareView = { flare: Countermeasures.Flare, part: BasePart, light: PointLight }

local MissileViewController = {
	Priority = 72,
	Launched = require(Shared.Util.Signal).new(), -- (position, ownerJetId) for audio
	Exploded = require(Shared.Util.Signal).new(), -- (position)
}

local folder: Folder
local views: { [number]: MissileView } = {}
local flareViews: { FlareView } = {}
local smokeTemplate: ParticleEmitter

local function newMissileView(position: Vector3, velocity: Vector3): MissileView
	local part = Instance.new("Part")
	part.Name = "Missile"
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Size = Vector3.new(0.17, 0.17, 2.5)
	part.Color = Color3.fromRGB(225, 225, 220)
	part.Material = Enum.Material.SmoothPlastic
	part.CFrame = CFrame.lookAt(position, position + velocity)
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 0.11, 1.25)
	a0.Parent = part
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -0.11, 1.25)
	a1.Parent = part
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.FaceCamera = true
	trail.Lifetime = 5
	trail.Color = ColorSequence.new(Color3.fromRGB(235, 235, 235))
	trail.Transparency = NumberSequence.new(0.25, 1)
	trail.WidthScale = NumberSequence.new(1, 6)
	trail.Parent = part
	local flame = Instance.new("PointLight")
	flame.Color = Color3.fromRGB(255, 190, 110)
	flame.Range = 7
	flame.Brightness = 4
	flame.Parent = a0
	part.Parent = folder
	return {
		part = part,
		trail = trail,
		flame = flame,
		snapshots = {},
		ownerJetId = 0,
		born = os.clock(),
		railChecked = false,
	}
end

-- The launcher's hardpoint the missile left from, as this client draws the launcher right now: the one
-- whose sideways offset matches the launch point (the lag behind the jet is along its flight path).
local function launchRail(ownerJetId: number, position: Vector3): Attachment?
	local jets = workspace:FindFirstChild("Jets")
	if not (jets and ownerJetId ~= 0) then
		return nil
	end
	for _, model in jets:GetChildren() do
		local root = model:IsA("Model") and model:GetAttribute("JetId") == ownerJetId and model.PrimaryPart
		if root then
			local side = root.CFrame:PointToObjectSpace(position).X
			local best, bestGap = nil, math.huge
			for _, a in root:GetChildren() do
				if a:IsA("Attachment") and string.match(a.Name, "^Hardpoint%d+$") then
					local gap = math.abs(a.Position.X - side)
					if gap < bestGap then
						best, bestGap = a, gap
					end
				end
			end
			return best
		end
	end
	return nil
end

local function sample(view: MissileView, renderTime: number): (Vector3?, Vector3?, boolean)
	local snaps = view.snapshots
	if #snaps == 0 then
		return nil, nil, false
	end
	for i = #snaps, 2, -1 do
		local a, b = snaps[i - 1], snaps[i]
		if a.time <= renderTime and renderTime <= b.time then
			local alpha = (renderTime - a.time) / math.max(b.time - a.time, 1e-3)
			return a.position:Lerp(b.position, alpha), b.velocity, b.burning
		end
	end
	local last = snaps[#snaps]
	local ahead = math.clamp(renderTime - last.time, 0, MAX_EXTRAPOLATE)
	return last.position + Units.velocityToStuds(last.velocity) * ahead, last.velocity, last.burning
end

local function removeView(id: number, fade: boolean)
	local view = views[id]
	if not view then
		return
	end
	views[id] = nil
	view.flame.Brightness = 0
	view.part.Transparency = 1
	if fade then
		-- Let the smoke trail hang in the air for a moment.
		view.trail.Enabled = false
		task.delay(view.trail.Lifetime, function()
			view.part:Destroy()
		end)
	else
		view.part:Destroy()
	end
end

local function spawnFlare(position: Vector3, velocity: Vector3)
	local part = Instance.new("Part")
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(0.45, 0.45, 0.45)
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Material = Enum.Material.Neon
	part.Color = Color3.fromRGB(255, 235, 190)
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 210, 150)
	light.Range = 11
	light.Brightness = 6
	light.Parent = part
	local smoke = smokeTemplate:Clone()
	smoke.Parent = part
	smoke.Enabled = true
	part.Position = position
	part.Parent = folder
	table.insert(flareViews, {
		flare = { id = 0, position = position, velocity = velocity, age = 0 },
		part = part,
		light = light,
	})
end

local function spawnChaff(position: Vector3)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Transparency = 1
	part.Size = Vector3.one * 0.28
	part.Position = position
	local cloud = Instance.new("ParticleEmitter")
	cloud.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	cloud.Color = ColorSequence.new(Color3.fromRGB(200, 200, 210))
	cloud.LightEmission = 0.3
	cloud.Size = NumberSequence.new(0.17, 0.056)
	cloud.Lifetime = NumberRange.new(2, CHAFF_LIFETIME)
	cloud.Speed = NumberRange.new(1.4, 5.6)
	cloud.SpreadAngle = Vector2.new(180, 180)
	cloud.Drag = 2
	cloud.Acceleration = Vector3.new(0, -0.84, 0)
	cloud.Enabled = false
	cloud.Parent = part
	part.Parent = folder
	cloud:Emit(60)
	task.delay(CHAFF_LIFETIME + 0.5, function()
		part:Destroy()
	end)
end

local function update(dt: number)
	local serverNow = workspace:GetServerTimeNow()
	local clock = os.clock()
	for _, view in views do
		local t = math.min((clock - view.born) / LAUNCH_BLEND, 1)
		local ease = t * t * (3 - 2 * t) -- 0 at launch, 1 once settled
		local position, velocity, burning = sample(view, serverNow - INTERP_DELAY * ease)
		if position and velocity then
			if not view.railChecked then
				view.railChecked = true
				local rail = launchRail(view.ownerJetId, position)
				if rail and (rail.WorldPosition - position).Magnitude < 112 then
					view.railOffset = rail.WorldPosition - position
				end
			end
			if view.railOffset then
				position += view.railOffset * (1 - ease)
				if t >= 1 then
					view.railOffset = nil
				end
			end
			local dir = if velocity.Magnitude > 1 then velocity.Unit else view.part.CFrame.LookVector
			view.part.CFrame = CFrame.lookAt(position, position + dir)
			view.flame.Brightness = if burning then 4 + math.random() * 2 else 0
			view.trail.Transparency = if burning then NumberSequence.new(0.2, 1) else NumberSequence.new(0.6, 1) -- thinner smoke once the motor is out
		end
	end
	for i = #flareViews, 1, -1 do
		local fv = flareViews[i]
		fv.flare = Countermeasures.stepFlare(fv.flare, dt)
		local heat = Countermeasures.flareHeat(fv.flare) / Countermeasures.FLARE_HEAT
		if heat <= 0 then
			fv.part:Destroy()
			table.remove(flareViews, i)
		else
			fv.part.Position = fv.flare.position
			fv.light.Brightness = 6 * heat
			fv.part.Transparency = 1 - math.clamp(heat * 1.5, 0, 1)
		end
	end
end

function MissileViewController:Init()
	folder = Instance.new("Folder")
	folder.Name = "AfterburnerMissiles"
	folder.Parent = workspace

	smokeTemplate = Instance.new("ParticleEmitter")
	smokeTemplate.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smokeTemplate.Color = ColorSequence.new(Color3.fromRGB(230, 230, 230))
	smokeTemplate.Size = NumberSequence.new(0.42, 1.4)
	smokeTemplate.Transparency = NumberSequence.new(0.5, 1)
	smokeTemplate.Lifetime = NumberRange.new(1.5, 2.5)
	smokeTemplate.Rate = 25
	smokeTemplate.Speed = NumberRange.new(0, 0.28)
	smokeTemplate.Enabled = false

	Net.Client.on(
		"MissileSpawned",
		function(id: number, _weapon: string, ownerJetId: number, position: Vector3, velocity: Vector3)
			local view = newMissileView(position, velocity)
			view.ownerJetId = ownerJetId
			-- Show it on the rail from the first frame, before update() sets up the blend
			local rail = launchRail(ownerJetId, position)
			if rail and (rail.WorldPosition - position).Magnitude < 112 then
				view.part.CFrame = CFrame.lookAt(rail.WorldPosition, rail.WorldPosition + velocity)
			end
			table.insert(
				view.snapshots,
				{ time = workspace:GetServerTimeNow(), position = position, velocity = velocity, burning = true }
			)
			views[id] = view
			self.Launched:Fire(position, ownerJetId)
		end
	)
	Net.Client.on("MissileState", function(packed: buffer)
		local list = Pack.unpackMissiles(packed)
		if not list then
			return
		end
		local now = workspace:GetServerTimeNow()
		for _, snap in list do
			local view = views[snap.id]
			if view then
				table.insert(
					view.snapshots,
					{ time = now, position = snap.position, velocity = snap.velocity, burning = snap.burning }
				)
				if #view.snapshots > 8 then
					table.remove(view.snapshots, 1)
				end
			end
		end
	end)
	Net.Client.on("MissileDetonated", function(id: number, position: Vector3, _hitJetId: number)
		removeView(id, true)
		self.Exploded:Fire(position)
	end)
	Net.Client.on("CountermeasureFx", function(_jetId: number, kind: string, position: Vector3, velocity: Vector3)
		if kind == "Flare" then
			spawnFlare(position, velocity)
		else
			spawnChaff(position)
		end
	end)
end

function MissileViewController:Start()
	RunService.RenderStepped:Connect(update)
end

return MissileViewController
