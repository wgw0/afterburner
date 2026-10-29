--!strict
-- Skyflash (Tornado F3): a British Sparrow with a far better monopulse seeker, harder to decoy and
-- able to shoot down at low targets. Semi-active: keep the lock. Starting values from public figures;
-- tune in playtests.
return {
	Id = "Skyflash",
	DisplayName = "Skyflash",
	NameStatus = "Real",
	Class = "SARH",
	MotorBurnTime = 3.5,
	MotorAccel = 210,
	Drag = 0.00011,
	MaxG = 25,
	MinSpeed = 280,
	MaxRange = 12000,
	MinRange = 1000,
	SeekerCone = 25,
	Gimbal = 40,
	LockTime = 0,
	NavConstant = 3.6,
	FlareResistance = 1,
	ChaffResistance = 0.55,
	ProximityFuse = 10,
	Damage = 195,
	Lifetime = 45,
}
