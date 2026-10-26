--!strict
-- Two M39A2 20 mm revolver cannons in the F-5E's nose. Fast-firing, flat-shooting.
return {
	Id = "M39A2_Twin",
	DisplayName = "2× M39A2 20 mm",
	NameStatus = "Real",
	Class = "Gun",
	RateOfFire = 3000, -- ~1,500 rpm each
	MuzzleVelocity = 1030,
	Damage = 10,
	Ammo = 560, -- 280 per gun
	Spread = 0.35,
	Drag = 0.00018,
	Lifetime = 2.0,
	HeatPerShot = 0.004,
	CoolRate = 0.25,
}
