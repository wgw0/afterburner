--!strict
-- McDonnell Douglas F-15C Eagle. Big wing, huge thrust and the AN/APG-63: the air-superiority benchmark,
-- with AIM-120As and AIM-9Ms. The NATO branch's Tier IV jet. Starting values from public figures; tune in
-- playtests.
return {
	Id = "F15C",
	DisplayName = "F-15C Eagle",
	NameStatus = "Real",
	FallbackName = 'F-15C "Eagle-C"',
	Branch = "NATO",
	Tier = 4,
	BattleRating = 7.7,
	Era = "EarlyGlass",
	ModelName = "F15C",

	Mass = 14500, -- empty 12,700 kg + pilot, gun, ammo, pylons
	Fuel = 6100,
	MaxThrust = 130000, -- 2 × F100-PW-220 dry
	AfterburnerMult = 1.63, -- 212 kN wet
	FuelBurnDry = 2.4,
	FuelBurnAB = 10.0,

	WingArea = 56.5,
	CD0 = 0.021,
	InducedK = 0.09,
	CLAlpha = 4.6,
	CLMax = 1.65,
	CriticalAoA = 28,

	MaxG = 9.0,
	MinG = -3,
	MaxRollRate = 100,
	MaxPitchRate = 24,
	MaxYawRate = 11,
	-- Weapons and sensors
	Missiles = { { Weapon = "AIM9M", Count = 4 }, { Weapon = "AIM120A", Count = 4 } },
	Radar = { Range = 60000, Cone = 30, CanNotch = true }, -- AN/APG-63: pulse-Doppler
	RWR = { LaunchWarning = false, Resolution = "Fine" },
	Countermeasures = { Flares = 30, Chaff = 30 },
	Gun = "M61A1",
	MaxMach = 2.5,
}
