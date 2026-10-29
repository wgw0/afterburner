--!strict
-- R-24R: Soviet medium-range radar-guided missile (MiG-23MLD). Long reach for its tier; keep the lock.
-- Starting values from public figures; tune in playtests.
return {
	Id = "R24R",
	DisplayName = "R-24R",
	NameStatus = "Real",
	Class = "SARH",
	MotorBurnTime = 3.4,
	MotorAccel = 215,
	Drag = 0.00011,
	MaxG = 22,
	MinSpeed = 280,
	MaxRange = 10800,
	MinRange = 1000,
	SeekerCone = 25,
	Gimbal = 40,
	LockTime = 0,
	NavConstant = 3.5,
	FlareResistance = 1,
	ChaffResistance = 0.3,
	ProximityFuse = 10,
	Damage = 200,
	Lifetime = 45,
}
