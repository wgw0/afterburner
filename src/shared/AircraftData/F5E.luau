--!strict
-- Northrop F-5E Tiger II. Light, agile, short-legged. The NATO starter jet.
-- Starting values from public figures; tune in playtests.
return {
	Id = "F5E",
	DisplayName = "F-5E Tiger II",
	NameStatus = "Real",
	FallbackName = 'F-5E "Tiger-E"',
	Branch = "NATO",
	Tier = 1,
	BattleRating = 1.7,
	Era = "Analogue",
	ModelName = "F5E",

	Mass = 4600, -- empty 4,350 kg + pilot, gun, ammo
	Fuel = 2000,
	MaxThrust = 31000, -- 2 × J85-GE-21 dry
	AfterburnerMult = 1.43, -- 44.4 kN wet
	FuelBurnDry = 0.88,
	FuelBurnAB = 2.75,

	WingArea = 17.3,
	CD0 = 0.021,
	InducedK = 0.11,
	CLAlpha = 4.2,
	CLMax = 1.4,
	CriticalAoA = 22,

	MaxG = 7.33,
	MinG = -3,
	MaxRollRate = 200,
	MaxPitchRate = 28,
	MaxYawRate = 12,
	MaxMach = 1.6,
}
