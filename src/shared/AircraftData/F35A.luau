--!strict
-- Lockheed Martin F-35A Lightning II. The stealthiest sensor-fused fighter with a huge single engine; not a
-- dogfighter like the Raptor, but very hard to find first. The NATO branch's second Tier VII jet. Starting
-- values from public figures; tune in playtests.
return {
	Id = "F35A",
	DisplayName = "F-35A Lightning II",
	NameStatus = "Real",
	FallbackName = 'F-35A "Panther"',
	Branch = "NATO",
	Tier = 7,
	BattleRating = 11.7,
	Era = "WAD",
	ModelName = "F35A",

	Mass = 14200, -- empty 13,300 kg + pilot, gun, ammo
	Fuel = 5500,
	MaxThrust = 125000, -- F135-PW-100 dry
	AfterburnerMult = 1.53, -- 191 kN wet
	FuelBurnDry = 2.2,
	FuelBurnAB = 10.0,
	Stealth = 0.003, -- radar sees it at under a quarter of the usual range

	WingArea = 42.7,
	CD0 = 0.022,
	InducedK = 0.11,
	CLAlpha = 4.5,
	CLMax = 1.7,
	CriticalAoA = 30,

	MaxG = 9.0,
	MinG = -3,
	MaxRollRate = 100,
	MaxPitchRate = 24,
	MaxYawRate = 12,
	-- Weapons and sensors (carried internally)
	Missiles = { { Weapon = "AIM9X", Count = 2 }, { Weapon = "AIM120D", Count = 4 } },
	Radar = { Range = 110000, Cone = 30, CanNotch = true }, -- AN/APG-81: AESA
	RWR = { LaunchWarning = true, Resolution = "Fine" },
	Countermeasures = { Flares = 30, Chaff = 30 },
	Gun = "GAU22",
	MaxMach = 1.6,
}
