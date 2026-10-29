--!strict
-- Super 530F: French medium-range radar-guided missile (Mirage F1). Keep the lock or it goes dumb.
-- Starting values from public figures; tune in playtests.
return {
	Id = "Super530F",
	DisplayName = "Super 530F",
	NameStatus = "Real",
	Class = "SARH",
	MotorBurnTime = 3.0,
	MotorAccel = 220,
	Drag = 0.00012,
	MaxG = 22,
	MinSpeed = 280,
	MaxRange = 8800,
	MinRange = 1000,
	SeekerCone = 25,
	Gimbal = 40,
	LockTime = 0,
	NavConstant = 3.5,
	FlareResistance = 1,
	ChaffResistance = 0.3,
	ProximityFuse = 10,
	Damage = 200,
	Lifetime = 40,
}
