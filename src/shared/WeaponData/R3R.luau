--!strict
-- R-3R: Early radar-guided missile: the launching jet must keep its radar locked until impact.
-- Starting values from public figures; tune in playtests.
return {
	Id = "R3R",
	DisplayName = "R-3R",
	NameStatus = "Real",
	Class = "SARH",
	MotorBurnTime = 2.0,
	MotorAccel = 220,
	Drag = 0.00018,
	MaxG = 15,
	MinSpeed = 250,
	MaxRange = 3200,
	MinRange = 800,
	SeekerCone = 20,
	Gimbal = 30,
	LockTime = 0,
	NavConstant = 3,
	FlareResistance = 1,
	ChaffResistance = 0.2,
	ProximityFuse = 8,
	Damage = 140,
	Lifetime = 25,
}
