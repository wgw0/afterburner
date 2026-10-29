--!strict
-- Dassault Rafale C. A close-coupled canard delta: superb at low speed and in the instantaneous turn, with
-- MICA IR and Meteor on the RBE2 radar. The Europe branch's second Tier VI jet. Starting values from public
-- figures; tune in playtests.
return {
	Id = "RafaleC",
	DisplayName = "Rafale C",
	NameStatus = "Real",
	FallbackName = 'Rafale "C"',
	Branch = "Europe",
	Tier = 6,
	BattleRating = 10.7,
	Era = "FullGlass",
	ModelName = "RafaleC",

	Mass = 10800, -- empty 9,850 kg + pilot, gun, ammo, pylons
	Fuel = 4000,
	MaxThrust = 100000, -- 2 × M88-2 dry
	AfterburnerMult = 1.5, -- 150 kN wet
	FuelBurnDry = 1.8,
	FuelBurnAB = 7.5,

	WingArea = 45.7,
	CD0 = 0.018,
	InducedK = 0.1,
	CLAlpha = 4.3,
	CLMax = 1.8,
	CriticalAoA = 30,

	MaxG = 9.0,
	MinG = -3,
	MaxRollRate = 140,
	MaxPitchRate = 28,
	MaxYawRate = 13,
	-- Weapons and sensors
	Missiles = { { Weapon = "MICAIR", Count = 2 }, { Weapon = "Meteor", Count = 4 } },
	Radar = { Range = 30000, Cone = 30, CanNotch = true }, -- RBE2: electronically scanned
	RWR = { LaunchWarning = true, Resolution = "Fine" },
	Countermeasures = { Flares = 30, Chaff = 30 },
	Gun = "GIAT30M791",
	MaxMach = 1.8,
}
