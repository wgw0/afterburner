--!strict
-- McDonnell Douglas F-15E Strike Eagle. A two-seat Eagle with conformal tanks: heavier and draggier
-- than the F-15C, but more thrust, more fuel and the AN/APG-70. The NATO branch's second Tier V jet.
-- Starting values from public figures; tune in playtests.
return {
	Id = "F15E",
	DisplayName = "F-15E Strike Eagle",
	NameStatus = "Real",
	FallbackName = 'F-15E "Mudhen"',
	Branch = "NATO",
	Tier = 5,
	BattleRating = 8.7,
	Era = "FullGlass",
	ModelName = "F15E",

	Mass = 16800, -- empty 14,300 kg + crew, gun, ammo, conformal tanks and their pylons
	Fuel = 6500,
	MaxThrust = 158000, -- 2 × F100-PW-229 dry
	AfterburnerMult = 1.63, -- 258 kN wet
	FuelBurnDry = 2.8,
	FuelBurnAB = 12.0,

	WingArea = 56.5,
	CD0 = 0.027, -- the conformal tanks
	InducedK = 0.09,
	CLAlpha = 4.6,
	CLMax = 1.65,
	CriticalAoA = 28,

	MaxG = 9.0,
	MinG = -3,
	MaxRollRate = 90,
	MaxPitchRate = 23,
	MaxYawRate = 10,
	-- Weapons and sensors
	Missiles = { { Weapon = "AIM9X", Count = 4 }, { Weapon = "AIM120C", Count = 4 } },
	Radar = { Range = 28000, Cone = 30, CanNotch = true }, -- AN/APG-70: pulse-Doppler
	RWR = { LaunchWarning = true, Resolution = "Fine" },
	Countermeasures = { Flares = 30, Chaff = 30 },
	Gun = "M61A1",
	MaxMach = 2.5,
}
