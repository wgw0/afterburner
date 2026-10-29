--!strict
-- Settings (DEVELOPMENT.md §29, SET-01). Values live in your save (PlayerDataController); this
-- controller applies them and is the one place to change them:
--   SettingsController:Get(key), SettingsController:Set(key, value) (validated, then saved by the
--   server through SettingsUpdate), and SettingsController.Changed (key, value).
-- Applied straight away: control scheme, mouse sensitivity and invert, field of view, default camera,
-- master and cockpit volume. Read where they're used: Units (HUD), ReduceFlashing (HUD warnings, RWR marks,
-- explosions and muzzle flashes). ReduceShake has nothing to act on yet (there's no camera shake).
-- The settings screen (UI/Screens/Settings) changes them through Set.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Settings = require(Shared.Config.Settings)
local Signal = require(Shared.Util.Signal)

local BindingsController = require(script.Parent.BindingsController)
local CameraController = require(script.Parent.CameraController)
local InputController = require(script.Parent.InputController)
local PlayerDataController = require(script.Parent.PlayerDataController)

local SettingsController = {
	Priority = 6,
	values = Settings.defaults(),
	Changed = Signal.new(), -- (key, value)
}

-- Sound groups with their own volume setting on top of the master volume
local GROUP_SETTINGS = { Cockpit = "CockpitVolume", Music = "MusicVolume", Radio = "RadioVolume" }

local function applyVolumes()
	local master = SettingsController.values.MasterVolume
	for _, group in SoundService:GetChildren() do
		if group:IsA("SoundGroup") then
			local base = group:GetAttribute("BaseVolume") :: number?
			if base == nil then
				base = group.Volume
				group:SetAttribute("BaseVolume", base)
			end
			local own = GROUP_SETTINGS[group.Name]
			group.Volume = (base :: number) * master * (if own then SettingsController.values[own] else 1)
		end
	end
end

local function apply(key: string, value: any)
	if key == "ControlScheme" then
		InputController:SetScheme(value)
	elseif key == "MouseSensitivity" then
		InputController.sensitivity = value
	elseif key == "InvertPitch" then
		InputController.invertPitch = value
	elseif key == "FieldOfView" then
		CameraController.baseFov = value
	elseif key == "DefaultCamera" then
		CameraController.defaultMode = value
	elseif key == "Bindings" then
		BindingsController:SetOverrides(value)
	elseif key == "MasterVolume" or key == "CockpitVolume" or key == "MusicVolume" or key == "RadioVolume" then
		applyVolumes()
	end
end

function SettingsController:Get(key: string): any
	return self.values[key]
end

-- Changes one setting (ignored if the value isn't allowed). Applies at once and saves it.
function SettingsController:Set(key: string, value: any)
	if not Settings.valid(key, value) or self.values[key] == value then
		return
	end
	self.values[key] = value
	apply(key, value)
	self.Changed:Fire(key, value)
	Net.Client.fire("SettingsUpdate", { [key] = value })
end

local function load(saved: any)
	local clean = Settings.sanitize(saved)
	for key, value in clean do
		local changed = SettingsController.values[key] ~= value
		SettingsController.values[key] = value
		apply(key, value)
		if changed then
			SettingsController.Changed:Fire(key, value)
		end
	end
end

function SettingsController:Start()
	-- M toggles the scheme in flight; keep the saved setting in step with it
	InputController.SchemeChanged:Connect(function(scheme)
		if self.values.ControlScheme ~= scheme then
			self:Set("ControlScheme", scheme)
		end
	end)
	PlayerDataController.Changed:Connect(function(keys, data)
		if keys.Settings and data.Settings then
			load(data.Settings)
		end
	end)
	if PlayerDataController.data then
		load(PlayerDataController.data.Settings)
	end
	task.delay(3, applyVolumes) -- sound groups made by other controllers
	SoundService.ChildAdded:Connect(function(child)
		if child:IsA("SoundGroup") then
			task.defer(applyVolumes) -- after its maker has set its base volume
		end
	end)
end

return SettingsController
