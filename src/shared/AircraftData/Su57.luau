--!strict
-- Sukhoi Su-57. A stealthy Flanker successor: less stealthy than the Raptor, but with 3D thrust vectoring,
-- huge thrust and R-77Ms. The East branch's Tier VII jet. Starting values from public figures; tune in
-- playtests.
return {
	Id = "Su57",
	DisplayName = "Su-57",
	NameStatus = "Real",
	FallbackName = 'Su-57 "Felon"',
	Branch = "East",
	Tier = 7,
	BattleRating = 12.3,
	Era = "WAD",
	ModelName = "Su57",

	Mass = 19000, -- empty 18,000 kg + pilot, gun, ammo
	Fuel = 7000,
	MaxThrust = 176000, -- 2 × AL-41F1 dry
	AfterburnerMult = 1.67, -- 294 kN wet
	FuelBurnDry = 3.0,
	FuelBurnAB = 13.0,
	ThrustVectoring = true,
	Stealth = 0.05, -- radar sees it at about half the usual range

	WingArea = 78.8,
	CD0 = 0.02,
	InducedK = 0.09,
	CLAlpha = 4.8,
	CLMax = 1.9,
	CriticalAoA = 35,

	MaxG = 9.0,
	MinG = -3,
	MaxRollRate = 120,
	MaxPitchRate = 28,
	MaxYawRate = 15,
	-- Weapons and sensors (carried internally)
	Missiles = { { Weapon = "R74M", Count = 2 }, { Weapon = "R77M", Count = 4 } },
	Radar = { Range = 44000, Cone = 30, CanNotch = true }, -- N036 Byelka: AESA
	RWR = { LaunchWarning = true, Resolution = "Fine" },
	Countermeasures = { Flares = 30, Chaff = 30 },
	Gun = "GSh301",
	MaxMach = 2.0,
}
