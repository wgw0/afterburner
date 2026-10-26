--!strict
-- AIM-9P Sidewinder: Rear-aspect heat-seeker. The F-5E's missile: reliable from behind, easily decoyed.
-- Starting values from public figures; tune in playtests.
return {
	Id = "AIM9P",
	DisplayName = "AIM-9P Sidewinder",
	NameStatus = "Real",
	Class = "IR_Rear",
	MotorBurnTime = 2.2,
	MotorAccel = 250,
	Drag = 0.00016,
	MaxG = 22,
	MinSpeed = 250,
	MaxRange = 6000,
	MinRange = 500,
	SeekerCone = 12,
	Gimbal = 25,
	LockTime = 1.0,
	NavConstant = 3.5,
	FlareResistance = 0.2,
	ChaffResistance = 1,
	ProximityFuse = 6,
	Damage = 110,
	Lifetime = 20,
}
