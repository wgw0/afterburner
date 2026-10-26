--!strict
-- Skins on jet models (art pipeline §2). Shared: the server paints spawned jets (everyone sees the same
-- paint) and the client paints its menu previews. A skin is a folder of SurfaceAppearances, one per
-- texture set, in ReplicatedStorage.Assets.Skins.<Airframe>.<SkinId>; applying it clones each into
-- every MeshPart whose TextureSet attribute matches. Scripts can't change a SurfaceAppearance's images,
-- so skins are swapped as whole instances.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SkinConfig = require(script.Parent.Config.Skins)

local Skins = {}

function Skins.list(airframeId: string): { SkinConfig.Skin }
	return SkinConfig[airframeId] or {}
end

function Skins.get(airframeId: string, skinId: string): SkinConfig.Skin?
	for _, skin in Skins.list(airframeId) do
		if skin.Id == skinId then
			return skin
		end
	end
	return nil
end

-- The skin a jet comes with ("Default" for airframes without skins yet).
function Skins.default(airframeId: string): string
	for _, skin in Skins.list(airframeId) do
		if skin.Default then
			return skin.Id
		end
	end
	return "Default"
end

local function folderFor(airframeId: string, skinId: string): Instance?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local skins = assets and assets:FindFirstChild("Skins")
	local airframe = skins and skins:FindFirstChild(airframeId)
	return airframe and airframe:FindFirstChild(skinId)
end

-- Paints a jet model. Returns whether the skin's textures were found.
function Skins.apply(model: Model, airframeId: string, skinId: string): boolean
	local folder = folderFor(airframeId, skinId)
	if not folder then
		return false
	end
	for _, part in model:GetChildren() do
		local set = part:IsA("MeshPart") and part:GetAttribute("TextureSet")
		local source = set and folder:FindFirstChild(set)
		if source and source:IsA("SurfaceAppearance") then
			local old = part:FindFirstChildWhichIsA("SurfaceAppearance")
			if old then
				old:Destroy()
			end
			source:Clone().Parent = part
		end
	end
	model:SetAttribute("Skin", skinId)
	return true
end

return Skins
