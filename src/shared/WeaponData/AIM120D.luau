--!strict
-- AIM-120D AMRAAM (F-22A, F-35A): the longest-reaching AMRAAM, with a two-way data link and a better
-- seeker. Starting values from public figures; tune in playtests.
return {
	Id = "AIM120D",
	DisplayName = "AIM-120D AMRAAM",
	NameStatus = "Real",
	Class = "ARH",
	MotorBurnTime = 5.0,
	MotorAccel = 240,
	Drag = 9e-05,
	MaxG = 32,
	MinSpeed = 280,
	MaxRange = 22000,
	Loft = true, -- climbs on long shots (MSL-08)
	MinRange = 1000,
	SeekerCone = 30,
	Gimbal = 55,
	LockTime = 0,
	NavConstant = 4.0,
	FlareResistance = 1,
	ChaffResistance = 0.6,
	ProximityFuse = 10,
	Damage = 180,
	Lifetime = 80,
	ActiveRange = 4400,
}
