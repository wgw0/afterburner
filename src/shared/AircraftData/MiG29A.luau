--!strict
-- Mikoyan MiG-29A. Twin engines, a high-AoA airframe, R-73s and R-27Rs: the East branch's Tier III jet
-- and the F-16's classic rival. Starting values from public figures; tune in playtests.
return {
	Id = "MiG29A",
	DisplayName = "MiG-29A",
	NameStatus = "Real",
	FallbackName = 'MiG-29A "Fulcrum-A"',
	Branch = "East",
	Tier = 3,
	BattleRating = 5.0,
	Era = "Analogue",
	ModelName = "MiG29A",

	Mass = 12000, -- empty 10,900 kg + pilot, gun, ammo, pylons
	Fuel = 3500,
	MaxThrust = 99000, -- 2 × RD-33 dry
	AfterburnerMult = 1.65, -- 162.6 kN wet
	FuelBurnDry = 2.0,
	FuelBurnAB = 8.0,

	WingArea = 38,
	CD0 = 0.02,
	InducedK = 0.1,
	CLAlpha = 4.6,
	CLMax = 1.65,
	CriticalAoA = 26,

	MaxG = 9.0,
	MinG = -3,
	MaxRollRate = 95,
	MaxPitchRate = 25,
	MaxYawRate = 12,
	-- Weapons and sensors
	Missiles = { { Weapon = "R73", Count = 4 }, { Weapon = "R27R", Count = 2 } },
	Radar = { Range = 45000, Cone = 30, CanNotch = true }, -- N019: pulse-Doppler
	RWR = { LaunchWarning = false, Resolution = "Fine" },
	Countermeasures = { Flares = 30, Chaff = 30 },
	Gun = "GSh301",
	MaxMach = 2.25,
}
