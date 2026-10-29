--!strict
-- MICA IR (Rafale C): the MICA with an imaging infrared seeker, vectored thrust and a long reach for a
-- heat-seeker. Starting values from public figures; tune in playtests.
return {
	Id = "MICAIR",
	DisplayName = "MICA IR",
	NameStatus = "Real",
	Class = "IR_Adv",
	MotorBurnTime = 3.0,
	MotorAccel = 270,
	Drag = 0.00013,
	MaxG = 50,
	MinSpeed = 250,
	MaxRange = 5400,
	MinRange = 300,
	SeekerCone = 45,
	Gimbal = 60,
	LockTime = 0.6,
	NavConstant = 4.2,
	FlareResistance = 0.75,
	ChaffResistance = 1,
	ProximityFuse = 7,
	Damage = 135,
	Lifetime = 24,
	Model = "TailIR",
	Length = 3.1,
}
