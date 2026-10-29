--!strict
-- Dassault Mirage IIIE. A Mach 2 delta: fast and slick in a straight line, bleeds speed in hard turns.
-- The Europe branch's Tier I jet (a sidegrade from the starters). Starting values from public figures;
-- tune in playtests.
return {
	Id = "MirageIII",
	DisplayName = "Mirage IIIE",
	NameStatus = "Real",
	FallbackName = 'Mirage "Delta-III"',
	Branch = "Europe",
	Tier = 1,
	BattleRating = 2.0,
	Era = "Analogue",
	ModelName = "MirageIII",

	Mass = 7400, -- empty 7,050 kg + pilot, guns, ammo
	Fuel = 2400,
	MaxThrust = 42000, -- Atar 9C dry
	AfterburnerMult = 1.45, -- 60.8 kN wet
	FuelBurnDry = 1.1,
	FuelBurnAB = 4.0,

	WingArea = 34.85,
	CD0 = 0.016,
	WaveDrag = 0.45, -- a thin delta built for Mach 2 (too little dry thrust to supercruise)
	InducedK = 0.2, -- delta: big induced drag in hard turns
	CLAlpha = 2.9,
	CLMax = 1.3,
	CriticalAoA = 28,

	MaxG = 7.0,
	MinG = -3,
	MaxRollRate = 70,
	MaxPitchRate = 18,
	MaxYawRate = 8,
	-- Weapons and sensors
	Missiles = { { Weapon = "R550Magic", Count = 2 } },
	Radar = { Range = 8800, Cone = 30, CanNotch = false }, -- Cyrano II: pulse radar
	RWR = { LaunchWarning = false, Resolution = "Coarse" },
	Countermeasures = { Flares = 20, Chaff = 20 },
	Gun = "DEFA552_Twin",
	MaxMach = 2.2,
}
