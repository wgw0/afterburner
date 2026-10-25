--!strict
-- Mikoyan-Gurevich MiG-21bis. Fast in a straight line, bleeds energy in turns. The Eastern starter jet.
-- Starting values from public figures; tune in playtests.
return {
	Id = "MiG21bis",
	DisplayName = "MiG-21bis",
	NameStatus = "Real",
	FallbackName = 'MiG-21bis "Fishbed-L"',
	Branch = "East",
	Tier = 1,
	BattleRating = 1.7,
	Era = "Analogue",
	ModelName = "MiG21bis",

	Mass = 5700, -- empty 5,460 kg + pilot, gun, ammo
	Fuel = 2350,
	MaxThrust = 40200, -- R25-300 dry
	AfterburnerMult = 1.73, -- 69.6 kN wet
	FuelBurnDry = 1.08,
	FuelBurnAB = 4.25,

	WingArea = 23.0,
	CD0 = 0.018,
	InducedK = 0.19, -- low aspect-ratio delta: big induced drag in hard turns
	CLAlpha = 2.9,
	CLMax = 1.25,
	CriticalAoA = 28,

	MaxG = 7.0,
	MinG = -3,
	MaxRollRate = 65, -- scaled from the F-5E playtest tuning
	MaxPitchRate = 17,
	MaxYawRate = 8,
	MaxMach = 2.05,
}
