--!strict
-- B-1B Lancer (AI-06): the AI bomber of Strike Escort and PvE waves. Nobody flies it (AIOnly keeps it out of
-- the hangar, the tech tree and the AI fighters' picks). Heavy, slow to turn and slower than the fighters
-- hunting it, so a bomber can be caught; four engines, swing wings, no gun or missiles of its own (the Gun
-- is only there for the schema). The real jet is far heavier than the schema allows: mass and thrust are
-- scaled down together so its thrust-to-weight and handling stay a bomber's.
return {
	Id = "B1B",
	DisplayName = "B-1B Lancer",
	NameStatus = "Real",
	FallbackName = 'B-1B "Bone"',
	Branch = "NATO",
	Tier = 6,
	BattleRating = 10,
	Era = "EarlyGlass",
	ModelName = "B1B",
	AIOnly = true,

	Mass = 40000,
	Fuel = 20000,
	MaxThrust = 92000, -- dry: thrust-to-weight about 0.23, a loaded bomber's
	AfterburnerMult = 1.4,
	FuelBurnDry = 4,
	FuelBurnAB = 14,

	WingArea = 150,
	CD0 = 0.024,
	InducedK = 0.07,
	CLAlpha = 4.8,
	CLMax = 1.4,
	-- The sweep follows Mach like the F-14's: forward when slow, back when fast
	VariableGeometry = {
		Schedule = { { 0.5, 15 }, { 0.7, 25 }, { 0.85, 45 }, { 1.0, 67 } },
		Forward = { CLMax = 1.6, CLAlpha = 5.2, InducedK = 0.06, CD0 = 0.026, WaveDrag = 1.2 },
		Back = { CLMax = 1.0, CLAlpha = 3.6, InducedK = 0.12, CD0 = 0.021, WaveDrag = 0.8 },
		ModelSweep = 40,
		Pivot = Vector3.new(-5.8, 0.05, 0),
	},
	CriticalAoA = 18,

	MaxG = 3,
	MinG = -1,
	MaxRollRate = 35,
	MaxPitchRate = 7,
	MaxYawRate = 4,
	Countermeasures = { Flares = 60, Chaff = 60 },
	RWR = { LaunchWarning = true, Resolution = "Fine" },
	Gun = "M61A1",
	MaxMach = 1.25,
}
