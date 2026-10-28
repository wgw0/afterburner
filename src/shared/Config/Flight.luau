--!strict
-- Global flight constants (DEVELOPMENT.md §6). Per-aircraft numbers live in AircraftData.

return table.freeze({
	GRAVITY = 9.81, -- m/s²
	MAX_SUBSTEP = 1 / 120, -- seconds; larger frame times are split for stability

	-- Control authority scales with dynamic pressure up to this (Pa). ~120 m/s at sea level.
	Q_REFERENCE = 0.5 * 1.225 * 120 ^ 2,
	MIN_AUTHORITY = 0.15,
	THRUST_VECTORING_MIN_AUTHORITY = 0.6,

	-- Control law responsiveness
	AOA_TRACKING_GAIN = 6, -- 1/s: how fast AoA follows the commanded AoA
	PITCH_RATE_RESPONSE = 10, -- 1/s
	ROLL_RATE_RESPONSE = 2.5, -- 1/s: roll builds over ~0.4 s (roll inertia)
	SIDESLIP_STABILITY = 3, -- 1/s: weathervaning in yaw
	SIDE_FORCE_COEFFICIENT = -0.8, -- per radian of sideslip
	PROTECTED_AOA_FRACTION = 0.92, -- AoA limiter keeps below this fraction of critical
	UNPROTECTED_AOA_FRACTION = 1.5,

	-- Pilot G tolerance
	G_STRESS_ONSET = 6.5, -- G
	G_STRESS_RATE = 0.12, -- stress per second per G above onset
	G_STRESS_DECAY = 0.25, -- per second below onset
	RED_ONSET = -2.5, -- G
	RED_STRESS_RATE = 0.25,
	GLOC_DURATION = 3, -- seconds
	GLOC_RECOVERY_STRESS = 0.6,

	-- Instructor (mouse-aim autopilot) gains
	INSTRUCTOR_PITCH_GAIN = 4,
	INSTRUCTOR_PITCH_DAMPING = 1.2,
	INSTRUCTOR_ROLL_GAIN = 2,
	INSTRUCTOR_ROLL_DAMPING = 0.5,
	INSTRUCTOR_YAW_GAIN = 4,
	INSTRUCTOR_LEVEL_GAIN = 1.5,
	INSTRUCTOR_SAFE_G = 6.5, -- protected G limit unless the pilot overrides

	-- Effects thresholds
	CONTRAIL_ALTITUDE = 7000, -- real metres
	VAPOUR_G = 5,

	-- Phase 1 test spawn
	SPAWN_ALTITUDE_STUDS = 336, -- ~2,900 ft real: low enough to see the ground clearly
	SPAWN_SPEED = 220, -- real m/s
})
