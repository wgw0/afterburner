--!strict
-- Sukhoi Su-27S. Huge fuel, huge thrust and a superb turn: the Eagle's rival, with R-73s and long-burn
-- R-27ERs (radar-guided, so keep the lock). The East branch's Tier IV jet. Starting values from public
-- figures; tune in playtests.
return {
	Id = "Su27S",
	DisplayName = "Su-27S",
	NameStatus = "Real",
	FallbackName = 'Su-27S "Flanker-B"',
	Branch = "East",
	Tier = 4,
	BattleRating = 7.7,
	Era = "Analogue",
	ModelName = "Su27S",

	Mass = 17500, -- empty 16,380 kg + pilot, gun, ammo, pylons
	Fuel = 5500, -- of 9,400 kg internal: a normal combat load
	MaxThrust = 150000, -- 2 × AL-31F dry
	AfterburnerMult = 1.64, -- 246 kN wet
	FuelBurnDry = 2.6,
	FuelBurnAB = 11.0,

	WingArea = 62,
	CD0 = 0.021,
	InducedK = 0.09,
	CLAlpha = 4.7,
	CLMax = 1.75,
	CriticalAoA = 30,

	MaxG = 9.0,
	MinG = -3,
	MaxRollRate = 95,
	MaxPitchRate = 24,
	MaxYawRate = 12,
	-- Weapons and sensors
	Missiles = { { Weapon = "R73", Count = 4 }, { Weapon = "R27ER", Count = 4 } },
	Radar = { Range = 60000, Cone = 30, CanNotch = true }, -- N001: pulse-Doppler
	RWR = { LaunchWarning = false, Resolution = "Fine" },
	Countermeasures = { Flares = 30, Chaff = 30 },
	Gun = "GSh301",
	MaxMach = 2.35,
}
