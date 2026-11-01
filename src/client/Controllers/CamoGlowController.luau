--!strict
-- The Galaxy camo's breathing glow (Shared/CamoGlow). Skins.apply clones the camo's SurfaceAppearances onto a
-- jet, tag and all; every tagged copy outside ReplicatedStorage.Assets gets its EmissiveStrength and
-- EmissiveTint set each frame. Only those jets, on this screen only: nothing goes over the network.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CamoGlow = require(Shared.CamoGlow)

local SettingsController = require(script.Parent.SettingsController)

local CamoGlowController = {
	Priority = 40,
}

local glowing: { [SurfaceAppearance]: number } = {} -- appearance -> its jet's phase

-- One phase per jet model, so its parts breathe together
local function phaseOf(appearance: SurfaceAppearance): number
	local model = appearance:FindFirstAncestorWhichIsA("Model")
	local name = if model then model:GetFullName() else appearance:GetFullName()
	local hash = 0
	for i = 1, #name do
		hash = (hash * 31 + string.byte(name, i)) % 1000
	end
	return hash / 1000
end

local function track(instance: Instance)
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if instance:IsA("SurfaceAppearance") and not (assets and instance:IsDescendantOf(assets)) then
		glowing[instance] = phaseOf(instance)
	end
end

function CamoGlowController:Start()
	CollectionService:GetInstanceAddedSignal(CamoGlow.TAG):Connect(track)
	CollectionService:GetInstanceRemovedSignal(CamoGlow.TAG):Connect(function(instance)
		glowing[instance :: any] = nil
	end)
	for _, instance in CollectionService:GetTagged(CamoGlow.TAG) do
		track(instance)
	end
	RunService.Heartbeat:Connect(function()
		if next(glowing) == nil then
			return
		end
		local now = os.clock()
		local steady = SettingsController:Get("ReduceFlashing") == true
		for appearance, phase in glowing do
			if appearance.Parent == nil then
				glowing[appearance] = nil
				continue
			end
			local strength, tint = CamoGlow.at(now, phase, steady)
			appearance.EmissiveStrength = strength
			appearance.EmissiveTint = tint
		end
	end)
end

return CamoGlowController
