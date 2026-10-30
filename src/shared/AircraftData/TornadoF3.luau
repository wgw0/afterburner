--!strict
-- Panavia Tornado F3. A swing-wing long-range interceptor: fast low down and long-legged, with the
-- Foxhunter radar and Skyflash, but no dogfighter. The Europe branch's Tier IV jet. Starting values from
-- public figures; tune in playtests.
return {
	Id = "TornadoF3",
	DisplayName = "Tornado F3",
	NameStatus = "Real",
	FallbackName = 'Tornado "ADV"',
	Branch = "Europe",
	Tier = 4,
	BattleRating = 6.7,
	Era = "EarlyGlass",
	ModelName = "TornadoF3",

	Mass = 15500, -- empty 14,500 kg + crew, gun, ammo, pylons
	Fuel = 5800,
	MaxThrust = 81000, -- 2 × RB199 Mk 104 dry
	AfterburnerMult = 1.81, -- 147 kN wet
	FuelBurnDry = 1.8,
	FuelBurnAB = 9.0,

	WingArea = 30, -- wings at mid sweep (25.5 m² fully swept, 31 spread)
	CD0 = 0.021,
	InducedK = 0.12,
	CLAlpha = 4.0,
	CLMax = 1.5,
	-- Swing wings (FLT-08): 25° to 67°, following speed. The model wasn't built around its pivot, so the
	-- visual pivot is the wing's inner leading corner (close to the real one inside the glove)
	VariableGeometry = {
		Schedule = { { 0.55, 25 }, { 0.8, 45 }, { 1.05, 67 } },
		Forward = { CLMax = 1.6, CLAlpha = 4.3, InducedK = 0.11, CD0 = 0.022, WaveDrag = 1.1 },
		Back = { CLMax = 1.05, CLAlpha = 3.1, InducedK = 0.16, CD0 = 0.018, WaveDrag = 0.7 },
		ModelSweep = 25,
		Pivot = Vector3.new(-2.2022, 0.361, -1.17),
	},
	CriticalAoA = 22,

	MaxG = 7.5,
	MinG = -3,
	MaxRollRate = 75,
	MaxPitchRate = 18,
	MaxYawRate = 9,
	-- Weapons and sensors
	Missiles = { { Weapon = "AIM9L", Count = 4 }, { Weapon = "Skyflash", Count = 4 } },
	Radar = { Range = 22000, Cone = 30, CanNotch = true }, -- AI.24 Foxhunter: pulse-Doppler
	RWR = { LaunchWarning = false, Resolution = "Fine" },
	Countermeasures = { Flares = 30, Chaff = 30 },
	Gun = "BK27",
	MaxMach = 2.2,
}
