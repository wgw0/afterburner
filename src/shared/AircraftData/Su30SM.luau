--!strict
-- Sukhoi Su-30SM. A two-seat Flanker with canards and thrust-vectoring nozzles: it can point its nose
-- almost anywhere, with the Bars radar and R-77s. The East branch's Tier V jet. Starting values from public
-- figures; tune in playtests.
return {
	Id = "Su30SM",
	DisplayName = "Su-30SM",
	NameStatus = "Real",
	FallbackName = 'Su-30SM "Flanker-H"',
	Branch = "East",
	Tier = 5,
	BattleRating = 9.3,
	Era = "FullGlass",
	ModelName = "Su30SM",

	Mass = 20000, -- empty 18,800 kg + crew, gun, ammo, pylons
	Fuel = 6000,
	MaxThrust = 150000, -- 2 × AL-31FP dry
	AfterburnerMult = 1.64, -- 246 kN wet
	FuelBurnDry = 2.8,
	FuelBurnAB = 12.0,
	ThrustVectoring = true,

	WingArea = 62,
	CD0 = 0.022,
	InducedK = 0.09,
	CLAlpha = 4.7,
	CLMax = 1.8,
	CriticalAoA = 32,

	MaxG = 9.0,
	MinG = -3,
	MaxRollRate = 95,
	MaxPitchRate = 26,
	MaxYawRate = 14,
	-- Weapons and sensors
	Missiles = { { Weapon = "R73", Count = 4 }, { Weapon = "R77", Count = 4 }, { Weapon = "R27ER", Count = 2 } },
	Radar = { Range = 80000, Cone = 30, CanNotch = true }, -- N011M Bars: electronically scanned
	RWR = { LaunchWarning = true, Resolution = "Fine" },
	Countermeasures = { Flares = 30, Chaff = 30 },
	Gun = "GSh301",
	MaxMach = 2.0,
}
