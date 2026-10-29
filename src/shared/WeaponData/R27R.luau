--!strict
-- R-27R: Medium-range Soviet radar-guided missile. Keep the lock or it goes dumb.
-- Starting values from public figures; tune in playtests.
return {
	Id = "R27R",
	DisplayName = "R-27R",
	NameStatus = "Real",
	Class = "SARH",
	MotorBurnTime = 3.0,
	MotorAccel = 210,
	Drag = 0.00011,
	MaxG = 25,
	MinSpeed = 280,
	MaxRange = 10000,
	MinRange = 1000,
	SeekerCone = 25,
	Gimbal = 45,
	LockTime = 0,
	NavConstant = 3.5,
	FlareResistance = 1,
	ChaffResistance = 0.35,
	ProximityFuse = 10,
	Damage = 190,
	Lifetime = 45,
}
