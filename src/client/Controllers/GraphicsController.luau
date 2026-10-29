--!strict
-- The effects quality profile for this device (DEVELOPMENT.md §20, FX-05): the EffectsQuality setting
-- through Config/Graphics, with Auto looking at the device (touch-only, Roblox's graphics level). Effects
-- controllers read :Profile() as they make or fire an effect, and Changed fires when it changes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Graphics = require(Shared.Config.Graphics)
local Signal = require(Shared.Util.Signal)

local SettingsController = require(script.Parent.SettingsController)

local GraphicsController = {
	Priority = 8,
	level = "High",
	Changed = Signal.new(), -- (level)
}

local profile: Graphics.Profile = Graphics.PROFILES.High

local function robloxLevel(): number
	local ok, level = pcall(function()
		return UserSettings():GetService("UserGameSettings").SavedQualityLevel.Value
	end)
	return if ok and type(level) == "number" then level else 0
end

local function refresh()
	local level = Graphics.level(SettingsController:Get("EffectsQuality") or "Auto", {
		touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled,
		robloxLevel = robloxLevel(),
	})
	if level ~= GraphicsController.level then
		GraphicsController.level = level
		profile = Graphics.PROFILES[level]
		GraphicsController.Changed:Fire(level)
	end
end

function GraphicsController:Profile(): Graphics.Profile
	return profile
end

-- A burst size for this profile (at least 1).
function GraphicsController:Count(n: number): number
	return Graphics.count(profile, n)
end

function GraphicsController:Init()
	refresh()
	SettingsController.Changed:Connect(function(key)
		if key == "EffectsQuality" then
			refresh()
		end
	end)
	-- Auto follows Roblox's graphics slider
	pcall(function()
		UserSettings():GetService("UserGameSettings"):GetPropertyChangedSignal("SavedQualityLevel"):Connect(refresh)
	end)
end

return GraphicsController
