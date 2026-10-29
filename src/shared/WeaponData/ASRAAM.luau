--!strict
-- ASRAAM (Typhoon): a fast, long-reaching heat-seeker with an imaging seeker, locked far off the nose.
-- Starting values from public figures; tune in playtests.
return {
	Id = "ASRAAM",
	DisplayName = "ASRAAM",
	NameStatus = "Real",
	Class = "IR_Adv",
	MotorBurnTime = 2.6,
	MotorAccel = 300,
	Drag = 0.00013,
	MaxG = 50,
	MinSpeed = 250,
	MaxRange = 6000,
	MinRange = 300,
	SeekerCone = 45,
	Gimbal = 90,
	LockTime = 0.6,
	NavConstant = 4.2,
	FlareResistance = 0.8,
	ChaffResistance = 1,
	ProximityFuse = 7,
	Damage = 140,
	Lifetime = 24,
	Model = "TailIR",
	Length = 2.9,
}
