--!strict
-- Meteor (Typhoon, Rafale C): a ramjet that keeps burning almost all the way, so it arrives fast at ranges
-- where other missiles are coasting. Data link midcourse, active seeker at the end. Starting values from
-- public figures; tune in playtests.
return {
	Id = "Meteor",
	DisplayName = "Meteor",
	NameStatus = "Real",
	Class = "ARH",
	MotorBurnTime = 12.0,
	MotorAccel = 130,
	Drag = 8e-05,
	MaxG = 30,
	MinSpeed = 300,
	MaxRange = 24000,
	MinRange = 1500,
	SeekerCone = 30,
	Gimbal = 50,
	LockTime = 0,
	NavConstant = 3.9,
	FlareResistance = 1,
	ChaffResistance = 0.6,
	ProximityFuse = 10,
	Damage = 180,
	Lifetime = 100,
	Model = "MediumRadar",
	Length = 3.65,
	ActiveRange = 4800,
}
