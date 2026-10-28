--!strict
-- AIM-9X Sidewinder: an imaging seeker cued by the pilot's helmet, so it locks far off the nose, and
-- thrust vectoring to turn hard after launch. Rarely fooled by flares. Starting values from public figures;
-- tune in playtests.
return {
	Id = "AIM9X",
	DisplayName = "AIM-9X Sidewinder",
	NameStatus = "Real",
	Class = "IR_Adv",
	MotorBurnTime = 2.5,
	MotorAccel = 270,
	Drag = 0.00014,
	MaxG = 50,
	MinSpeed = 240,
	MaxRange = 9000,
	MinRange = 300,
	SeekerCone = 45,
	Gimbal = 90,
	LockTime = 0.6,
	NavConstant = 4.2,
	FlareResistance = 0.8,
	ChaffResistance = 1,
	ProximityFuse = 7,
	Damage = 140,
	Lifetime = 22,
}
