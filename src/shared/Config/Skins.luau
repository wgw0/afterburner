--!strict
-- Paint schemes per airframe (art pipeline §2). The textures are SurfaceAppearances in
-- ReplicatedStorage.Assets.Skins.<Airframe>.<Id>, one per texture set; the paint script
-- (tools/blender/f5e_paint.py) makes them. The Default skin comes with the jet; others are bought with
-- Credits (Robux and season-pass skins come with the shop, Phase 7).

export type Skin = {
	Id: string,
	DisplayName: string,
	Credits: number?, -- price; nil = free with the jet
	Default: boolean?,
}

local SKINS: { [string]: { Skin } } = {
	F5E = {
		{ Id = "Ghost", DisplayName = "Ghost Grey", Default = true },
		{ Id = "Desert", DisplayName = "Desert Aggressor", Credits = 5000 },
		{ Id = "Pacific", DisplayName = "Pacific Aggressor", Credits = 5000 },
		{ Id = "Lizard", DisplayName = "Lizard Aggressor", Credits = 5000 },
	},
	MiG21bis = {
		{ Id = "Silver", DisplayName = "Natural Metal", Default = true },
		{ Id = "Grey", DisplayName = "Interceptor Grey", Credits = 5000 },
		{ Id = "Tactical", DisplayName = "Tactical Camouflage", Credits = 5000 },
	},
}

for _, list in SKINS do
	for _, skin in list do
		table.freeze(skin)
	end
	table.freeze(list)
end
return table.freeze(SKINS)
