--!strict
-- Radio calls (DEVELOPMENT.md §21, AUD-04): your own short callouts, through the Radio sound group.
--   Your missile leaves the rail:  "Fox one" (semi-active radar), "Fox two" (heat-seeker), "Fox three"
--                                  (active radar)
--   Your kill:                     "Splash one", "Splash two", "Splash three", then "Splash" (counted per life)
--   A missile is fired at you:     "Missile, missile, missile!" (once per missile)
-- Each call is a squelch (RadioIn), the voice line (Assets.Audio.Radio_<Call>), then the squelch tail
-- (RadioOut). With no recording yet the call is text only: it shows in the subtitle area whatever the
-- Subtitles setting (that's all there is of it); with a recording it shows when Subtitles are on.
-- One call at a time; a new one waits for the last, and a call more than QUEUE_LIFE old is dropped.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local WeaponData = require(Shared.WeaponData)

local FlightController = require(script.Parent.FlightController)
local SensorController = require(script.Parent.SensorController)
local ToneController = require(script.Parent.ToneController)

local GAP = 0.25 -- seconds of quiet between calls
local QUEUE_LIFE = 3 -- a call that's waited this long is stale
local TEXT_SECONDS = 2.2 -- how long a text-only call stays up

local CALLS = {
	FoxOne = "Fox one",
	FoxTwo = "Fox two",
	FoxThree = "Fox three",
	SplashOne = "Splash one",
	SplashTwo = "Splash two",
	SplashThree = "Splash three",
	Splash = "Splash",
	MissileMissile = "Missile, missile, missile!",
}
local FOX = { SARH = "FoxOne", IR_Rear = "FoxTwo", IR_All = "FoxTwo", IR_Adv = "FoxTwo", ARH = "FoxThree" }
local SPLASH = { "SplashOne", "SplashTwo", "SplashThree" }

local RadioController = {
	Priority = 82, -- after ToneController
}

local group: SoundGroup
local queue: { { call: string, at: number } } = {}
local busyUntil = 0
local killsThisLife = 0
local knownLaunches: { [number]: boolean } = {}

local function clip(name: string): Sound?
	local audio = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Audio")
	local sound = audio and audio:FindFirstChild(name)
	return if sound and sound:IsA("Sound") then sound else nil
end

-- Plays a clip once through the Radio group; returns its length (0 if there's no such clip).
local function play(name: string): number
	local source = clip(name)
	if not source then
		return 0
	end
	local s = source:Clone()
	s.SoundGroup = group
	s.Parent = SoundService
	s:Play()
	local length = if s.TimeLength > 0 then s.TimeLength else 1
	task.delay(length + 0.5, function()
		s:Destroy()
	end)
	return length
end

local function say(call: string)
	local text = `Radio: "{CALLS[call]}"`
	local voice = clip(`Radio_{call}`)
	if not voice then
		-- Not recorded yet: the squelch and the words on screen
		ToneController:Subtitle(text, TEXT_SECONDS, true)
		busyUntil = os.clock() + play("RadioIn") + 0.6 + GAP
		return
	end
	local squelch = play("RadioIn")
	task.delay(squelch * 0.6, function()
		local length = play(`Radio_{call}`)
		ToneController:Subtitle(text, length + 0.5)
		task.delay(length, function()
			play("RadioOut")
		end)
	end)
	busyUntil = os.clock() + squelch * 0.6 + voice.TimeLength + 0.2 + GAP
end

-- Queues a call (only while you're flying).
local function call(name: string)
	if FlightController.jet then
		table.insert(queue, { call = name, at = os.clock() })
	end
end

local function myJetId(): number
	local jet = FlightController.jet
	return if jet then (jet:GetAttribute("JetId") :: number?) or -1 else -1
end

function RadioController:Init()
	group = SoundService:FindFirstChild("Radio") :: SoundGroup? or Instance.new("SoundGroup")
	group.Name = "Radio"
	group.Volume = 0.5
	group.Parent = SoundService
end

function RadioController:Start()
	Net.Client.on("MissileSpawned", function(_id: number, weaponId: string, ownerJetId: number)
		if ownerJetId ~= myJetId() then
			return
		end
		local weapon = WeaponData.getMissile(weaponId) :: any
		local fox = weapon and FOX[weapon.Class]
		if fox then
			call(fox)
		end
	end)
	Net.Client.on("KillFeed", function(killer: string)
		if killer == Players.LocalPlayer.Name then
			killsThisLife += 1
			call(SPLASH[killsThisLife] or "Splash")
		end
	end)
	FlightController.JetChanged:Connect(function()
		killsThisLife = 0
		table.clear(queue)
		table.clear(knownLaunches)
	end)

	RunService.Heartbeat:Connect(function()
		-- A new missile guiding on you
		if FlightController.jet then
			local launches: { [number]: boolean } = {}
			for _, threat in SensorController.threats do
				if threat.kind == "Launch" then
					launches[threat.id] = true
					if not knownLaunches[threat.id] then
						call("MissileMissile")
					end
				end
			end
			knownLaunches = launches
		end

		local now = os.clock()
		while #queue > 0 and now - queue[1].at > QUEUE_LIFE do
			table.remove(queue, 1)
		end
		if #queue > 0 and now >= busyUntil then
			say(table.remove(queue, 1).call)
		end
	end)
end

return RadioController
