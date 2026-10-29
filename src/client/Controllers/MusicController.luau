--!strict
-- Music (DEVELOPMENT.md §21, AUD-05), through the Music sound group (its own volume setting).
--   Menu music (Assets.Audio.MenuMusic, looped) fades in while the menu is up and out when you fly.
--   The results screen: a short sting, VictorySting if you (or your team) won, DefeatSting otherwise, with
--   the menu music held off until the results are done.
-- Missing clips are silent. The tracks are licensed APM Music from Roblox's Creator Store.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local MatchController = require(script.Parent.MatchController)
local MenuController = require(script.Parent.MenuController)

local FADE = 1.5 -- seconds from silent to full, or back

local MusicController = {
	Priority = 92, -- after MenuController
}

local group: SoundGroup
local menuMusic: Sound?
local menuVolume = 0.5 -- the clip's own volume, faded by `level`
local level = 0 -- the menu music's fade, 0..1
local lastState: string? = nil

local function clip(name: string): Sound?
	local audio = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Audio")
	local sound = audio and audio:FindFirstChild(name)
	return if sound and sound:IsA("Sound") then sound else nil
end

local function playOnce(name: string)
	local source = clip(name)
	if not source then
		return
	end
	local s = source:Clone()
	s.Looped = false
	s.SoundGroup = group
	s.Parent = SoundService
	s:Play()
	s.Ended:Connect(function()
		s:Destroy()
	end)
end

-- Did the local player (or their team) win the match these results are for?
local function won(s: any): boolean
	local me = Players.LocalPlayer.Name
	if s.winner == me then
		return true
	end
	for _, score in s.ranking or {} do
		if score.name == me then
			return score.team ~= nil and score.team == s.winner
		end
	end
	return false
end

local function inMatch(s: any): boolean
	for _, score in s.ranking or {} do
		if score.name == Players.LocalPlayer.Name then
			return true
		end
	end
	return false
end

function MusicController:Init()
	group = SoundService:FindFirstChild("Music") :: SoundGroup? or Instance.new("SoundGroup")
	group.Name = "Music"
	group.Volume = 0.35
	group.Parent = SoundService
end

function MusicController:Start()
	local source = clip("MenuMusic")
	if source then
		local s = source:Clone()
		s.Looped = true
		s.Volume = 0
		s.SoundGroup = group
		s.Parent = SoundService
		menuMusic = s
		menuVolume = source.Volume
	end

	MatchController.Changed:Connect(function(s: any)
		if s.state == "Results" and lastState ~= "Results" and inMatch(s) then
			playOnce(if won(s) then "VictorySting" else "DefeatSting")
		end
		lastState = s.state
	end)

	RunService.Heartbeat:Connect(function(dt)
		local music = menuMusic
		if not music then
			return
		end
		local s = MatchController.state
		local results = s ~= nil and s.state == "Results"
		local target = if MenuController.visible and not results then 1 else 0
		level = math.clamp(level + (if target > level then dt else -dt) / FADE, 0, 1)
		music.Volume = menuVolume * level
		if level > 0 and not music.IsPlaying then
			music:Resume()
		elseif level == 0 and music.IsPlaying then
			music:Pause() -- resumes where it left off
		end
	end)
end

return MusicController
