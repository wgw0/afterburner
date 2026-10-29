--!strict
-- General Dynamics F-16C Block 50. The F-16 with a bigger engine, a better radar and a helmet sight:
-- AIM-9Xs that lock far off the nose and AIM-120Cs. The NATO branch's Tier V jet. Starting values from
-- public figures; tune in playtests.
return {
	Id = "F16C",
	DisplayName = "F-16C Fighting Falcon",
	NameStatus = "Real",
	FallbackName = 'F-16C "Viper-C"',
	Branch = "NATO",
	Tier = 5,
	BattleRating = 9.0,
	Era = "FullGlass",
	ModelName = "F16C",

	Mass = 10000, -- empty 8,900 kg + pilot, gun, ammo, rails
	Fuel = 3200,
	MaxThrust = 76000, -- F110-GE-129 dry
	AfterburnerMult = 1.72, -- 131 kN wet
	FuelBurnDry = 1.6,
	FuelBurnAB = 7.0,

	WingArea = 27.87,
	CD0 = 0.02,
	InducedK = 0.1,
	CLAlpha = 4.5,
	CLMax = 1.6,
	CriticalAoA = 25,

	MaxG = 9.0,
	MinG = -3,
	MaxRollRate = 110,
	MaxPitchRate = 26,
	MaxYawRate = 12,
	-- Weapons and sensors
	Missiles = { { Weapon = "AIM9X", Count = 2 }, { Weapon = "AIM120C", Count = 4 } },
	Radar = { Range = 20000, Cone = 30, CanNotch = true }, -- AN/APG-68: pulse-Doppler
	RWR = { LaunchWarning = true, Resolution = "Fine" },
	Countermeasures = { Flares = 30, Chaff = 30 },
	Gun = "M61A1",
	MaxMach = 2.0,
}
