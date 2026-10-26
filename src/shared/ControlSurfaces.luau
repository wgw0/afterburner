--!strict
-- How a jet's control surfaces move (art pipeline §5; used by ControlSurfaceController). Pure functions:
-- stick commands -> surface deflections -> hinge angles for the Motor6D on each surface.
--
-- Deflections are in degrees in the surface's own sense: trailing edge down is positive for ailerons,
-- flaps and stabilators, leading edge down (droop) for leading-edge flaps, trailing edge right for the
-- rudder. A surface's hinge axis comes from the model (HingeAxis attribute, model space), so mirrored
-- surfaces with opposite axes still move the right way.

local ControlSurfaces = {}

-- Controls the controller animates. Gear, doors and wheels stay put (the gear is hidden in flight).
ControlSurfaces.ANIMATED = {
	AileronL = true,
	AileronR = true,
	Stabilator = true,
	Rudder = true,
	Flap = true,
	LEFlap = true,
}

-- Manoeuvring flaps: out with angle of attack, in at high speed (degrees, metres per second)
local FLAP_AOA_START, FLAP_AOA_FULL = 3, 12
local FLAP_SPEED_FULL, FLAP_SPEED_NONE = 230, 290
local FULL_RUDDER_SIDESLIP = 6 -- degrees of sideslip shown as full rudder

export type Commands = {
	pitch: number, -- -1..1, nose up positive
	roll: number, -- -1..1, right positive
	yaw: number, -- -1..1, right positive
	flap: number, -- 0..1
}

local function clamp1(v: number): number
	return math.clamp(v, -1, 1)
end

-- Angle of attack in degrees from the jet's CFrame and velocity (any units).
function ControlSurfaces.angleOfAttack(cframe: CFrame, velocity: Vector3): number
	local v = cframe:VectorToObjectSpace(velocity)
	if v.Magnitude < 1e-3 then
		return 0
	end
	return math.deg(math.atan2(-v.Y, -v.Z))
end

-- Manoeuvring flap position 0..1 from angle of attack (degrees) and speed (metres per second).
function ControlSurfaces.flapFraction(aoa: number, speed: number): number
	local byAoA = math.clamp((aoa - FLAP_AOA_START) / (FLAP_AOA_FULL - FLAP_AOA_START), 0, 1)
	local bySpeed = math.clamp((FLAP_SPEED_NONE - speed) / (FLAP_SPEED_NONE - FLAP_SPEED_FULL), 0, 1)
	return byAoA * bySpeed
end

-- Sideslip in degrees: positive when the nose points right of the flight path.
function ControlSurfaces.sideslip(cframe: CFrame, velocity: Vector3): number
	local v = cframe:VectorToObjectSpace(velocity)
	if v.Magnitude < 1e-3 then
		return 0
	end
	return math.deg(math.atan2(-v.X, -v.Z))
end

-- Commands for a jet we only see moving (other players, AI). Pitch and roll come from body rates against
-- the airframe's maximum rates. Yaw comes from sideslip, not yaw rate: in a banked turn the body yaw rate
-- is large while the rudder stays near centre. angularVelocity is world space (rad/s); velocity is
-- metres per second.
function ControlSurfaces.fromMotion(
	cframe: CFrame,
	angularVelocity: Vector3,
	velocity: Vector3,
	airframe: any
): Commands
	local w = cframe:VectorToObjectSpace(angularVelocity)
	-- Nose along -Z: pitch up is +X rotation, roll right is -Z rotation.
	local pitchRate, rollRate = w.X, -w.Z
	return {
		pitch = clamp1(pitchRate / math.rad(airframe.MaxPitchRate or 20)),
		roll = clamp1(rollRate / math.rad(airframe.MaxRollRate or 90)),
		yaw = clamp1(ControlSurfaces.sideslip(cframe, velocity) / FULL_RUDDER_SIDESLIP),
		flap = ControlSurfaces.flapFraction(ControlSurfaces.angleOfAttack(cframe, velocity), velocity.Magnitude),
	}
end

-- Target deflection (degrees, surface sense) for a control, within the surface's limits.
function ControlSurfaces.deflection(control: string, commands: Commands, min: number, max: number): number
	local target = 0
	if control == "AileronR" then
		target = -commands.roll * 20 -- roll right: right aileron trailing edge up
	elseif control == "AileronL" then
		target = commands.roll * 20
	elseif control == "Stabilator" then
		target = -commands.pitch * 20 -- nose up: trailing edge up
	elseif control == "Rudder" then
		target = commands.yaw * 30
	elseif control == "Flap" or control == "LEFlap" then
		target = commands.flap * max
	end
	return math.clamp(target, min, max)
end

-- Hinge rotation (radians, about the hinge axis) that produces a deflection.
function ControlSurfaces.hingeAngle(control: string, axis: Vector3, deflection: number): number
	if control == "Rudder" then
		-- A positive turn about an upward axis swings the trailing edge (aft of the hinge) to the right
		return math.rad(deflection) * (if axis.Y >= 0 then 1 else -1)
	end
	-- A positive turn about an outboard (+X) axis moves the trailing edge down; a leading-edge flap sits
	-- ahead of its hinge, so its droop is the opposite turn.
	local sign = if axis.X >= 0 then 1 else -1
	if control == "LEFlap" then
		sign = -sign
	end
	return math.rad(deflection) * sign
end

return ControlSurfaces
