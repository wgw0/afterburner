--!strict
-- Server-side movement sanity checks for pilot-owned jets (DEVELOPMENT.md §16.1, SEC-01). Pure, so the
-- limits can be unit-tested against real flight-model output (normal flying must never trip them).
--
-- Samples are taken ~10× a second from the server's view of the jet. Generous margins: the goal is to
-- catch speed hacks and teleports, never to punish an honest pilot for lag or an aggressive dive.

local Flight = require(script.Parent.Config.Flight)
local Units = require(script.Parent.Units)

local MovementCheck = {}

local G = Flight.GRAVITY

export type Sample = { time: number, position: Vector3, velocity: Vector3 } -- studs, studs/s
export type Limits = { maxSpeed: number, maxAccel: number } -- real m/s, real m/s²

MovementCheck.SPEED_MARGIN = 1.15
MovementCheck.ACCEL_MARGIN = 1.5
MovementCheck.TELEPORT_MARGIN = 1.5
MovementCheck.TELEPORT_SLACK = 60 -- studs of allowance for replication jitter

MovementCheck.STRIKE_WINDOW = 10 -- seconds
MovementCheck.STRIKES_TO_RESET = 3
MovementCheck.RESET_WINDOW = 60
MovementCheck.RESETS_TO_KICK = 3

function MovementCheck.limits(airframe: any): Limits
	-- Top speed: MaxMach at sea-level speed of sound (the fastest it can be anywhere), plus margin.
	local maxSpeed = airframe.MaxMach * 340.3 * MovementCheck.SPEED_MARGIN
	-- Acceleration: full afterburner thrust on an empty jet, plus the hardest pull and gravity.
	local thrustAccel = airframe.MaxThrust * airframe.AfterburnerMult / airframe.Mass
	local maxAccel = (thrustAccel + (airframe.MaxG + 3) * G) * MovementCheck.ACCEL_MARGIN
	return { maxSpeed = maxSpeed, maxAccel = maxAccel }
end

-- Checks one step between two samples. Returns (ok, reason, detail).
function MovementCheck.evaluate(previous: Sample, current: Sample, limits: Limits): (boolean, string?, number?)
	local dt = current.time - previous.time
	if dt < 0.02 then
		return true, nil, nil
	end
	local speed = Units.velocityFromStuds(current.velocity.Magnitude)
	if speed > limits.maxSpeed then
		return false, "speed", speed
	end
	local fastest = math.max(previous.velocity.Magnitude, current.velocity.Magnitude)
	local moved = (current.position - previous.position).Magnitude
	local allowed = fastest * dt * MovementCheck.TELEPORT_MARGIN + MovementCheck.TELEPORT_SLACK
	if moved > allowed then
		return false, "teleport", moved
	end
	-- A sudden stop is a crash (the client halts the jet on impact), not a cheat: only check acceleration
	-- while the jet keeps most of its speed.
	local stopping = current.velocity.Magnitude < previous.velocity.Magnitude * 0.3
	local accel = Units.velocityFromStuds((current.velocity - previous.velocity).Magnitude) / dt
	if accel > limits.maxAccel and not stopping then
		return false, "acceleration", accel
	end
	return true, nil, nil
end

export type Strikes = { strikes: { number }, resets: { number } }

function MovementCheck.newStrikes(): Strikes
	return { strikes = {}, resets = {} }
end

local function prune(list: { number }, now: number, window: number)
	for i = #list, 1, -1 do
		if now - list[i] > window then
			table.remove(list, i)
		end
	end
end

-- Records a strike. Returns "none" | "reset" | "kick".
function MovementCheck.strike(state: Strikes, now: number): string
	prune(state.strikes, now, MovementCheck.STRIKE_WINDOW)
	table.insert(state.strikes, now)
	if #state.strikes < MovementCheck.STRIKES_TO_RESET then
		return "none"
	end
	table.clear(state.strikes)
	prune(state.resets, now, MovementCheck.RESET_WINDOW)
	table.insert(state.resets, now)
	if #state.resets >= MovementCheck.RESETS_TO_KICK then
		return "kick"
	end
	return "reset"
end

return MovementCheck
