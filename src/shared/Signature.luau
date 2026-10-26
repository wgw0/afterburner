--!strict
-- How visible a jet is to heat seekers and radar (DEVELOPMENT.md §14.5, SNS-06; notching §14.2, SNS-04).
-- Pure maths, shared by the server (locks, missiles) and the client (radar scope, seeker tone).

local Units = require(script.Parent.Units)

local Signature = {}

local RAD = math.pi / 180
Signature.REAR_ASPECT_LIMIT = 60 * RAD -- rear-aspect seekers only see a jet within this of its tail
Signature.NOTCH_SPEED = 30 -- m/s: radial speeds below this are filtered as ground clutter
Signature.LOW_ALTITUDE = 1500 -- real metres: below this there's always ground clutter behind a target

-- Angle (radians) between the target's tailpipe direction and the direction to the observer.
-- 0 = looking straight up its tailpipe, π = head-on.
function Signature.aspectAngle(targetCF: CFrame, observerPosition: Vector3): number
	local toObserver = observerPosition - targetCF.Position
	if toObserver.Magnitude < 1e-3 then
		return 0
	end
	return math.acos(math.clamp((-targetCF.LookVector):Dot(toObserver.Unit), -1, 1))
end

-- Infrared strength seen from `observerPosition`. ~1 for a jet at military power seen from behind.
-- rearOnly: early seekers can't see the hot parts from the front or side at all.
function Signature.ir(
	targetCF: CFrame,
	throttle: number,
	afterburner: boolean,
	observerPosition: Vector3,
	rearOnly: boolean
): number
	local aspect = Signature.aspectAngle(targetCF, observerPosition)
	local aspectFactor
	if rearOnly then
		if aspect > Signature.REAR_ASPECT_LIMIT then
			return 0
		end
		aspectFactor = 1 - 0.5 * (aspect / Signature.REAR_ASPECT_LIMIT)
	else
		aspectFactor = 1 - 0.75 * (aspect / math.pi) -- rear 1.0, beam ~0.6, head-on 0.25
	end
	local engine = 0.35 + 0.65 * math.clamp(throttle, 0, 1)
	if afterburner then
		engine *= 4 -- afterburner is a huge heat source: flares barely compete (tuned in Engagement.spec)
	end
	return engine * aspectFactor
end

-- Target's velocity along the line of sight from the radar (m/s, positive = moving away).
-- Uses ground-relative velocity: a jet flying perpendicular to the beam has ~0 Doppler, like the ground.
function Signature.radialSpeed(radarPosition: Vector3, targetPosition: Vector3, targetVelocity: Vector3): number
	local los = targetPosition - radarPosition
	if los.Magnitude < 1e-3 then
		return 0
	end
	return targetVelocity:Dot(los.Unit)
end

export type RadarSpec = { Range: number, Cone: number, CanNotch: boolean }

-- Can this radar see the target right now? Returns (detected, reason). Line-of-sight to terrain is
-- checked separately by the caller (it needs raycasts).
--   Pulse radar (CanNotch = false): blind when looking down into ground clutter.
--   Pulse-Doppler (CanNotch = true): sees down, but loses targets flying perpendicular (the notch).
function Signature.radarDetects(
	radar: RadarSpec,
	radarCF: CFrame,
	targetPosition: Vector3,
	targetVelocity: Vector3,
	stealth: number?
): (boolean, string)
	local los = targetPosition - radarCF.Position
	local distance = los.Magnitude
	if distance < 1e-3 then
		return true, "ok"
	end
	local range = Units.toMetres(distance)
	local rcs = stealth or 1
	if range > radar.Range * rcs ^ 0.25 then
		return false, "range"
	end
	local off = math.acos(math.clamp(radarCF.LookVector:Dot(los.Unit), -1, 1))
	if off > radar.Cone * RAD then
		return false, "cone"
	end
	local lookingDown = los.Unit.Y < -0.05
	local targetLow = Units.altitudeMetres(targetPosition.Y) < Signature.LOW_ALTITUDE
	local clutter = lookingDown or targetLow
	if clutter then
		if not radar.CanNotch then
			return false, "clutter"
		end
		if
			math.abs(Signature.radialSpeed(radarCF.Position, targetPosition, targetVelocity)) < Signature.NOTCH_SPEED
		then
			return false, "notch"
		end
	end
	return true, "ok"
end

return Signature
