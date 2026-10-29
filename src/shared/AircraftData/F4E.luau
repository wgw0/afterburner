--!strict
-- McDonnell Douglas F-4E Phantom II. Heavy, powerful, a big radar and Sparrows: the NATO branch's first
-- radar-missile jet. Brutal climb, poor sustained turn. Starting values from public figures; tune in
-- playtests.
return {
	Id = "F4E",
	DisplayName = "F-4E Phantom II",
	NameStatus = "Real",
	FallbackName = 'F-4E "Phantom-E"',
	Branch = "NATO",
	Tier = 2,
	BattleRating = 3.0,
	Era = "Analogue",
	ModelName = "F4E",

	Mass = 15000, -- empty 13,760 kg + crew, gun, ammo, pylons
	Fuel = 6000,
	MaxThrust = 105600, -- 2 × J79-GE-17 dry
	AfterburnerMult = 1.51, -- 159 kN wet
	FuelBurnDry = 2.4,
	FuelBurnAB = 8.5,

	WingArea = 49.2,
	CD0 = 0.023,
	InducedK = 0.13,
	CLAlpha = 3.8,
	CLMax = 1.3,
	CriticalAoA = 22,

	MaxG = 7.33,
	MinG = -3,
	MaxRollRate = 58,
	MaxPitchRate = 16,
	MaxYawRate = 8,
	-- Weapons and sensors
	Missiles = { { Weapon = "AIM9P", Count = 4 }, { Weapon = "AIM7F", Count = 4 } },
	Radar = { Range = 16000, Cone = 30, CanNotch = false }, -- AN/APQ-120: pulse radar, poor look-down
	RWR = { LaunchWarning = false, Resolution = "Coarse" },
	Countermeasures = { Flares = 30, Chaff = 30 },
	Gun = "M61A1",
	MaxMach = 2.2,
}
