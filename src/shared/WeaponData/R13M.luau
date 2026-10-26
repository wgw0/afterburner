--!strict
-- R-13M: Soviet rear-aspect heat-seeker, Sidewinder-derived.
-- Starting values from public figures; tune in playtests.
return {
	Id = "R13M",
	DisplayName = "R-13M",
	NameStatus = "Real",
	Class = "IR_Rear",
	MotorBurnTime = 2.0,
	MotorAccel = 240,
	Drag = 0.00018,
	MaxG = 20,
	MinSpeed = 250,
	MaxRange = 5500,
	MinRange = 500,
	SeekerCone = 11,
	Gimbal = 22,
	LockTime = 1.1,
	NavConstant = 3.5,
	FlareResistance = 0.15,
	ChaffResistance = 1,
	ProximityFuse = 6,
	Damage = 130,
	Lifetime = 20,
}
