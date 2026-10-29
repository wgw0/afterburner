--!strict
-- Sukhoi Su-35S. The ultimate Flanker: AL-41 engines with three-dimensional thrust vectoring, the Irbis-E
-- radar and R-77-1s. Unmatched at low speed. The East branch's Tier VI jet. Starting values from public
-- figures; tune in playtests.
return {
	Id = "Su35S",
	DisplayName = "Su-35S",
	NameStatus = "Real",
	FallbackName = 'Su-35S "Flanker-E"',
	Branch = "East",
	Tier = 6,
	BattleRating = 11.0,
	Era = "FullGlass",
	ModelName = "Su35S",

	Mass = 20000, -- empty 19,000 kg + pilot, gun, ammo, pylons
	Fuel = 6500,
	MaxThrust = 172600, -- 2 × AL-41F1S dry
	AfterburnerMult = 1.65, -- 284 kN wet
	FuelBurnDry = 3.0,
	FuelBurnAB = 13.0,
	ThrustVectoring = true,

	WingArea = 62,
	CD0 = 0.021,
	InducedK = 0.09,
	CLAlpha = 4.7,
	CLMax = 1.85,
	CriticalAoA = 33,

	MaxG = 9.0,
	MinG = -3,
	MaxRollRate = 110,
	MaxPitchRate = 27,
	MaxYawRate = 15,
	-- Weapons and sensors
	Missiles = { { Weapon = "R74M", Count = 4 }, { Weapon = "R77_1", Count = 6 } },
	Radar = { Range = 40000, Cone = 30, CanNotch = true }, -- N035 Irbis-E: electronically scanned
	RWR = { LaunchWarning = true, Resolution = "Fine" },
	Countermeasures = { Flares = 30, Chaff = 30 },
	Gun = "GSh301",
	MaxMach = 2.25,
}
