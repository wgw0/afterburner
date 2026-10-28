--!strict
-- McDonnell Douglas F/A-18C Hornet. Slower than the Eagle, but its leading-edge extensions let it fly
-- at angles of attack nothing else at this tier can, so it points its nose anywhere at low speed.
-- The NATO branch's second Tier IV jet. Starting values from public figures; tune in playtests.
return {
	Id = "FA18C",
	DisplayName = "F/A-18C Hornet",
	NameStatus = "Real",
	FallbackName = 'F/A-18C "Hornet-C"',
	Branch = "NATO",
	Tier = 4,
	BattleRating = 7.0,
	Era = "EarlyGlass",
	ModelName = "FA18C",

	Mass = 11600, -- empty 10,400 kg + pilot, gun, ammo, pylons
	Fuel = 4900,
	MaxThrust = 98000, -- 2 × F404-GE-402 dry
	AfterburnerMult = 1.61, -- 158 kN wet
	FuelBurnDry = 2.0,
	FuelBurnAB = 8.0,

	WingArea = 37.2,
	CD0 = 0.022,
	InducedK = 0.1,
	CLAlpha = 4.8,
	CLMax = 1.8,
	CriticalAoA = 35,

	MaxG = 7.5,
	MinG = -3,
	MaxRollRate = 110,
	MaxPitchRate = 25,
	MaxYawRate = 14,
	-- Weapons and sensors
	Missiles = { { Weapon = "AIM9M", Count = 2 }, { Weapon = "AIM120A", Count = 4 } },
	Radar = { Range = 50000, Cone = 30, CanNotch = true }, -- AN/APG-73: pulse-Doppler
	RWR = { LaunchWarning = false, Resolution = "Fine" },
	Countermeasures = { Flares = 30, Chaff = 30 },
	Gun = "M61A1",
	MaxMach = 1.8,
}
