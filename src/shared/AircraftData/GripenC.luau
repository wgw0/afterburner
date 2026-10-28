--!strict
-- Saab JAS 39C Gripen. Small, light and cheap to run: a canard delta that rolls and points fast, with
-- IRIS-T and AIM-120Cs on the PS-05/A radar. The Europe branch's Tier V jet. Starting values from public
-- figures; tune in playtests.
return {
	Id = "GripenC",
	DisplayName = "JAS 39C Gripen",
	NameStatus = "Real",
	FallbackName = 'Gripen "C"',
	Branch = "Europe",
	Tier = 5,
	BattleRating = 8.7,
	Era = "FullGlass",
	ModelName = "GripenC",

	Mass = 7100, -- empty 6,620 kg + pilot, gun, ammo, rails
	Fuel = 2100,
	MaxThrust = 54000, -- RM12 dry
	AfterburnerMult = 1.49, -- 80.5 kN wet
	FuelBurnDry = 1.2,
	FuelBurnAB = 5.0,

	WingArea = 30, -- a close-coupled canard delta
	CD0 = 0.018,
	InducedK = 0.11,
	CLAlpha = 4.2,
	CLMax = 1.7,
	CriticalAoA = 28,

	MaxG = 9.0,
	MinG = -3,
	MaxRollRate = 140,
	MaxPitchRate = 28,
	MaxYawRate = 13,
	-- Weapons and sensors
	Missiles = { { Weapon = "IRIST", Count = 2 }, { Weapon = "AIM120C", Count = 4 } },
	Radar = { Range = 60000, Cone = 30, CanNotch = true }, -- PS-05/A: pulse-Doppler
	RWR = { LaunchWarning = true, Resolution = "Fine" },
	Countermeasures = { Flares = 30, Chaff = 30 },
	Gun = "BK27",
	MaxMach = 2.0,
}
