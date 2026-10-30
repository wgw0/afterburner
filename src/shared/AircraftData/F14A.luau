--!strict
-- Grumman F-14A Tomcat. A big swing-wing fleet interceptor with the AWG-9 radar and the AIM-54 Phoenix:
-- the longest reach at Tier III, but heavy, thirsty on its TF30s and slower to turn than the F-16.
-- The NATO branch's second Tier III jet. Starting values from public figures; tune in playtests.
return {
	Id = "F14A",
	DisplayName = "F-14A Tomcat",
	NameStatus = "Real",
	FallbackName = 'F-14A "Tom-A"',
	Branch = "NATO",
	Tier = 3,
	BattleRating = 5.7,
	Era = "Analogue",
	ModelName = "F14A",

	Mass = 20500, -- empty 18,200 kg + pilot and RIO, gun, ammo, pylons
	Fuel = 7300,
	MaxThrust = 125000, -- 2 × TF30-P-414A dry
	AfterburnerMult = 1.48, -- 186 kN wet
	FuelBurnDry = 2.6,
	FuelBurnAB = 11.0,

	WingArea = 52.5, -- wings forward
	-- Mid-sweep values; in flight VariableGeometry blends them with the sweep (FLT-08)
	CD0 = 0.022,
	InducedK = 0.09,
	CLAlpha = 4.6,
	CLMax = 1.7,
	-- The Mach sweep programmer: 20° up to Mach 0.6, fully back (68°) by Mach 1.05
	VariableGeometry = {
		Schedule = { { 0.6, 20 }, { 0.75, 30 }, { 0.9, 55 }, { 1.05, 68 } },
		Forward = { CLMax = 1.9, CLAlpha = 5.0, InducedK = 0.075, CD0 = 0.023, WaveDrag = 1.15 },
		Back = { CLMax = 1.1, CLAlpha = 3.4, InducedK = 0.15, CD0 = 0.018, WaveDrag = 0.7 },
		ModelSweep = 35,
		Pivot = Vector3.new(-2.72, 0.7178, -0.9901),
	},
	CriticalAoA = 25,

	MaxG = 7.5,
	MinG = -3,
	MaxRollRate = 75,
	MaxPitchRate = 21,
	MaxYawRate = 10,
	-- Weapons and sensors
	Missiles = {
		{ Weapon = "AIM9L", Count = 2 },
		{ Weapon = "AIM7F", Count = 2 },
		{ Weapon = "AIM54A", Count = 4 },
	},
	Radar = { Range = 24000, Cone = 30, CanNotch = true }, -- AN/AWG-9: pulse-Doppler, huge reach
	RWR = { LaunchWarning = false, Resolution = "Fine" },
	Countermeasures = { Flares = 30, Chaff = 30 },
	Gun = "M61A1",
	MaxMach = 2.34,
}
