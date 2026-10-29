--!strict
-- Menu sounds (DEVELOPMENT.md §21, AUD-05), through the UI sound group. Clips come from
-- ReplicatedStorage.Assets.Audio (made by tools/audio/ui_sounds.py); a missing clip is silent.
--   UIClick     every menu button
--   UIConfirm   a purchase, research or lineup change that went through
--   LevelUp     a new pilot level on the results screen
--   MatchFound  the matchmaker found you a match

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Sounds = {}

local group: SoundGroup? = nil

local function uiGroup(): SoundGroup
	if group and group.Parent then
		return group
	end
	local g = SoundService:FindFirstChild("UI") :: SoundGroup?
	if not g then
		local made = Instance.new("SoundGroup")
		made.Name = "UI"
		made.Volume = 0.6
		made.Parent = SoundService
		g = made
	end
	group = g
	return g :: SoundGroup
end

function Sounds.play(name: string)
	local audio = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Audio")
	local source = audio and audio:FindFirstChild(name)
	if not (source and source:IsA("Sound")) then
		return
	end
	local s = source:Clone()
	s.SoundGroup = uiGroup()
	s.Parent = SoundService
	s:Play()
	s.Ended:Connect(function()
		s:Destroy()
	end)
end

return Sounds
