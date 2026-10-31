--!strict
-- Skins on jet models (art pipeline §2). Shared: the server paints spawned jets (everyone sees the same
-- paint) and the client paints its menu previews. A skin is a folder of SurfaceAppearances, one per
-- texture set, in ReplicatedStorage.Assets.Skins.<Airframe>.<SkinId>; applying it clones each into
-- every MeshPart whose TextureSet attribute matches. Scripts can't change a SurfaceAppearance's images,
-- so skins are swapped as whole instances.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LevelRewards = require(script.Parent.Config.LevelRewards)
local SkinConfig = require(script.Parent.Config.Skins)

local Skins = {}

local function folderFor(airframeId: string, skinId: string): Instance?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local skins = assets and assets:FindFirstChild("Skins")
	local airframe = skins and skins:FindFirstChild(airframeId)
	return airframe and airframe:FindFirstChild(skinId)
end

-- A jet's skins: its own, then the level skins whose paint for it is installed.
function Skins.list(airframeId: string): { SkinConfig.Skin }
	local own = SkinConfig[airframeId]
	if not own then
		return {}
	end
	local list = table.clone(own)
	for _, skin in LevelRewards.SKINS do
		if folderFor(airframeId, skin.Id) then
			table.insert(list, { Id = skin.Id, DisplayName = skin.DisplayName, Level = skin.Level })
		end
	end
	return list
end

function Skins.get(airframeId: string, skinId: string): SkinConfig.Skin?
	for _, skin in Skins.list(airframeId) do
		if skin.Id == skinId then
			return skin
		end
	end
	return nil
end

-- Whether a skin's paint for this jet is installed (camos are painted for every jet, but check).
function Skins.installed(airframeId: string, skinId: string): boolean
	return folderFor(airframeId, skinId) ~= nil
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

-- Wings for a skin that's sold for Credits, unless it sets its own price (DESIGN §8.2: 75-600 R$ worth; SHP-04)
Skins.WINGS_PRICE = 150

-- A skin's price in Wings, or nil if it isn't sold (it comes with the jet, or with a pilot level).
function Skins.wingsPrice(skin: SkinConfig.Skin): number?
	if skin.Default or skin.Level then
		return nil
	end
	return skin.Wings or (if skin.Credits then Skins.WINGS_PRICE else nil)
end

return Skins
