--!strict
-- AIM-54A Phoenix (F-14A): a heavy long-range missile with its own radar seeker for the last stretch.
-- Huge reach, but built to kill bombers: it turns poorly, so a fighter that sees it coming can beat it.
-- Starting values from public figures; tune in playtests.
return {
	Id = "AIM54A",
	DisplayName = "AIM-54A Phoenix",
	NameStatus = "Real",
	Class = "ARH",
	MotorBurnTime = 6.0,
	MotorAccel = 190,
	Drag = 0.00009,
	MaxG = 17,
	MinSpeed = 300,
	MaxRange = 50000,
	MinRange = 2000,
	SeekerCone = 25,
	Gimbal = 40,
	LockTime = 0,
	NavConstant = 3.2,
	FlareResistance = 1,
	ChaffResistance = 0.35,
	ProximityFuse = 14,
	Damage = 220,
	Lifetime = 80,
	ActiveRange = 12000,
}
