--!strict
-- R-74M (Su-35S): the R-73 brought up to date: helmet-cued far off the nose, harder to decoy.
-- Starting values from public figures; tune in playtests.
return {
	Id = "R74M",
	DisplayName = "R-74M",
	NameStatus = "Real",
	Class = "IR_Adv",
	MotorBurnTime = 2.6,
	MotorAccel = 275,
	Drag = 0.00015,
	MaxG = 45,
	MinSpeed = 240,
	MaxRange = 4800,
	MinRange = 300,
	SeekerCone = 45,
	Gimbal = 75,
	LockTime = 0.6,
	NavConstant = 4.2,
	FlareResistance = 0.7,
	ChaffResistance = 1,
	ProximityFuse = 7,
	Damage = 135,
	Lifetime = 22,
}
