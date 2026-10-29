--!strict
-- R-77-1 (Su-35S): the R-77 with a longer motor and a better seeker. Data link midcourse, active at the
-- end. Starting values from public figures; tune in playtests.
return {
	Id = "R77_1",
	DisplayName = "R-77-1",
	NameStatus = "Real",
	Class = "ARH",
	MotorBurnTime = 4.5,
	MotorAccel = 240,
	Drag = 0.0001,
	MaxG = 32,
	MinSpeed = 280,
	MaxRange = 18000,
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
	ActiveRange = 4000,
}
