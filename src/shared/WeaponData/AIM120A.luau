--!strict
-- AIM-120A AMRAAM: the first active radar missile. Flies midcourse on the launcher's data link, then its
-- own seeker goes active ("pitbull") and the launcher can turn away. Tier IV. Starting values from
-- public figures; tune in playtests.
return {
	Id = "AIM120A",
	DisplayName = "AIM-120A AMRAAM",
	NameStatus = "Real",
	Class = "ARH",
	MotorBurnTime = 4.0,
	MotorAccel = 230,
	Drag = 0.0001,
	MaxG = 30,
	MinSpeed = 280,
	MaxRange = 14000,
	MinRange = 1000,
	SeekerCone = 30,
	Gimbal = 45,
	LockTime = 0,
	NavConstant = 3.8,
	FlareResistance = 1,
	ChaffResistance = 0.5,
	ProximityFuse = 10,
	Damage = 180,
	Lifetime = 60,
	Model = "MediumRadar",
	Length = 3.66,
	ActiveRange = 3600,
}
