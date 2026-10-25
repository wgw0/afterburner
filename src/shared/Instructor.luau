--!strict
-- Mouse-aim autopilot (DEVELOPMENT.md §7.3). Pure: turns "point the nose here" into stick inputs.
-- Also used to fly AI jets and to hold the jet level during G-LOC.
--
-- Bank-to-turn: roll so the aim point sits above the nose, then pull. Small offsets below the nose
-- are handled by rolling the target underneath and pushing, rather than rolling inverted.

local Flight = require(script.Parent.Config.Flight)
local Types = require(script.Parent.Types)

type FlightState = Types.FlightState
type ControlInput = Types.ControlInput
type Airframe = Types.Airframe

export type Settings = {
	allowOverG: boolean?, -- pilot override: pull past the safe G limit
	throttle: number?,
	afterburner: boolean?,
}

local RAD = math.pi / 180

local function smoothstep(edge0: number, edge1: number, x: number): number
	local t = math.clamp((x - edge0) / (edge1 - edge0), 0, 1)
	return t * t * (3 - 2 * t)
end

local Instructor = {}

-- Angle (radians) between the nose and a world direction.
function Instructor.offAngle(cframe: CFrame, aimDirection: Vector3): number
	return math.acos(math.clamp(cframe.LookVector:Dot(aimDirection.Unit), -1, 1))
end

-- World bank angle (radians, right wing down positive).
function Instructor.bankAngle(cframe: CFrame): number
	return math.atan2(-cframe.RightVector.Y, cframe.UpVector.Y)
end

function Instructor.compute(
	state: FlightState,
	aimDirection: Vector3,
	airframe: Airframe,
	settings: Settings?
): ControlInput
	local cf = state.cframe
	-- Work in the flight-path frame: the body frame pitched down by the AoA, so "forward" is where the
	-- jet is actually going. Holding the aim level then holds altitude, and AoA never looks like an
	-- error to correct.
	local pathFrame = cf * CFrame.Angles(-state.aoa, 0, 0)
	local aim = pathFrame:VectorToObjectSpace(aimDirection.Unit) -- object space: forward is -Z
	local off = math.acos(math.clamp(-aim.Z, -1, 1))

	-- Roll: which way round the nose is the target? (0 = straight above the nose)
	local below = aim.Y < 0 and off < 20 * RAD
	local rollError = if below then math.atan2(aim.X, -aim.Y) else math.atan2(aim.X, aim.Y)
	local turnWeight = smoothstep(2 * RAD, 10 * RAD, off)
	local levelError = -Instructor.bankAngle(cf)
	local roll = turnWeight * (rollError * Flight.INSTRUCTOR_ROLL_GAIN)
		+ (1 - turnWeight) * (levelError * Flight.INSTRUCTOR_LEVEL_GAIN)
		- state.rollRate * Flight.INSTRUCTOR_ROLL_DAMPING

	-- Pitch: angle to the target in the jet's vertical plane. Only pull hard once the roll is lined up.
	local pitchError = math.atan2(aim.Y, -aim.Z)
	local alignment = math.clamp(math.cos(rollError), 0, 1)
	local pitch = pitchError * Flight.INSTRUCTOR_PITCH_GAIN * (if below then 1 else 0.3 + 0.7 * alignment)
		- state.pitchRate * Flight.INSTRUCTOR_PITCH_DAMPING

	-- Protect the pilot: cap the commanded G below the G-LOC onset unless overridden.
	local allowOverG = settings ~= nil and settings.allowOverG == true
	if not allowOverG then
		local safe = (Flight.INSTRUCTOR_SAFE_G - 1) / math.max(airframe.MaxG - 1, 1e-3)
		pitch = math.min(pitch, safe)
	end

	-- Rudder: fine lateral corrections only near the target.
	local yawError = math.atan2(aim.X, -aim.Z)
	local yaw = yawError * Flight.INSTRUCTOR_YAW_GAIN * (1 - smoothstep(3 * RAD, 12 * RAD, off))

	return {
		pitch = math.clamp(pitch, -1, 1),
		roll = math.clamp(roll, -1, 1),
		yaw = math.clamp(yaw, -1, 1),
		throttle = if settings and settings.throttle then settings.throttle else 0.85,
		afterburner = if settings and settings.afterburner ~= nil then settings.afterburner else false,
		protections = not allowOverG,
	}
end

return Instructor
