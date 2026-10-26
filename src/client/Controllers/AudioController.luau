--!strict
-- Engine and wind audio (DEVELOPMENT.md §21, AUD-01).
--   Your jet: engine (pitch follows throttle, muffled in the cockpit) plus wind that rises with speed.
--   Other jets: 3D engine sound on their Root, pitch from their Throttle attribute.
-- Sounds come from ReplicatedStorage.Assets.Audio and play through SoundGroups for the future mixer.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Trove = require(Shared.Util.Trove)

local CameraController = require(script.Parent.CameraController)
local FlightController = require(script.Parent.FlightController)

local AudioController = {
	Priority = 80,
}

type JetSound = { engine: Sound, trove: Trove.Trove }

local groups: { [string]: SoundGroup } = {}
local others: { [Model]: JetSound } = {}
local ownEngine: Sound?
local ownWind: Sound?
local cockpitFilter: EqualizerSoundEffect?

local function group(name: string, volume: number): SoundGroup
	local g = SoundService:FindFirstChild(name) :: SoundGroup?
	if not g then
		g = Instance.new("SoundGroup")
		g.Name = name
		g.Parent = SoundService
	end
	(g :: SoundGroup).Volume = volume
	groups[name] = g :: SoundGroup
	return g :: SoundGroup
end

local function template(name: string): Sound?
	local audio = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Audio")
	local sound = audio and audio:FindFirstChild(name)
	return if sound and sound:IsA("Sound") then sound else nil
end

local function loopFrom(name: string, parent: Instance, soundGroup: SoundGroup): Sound?
	local source = template(name)
	if not source then
		warn(`[Audio] Missing ReplicatedStorage.Assets.Audio.{name}`)
		return nil
	end
	local s = source:Clone()
	s.Looped = true
	s.SoundGroup = soundGroup
	s.Volume = 0
	s.Parent = parent
	s:Play()
	return s
end

local function setupOwn()
	if ownEngine then
		ownEngine:Destroy()
	end
	if ownWind then
		ownWind:Destroy()
	end
	-- Parented to SoundService so they play without position (you're sitting in the jet).
	ownEngine = loopFrom("EngineLoop", SoundService, groups.Engine)
	ownWind = loopFrom("WindLoop", SoundService, groups.Wind)
	if ownEngine then
		cockpitFilter = Instance.new("EqualizerSoundEffect")
		cockpitFilter.HighGain = 0
		cockpitFilter.MidGain = 0
		cockpitFilter.LowGain = 0
		cockpitFilter.Parent = ownEngine
	end
end

local function clearOwn()
	if ownEngine then
		ownEngine:Destroy()
		ownEngine = nil
	end
	if ownWind then
		ownWind:Destroy()
		ownWind = nil
	end
	cockpitFilter = nil
end

local function setupOther(model: Model)
	if others[model] or model == FlightController.jet then
		return
	end
	local root = model.PrimaryPart or model:WaitForChild("Root", 5) :: BasePart?
	if not root or model == FlightController.jet then
		return
	end
	local engine = loopFrom("EngineLoop", root, groups.Engine)
	if not engine then
		return
	end
	engine.RollOffMode = Enum.RollOffMode.InverseTapered
	engine.RollOffMinDistance = 60
	engine.RollOffMaxDistance = 3000
	local trove = Trove.new()
	trove:Add(engine)
	others[model] = { engine = engine, trove = trove }
	trove:Add(model.AncestryChanged:Connect(function()
		if not model:IsDescendantOf(workspace) then
			trove:Clean()
			others[model] = nil
		end
	end))
end

local function update()
	local input, state = FlightController.input, FlightController.state
	if ownEngine and input then
		local throttle = input.throttle
		ownEngine.PlaybackSpeed = 0.55 + 0.3 * throttle + (if input.afterburner then 0.05 else 0)
		ownEngine.Volume = 0.1 + 0.15 * throttle + (if input.afterburner then 0.1 else 0)
		if cockpitFilter then
			local inCockpit = CameraController.mode == "Cockpit"
			cockpitFilter.HighGain = if inCockpit then -18 else 0
			cockpitFilter.MidGain = if inCockpit then -6 else 0
		end
	end
	if ownWind and state then
		local s = math.clamp((state.speed - 80) / 300, 0, 1)
		ownWind.Volume = 0.03 + 0.25 * s
		ownWind.PlaybackSpeed = 0.8 + 0.5 * s
	end
	for model, sound in others do
		if model == FlightController.jet then
			-- Never a second (3D) engine on your own jet.
			sound.trove:Clean()
			others[model] = nil
			continue
		end
		local throttle = (model:GetAttribute("Throttle") :: number?) or 0.8
		local ab = model:GetAttribute("Afterburner") == true
		sound.engine.PlaybackSpeed = 0.55 + 0.3 * throttle + (if ab then 0.05 else 0)
		sound.engine.Volume = 0.25 + 0.2 * throttle + (if ab then 0.2 else 0)
	end
end

function AudioController:Init()
	group("Engine", 0.12)
	group("Wind", 0.08)
end

function AudioController:Start()
	FlightController.JetChanged:Connect(function(jet)
		if jet then
			setupOwn()
			local existing = others[jet]
			if existing then
				existing.trove:Clean()
				others[jet] = nil
			end
		else
			clearOwn()
		end
	end)
	local jets = workspace:WaitForChild("Jets")
	jets.ChildAdded:Connect(function(child)
		if child:IsA("Model") then
			task.defer(setupOther, child)
		end
	end)
	for _, child in jets:GetChildren() do
		if child:IsA("Model") then
			task.defer(setupOther, child)
		end
	end
	RunService.RenderStepped:Connect(update)
end

return AudioController
