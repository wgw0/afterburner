--!strict
-- R-73: All-aspect heat-seeker with high off-boresight lock and big turn rate.
-- Starting values from public figures; tune in playtests.
return {
	Id = "R73",
	DisplayName = "R-73",
	NameStatus = "Real",
	Class = "IR_All",
	MotorBurnTime = 2.5,
	MotorAccel = 270,
	Drag = 0.00016,
	MaxG = 40,
	MinSpeed = 240,
	MaxRange = 7000,
	MinRange = 300,
	SeekerCone = 40,
	Gimbal = 60,
	LockTime = 0.7,
	NavConstant = 4,
	FlareResistance = 0.5,
	ChaffResistance = 1,
	ProximityFuse = 7,
	Damage = 100,
	Lifetime = 22,
}
