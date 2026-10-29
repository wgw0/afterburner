--!strict
-- Dassault Mirage 2000C. A fly-by-wire delta: a brilliant instantaneous turn and climb, then it bleeds
-- speed fast; Magic IIs and Super 530Ds with a look-down radar. The Europe branch's Tier III jet.
-- Starting values from public figures; tune in playtests.
return {
	Id = "Mirage2000C",
	DisplayName = "Mirage 2000C",
	NameStatus = "Real",
	FallbackName = 'Mirage "Two-Thousand"',
	Branch = "Europe",
	Tier = 3,
	BattleRating = 5.0,
	Era = "EarlyGlass",
	ModelName = "Mirage2000C",

	Mass = 9000, -- empty 7,500 kg + pilot, guns, ammo, pylons
	Fuel = 3100,
	MaxThrust = 64000, -- M53-P2 dry
	AfterburnerMult = 1.48, -- 95 kN wet
	FuelBurnDry = 1.5,
	FuelBurnAB = 6.2,

	WingArea = 41, -- a big delta: low wing loading, high drag in the turn
	CD0 = 0.018,
	WaveDrag = 0.6, -- a thin delta built for Mach 2
	InducedK = 0.13,
	CLAlpha = 3.6,
	CLMax = 1.7,
	CriticalAoA = 29,

	MaxG = 9.0,
	MinG = -3.2,
	MaxRollRate = 140,
	MaxPitchRate = 27,
	MaxYawRate = 11,
	-- Weapons and sensors
	Missiles = { { Weapon = "R550Magic2", Count = 2 }, { Weapon = "Super530D", Count = 2 } },
	Radar = { Range = 45000, Cone = 30, CanNotch = true }, -- RDI: pulse-Doppler, look-down
	RWR = { LaunchWarning = false, Resolution = "Fine" },
	Countermeasures = { Flares = 30, Chaff = 30 },
	Gun = "DEFA554_Twin",
	MaxMach = 2.2,
}
