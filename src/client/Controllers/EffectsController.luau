--!strict
-- Visual effects for every jet (DEVELOPMENT.md §20, FX-01 / FX-04): afterburner flame, contrails, wingtip
-- vapour, and smoke / fire from a damaged engine (Smoking / OnFire attributes set by the server).
-- Your own jet uses live flight state; other jets use the Throttle/Afterburner/GLoad attributes the
-- server sets from each pilot's telemetry. Client-only; the server never creates effects.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Flight = require(Shared.Config.Flight)
local Trove = require(Shared.Util.Trove)
local Units = require(Shared.Units)

local FlightController = require(script.Parent.FlightController)

local FLAME_COLOUR = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 245, 200)),
	ColorSequenceKeypoint.new(0.35, Color3.fromRGB(255, 160, 60)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 70, 30)),
})

type JetFx = {
	model: Model,
	flames: { Beam },
	lights: { PointLight },
	contrails: { Trail },
	vapour: { Trail },
	smoke: { ParticleEmitter },
	fire: { ParticleEmitter },
	trove: Trove.Trove,
}

local EffectsController = {
	Priority = 70,
}

local active: { [Model]: JetFx } = {}

local function trailPair(root: BasePart, anchor: Attachment, name: string, trove: Trove.Trove): Trail
	local a0 = Instance.new("Attachment")
	a0.Name = name .. "0"
	a0.Position = anchor.Position + Vector3.new(0, 0.15, 0)
	a0.Parent = root
	local a1 = Instance.new("Attachment")
	a1.Name = name .. "1"
	a1.Position = anchor.Position - Vector3.new(0, 0.15, 0)
	a1.Parent = root
	local trail = Instance.new("Trail")
	trail.Name = name
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.FaceCamera = true
	trail.Enabled = false
	trail.Parent = root
	trove:Add(a0)
	trove:Add(a1)
	trove:Add(trail)
	return trail
end

local function setup(model: Model)
	if active[model] then
		return
	end
	local root = model.PrimaryPart or model:WaitForChild("Root", 5) :: BasePart?
	if not root then
		return
	end
	local trove = Trove.new()
	local fx: JetFx =
		{ model = model, flames = {}, lights = {}, contrails = {}, vapour = {}, smoke = {}, fire = {}, trove = trove }

	for _, nozzle in root:GetChildren() do
		if nozzle:IsA("Attachment") and string.match(nozzle.Name, "^Nozzle%d+$") then
			local tail = Instance.new("Attachment")
			tail.Name = nozzle.Name .. "FlameTail"
			tail.Position = nozzle.Position + Vector3.new(0, 0, 14)
			tail.Parent = root
			local beam = Instance.new("Beam")
			beam.Attachment0 = nozzle
			beam.Attachment1 = tail
			beam.FaceCamera = true
			beam.LightEmission = 1
			beam.LightInfluence = 0
			beam.Color = FLAME_COLOUR
			beam.Width0 = 1.8
			beam.Width1 = 0.2
			beam.Transparency = NumberSequence.new(0.1, 1)
			beam.Enabled = false
			beam.Parent = root
			local light = Instance.new("PointLight")
			light.Color = Color3.fromRGB(255, 150, 60)
			light.Range = 30
			light.Brightness = 0
			light.Parent = nozzle
			table.insert(fx.flames, beam)
			-- Damage smoke and fire trail from the engine (FX-04)
			local smoke = Instance.new("ParticleEmitter")
			smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
			smoke.Color = ColorSequence.new(Color3.fromRGB(60, 60, 60), Color3.fromRGB(25, 25, 25))
			smoke.Size = NumberSequence.new(3, 14)
			smoke.Transparency = NumberSequence.new(0.35, 1)
			smoke.Lifetime = NumberRange.new(2.5, 4)
			smoke.Rate = 40
			smoke.Speed = NumberRange.new(2, 6)
			smoke.EmissionDirection = Enum.NormalId.Back
			smoke.Enabled = false
			smoke.Parent = nozzle
			table.insert(fx.smoke, smoke)
			local fire = Instance.new("ParticleEmitter")
			fire.Texture = "rbxasset://textures/particles/fire_main.dds"
			fire.Color = ColorSequence.new(Color3.fromRGB(255, 200, 110), Color3.fromRGB(255, 70, 20))
			fire.LightEmission = 1
			fire.Size = NumberSequence.new(4, 1)
			fire.Transparency = NumberSequence.new(0.1, 1)
			fire.Lifetime = NumberRange.new(0.3, 0.6)
			fire.Rate = 60
			fire.Speed = NumberRange.new(4, 10)
			fire.EmissionDirection = Enum.NormalId.Back
			fire.Enabled = false
			fire.Parent = nozzle
			table.insert(fx.fire, fire)
			trove:Add(smoke)
			trove:Add(fire)
			table.insert(fx.lights, light)
			trove:Add(tail)
			trove:Add(beam)
			trove:Add(light)
		end
	end

	for _, side in { "WingtipL", "WingtipR" } do
		local tip = root:FindFirstChild(side) :: Attachment?
		if tip then
			local contrail = trailPair(root, tip, side .. "Contrail", trove)
			contrail.Lifetime = 4
			contrail.Color = ColorSequence.new(Color3.new(1, 1, 1))
			contrail.Transparency = NumberSequence.new(0.35, 1)
			contrail.WidthScale = NumberSequence.new(0.6, 3)
			table.insert(fx.contrails, contrail)

			local vapour = trailPair(root, tip, side .. "Vapour", trove)
			vapour.Lifetime = 0.5
			vapour.Color = ColorSequence.new(Color3.new(1, 1, 1))
			vapour.Transparency = NumberSequence.new(0.5, 1)
			vapour.WidthScale = NumberSequence.new(0.3, 1)
			table.insert(fx.vapour, vapour)
		end
	end

	active[model] = fx
	trove:Add(model.AncestryChanged:Connect(function()
		if not model:IsDescendantOf(workspace) then
			trove:Clean()
			active[model] = nil
		end
	end))
end

local function update()
	for model, fx in active do
		local root = model.PrimaryPart
		if not root then
			continue
		end
		local afterburner: boolean, throttle: number, gLoad: number
		if model == FlightController.jet and FlightController.input and FlightController.state then
			afterburner = FlightController.input.afterburner
			throttle = FlightController.input.throttle
			gLoad = FlightController.state.gLoad
		else
			afterburner = model:GetAttribute("Afterburner") == true
			throttle = (model:GetAttribute("Throttle") :: number?) or 0
			gLoad = (model:GetAttribute("GLoad") :: number?) or 1
		end
		local flicker = 0.85 + 0.15 * math.noise(os.clock() * 12, model:GetAttribute("JetId") :: number? or 0)
		for i, beam in fx.flames do
			beam.Enabled = afterburner or throttle > 0.95
			local strength = if afterburner then 1 else 0.35
			beam.Width0 = 1.8 * strength * flicker
			fx.lights[i].Brightness = if afterburner then 3 * flicker else 0
		end
		local altitude = Units.altitudeMetres(root.Position.Y)
		local contrailsOn = altitude > Flight.CONTRAIL_ALTITUDE
		for _, trail in fx.contrails do
			trail.Enabled = contrailsOn
		end
		local smoking = model:GetAttribute("Smoking") == true
		local burning = model:GetAttribute("OnFire") == true
		for _, emitter in fx.smoke do
			emitter.Enabled = smoking or burning
		end
		for _, emitter in fx.fire do
			emitter.Enabled = burning
		end
		local vapourOn = gLoad > Flight.VAPOUR_G
		for _, trail in fx.vapour do
			trail.Enabled = vapourOn
		end
	end
end

function EffectsController:Start()
	local jets = workspace:WaitForChild("Jets")
	jets.ChildAdded:Connect(function(child)
		if child:IsA("Model") then
			task.spawn(setup, child)
		end
	end)
	for _, child in jets:GetChildren() do
		if child:IsA("Model") then
			task.spawn(setup, child)
		end
	end
	RunService.RenderStepped:Connect(update)
end

return EffectsController
