--!strict
-- General Dynamics F-16A Fighting Falcon. Fly-by-wire, 9 G, a superb sustained turn and all-aspect
-- AIM-9Ls; no radar missiles yet. The NATO branch's Tier III jet. Starting values from public figures;
-- tune in playtests.
return {
	Id = "F16A",
	DisplayName = "F-16A Fighting Falcon",
	NameStatus = "Real",
	FallbackName = 'F-16A "Viper-A"',
	Branch = "NATO",
	Tier = 3,
	BattleRating = 4.7,
	Era = "EarlyGlass",
	ModelName = "F16A",

	Mass = 8600, -- empty 7,070 kg + pilot, gun, ammo, rails
	Fuel = 3200,
	MaxThrust = 65000, -- F100-PW-200 dry
	AfterburnerMult = 1.63, -- 106 kN wet
	FuelBurnDry = 1.4,
	FuelBurnAB = 6.0,

	WingArea = 27.87,
	CD0 = 0.019,
	InducedK = 0.1,
	CLAlpha = 4.5,
	CLMax = 1.6,
	CriticalAoA = 25,

	MaxG = 9.0,
	MinG = -3,
	MaxRollRate = 105,
	MaxPitchRate = 26,
	MaxYawRate = 12,
	-- Weapons and sensors
	Missiles = { { Weapon = "AIM9L", Count = 6 } },
	Radar = { Range = 16000, Cone = 30, CanNotch = true }, -- AN/APG-66: pulse-Doppler
	RWR = { LaunchWarning = false, Resolution = "Fine" },
	Countermeasures = { Flares = 30, Chaff = 30 },
	Gun = "M61A1",
	MaxMach = 2.0,
}
