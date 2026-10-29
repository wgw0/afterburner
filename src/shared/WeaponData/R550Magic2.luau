--!strict
-- R.550 Magic II (Mirage 2000C): the Magic with an all-aspect seeker. Agile and quick to lock.
-- Starting values from public figures; tune in playtests.
return {
	Id = "R550Magic2",
	DisplayName = "R.550 Magic II",
	NameStatus = "Real",
	Class = "IR_All",
	MotorBurnTime = 2.0,
	MotorAccel = 275,
	Drag = 0.00017,
	MaxG = 35,
	MinSpeed = 240,
	MaxRange = 4200,
	MinRange = 350,
	SeekerCone = 15,
	Gimbal = 30,
	LockTime = 0.7,
	NavConstant = 4,
	FlareResistance = 0.4,
	ChaffResistance = 1,
	ProximityFuse = 6,
	Damage = 130,
	Lifetime = 20,
}
