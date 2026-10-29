--!strict
-- Eurofighter Typhoon. A clean, unstable canard delta with huge dry thrust: it supercruises, climbs like a
-- rocket and carries ASRAAM and Meteor. The Europe branch's Tier VI jet. Starting values from public figures;
-- tune in playtests.
return {
	Id = "Typhoon",
	DisplayName = "Eurofighter Typhoon",
	NameStatus = "Real",
	FallbackName = 'Typhoon "EF-2000"',
	Branch = "Europe",
	Tier = 6,
	BattleRating = 11.0,
	Era = "FullGlass",
	ModelName = "Typhoon",

	Mass = 12000, -- empty 11,000 kg + pilot, gun, ammo, semi-recessed missiles
	Fuel = 4000,
	MaxThrust = 120000, -- 2 × EJ200 dry
	AfterburnerMult = 1.5, -- 180 kN wet
	FuelBurnDry = 2.0,
	FuelBurnAB = 8.5,

	WingArea = 51.2,
	CD0 = 0.017, -- very clean: it supercruises
	WaveDrag = 0.5, -- area-ruled and very clean: it supercruises
	InducedK = 0.1,
	CLAlpha = 4.4,
	CLMax = 1.75,
	CriticalAoA = 28,

	MaxG = 9.0,
	MinG = -3,
	MaxRollRate = 135,
	MaxPitchRate = 28,
	MaxYawRate = 13,
	-- Weapons and sensors
	Missiles = { { Weapon = "ASRAAM", Count = 2 }, { Weapon = "Meteor", Count = 4 } },
	Radar = { Range = 80000, Cone = 30, CanNotch = true }, -- CAPTOR-M: pulse-Doppler
	RWR = { LaunchWarning = true, Resolution = "Fine" },
	Countermeasures = { Flares = 30, Chaff = 30 },
	Gun = "BK27",
	MaxMach = 2.0,
}
