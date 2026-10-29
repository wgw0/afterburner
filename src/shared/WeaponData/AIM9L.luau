--!strict
-- AIM-9L Sidewinder: All-aspect heat-seeker: can be fired head-on. Harder to flare.
-- Starting values from public figures; tune in playtests.
return {
	Id = "AIM9L",
	DisplayName = "AIM-9L Sidewinder",
	NameStatus = "Real",
	Class = "IR_All",
	MotorBurnTime = 2.4,
	MotorAccel = 260,
	Drag = 0.00014,
	MaxG = 30,
	MinSpeed = 250,
	MaxRange = 4800,
	MinRange = 400,
	SeekerCone = 15,
	Gimbal = 30,
	LockTime = 0.8,
	NavConstant = 4,
	FlareResistance = 0.4,
	ChaffResistance = 1,
	ProximityFuse = 7,
	Damage = 140,
	Lifetime = 22,
	Model = "Sidewinder",
	Length = 2.87,
}
