--!strict
-- Lockheed Martin F-22A Raptor. Stealth, supercruise and thrust vectoring: hard to see on radar, very
-- fast and superb at any speed, with AIM-120Ds and AIM-9Xs in its bays. The NATO branch's Tier VII jet.
-- Starting values from public figures; tune in playtests.
return {
	Id = "F22A",
	DisplayName = "F-22A Raptor",
	NameStatus = "Real",
	FallbackName = 'F-22A "Raptor"',
	Branch = "NATO",
	Tier = 7,
	BattleRating = 12.7,
	Era = "WAD",
	ModelName = "F22A",

	Mass = 20500, -- empty 19,700 kg + pilot, gun, ammo
	Fuel = 6500,
	MaxThrust = 232000, -- 2 × F119-PW-100 dry
	AfterburnerMult = 1.34, -- 312 kN wet
	FuelBurnDry = 3.0,
	FuelBurnAB = 12.0,
	ThrustVectoring = true,
	Stealth = 0.002, -- radar sees it at about a fifth of the usual range

	WingArea = 78,
	CD0 = 0.018,
	WaveDrag = 0.5, -- shaped for supercruise
	InducedK = 0.09,
	CLAlpha = 4.7,
	CLMax = 1.9,
	CriticalAoA = 35,

	MaxG = 9.0,
	MinG = -3,
	MaxRollRate = 120,
	MaxPitchRate = 28,
	MaxYawRate = 14,
	-- Weapons and sensors (carried internally)
	Missiles = { { Weapon = "AIM9X", Count = 2 }, { Weapon = "AIM120D", Count = 6 } },
	Radar = { Range = 48000, Cone = 30, CanNotch = true }, -- AN/APG-77: AESA
	RWR = { LaunchWarning = true, Resolution = "Fine" },
	Countermeasures = { Flares = 30, Chaff = 30 },
	Gun = "M61A1",
	MaxMach = 2.25,
}
