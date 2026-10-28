--!strict
-- IRIS-T (Gripen C): the European high off-boresight heat-seeker, helmet-cued and thrust-vectored.
-- Starting values from public figures; tune in playtests.
return {
	Id = "IRIST",
	DisplayName = "IRIS-T",
	NameStatus = "Real",
	Class = "IR_Adv",
	MotorBurnTime = 2.4,
	MotorAccel = 275,
	Drag = 0.00014,
	MaxG = 50,
	MinSpeed = 240,
	MaxRange = 8500,
	MinRange = 300,
	SeekerCone = 45,
	Gimbal = 90,
	LockTime = 0.6,
	NavConstant = 4.2,
	FlareResistance = 0.8,
	ChaffResistance = 1,
	ProximityFuse = 7,
	Damage = 140,
	Lifetime = 22,
}
