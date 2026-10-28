--!strict
-- R-27ER: the R-27R with a much bigger motor (Su-27S). Long reach, but still semi-active: keep the lock
-- or it goes dumb. Starting values from public figures; tune in playtests.
return {
	Id = "R27ER",
	DisplayName = "R-27ER",
	NameStatus = "Real",
	Class = "SARH",
	MotorBurnTime = 5.0,
	MotorAccel = 220,
	Drag = 0.0001,
	MaxG = 25,
	MinSpeed = 280,
	MaxRange = 40000,
	MinRange = 1000,
	SeekerCone = 25,
	Gimbal = 45,
	LockTime = 0,
	NavConstant = 3.5,
	FlareResistance = 1,
	ChaffResistance = 0.4,
	ProximityFuse = 11,
	Damage = 200,
	Lifetime = 60,
}
