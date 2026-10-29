--!strict
-- Dassault Mirage F1C. A swept-wing successor to the Mirage III: turns far better at low speed, with a
-- radar and Super 530s. The Europe branch's Tier II jet. Starting values from public figures; tune in
-- playtests.
return {
	Id = "MirageF1",
	DisplayName = "Mirage F1C",
	NameStatus = "Real",
	FallbackName = 'Mirage "F-One"',
	Branch = "Europe",
	Tier = 2,
	BattleRating = 3.0,
	Era = "Analogue",
	ModelName = "MirageF1",

	Mass = 8300, -- empty 7,400 kg + pilot, guns, ammo, pylons
	Fuel = 3400,
	MaxThrust = 49000, -- Atar 9K-50 dry
	AfterburnerMult = 1.44, -- 70.6 kN wet
	FuelBurnDry = 1.3,
	FuelBurnAB = 4.6,

	WingArea = 25,
	CD0 = 0.019,
	WaveDrag = 0.8, -- a thin wing built for Mach 2
	InducedK = 0.11,
	CLAlpha = 4.0,
	CLMax = 1.35,
	CriticalAoA = 22,

	MaxG = 7.5,
	MinG = -3,
	MaxRollRate = 75,
	MaxPitchRate = 19,
	MaxYawRate = 9,
	-- Weapons and sensors
	Missiles = { { Weapon = "R550Magic", Count = 2 }, { Weapon = "Super530F", Count = 2 } },
	Radar = { Range = 16800, Cone = 30, CanNotch = false }, -- Cyrano IV: pulse radar
	RWR = { LaunchWarning = false, Resolution = "Coarse" },
	Countermeasures = { Flares = 30, Chaff = 30 },
	Gun = "DEFA552_Twin",
	MaxMach = 2.2,
}
