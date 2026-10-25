--!strict
-- Shared type definitions (DEVELOPMENT.md §3.1).

export type ControlInput = {
	pitch: number, -- -1..1 (commands load factor: 0 = 1 G, 1 = max G, -1 = min G)
	roll: number, -- -1..1 (right positive)
	yaw: number, -- -1..1 (right positive)
	throttle: number, -- 0..1 (1 = military power)
	afterburner: boolean,
	protections: boolean, -- AoA limiter on
}

export type FlightState = {
	cframe: CFrame, -- world CFrame (studs)
	velocity: Vector3, -- real m/s, world axes
	angularVelocity: Vector3, -- rad/s, world axes
	pitchRate: number, -- rad/s (internal lag state)
	rollRate: number,
	yawRate: number,
	fuel: number, -- kg
	gLoad: number,
	aoa: number, -- radians
	sideslip: number, -- radians
	stalled: boolean,
	gStress: number, -- 0..1 (1 = G-LOC)
	redStress: number, -- 0..1
	mach: number,
	altitude: number, -- real-equivalent metres
	speed: number, -- real m/s
}

export type Modifiers = {
	thrust: number?,
	lift: number?,
	roll: number?,
	pitch: number?,
}

export type Airframe = {
	Id: string,
	DisplayName: string,
	NameStatus: "Real" | "SemiFictional",
	FallbackName: string,
	Branch: "NATO" | "East" | "Europe",
	Tier: number,
	BattleRating: number,
	Era: "Analogue" | "EarlyGlass" | "FullGlass" | "WAD",
	ModelName: string,
	Mass: number, -- kg, operating empty (pilot, gun, ammo), without fuel
	MaxThrust: number, -- N, dry, sea level
	AfterburnerMult: number,
	FuelBurnDry: number, -- kg/s at military power
	FuelBurnAB: number, -- kg/s in full afterburner
	Fuel: number, -- kg internal
	WingArea: number, -- m²
	CD0: number,
	InducedK: number,
	CLAlpha: number, -- per radian
	CLMax: number,
	CriticalAoA: number, -- degrees
	MaxG: number,
	MinG: number,
	MaxRollRate: number, -- deg/s
	MaxPitchRate: number, -- deg/s
	MaxYawRate: number, -- deg/s
	MaxMach: number,
	ThrustVectoring: boolean?,
	Stealth: number?,
}

return {}
