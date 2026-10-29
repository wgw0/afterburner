--!strict
-- R.550 Magic: French short-range heat-seeker (Mirage III, Mirage F1). A rear-aspect seeker that's a
-- little harder to decoy than an AIM-9P. Starting values from public figures; tune in playtests.
return {
	Id = "R550Magic",
	DisplayName = "R.550 Magic",
	NameStatus = "Real",
	Class = "IR_Rear",
	MotorBurnTime = 1.9,
	MotorAccel = 270,
	Drag = 0.00018,
	MaxG = 30,
	MinSpeed = 240,
	MaxRange = 3000,
	MinRange = 400,
	SeekerCone = 14,
	Gimbal = 30,
	LockTime = 0.9,
	NavConstant = 3.8,
	FlareResistance = 0.3,
	ChaffResistance = 1,
	ProximityFuse = 6,
	Damage = 120,
	Lifetime = 18,
}
