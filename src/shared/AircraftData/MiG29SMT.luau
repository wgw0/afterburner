--!strict
-- Mikoyan MiG-29SMT. The Fulcrum modernised: a glass cockpit, the Zhuk-ME radar and R-77s, with the
-- MiG-29's agility. The East branch's second Tier V jet. Starting values from public figures; tune in
-- playtests.
return {
	Id = "MiG29SMT",
	DisplayName = "MiG-29SMT",
	NameStatus = "Real",
	FallbackName = 'MiG-29SMT "Fulcrum-E"',
	Branch = "East",
	Tier = 5,
	BattleRating = 8.7,
	Era = "FullGlass",
	ModelName = "MiG29SMT",

	Mass = 12800, -- empty 11,800 kg + pilot, gun, ammo, pylons
	Fuel = 4000,
	MaxThrust = 99000, -- 2 × RD-33 series 3 dry
	AfterburnerMult = 1.65, -- 163 kN wet
	FuelBurnDry = 2.0,
	FuelBurnAB = 8.0,

	WingArea = 38,
	CD0 = 0.021,
	InducedK = 0.1,
	CLAlpha = 4.6,
	CLMax = 1.65,
	CriticalAoA = 26,

	MaxG = 9.0,
	MinG = -3,
	MaxRollRate = 95,
	MaxPitchRate = 25,
	MaxYawRate = 12,
	-- Weapons and sensors
	Missiles = { { Weapon = "R73", Count = 2 }, { Weapon = "R77", Count = 4 } },
	Radar = { Range = 60000, Cone = 30, CanNotch = true }, -- Zhuk-ME: pulse-Doppler
	RWR = { LaunchWarning = true, Resolution = "Fine" },
	Countermeasures = { Flares = 30, Chaff = 30 },
	Gun = "GSh301",
	MaxMach = 2.25,
}
