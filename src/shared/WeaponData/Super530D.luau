--!strict
-- Super 530D (Mirage 2000C): the Super 530 made for a pulse-Doppler radar, so it can be fired down at
-- low targets; faster and longer-ranged than the 530F. Keep the lock or it goes dumb.
-- Starting values from public figures; tune in playtests.
return {
	Id = "Super530D",
	DisplayName = "Super 530D",
	NameStatus = "Real",
	Class = "SARH",
	MotorBurnTime = 3.5,
	MotorAccel = 240,
	Drag = 0.00011,
	MaxG = 24,
	MinSpeed = 280,
	MaxRange = 12000,
	MinRange = 1000,
	SeekerCone = 25,
	Gimbal = 40,
	LockTime = 0,
	NavConstant = 3.5,
	FlareResistance = 1,
	ChaffResistance = 0.3,
	ProximityFuse = 10,
	Damage = 200,
	Lifetime = 45,
}
