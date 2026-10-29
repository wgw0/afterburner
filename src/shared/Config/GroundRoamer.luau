--!strict
-- The Ground Roamer (DEVELOPMENT.md §36): a drivable 4x4 for exploring the map from the ground. Geometry comes
-- from its model (tools/Manifests/Vehicles/GroundRoamer.luau, metres = studs); the handling is tuned here.
-- Wheel positions are relative to the model's pivot: on the ground, midway between the axles; x right, z aft.

local GroundRoamer = {
	-- Off since November 2026 (Will: no Drive mode for now). The model and code stay so it can come back:
	-- set this to true and the hangar's DRIVE button needs re-adding (see git history of Screens/Hangar).
	Enabled = false,
	ModelName = "GroundRoamer",
	DisplayName = "Ground Roamer",

	-- Wheels: hub positions at rest on flat ground, the tyre radius, and which wheels steer
	Wheels = {
		{ name = "FL", hub = Vector3.new(-0.655, 0.4, -1.1175), steers = true },
		{ name = "FR", hub = Vector3.new(0.655, 0.4, -1.1175), steers = true },
		{ name = "RL", hub = Vector3.new(-0.655, 0.4, 1.1175), steers = false },
		{ name = "RR", hub = Vector3.new(0.655, 0.4, 1.1175), steers = false },
	},
	WheelRadius = 0.4,

	-- Suspension: soft leaf springs (natural frequency per corner) with light damping, and its travel. Each
	-- wheel's ray starts SuspensionTravel above its rest hub position.
	SuspensionFrequency = 1.5, -- Hz
	SuspensionDamping = 0.45, -- fraction of critical damping
	SuspensionTravel = 0.22, -- metres of bump (and the same of droop) from rest
	AntiRoll = 1.2, -- anti-roll bar stiffness, as a fraction of the spring rate

	-- Drive (all four wheels), brakes, grip
	EngineAccel = 3.2, -- m/s² at full throttle from rest, falling away near TopSpeed
	TopSpeed = 29, -- m/s (105 km/h, 65 mph)
	ReverseSpeed = 7, -- m/s
	BrakeAccel = 7.5, -- m/s²
	HandbrakeAccel = 5, -- m/s², rear wheels
	RollingResistance = 0.15, -- m/s²
	Grip = 0.8, -- friction coefficient (tyre on terrain)
	LateralStiffness = 6, -- per second: how quickly a sliding tyre's sideways speed is cancelled
	AirDrag = 0.0008, -- per metre: deceleration = AirDrag * speed²

	-- Steering: lock at walking pace, less at speed
	MaxSteer = math.rad(34),
	MinSteer = math.rad(9), -- at TopSpeed
	SteerRate = math.rad(140), -- degrees per second the wheels turn

	Gravity = 9.81, -- m/s²: the vehicle cancels the rest of workspace.Gravity (studs are metres)

	-- Cameras: chase offset (behind, up) and the driver's eye (right-hand drive), relative to the pivot
	ChaseOffset = Vector3.new(0, 3.0, 7.5),
	DriverEye = Vector3.new(0.38, 1.52, 0.12),

	-- Skins (texture sets made by tools/blender/groundroamer_paint.py); asset ids are filled in after upload
	Skins = { "BronzeGreen", "Sand", "PastelGreen", "Red" },
	DefaultSkin = "BronzeGreen",

	-- Where it can be collected: airbase aprons and the island (x, z; the server finds the ground) and the yaw
	-- (radians) it faces
	SpawnSpots = {
		{ name = "West airbase", x = -3040, z = -2420, yaw = 0 },
		{ name = "East airbase", x = 3180, z = 2280, yaw = math.pi },
		{ name = "Island", x = 250, z = 250, yaw = math.pi / 4 },
	},

	-- Server sanity limits (the driver owns the physics)
	MaxSpeed = 60, -- m/s: faster than this and the vehicle is removed
}

return table.freeze(GroundRoamer)
