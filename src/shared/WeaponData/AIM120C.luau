--!strict
-- AIM-120C AMRAAM: the AMRAAM with clipped fins and a longer reach. Data link midcourse, then its own
-- seeker goes active. Tier V. Starting values from public figures; tune in playtests.
return {
	Id = "AIM120C",
	DisplayName = "AIM-120C AMRAAM",
	NameStatus = "Real",
	Class = "ARH",
	MotorBurnTime = 4.5,
	MotorAccel = 235,
	Drag = 9e-05,
	MaxG = 30,
	MinSpeed = 280,
	MaxRange = 42000,
	MinRange = 1000,
	SeekerCone = 30,
	Gimbal = 50,
	LockTime = 0,
	NavConstant = 3.9,
	FlareResistance = 1,
	ChaffResistance = 0.55,
	ProximityFuse = 10,
	Damage = 180,
	Lifetime = 70,
	ActiveRange = 10000,
}
