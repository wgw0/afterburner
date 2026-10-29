--!strict
-- Cockpit tones and voice (DEVELOPMENT.md §21, AUD-03/04).
--   Your weapons, from one pure sine (Assets.Audio.Tone, 741 Hz) pitched with PlaybackSpeed and gated
--   with short volume ramps:
--     Heat-seeker sees a target: a low warbling growl. Locked: a high steady tone.
--     Radar lock-on (1 s): fast beeps. Lock confirmed: one long high beep.
--   Threats (RWR), from Will's recordings in Assets.Audio (falling back to the sine if one is missing):
--     A new radar searching you: RwrContact, once.
--     Locked on you (radar or heat-seeker): RwrLock, over and over.
--     A missile guiding on you: RwrLaunch, over and over.
--   Voice ("Betty"): the HUD's most urgent warning that has a recording is called out, one line at a
--     time; PULL UP cuts in at once and repeats back to back. Warnings without a recording get the
--     master warning chime once when they come up.
--   Missile launch: a whoosh (yours non-positional, others 3D). Detonations: CombatFxController.
--   Subtitles (SET-03 setting): the voice lines and the RWR warnings as text near the bottom of the screen.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local FlightController = require(script.Parent.FlightController)
local HUDController = require(script.Parent.HUDController)
local MissileViewController = require(script.Parent.MissileViewController)
local SensorController = require(script.Parent.SensorController)
local SettingsController = require(script.Parent.SettingsController)

local FALLBACK = "rbxasset://sounds/electronicpingshort.wav"
local RAMP = 60 -- volume units per second: ~15 ms fades, so gating the tone doesn't click
local VOICE_GAP = 0.35 -- seconds of quiet between voice lines
-- Warnings (Betty, the master chime, RWR) are scaled by this: at full volume they drowned everything else
local ALERT_VOLUME = 0.15

-- HUD warnings Betty calls out, most urgent first: the recording, and seconds between repeats while the
-- warning stays up (0 = back to back)
local CALLOUTS = {
	{ warning = "PULL UP", clip = "PullUp", every = 0 },
	{ warning = "ENGINE FIRE", clip = "EngineFire", every = 6 },
	{ warning = "BINGO FUEL", clip = "Bingo", every = 15 },
	{ warning = "ENGINE DAMAGE", clip = "Caution", every = 12 },
}
-- What each recording says, for subtitles
local SUBTITLES = {
	PullUp = "PULL UP, PULL UP",
	EngineFire = "ENGINE FIRE",
	Bingo = "BINGO FUEL",
	Caution = "CAUTION",
	MasterWarning = "[master warning]",
}
-- HUD warnings with no recording: the master warning chime when they come up
local CHIMED = { "STALL", "OVER-G", "G-LIMIT", "RETURN TO BATTLE AREA" }

local ToneController = {
	Priority = 82,
}

type Voice = { sound: Sound, volume: number }

local group: SoundGroup
local seeker: Voice -- your own weapon tones
local warn: Voice -- RWR fallback tones
local knownSearch: { [number]: boolean } = {}
local searchBeepUntil = 0
local lockedBeepUntil = 0
local lastLockId = 0
local clock = 0
local speaking: Sound? = nil -- the voice line playing now
local speakingClip = ""
local voiceFreeAt = 0
local lastSaid: { [string]: number } = {}
local wasUp: { [string]: boolean } = {}
local rwrNextAt = 0 -- when the looping RWR warning plays again
local subtitleLabel: TextLabel
local subtitles: { [string]: number } = {} -- line → shown until (os.clock)

-- Shows a subtitle line for `seconds` (if the Subtitles setting is on); a line already showing is extended.
local function subtitle(text: string, seconds: number)
	if SettingsController:Get("Subtitles") then
		subtitles[text] = math.max(subtitles[text] or 0, os.clock() + seconds)
	end
end

-- For other controllers (RadioController): a line of text in the subtitle area. `always` shows it even with
-- the Subtitles setting off (a radio call with no recording yet is only text).
function ToneController:Subtitle(text: string, seconds: number, always: boolean?)
	if always then
		subtitles[text] = math.max(subtitles[text] or 0, os.clock() + seconds)
	else
		subtitle(text, seconds)
	end
end

local function drawSubtitles(now: number)
	local lines = {}
	for text, untilTime in subtitles do
		if now >= untilTime then
			subtitles[text] = nil
		else
			table.insert(lines, text)
		end
	end
	table.sort(lines)
	subtitleLabel.Text = table.concat(lines, "\n")
	subtitleLabel.Visible = #lines > 0
end

local function clipOf(name: string): Sound?
	local audio = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Audio")
	local source = audio and audio:FindFirstChild(name)
	return if source and source:IsA("Sound") then source else nil
end

local function voice(): Voice
	local source = clipOf("Tone")
	local s: Sound
	if source then
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

local function playAsset(name: string, position: Vector3?, volume: number): Sound?
	local source = clipOf(name)
	if not source then
		return nil
	end
	local s = source:Clone()
	s.Volume = volume
	s.SoundGroup = group
	if position then
		local anchor = Instance.new("Attachment")
		anchor.WorldPosition = position
		anchor.Parent = workspace.Terrain
		s.RollOffMaxDistance = 840
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
	return s
end

local function clipLength(name: string): number
	local source = clipOf(name)
	return if source and source.TimeLength > 0 then source.TimeLength else 1.5
end

local function say(clip: string, now: number)
	if speaking and speaking.Parent then
		speaking:Destroy()
	end
	speaking = playAsset(clip, nil, ALERT_VOLUME)
	speakingClip = clip
	subtitle(`"{SUBTITLES[clip] or clip}"`, clipLength(clip) + 0.5)
	voiceFreeAt = now + clipLength(clip) + VOICE_GAP
	lastSaid[clip] = now
end

local function updateVoice(flying: boolean, now: number)
	local up: { [string]: boolean } = {}
	if flying then
		for _, text in HUDController.warnings do
			-- RETURN TO BATTLE AREA carries a countdown after it
			up[if string.sub(text, 1, 21) == "RETURN TO BATTLE AREA" then "RETURN TO BATTLE AREA" else text] = true
		end
	end
	for _, name in CHIMED do
		if up[name] and not wasUp[name] then
			playAsset("MasterWarning", nil, 0.7 * ALERT_VOLUME)
			subtitle(SUBTITLES.MasterWarning, 2)
		end
	end
	for _, callout in CALLOUTS do
		if not up[callout.warning] then
			lastSaid[callout.clip] = nil -- comes straight back next time it's up
		end
	end
	-- PULL UP cuts in over anything else
	if up["PULL UP"] and not wasUp["PULL UP"] and speakingClip ~= "PullUp" then
		say("PullUp", now)
	elseif now >= voiceFreeAt then
		for _, callout in CALLOUTS do
			local said = lastSaid[callout.clip]
			if up[callout.warning] and (said == nil or now - said >= clipLength(callout.clip) + callout.every) then
				say(callout.clip, now)
				break
			end
		end
	end
	wasUp = up
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
	local hasLock, hasLaunch, newSearch = false, false, false
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
					newSearch = true
				end
			end
		end
	end
	knownSearch = search
	if hasLaunch then
		subtitle("[missile launch warning]", 0.5)
	elseif hasLock then
		subtitle("[radar lock warning]", 0.5)
	end
	if newSearch then
		subtitle("[new radar contact]", 2)
	end
	local loop = if hasLaunch then "RwrLaunch" elseif hasLock then "RwrLock" else nil
	if loop and clipOf(loop) then
		-- Will's recordings: the launch or lock warning, over and over while it lasts
		drive(warn, 0, 1, dt)
		if now >= rwrNextAt then
			playAsset(loop, nil, 0.8 * ALERT_VOLUME)
			rwrNextAt = now + clipLength(loop)
		end
	else
		if not loop then
			rwrNextAt = 0
		end
		if newSearch and not playAsset("RwrContact", nil, 0.6 * ALERT_VOLUME) then
			searchBeepUntil = now + 0.14 -- no recording: a short beep instead
		end
		if hasLaunch then
			drive(warn, 0.6 * ALERT_VOLUME, if pulse(0.24, 0.12) then 1.6 else 1.2, dt)
		elseif hasLock then
			local beeping = clock % 0.8 < 0.1 or (clock % 0.8 > 0.18 and clock % 0.8 < 0.28)
			drive(warn, if beeping then 0.5 * ALERT_VOLUME else 0, 1.15, dt)
		elseif now < searchBeepUntil then
			drive(warn, 0.4 * ALERT_VOLUME, 0.9, dt)
		else
			drive(warn, 0, 1, dt)
		end
	end

	updateVoice(flying, now)
	drawSubtitles(now)
end

function ToneController:Init()
	group = SoundService:FindFirstChild("Cockpit") :: SoundGroup? or Instance.new("SoundGroup")
	group.Name = "Cockpit"
	group.Volume = 0.8
	group.Parent = SoundService
	seeker = voice()
	warn = voice()

	local gui = Instance.new("ScreenGui")
	gui.Name = "AfterburnerSubtitles"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 30
	subtitleLabel = Instance.new("TextLabel")
	subtitleLabel.AnchorPoint = Vector2.new(0.5, 1)
	subtitleLabel.Position = UDim2.new(0.5, 0, 1, -215) -- above the radar scopes
	subtitleLabel.Size = UDim2.fromOffset(600, 60)
	subtitleLabel.BackgroundColor3 = Color3.new(0, 0, 0)
	subtitleLabel.BackgroundTransparency = 0.45
	subtitleLabel.Font = Enum.Font.GothamBold
	subtitleLabel.TextSize = 18
	subtitleLabel.TextColor3 = Color3.new(1, 1, 1)
	subtitleLabel.TextYAlignment = Enum.TextYAlignment.Center
	subtitleLabel.AutomaticSize = Enum.AutomaticSize.Y
	subtitleLabel.Visible = false
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = subtitleLabel
	subtitleLabel.Parent = gui
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

function ToneController:Start()
	MissileViewController.Launched:Connect(function(position: Vector3, ownerJetId: number)
		local mine = FlightController.jet and FlightController.jet:GetAttribute("JetId") == ownerJetId
		playAsset("MissileLaunch", if mine then nil else position, if mine then 0.5 else 0.9)
	end)
	RunService.RenderStepped:Connect(update)
end

return ToneController
