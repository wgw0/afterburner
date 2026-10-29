--!strict
-- R-77: the Soviet/Russian active radar missile. Data link midcourse, active seeker for the last
-- stretch. Tier IV. Starting values from public figures; tune in playtests.
return {
	Id = "R77",
	DisplayName = "R-77",
	NameStatus = "Real",
	Class = "ARH",
	MotorBurnTime = 3.8,
	MotorAccel = 235,
	Drag = 0.00011,
	MaxG = 32,
	MinSpeed = 280,
	MaxRange = 13200,
	Loft = true, -- climbs on long shots (MSL-08)
	MinRange = 1000,
	SeekerCone = 30,
	Gimbal = 50,
	LockTime = 0,
	NavConstant = 3.8,
	FlareResistance = 1,
	ChaffResistance = 0.45,
	ProximityFuse = 10,
	Damage = 180,
	Lifetime = 60,
	Model = "MediumRadar",
	Length = 3.6,
	ActiveRange = 3400,
}
