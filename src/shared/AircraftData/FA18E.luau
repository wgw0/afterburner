--!strict
-- Boeing F/A-18E Super Hornet. Bigger, heavier and longer-legged than the Hornet, with the APG-79 AESA radar
-- and six AIM-120Cs; still the high-angle-of-attack nose-pointer. The NATO branch's Tier VI jet. Starting
-- values from public figures; tune in playtests.
return {
	Id = "FA18E",
	DisplayName = "F/A-18E Super Hornet",
	NameStatus = "Real",
	FallbackName = 'F/A-18E "Rhino"',
	Branch = "NATO",
	Tier = 6,
	BattleRating = 10.0,
	Era = "FullGlass",
	ModelName = "FA18E",

	Mass = 15600, -- empty 14,550 kg + pilot, gun, ammo, pylons
	Fuel = 6500,
	MaxThrust = 124000, -- 2 × F414-GE-400 dry
	AfterburnerMult = 1.58, -- 196 kN wet
	FuelBurnDry = 2.4,
	FuelBurnAB = 10.0,

	WingArea = 46.5,
	CD0 = 0.024, -- draggy canted pylons
	InducedK = 0.1,
	CLAlpha = 4.8,
	CLMax = 1.85,
	CriticalAoA = 35,

	MaxG = 7.5,
	MinG = -3,
	MaxRollRate = 100,
	MaxPitchRate = 24,
	MaxYawRate = 13,
	-- Weapons and sensors
	Missiles = { { Weapon = "AIM9X", Count = 2 }, { Weapon = "AIM120C", Count = 6 } },
	Radar = { Range = 32000, Cone = 30, CanNotch = true }, -- AN/APG-79: AESA
	RWR = { LaunchWarning = true, Resolution = "Fine" },
	Countermeasures = { Flares = 30, Chaff = 30 },
	Gun = "M61A1",
	MaxMach = 1.8,
}
