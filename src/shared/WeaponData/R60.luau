--!strict
-- R-60: Small, very agile short-range heat-seeker with a light warhead.
-- Starting values from public figures; tune in playtests.
return {
	Id = "R60",
	DisplayName = "R-60",
	NameStatus = "Real",
	Class = "IR_Rear",
	MotorBurnTime = 1.8,
	MotorAccel = 300,
	Drag = 0.00022,
	MaxG = 35,
	MinSpeed = 230,
	MaxRange = 2100,
	MinRange = 300,
	SeekerCone = 14,
	Gimbal = 30,
	LockTime = 0.8,
	NavConstant = 4,
	FlareResistance = 0.15,
	ChaffResistance = 1,
	ProximityFuse = 5,
	Damage = 90,
	Lifetime = 18,
}
