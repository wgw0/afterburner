--!strict
-- Paint schemes per airframe (art pipeline §2). The textures are SurfaceAppearances in
-- ReplicatedStorage.Assets.Skins.<Airframe>.<Id>, one per texture set; the paint script
-- (tools/blender/f5e_paint.py) makes them. The Default skin comes with the jet; others are bought with
-- Credits, or straight away with Wings (Skins.WINGS_PRICE unless a skin sets its own; SHP-04). Camos that paint every
-- jet are cosmetics (Config/Cosmetics), not skins.

export type Skin = {
	Id: string,
	DisplayName: string,
	Credits: number?, -- price; nil = free with the jet
	Wings: number?, -- price in Wings, if not Skins.WINGS_PRICE (skins with a Credits price can always be bought with Wings)
	Default: boolean?,
	Level: number?, -- a level skin (Config/LevelRewards): free at this pilot level, on every jet
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
	F14A = {
		{ Id = "Navy", DisplayName = "Navy Grey", Default = true },
		{ Id = "Gull", DisplayName = "Gull Grey and White", Credits = 5000 },
		{ Id = "Ghost", DisplayName = "Three-Tone Grey", Credits = 5000 },
		{ Id = "Desert", DisplayName = "Desert Camouflage", Credits = 5000 },
	},
	Mirage2000C = {
		{ Id = "AirDefence", DisplayName = "Air Defence Blue-Grey", Default = true },
		{ Id = "Grey", DisplayName = "Low-Visibility Grey", Credits = 5000 },
		{ Id = "Tactical", DisplayName = "Tactical Camouflage", Credits = 5000 },
		{ Id = "Desert", DisplayName = "Desert Camouflage", Credits = 5000 },
	},
	F15C = {
		{ Id = "ModEagle", DisplayName = "Mod Eagle Grey", Default = true },
		{ Id = "Blue", DisplayName = "Air Superiority Blue", Credits = 5000 },
		{ Id = "Aggressor", DisplayName = "Aggressor Blue", Credits = 5000 },
		{ Id = "Desert", DisplayName = "Desert Camouflage", Credits = 5000 },
	},
	FA18C = {
		{ Id = "Navy", DisplayName = "Navy Grey", Default = true },
		{ Id = "Gull", DisplayName = "Gull Grey and White", Credits = 5000 },
		{ Id = "Adversary", DisplayName = "Adversary Camouflage", Credits = 5000 },
		{ Id = "Ghost", DisplayName = "Three-Tone Grey", Credits = 5000 },
	},
	Su27S = {
		{ Id = "Flanker", DisplayName = "Flanker Blue", Default = true },
		{ Id = "Grey", DisplayName = "Low-Visibility Grey", Credits = 5000 },
		{ Id = "Naval", DisplayName = "Naval Blue", Credits = 5000 },
		{ Id = "Desert", DisplayName = "Desert Camouflage", Credits = 5000 },
	},
	TornadoF3 = {
		{ Id = "AirDefence", DisplayName = "Air Defence Grey", Default = true },
		{ Id = "DarkGrey", DisplayName = "Dark Grey", Credits = 5000 },
		{ Id = "Splinter", DisplayName = "Grey Splinter", Credits = 5000 },
		{ Id = "Desert", DisplayName = "Desert Pink", Credits = 5000 },
	},
	F16C = {
		{ Id = "Viper", DisplayName = "Viper Grey", Default = true },
		{ Id = "Ghost", DisplayName = "Blue Ghost", Credits = 5000 },
		{ Id = "Arctic", DisplayName = "Arctic Splinter", Credits = 5000 },
		{ Id = "Night", DisplayName = "Dark Grey", Credits = 5000 },
	},
	F15E = {
		{ Id = "Strike", DisplayName = "Gunship Grey", Default = true },
		{ Id = "Ghost", DisplayName = "Two-Tone Grey", Credits = 5000 },
		{ Id = "Splinter", DisplayName = "Grey Splinter", Credits = 5000 },
		{ Id = "Desert", DisplayName = "Desert Camouflage", Credits = 5000 },
	},
	Su30SM = {
		{ Id = "VKS", DisplayName = "Aerospace Forces Grey", Default = true },
		{ Id = "Blue", DisplayName = "Blue-Grey", Credits = 5000 },
		{ Id = "Naval", DisplayName = "Naval Blue", Credits = 5000 },
		{ Id = "Desert", DisplayName = "Desert Camouflage", Credits = 5000 },
	},
	MiG29SMT = {
		{ Id = "VKS", DisplayName = "Aerospace Forces Grey", Default = true },
		{ Id = "Blue", DisplayName = "Blue-Grey", Credits = 5000 },
		{ Id = "Splinter", DisplayName = "Grey-Green Splinter", Credits = 5000 },
		{ Id = "Desert", DisplayName = "Desert Camouflage", Credits = 5000 },
	},
	GripenC = {
		{ Id = "Grey", DisplayName = "Two-Tone Grey", Default = true },
		{ Id = "DarkGrey", DisplayName = "Dark Grey", Credits = 5000 },
		{ Id = "Splinter", DisplayName = "Splinter Camouflage", Credits = 5000 },
		{ Id = "Arctic", DisplayName = "Arctic", Credits = 5000 },
	},
	FA18E = {
		{ Id = "Navy", DisplayName = "Navy Grey", Default = true },
		{ Id = "CAG", DisplayName = "CAG Markings", Credits = 5000 },
		{ Id = "Adversary", DisplayName = "Adversary Blue", Credits = 5000 },
		{ Id = "Ghost", DisplayName = "Dark Grey", Credits = 5000 },
	},
	Su35S = {
		{ Id = "VKS", DisplayName = "Aerospace Forces Splinter", Default = true },
		{ Id = "Dark", DisplayName = "Dark Grey", Credits = 5000 },
		{ Id = "Flanker", DisplayName = "Flanker Blue", Credits = 5000 },
		{ Id = "Desert", DisplayName = "Desert Camouflage", Credits = 5000 },
	},
	Typhoon = {
		{ Id = "AirDefence", DisplayName = "Air Defence Grey", Default = true },
		{ Id = "TwoTone", DisplayName = "Two-Tone Grey", Credits = 5000 },
		{ Id = "DarkGrey", DisplayName = "Dark Grey", Credits = 5000 },
		{ Id = "Desert", DisplayName = "Desert Camouflage", Credits = 5000 },
	},
	RafaleC = {
		{ Id = "AirDefence", DisplayName = "Air Defence Grey", Default = true },
		{ Id = "TwoTone", DisplayName = "Two-Tone Grey", Credits = 5000 },
		{ Id = "DarkGrey", DisplayName = "Dark Grey", Credits = 5000 },
		{ Id = "Desert", DisplayName = "Desert Camouflage", Credits = 5000 },
	},
	F22A = {
		{ Id = "AirDominance", DisplayName = "Air Dominance Grey", Default = true },
		{ Id = "Dark", DisplayName = "Dark Grey", Credits = 5000 },
		{ Id = "Ghost", DisplayName = "Light Ghost Grey", Credits = 5000 },
		{ Id = "Splinter", DisplayName = "Grey Splinter", Credits = 5000 },
	},
	F35A = {
		{ Id = "Stealth", DisplayName = "Stealth Grey", Default = true },
		{ Id = "Dark", DisplayName = "Dark Grey", Credits = 5000 },
		{ Id = "Ghost", DisplayName = "Light Ghost Grey", Credits = 5000 },
		{ Id = "Aggressor", DisplayName = "Grey Splinter", Credits = 5000 },
	},
	Su57 = {
		{ Id = "VKS", DisplayName = "Aerospace Forces Splinter", Default = true },
		{ Id = "Dark", DisplayName = "Dark Grey", Credits = 5000 },
		{ Id = "Grey", DisplayName = "Two-Tone Grey", Credits = 5000 },
		{ Id = "Desert", DisplayName = "Desert Camouflage", Credits = 5000 },
	},
	Tempest = {
		{ Id = "Shadow", DisplayName = "Shadow Grey", Default = true },
		{ Id = "Storm", DisplayName = "Storm Grey", Credits = 5000 },
		{ Id = "Night", DisplayName = "Night", Credits = 5000 },
		{ Id = "Demonstrator", DisplayName = "Demonstrator", Credits = 5000 },
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
