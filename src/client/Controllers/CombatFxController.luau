--!strict
-- Combat effects and sounds (DEVELOPMENT.md §20–21, FX-02 / AUD-02). Client-only.
--   Muzzle flash and gun sound on any jet that's firing.
--   Sparks where rounds hit a jet (HitFx), dust where tracers hit the ground.
--   Explosion (fire, smoke, sparks, flash, sound) where a jet is destroyed.
--   A hit "tink" for your hits, and a thud when you're hit.
-- Effects are pooled anchors with ParticleEmitters fired with :Emit(), using built-in textures. Burst sizes,
-- impact dust and the muzzle light follow the effects quality (GraphicsController, FX-05); each jet's muzzle
-- flash is made once and reused for every burst.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Pool = require(Shared.Util.Pool)

local FlightController = require(script.Parent.FlightController)
local GraphicsController = require(script.Parent.GraphicsController)
local MissileViewController = require(script.Parent.MissileViewController)
local SettingsController = require(script.Parent.SettingsController)
local WeaponController = require(script.Parent.WeaponController)

local FIRE_TEXTURE = "rbxasset://textures/particles/fire_main.dds"
local SMOKE_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"
local SPARK_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"

local CombatFxController = {
	Priority = 75,
}

type FxAnchor =
	{ part: Part, fire: ParticleEmitter, smoke: ParticleEmitter, sparks: ParticleEmitter, light: PointLight }

local fxFolder: Folder
local anchorPool: any
local weaponsGroup: SoundGroup
local muzzleFx: { [Model]: { light: PointLight, flash: Part, sound: Sound? } } = {}
local lastDamageTotal = 0

local function emitter(parent: Instance, texture: string): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Texture = texture
	e.Enabled = false
	e.LightEmission = 0.6
	e.Parent = parent
	return e
end

local function makeAnchor(): FxAnchor
	local part = Instance.new("Part")
	part.Name = "FxAnchor"
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Transparency = 1
	part.Size = Vector3.new(0.28, 0.28, 0.28)
	local fire = emitter(part, FIRE_TEXTURE)
	fire.Color = ColorSequence.new(Color3.fromRGB(255, 200, 120), Color3.fromRGB(255, 80, 20))
	fire.LightEmission = 1
	local smoke = emitter(part, SMOKE_TEXTURE)
	smoke.Color = ColorSequence.new(Color3.fromRGB(70, 70, 70), Color3.fromRGB(30, 30, 30))
	smoke.LightEmission = 0
	local sparks = emitter(part, SPARK_TEXTURE)
	sparks.Color = ColorSequence.new(Color3.fromRGB(255, 220, 140))
	sparks.LightEmission = 1
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 160, 80)
	light.Brightness = 0
	light.Range = 17
	light.Parent = part
	return { part = part, fire = fire, smoke = smoke, sparks = sparks, light = light }
end

local function withAnchor(position: Vector3, lifetime: number, setup: (FxAnchor) -> ())
	local anchor: FxAnchor = anchorPool:Get()
	anchor.part.CFrame = CFrame.new(position)
	anchor.part.Parent = fxFolder
	setup(anchor)
	task.delay(lifetime, function()
		anchor.light.Brightness = 0
		anchorPool:Release(anchor)
	end)
end

local function playSound(name: string, position: Vector3?, volume: number)
	local audio = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Audio")
	local source = audio and audio:FindFirstChild(name)
	if not (source and source:IsA("Sound")) then
		return
	end
	local s = source:Clone()
	s.Volume = volume
	s.SoundGroup = weaponsGroup
	if position then
		withAnchor(position, 6, function(anchor)
			s.Parent = anchor.part
			s:Play()
			task.delay(5.9, function()
				s:Destroy()
			end)
		end)
	else
		s.Parent = SoundService
		s:Play()
		s.Ended:Once(function()
			s:Destroy()
		end)
	end
end

local function explosion(position: Vector3)
	withAnchor(position, 6, function(a)
		a.fire.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 5), NumberSequenceKeypoint.new(1, 11) })
		a.fire.Lifetime = NumberRange.new(0.5, 1.1)
		a.fire.Speed = NumberRange.new(5.6, 17)
		a.fire.SpreadAngle = Vector2.new(180, 180)
		a.fire.Transparency = NumberSequence.new(0.1, 1)
		a.fire:Emit(GraphicsController:Count(40))
		a.smoke.Color = ColorSequence.new(Color3.fromRGB(70, 70, 70), Color3.fromRGB(30, 30, 30))
		a.smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 5.6), NumberSequenceKeypoint.new(1, 20) })
		a.smoke.Lifetime = NumberRange.new(2.5, 4.5)
		a.smoke.Speed = NumberRange.new(2.2, 7)
		a.smoke.SpreadAngle = Vector2.new(180, 180)
		a.smoke.Transparency = NumberSequence.new(0.3, 1)
		a.smoke:Emit(GraphicsController:Count(25))
		a.sparks.Size = NumberSequence.new(0.42, 0)
		a.sparks.Lifetime = NumberRange.new(0.6, 1.4)
		a.sparks.Speed = NumberRange.new(17, 45)
		a.sparks.SpreadAngle = Vector2.new(180, 180)
		a.sparks.Acceleration = Vector3.new(0, -17, 0)
		a.sparks:Emit(GraphicsController:Count(50))
		a.light.Range = 34
		a.light.Brightness = if SettingsController:Get("ReduceFlashing") then 1.5 else 8
		task.delay(0.35, function()
			a.light.Brightness = 0
		end)
	end)
	playSound("Explosion", position, 1)
end

local function sparks(position: Vector3, count: number)
	withAnchor(position, 1.5, function(a)
		a.sparks.Size = NumberSequence.new(0.17, 0)
		a.sparks.Lifetime = NumberRange.new(0.2, 0.5)
		a.sparks.Speed = NumberRange.new(8.4, 22)
		a.sparks.SpreadAngle = Vector2.new(70, 70)
		a.sparks.Acceleration = Vector3.zero
		a.sparks:Emit(GraphicsController:Count(count))
	end)
end

local function dust(position: Vector3, material: Enum.Material)
	if not GraphicsController:Profile().impactDust then
		return
	end
	withAnchor(position, 2.5, function(a)
		local water = material == Enum.Material.Water
		a.smoke.Color = if water
			then ColorSequence.new(Color3.fromRGB(230, 240, 255))
			else ColorSequence.new(Color3.fromRGB(120, 105, 85))
		a.smoke.Size = NumberSequence.new(0.84, 2.5)
		a.smoke.Lifetime = NumberRange.new(0.6, 1.2)
		a.smoke.Speed = NumberRange.new(1.1, 3.4)
		a.smoke.SpreadAngle = Vector2.new(30, 30)
		a.smoke.Transparency = NumberSequence.new(0.4, 1)
		a.smoke:Emit(3)
	end)
end

local function dropMuzzle(model: Model)
	local fx = muzzleFx[model]
	if fx then
		fx.light:Destroy()
		fx.flash:Destroy()
		if fx.sound then
			fx.sound:Destroy()
		end
		muzzleFx[model] = nil
	end
end

-- Muzzle flash + gun sound for every firing jet. Made the first time a jet fires and kept (hidden and
-- silent between bursts) until the jet goes.
local function updateMuzzles()
	local me = FlightController.jet
	local lights = GraphicsController:Profile().jetLights
	for _, model in workspace.Jets:GetChildren() do
		if not model:IsA("Model") then
			continue
		end
		local firing = WeaponController:IsFiring(model)
		local fx = muzzleFx[model]
		if firing and not fx then
			local root = model.PrimaryPart
			local muzzle = root and root:FindFirstChild("GunMuzzle") :: Attachment?
			if not (root and muzzle) then
				continue
			end
			local light = Instance.new("PointLight")
			light.Color = Color3.fromRGB(255, 190, 110)
			light.Range = 7
			light.Parent = muzzle
			local flash = Instance.new("Part")
			flash.Anchored = true
			flash.CanCollide = false
			flash.CanTouch = false
			flash.CanQuery = false
			flash.CastShadow = false
			flash.Material = Enum.Material.Neon
			flash.Color = Color3.fromRGB(255, 210, 130)
			flash.Shape = Enum.PartType.Ball
			flash.Parent = fxFolder
			local audio = ReplicatedStorage.Assets:FindFirstChild("Audio")
			local source = audio and audio:FindFirstChild("GunLoop") :: Sound?
			local sound: Sound? = nil
			if source then
				local gunSound = source:Clone()
				gunSound.Looped = true
				gunSound.SoundGroup = weaponsGroup
				gunSound.Volume = if model == me then 0.5 else 0.8
				if model == me then
					gunSound.Parent = SoundService
				else
					gunSound.RollOffMinDistance = 11
					gunSound.RollOffMaxDistance = 700
					gunSound.Parent = root
				end
				sound = gunSound
			end
			fx = { light = light, flash = flash, sound = sound }
			muzzleFx[model] = fx
		end
		if not fx then
			continue
		end
		if fx.sound and firing ~= fx.sound.IsPlaying then
			if firing then
				fx.sound:Play()
			else
				fx.sound:Stop()
			end
		end
		fx.light.Enabled = firing and lights
		fx.flash.Parent = if firing then fxFolder else nil
		if firing then
			local muzzle = fx.light.Parent :: Attachment
			-- Reduce flashing: a steady, dim muzzle light instead of a flicker
			local flicker = if SettingsController:Get("ReduceFlashing") then 0.3 else math.random()
			fx.light.Brightness = 2 + 3 * flicker
			fx.flash.Size = Vector3.one * (0.22 + 0.39 * flicker)
			fx.flash.CFrame = muzzle.WorldCFrame * CFrame.new(0, 0, -0.28)
			fx.flash.Transparency = if flicker > 0.4 then 0.1 else 0.7
		end
	end
	for model in muzzleFx do
		if not model:IsDescendantOf(workspace) then
			dropMuzzle(model)
		end
	end
end

function CombatFxController:Init()
	fxFolder = Instance.new("Folder")
	fxFolder.Name = "AfterburnerFx"
	fxFolder.Parent = workspace
	anchorPool = Pool.new(makeAnchor, 12)
	weaponsGroup = SoundService:FindFirstChild("Weapons") :: SoundGroup? or Instance.new("SoundGroup")
	weaponsGroup.Name = "Weapons"
	weaponsGroup.Volume = 0.2
	weaponsGroup.Parent = SoundService
end

function CombatFxController:Start()
	WeaponController.Impact:Connect(function(position: Vector3, material: Enum.Material)
		dust(position, material)
	end)
	Net.Client.on("HitFx", function(_jetId: number, position: Vector3)
		sparks(position, 8)
	end)
	Net.Client.on("HitConfirm", function()
		playSound("HitImpact", nil, 0.35)
	end)
	Net.Client.on("JetDestroyed", function(_jetId: number, _killer: number, cause: string, position: Vector3)
		if cause == "Shot" or cause == "Crash" or cause == "Collision" then
			explosion(position)
		end
	end)
	-- A thud when you take damage
	Net.Client.on("DamageState", function(fractions: { [string]: number })
		local total = 0
		for _, f in fractions do
			total += f
		end
		if total < lastDamageTotal - 1e-3 then
			playSound("HitImpact", nil, 0.6)
		end
		lastDamageTotal = total
	end)
	FlightController.JetChanged:Connect(function()
		lastDamageTotal = 6
	end)
	MissileViewController.Exploded:Connect(explosion)
	RunService.RenderStepped:Connect(updateMuzzles)
end

return CombatFxController
