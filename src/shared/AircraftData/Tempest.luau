--!strict
-- Tempest-class concept. The prestige jet, after the UK-led Tempest/GCAP programme, which has no public
-- figures: these are invented (DESIGN §6.2). Extreme sensor range, very low observability, a deep internal
-- magazine. Unlocked from any Tier VII jet (the design also asks for two Tier VII jets and a challenge chain).
return {
	Id = "Tempest",
	DisplayName = "Tempest-class concept",
	NameStatus = "SemiFictional",
	FallbackName = '"Project Tempus"',
	Branch = "Europe",
	Tier = 8,
	BattleRating = 13.0,
	Era = "WAD",
	ModelName = "Tempest",

	Mass = 18000, -- invented: a large twin-engine airframe
	Fuel = 7000,
	MaxThrust = 220000, -- invented: two adaptive-cycle engines, dry
	AfterburnerMult = 1.4, -- 308 kN wet
	FuelBurnDry = 2.6,
	FuelBurnAB = 11.0,
	ThrustVectoring = true,
	Stealth = 0.001, -- radar sees it at under a fifth of the usual range

	WingArea = 85,
	CD0 = 0.017, -- invented: very clean
	InducedK = 0.085,
	CLAlpha = 4.8,
	CLMax = 2.0,
	CriticalAoA = 38,

	MaxG = 9.5,
	MinG = -3,
	MaxRollRate = 140,
	MaxPitchRate = 30,
	MaxYawRate = 15,
	-- Weapons and sensors (carried internally)
	Missiles = { { Weapon = "ASRAAM", Count = 2 }, { Weapon = "Meteor", Count = 6 } },
	Radar = { Range = 150000, Cone = 30, CanNotch = true }, -- invented: a fused multi-function array
	RWR = { LaunchWarning = true, Resolution = "Fine" },
	Countermeasures = { Flares = 30, Chaff = 30 },
	Gun = "BK27",
	MaxMach = 2.3,
}
