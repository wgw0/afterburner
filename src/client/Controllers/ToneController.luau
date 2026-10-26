--!strict
-- Cockpit tones (DEVELOPMENT.md §21, AUD-03). All built from one pure sine (Assets.Audio.Tone, 741 Hz),
-- pitched with PlaybackSpeed and switched on and off with short volume ramps, on two voices:
--   Your weapons:
--     Heat-seeker sees a target: a low warbling growl. Locked: a high steady tone.
--     Radar lock-on (1 s): fast beeps. Lock confirmed: one long high beep.
--   Threats (RWR):
--     A new radar searching you: one short beep.
--     Locked on you: a repeating double beep.
--     A missile guiding on you: a fast high-low alarm.
--   Missile launch: a whoosh (yours non-positional, others 3D). Detonations: CombatFxController.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local FlightController = require(script.Parent.FlightController)
local MissileViewController = require(script.Parent.MissileViewController)
local SensorController = require(script.Parent.SensorController)

local FALLBACK = "rbxasset://sounds/electronicpingshort.wav"
local RAMP = 60 -- volume units per second: ~15 ms fades, so gating the tone doesn't click

local ToneController = {
	Priority = 82,
}

type Voice = { sound: Sound, volume: number }

local group: SoundGroup
local seeker: Voice -- your own weapon tones
local warn: Voice -- RWR tones
local knownSearch: { [number]: boolean } = {}
local searchBeepUntil = 0
local lockedBeepUntil = 0
local lastLockId = 0
local clock = 0

local function voice(): Voice
	local audio = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Audio")
	local source = audio and audio:FindFirstChild("Tone")
	local s: Sound
	if source and source:IsA("Sound") then
		s = source:Clone()
	else
		s = Instance.new("Sound")
		s.SoundId = FALLBACK
	end
	s.Looped = true
	s.Volume = 0
	s.SoundGroup = group
	s.Parent = SoundService
	s.TimePosition = 5 -- skip any fade-in at the start of the recording
	s:Play()
	return { sound = s, volume = 0 }
end

-- Moves a voice toward a volume and pitch (1 = 741 Hz).
local function drive(v: Voice, volume: number, speed: number, dt: number)
	local step = RAMP * dt
	v.volume = if volume > v.volume then math.min(volume, v.volume + step) else math.max(volume, v.volume - step)
	v.sound.Volume = v.volume
	v.sound.PlaybackSpeed = speed
end

-- On/off pattern: true during the "on" part of each period.
local function pulse(period: number, on: number): boolean
	return clock % period < on
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
	clock += dt
	local now = os.clock()
	local flying = FlightController.jet ~= nil and not FlightController:IsUnconscious()

	-- Your weapons
	local missile = if flying then SensorController:SelectedMissile() else nil
	local irSelected = missile ~= nil and missile.Class:sub(1, 2) == "IR"
	if SensorController.lockId ~= 0 and SensorController.lockId ~= lastLockId then
		lockedBeepUntil = now + 0.45 -- radar lock confirmed
	end
	lastLockId = SensorController.lockId
	if flying and irSelected and SensorController.irLocked then
		drive(seeker, 0.45, 1.7, dt)
	elseif irSelected and SensorController.irTargetId ~= 0 then
		local warble = 0.65 + 0.35 * math.sin(clock * math.pi * 2 * 11)
		drive(seeker, 0.35 * warble, 0.55, dt)
	elseif flying and now < lockedBeepUntil then
		drive(seeker, 0.45, 1.6, dt)
	elseif flying and SensorController.acquiringId ~= 0 then
		drive(seeker, if pulse(0.16, 0.07) then 0.4 else 0, 1.35, dt)
	else
		drive(seeker, 0, 1, dt)
	end

	-- RWR
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
					searchBeepUntil = now + 0.14 -- a new radar searching you
				end
			end
		end
	end
	knownSearch = search
	if hasLaunch then
		drive(warn, 0.6, if pulse(0.24, 0.12) then 1.6 else 1.2, dt)
	elseif hasLock then
		local beeping = clock % 0.8 < 0.1 or (clock % 0.8 > 0.18 and clock % 0.8 < 0.28)
		drive(warn, if beeping then 0.5 else 0, 1.15, dt)
	elseif now < searchBeepUntil then
		drive(warn, 0.4, 0.9, dt)
	else
		drive(warn, 0, 1, dt)
	end
end

function ToneController:Init()
	group = SoundService:FindFirstChild("Cockpit") :: SoundGroup? or Instance.new("SoundGroup")
	group.Name = "Cockpit"
	group.Volume = 0.8
	group.Parent = SoundService
	seeker = voice()
	warn = voice()
end

function ToneController:Start()
	MissileViewController.Launched:Connect(function(position: Vector3, ownerJetId: number)
		local mine = FlightController.jet and FlightController.jet:GetAttribute("JetId") == ownerJetId
		playAsset("MissileLaunch", if mine then nil else position, if mine then 0.5 else 0.9)
	end)
	RunService.RenderStepped:Connect(update)
end

return ToneController
