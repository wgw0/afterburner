--!strict
-- AIM-9M Sidewinder: the AIM-9L with a better seeker that tells a jet from a flare far more often.
-- Starting values from public figures; tune in playtests.
return {
	Id = "AIM9M",
	DisplayName = "AIM-9M Sidewinder",
	NameStatus = "Real",
	Class = "IR_All",
	MotorBurnTime = 2.4,
	MotorAccel = 265,
	Drag = 0.00014,
	MaxG = 30,
	MinSpeed = 250,
	MaxRange = 5100,
	MinRange = 400,
	SeekerCone = 15,
	Gimbal = 30,
	LockTime = 0.7,
	NavConstant = 4,
	FlareResistance = 0.6,
	ChaffResistance = 1,
	ProximityFuse = 7,
	Damage = 140,
	Lifetime = 22,
	Model = "Sidewinder",
	Length = 2.87,
}
