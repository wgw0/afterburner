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
	MirageIII = {
		{ Id = "Tactical", DisplayName = "Armée de l'Air Camouflage", Default = true },
		{ Id = "Silver", DisplayName = "Natural Metal", Credits = 5000 },
		{ Id = "Desert", DisplayName = "Desert Camouflage", Credits = 5000 },
		{ Id = "Grey", DisplayName = "Air Superiority Grey", Credits = 5000 },
	},
	MirageF1 = {
		{ Id = "Interceptor", DisplayName = "Interceptor Blue-Grey", Default = true },
		{ Id = "Tactical", DisplayName = "Tactical Camouflage", Credits = 5000 },
		{ Id = "Desert", DisplayName = "Desert Camouflage", Credits = 5000 },
		{ Id = "Grey", DisplayName = "Low-Visibility Grey", Credits = 5000 },
	},
	F4E = {
		{ Id = "SEA", DisplayName = "Southeast Asia", Default = true },
		{ Id = "HillGray", DisplayName = "Hill Gray", Credits = 5000 },
		{ Id = "EuroOne", DisplayName = "European One", Credits = 5000 },
		{ Id = "Desert", DisplayName = "Desert Camouflage", Credits = 5000 },
	},
	F16A = {
		{ Id = "Falcon", DisplayName = "Three-Tone Grey", Default = true },
		{ Id = "Blue", DisplayName = "Blue Aggressor", Credits = 5000 },
		{ Id = "Desert", DisplayName = "Desert Aggressor", Credits = 5000 },
		{ Id = "Euro", DisplayName = "European Camouflage", Credits = 5000 },
	},
	MiG29A = {
		{ Id = "Grey", DisplayName = "Two-Tone Grey", Default = true },
		{ Id = "Euro", DisplayName = "Central European Grey", Credits = 5000 },
		{ Id = "BlueGrey", DisplayName = "Blue-Grey", Credits = 5000 },
		{ Id = "Desert", DisplayName = "Desert Camouflage", Credits = 5000 },
	},
	-- Art only so far: the F-14A has no flight data yet
	F14A = {
		{ Id = "Navy", DisplayName = "Navy Grey", Default = true },
		{ Id = "Gull", DisplayName = "Gull Grey and White", Credits = 5000 },
		{ Id = "Ghost", DisplayName = "Three-Tone Grey", Credits = 5000 },
		{ Id = "Desert", DisplayName = "Desert Camouflage", Credits = 5000 },
	},
	-- Art only so far: the Mirage 2000C has no flight data yet
	Mirage2000C = {
		{ Id = "AirDefence", DisplayName = "Air Defence Blue-Grey", Default = true },
		{ Id = "Grey", DisplayName = "Low-Visibility Grey", Credits = 5000 },
		{ Id = "Tactical", DisplayName = "Tactical Camouflage", Credits = 5000 },
		{ Id = "Desert", DisplayName = "Desert Camouflage", Credits = 5000 },
	},
	-- Art only so far: the F-15C has no flight data yet
	F15C = {
		{ Id = "ModEagle", DisplayName = "Mod Eagle Grey", Default = true },
		{ Id = "Blue", DisplayName = "Air Superiority Blue", Credits = 5000 },
		{ Id = "Aggressor", DisplayName = "Aggressor Blue", Credits = 5000 },
		{ Id = "Desert", DisplayName = "Desert Camouflage", Credits = 5000 },
	},
	-- Art only so far: the F/A-18C has no flight data yet
	FA18C = {
		{ Id = "Navy", DisplayName = "Navy Grey", Default = true },
		{ Id = "Gull", DisplayName = "Gull Grey and White", Credits = 5000 },
		{ Id = "Adversary", DisplayName = "Adversary Camouflage", Credits = 5000 },
		{ Id = "Ghost", DisplayName = "Three-Tone Grey", Credits = 5000 },
	},
	-- Art only so far: the Su-27S has no flight data yet
	Su27S = {
		{ Id = "Flanker", DisplayName = "Flanker Blue", Default = true },
		{ Id = "Grey", DisplayName = "Low-Visibility Grey", Credits = 5000 },
		{ Id = "Naval", DisplayName = "Naval Blue", Credits = 5000 },
		{ Id = "Desert", DisplayName = "Desert Camouflage", Credits = 5000 },
	},
	-- Art only so far: the Tornado F3 has no flight data yet
	TornadoF3 = {
		{ Id = "AirDefence", DisplayName = "Air Defence Grey", Default = true },
		{ Id = "DarkGrey", DisplayName = "Dark Grey", Credits = 5000 },
		{ Id = "Splinter", DisplayName = "Grey Splinter", Credits = 5000 },
		{ Id = "Desert", DisplayName = "Desert Pink", Credits = 5000 },
	},
	-- Art only so far: the F-16C has no flight data yet
	F16C = {
		{ Id = "Viper", DisplayName = "Viper Grey", Default = true },
		{ Id = "Ghost", DisplayName = "Blue Ghost", Credits = 5000 },
		{ Id = "Arctic", DisplayName = "Arctic Splinter", Credits = 5000 },
		{ Id = "Night", DisplayName = "Dark Grey", Credits = 5000 },
	},
	-- Art only so far: the F-15E has no flight data yet
	F15E = {
		{ Id = "Strike", DisplayName = "Gunship Grey", Default = true },
		{ Id = "Ghost", DisplayName = "Two-Tone Grey", Credits = 5000 },
		{ Id = "Splinter", DisplayName = "Grey Splinter", Credits = 5000 },
		{ Id = "Desert", DisplayName = "Desert Camouflage", Credits = 5000 },
	},
	-- Art only so far: the Su-30SM has no flight data yet
	Su30SM = {
		{ Id = "VKS", DisplayName = "Aerospace Forces Grey", Default = true },
		{ Id = "Blue", DisplayName = "Blue-Grey", Credits = 5000 },
		{ Id = "Naval", DisplayName = "Naval Blue", Credits = 5000 },
		{ Id = "Desert", DisplayName = "Desert Camouflage", Credits = 5000 },
	},
	-- Art only so far: the MiG-29SMT has no flight data yet
	MiG29SMT = {
		{ Id = "VKS", DisplayName = "Aerospace Forces Grey", Default = true },
		{ Id = "Blue", DisplayName = "Blue-Grey", Credits = 5000 },
		{ Id = "Splinter", DisplayName = "Grey-Green Splinter", Credits = 5000 },
		{ Id = "Desert", DisplayName = "Desert Camouflage", Credits = 5000 },
	},
	MiG23MLD = {
		{ Id = "Tactical", DisplayName = "Tactical Camouflage", Default = true },
		{ Id = "TwoTone", DisplayName = "Two-Tone Grey-Green", Credits = 5000 },
		{ Id = "Grey", DisplayName = "Air Defence Grey", Credits = 5000 },
		{ Id = "Desert", DisplayName = "Desert Camouflage", Credits = 5000 },
	},
}

for _, list in SKINS do
	for _, skin in list do
		table.freeze(skin)
	end
	table.freeze(list)
end
return table.freeze(SKINS)
