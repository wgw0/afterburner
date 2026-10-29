--!strict
-- Mikoyan-Gurevich MiG-23MLD. A swing-wing interceptor (flown here at mid sweep): blistering acceleration
-- and a look-down radar with R-24s, but touchy at high AoA. Starting values from public figures; tune
-- in playtests.
return {
	Id = "MiG23MLD",
	DisplayName = "MiG-23MLD",
	NameStatus = "Real",
	FallbackName = 'MiG-23MLD "Flogger-K"',
	Branch = "East",
	Tier = 2,
	BattleRating = 3.3,
	Era = "Analogue",
	ModelName = "MiG23MLD",

	Mass = 11500, -- empty 10,550 kg + pilot, gun, ammo
	Fuel = 4000,
	MaxThrust = 85000, -- R-35-300 dry
	AfterburnerMult = 1.5, -- 127.5 kN wet
	FuelBurnDry = 2.0,
	FuelBurnAB = 7.5,

	WingArea = 35,
	CD0 = 0.02,
	InducedK = 0.12,
	CLAlpha = 3.6,
	CLMax = 1.2,
	CriticalAoA = 18, -- the real jet had a strict AoA limit

	MaxG = 8.0,
	MinG = -3,
	MaxRollRate = 68,
	MaxPitchRate = 18,
	MaxYawRate = 9,
	-- Weapons and sensors
	Missiles = { { Weapon = "R60", Count = 4 }, { Weapon = "R24R", Count = 2 } },
	Radar = { Range = 18000, Cone = 30, CanNotch = true }, -- Sapfir-23ML: look-down capable
	RWR = { LaunchWarning = false, Resolution = "Coarse" },
	Countermeasures = { Flares = 30, Chaff = 30 },
	Gun = "GSh23L",
	MaxMach = 2.35,
}
