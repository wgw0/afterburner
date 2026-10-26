--!strict
-- Cockpit tones (DEVELOPMENT.md §21, AUD-03): IR seeker, RWR, missile launches.
--   Seeker: a low growl while a heat-seeker sees a target, a high steady tone once locked.
--   RWR: a ping per new search radar, a repeating tone while locked, a fast alarm while a missile guides
--     on you.
--   Missile launch: a whoosh (yours non-positional, others 3D). Detonations: CombatFxController.
-- Placeholder sounds: built-in Roblox content plus one Creator Store launch sound.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local FlightController = require(script.Parent.FlightController)
local MissileViewController = require(script.Parent.MissileViewController)
local SensorController = require(script.Parent.SensorController)

local PING = "rbxasset://sounds/electronicpingshort.wav"
local CLICK = "rbxasset://sounds/clickfast.wav"

local ToneController = {
	Priority = 82,
}

local group: SoundGroup
local seekerTone: Sound
local knownSearch: { [number]: boolean } = {}
local lockTimer = 0
local launchTimer = 0

local function sound(id: string, volume: number, looped: boolean): Sound
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume
	s.Looped = looped
	s.SoundGroup = group
	s.Parent = SoundService
	return s
end

local function oneShot(id: string, volume: number, speed: number)
	local s = sound(id, volume, false)
	s.PlaybackSpeed = speed
	s:Play()
	s.Ended:Once(function()
		s:Destroy()
	end)
end

local function playAsset(name: string, position: Vector3?, volume: number)
	local audio = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Audio")
	local source = audio and audio:FindFirstChild(name)
	if not (source and source:IsA("Sound")) then
		return
	end
	local s = source:Clone()
	s.Volume = volume
	s.SoundGroup = group
	if position then
		local anchor = Instance.new("Attachment")
		anchor.WorldPosition = position
		anchor.Parent = workspace.Terrain
		s.RollOffMaxDistance = 3000
		s.Parent = anchor
		s:Play()
		task.delay(6, function()
			anchor:Destroy()
		end)
	else
		s.Parent = SoundService
		s:Play()
		s.Ended:Once(function()
			s:Destroy()
		end)
	end
end

local function update(dt: number)
	local flying = FlightController.jet ~= nil and not FlightController:IsUnconscious()

	-- IR seeker tone
	local missile = if flying then SensorController:SelectedMissile() else nil
	local irSelected = missile ~= nil and missile.Class:sub(1, 2) == "IR"
	if irSelected and SensorController.irTargetId ~= 0 then
		if not seekerTone.IsPlaying then
			seekerTone:Play()
		end
		seekerTone.PlaybackSpeed = if SensorController.irLocked then 2.2 else 0.7
		seekerTone.Volume = if SensorController.irLocked then 0.35 else 0.2
	elseif seekerTone.IsPlaying then
		seekerTone:Stop()
	end

	-- RWR tones
	local hasLock, hasLaunch = false, false
	local search: { [number]: boolean } = {}
	if flying then
		for _, threat in SensorController.threats do
			if threat.kind == "Launch" then
				hasLaunch = true
			elseif threat.kind == "Lock" then
				hasLock = true
			else
				search[threat.id] = true
				if not knownSearch[threat.id] then
					oneShot(PING, 0.3, 1) -- new radar searching you
				end
			end
		end
	end
	knownSearch = search

	launchTimer -= dt
	lockTimer -= dt
	if hasLaunch and launchTimer <= 0 then
		launchTimer = 0.18
		oneShot(PING, 0.5, 2.2)
	elseif hasLock and not hasLaunch and lockTimer <= 0 then
		lockTimer = 0.6
		oneShot(PING, 0.4, 1.4)
	end
end

function ToneController:Init()
	group = SoundService:FindFirstChild("Cockpit") :: SoundGroup? or Instance.new("SoundGroup")
	group.Name = "Cockpit"
	group.Volume = 0.5
	group.Parent = SoundService
	seekerTone = sound(CLICK, 0.2, true)
end

function ToneController:Start()
	MissileViewController.Launched:Connect(function(position: Vector3, ownerJetId: number)
		local mine = FlightController.jet and FlightController.jet:GetAttribute("JetId") == ownerJetId
		playAsset("MissileLaunch", if mine then nil else position, if mine then 0.5 else 0.9)
	end)
	RunService.RenderStepped:Connect(update)
end

return ToneController
