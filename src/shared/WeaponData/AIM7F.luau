--!strict
-- AIM-7F Sparrow: Medium-range radar-guided missile. Keep the lock or it goes dumb.
-- Starting values from public figures; tune in playtests.
return {
	Id = "AIM7F",
	DisplayName = "AIM-7F Sparrow",
	NameStatus = "Real",
	Class = "SARH",
	MotorBurnTime = 3.5,
	MotorAccel = 200,
	Drag = 0.00011,
	MaxG = 25,
	MinSpeed = 280,
	MaxRange = 25000,
	MinRange = 1000,
	SeekerCone = 25,
	Gimbal = 40,
	LockTime = 0,
	NavConstant = 3.5,
	FlareResistance = 1,
	ChaffResistance = 0.3,
	ProximityFuse = 10,
	Damage = 190,
	Lifetime = 45,
}
