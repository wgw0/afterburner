--!strict
-- Pure flight model (DEVELOPMENT.md §6). No Roblox instances: shared by the pilot's client,
-- the server (AI, validation) and the unit tests. Same inputs + same dt = same output.
--
-- Forces are real-world SI. The pitch axis uses a load-factor command law (stick commands G,
-- neutral stick holds 1 G), so corner speed, stalls and energy bleed all emerge from the physics.
--
-- Roblox body axes: forward = LookVector (-Z), up = UpVector (+Y), right = RightVector (+X).

local Atmosphere = require(script.Parent.Atmosphere)
local Flight = require(script.Parent.Config.Flight)
local Types = require(script.Parent.Types)
local Units = require(script.Parent.Units)

type FlightState = Types.FlightState
type ControlInput = Types.ControlInput
type Airframe = Types.Airframe
type Modifiers = Types.Modifiers

local G = Flight.GRAVITY
local RAD = math.pi / 180

local FlightModel = {}

export type ForceBreakdown = {
	lift: Vector3,
	drag: Vector3,
	thrust: Vector3,
	side: Vector3,
	weight: Vector3,
	mass: number,
	q: number,
	cl: number,
	cd: number,
	aoa: number,
	sideslip: number,
	mach: number,
	altitude: number,
	density: number,
	stalled: boolean,
}

local function smoothstep(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

-- Extra drag through the transonic region (peaks just past Mach 1).
function FlightModel.waveDrag(mach: number): number
	if mach < 0.8 then
		return 0
	elseif mach < 1.05 then
		return 0.035 * smoothstep((mach - 0.8) / 0.25)
	end
	return 0.02 + 0.015 * math.exp(-(mach - 1.05) / 0.3)
end

-- Lift coefficient with a smooth post-stall drop to ~40% of CLMax.
function FlightModel.liftCoefficient(aoa: number, airframe: Airframe): (number, boolean)
	local critical = airframe.CriticalAoA * RAD
	local magnitude = math.abs(aoa)
	local sign = if aoa < 0 then -1 else 1
	if magnitude <= critical then
		return sign * math.min(airframe.CLAlpha * magnitude, airframe.CLMax), false
	end
	local falloff = smoothstep((magnitude - critical) / (20 * RAD))
	local peak = math.min(airframe.CLAlpha * critical, airframe.CLMax)
	return sign * peak * (1 - 0.6 * falloff), true
end

local function totalMass(airframe: Airframe, fuel: number): number
	return airframe.Mass + math.max(fuel, 0)
end

local function authority(q: number, airframe: Airframe): number
	local minimum = if airframe.ThrustVectoring then Flight.THRUST_VECTORING_MIN_AUTHORITY else Flight.MIN_AUTHORITY
	return math.clamp(q / Flight.Q_REFERENCE, minimum, 1)
end

-- Forces acting on the aircraft right now. Used by step() and by the debug panel.
function FlightModel.computeForces(
	state: FlightState,
	input: ControlInput,
	airframe: Airframe,
	mods: Modifiers?
): ForceBreakdown
	local cf = state.cframe
	local forward, up, right = cf.LookVector, cf.UpVector, cf.RightVector
	local v = state.velocity
	local speed = v.Magnitude
	local vhat = if speed > 1e-3 then v / speed else forward

	local altitude = Units.altitudeMetres(cf.Position.Y)
	local density = Atmosphere.density(altitude)
	local mach = speed / Atmosphere.speedOfSound(altitude)
	local q = 0.5 * density * speed * speed
	local mass = totalMass(airframe, state.fuel)

	local aoa = if speed > 1 then math.atan2(-v:Dot(up), v:Dot(forward)) else 0
	local sideslip = if speed > 1 then math.asin(math.clamp(v:Dot(right) / speed, -1, 1)) else 0

	local cl, stalled = FlightModel.liftCoefficient(aoa, airframe)
	cl *= (mods and mods.lift) or 1

	local liftDir = up - vhat * vhat:Dot(up)
	liftDir = if liftDir.Magnitude > 1e-4 then liftDir.Unit else up
	local sideDir = right - vhat * vhat:Dot(right)
	sideDir = if sideDir.Magnitude > 1e-4 then sideDir.Unit else right

	local S = airframe.WingArea
	local lift = liftDir * (q * S * cl)
	local side = sideDir * (q * S * Flight.SIDE_FORCE_COEFFICIENT * sideslip)

	local sinAoa = math.sin(aoa)
	local cd = airframe.CD0
		+ airframe.InducedK * cl * cl
		+ FlightModel.waveDrag(mach)
		+ (if stalled then 1.0 * sinAoa * sinAoa else 0)
		+ 0.5 * math.sin(sideslip) ^ 2
	local drag = -vhat * (q * S * cd)

	local thrustMagnitude = 0
	if state.fuel > 0 then
		local ab = if input.afterburner then airframe.AfterburnerMult else 1
		local lapse = (density / Atmosphere.SEA_LEVEL_DENSITY) ^ 0.7
		thrustMagnitude = airframe.MaxThrust * math.clamp(input.throttle, 0, 1) * ab * lapse
		thrustMagnitude *= (mods and mods.thrust) or 1
	end
	local thrust = forward * thrustMagnitude
	local weight = Vector3.new(0, -G * mass, 0)

	return {
		lift = lift,
		drag = drag,
		thrust = thrust,
		side = side,
		weight = weight,
		mass = mass,
		q = q,
		cl = cl,
		cd = cd,
		aoa = aoa,
		sideslip = sideslip,
		mach = mach,
		altitude = altitude,
		density = density,
		stalled = stalled,
	}
end

local function substep(
	s: FlightState,
	input: ControlInput,
	airframe: Airframe,
	h: number,
	mods: Modifiers?
): FlightState
	local f = FlightModel.computeForces(s, input, airframe, mods)
	local cf = s.cframe
	local forward, up, right = cf.LookVector, cf.UpVector, cf.RightVector
	local mass = f.mass

	-- Linear motion
	local aeroAndThrust = f.lift + f.drag + f.thrust + f.side
	local accel = aeroAndThrust / mass + f.weight / mass
	local velocity = s.velocity + accel * h
	local maxSpeed = airframe.MaxMach * Atmosphere.speedOfSound(f.altitude) * 1.05
	if velocity.Magnitude > maxSpeed then
		velocity = velocity.Unit * maxSpeed
	end
	local speed = velocity.Magnitude
	local gLoad = (aeroAndThrust / mass):Dot(up) / G

	-- Pitch: load-factor command -> commanded AoA -> pitch rate
	local auth = authority(f.q, airframe)
	local pitchInput = math.clamp(input.pitch, -1, 1)
	local nCommand = if pitchInput >= 0
		then 1 + pitchInput * (airframe.MaxG - 1)
		else 1 + -pitchInput * (airframe.MinG - 1)

	local critical = airframe.CriticalAoA * RAD
	local aoaLimit = critical
		* (if input.protections then Flight.PROTECTED_AOA_FRACTION else Flight.UNPROTECTED_AOA_FRACTION)
	local aoaCommand = 0
	if f.q > 1 then
		local clRequired = nCommand * mass * G / (f.q * airframe.WingArea)
		aoaCommand = clRequired / airframe.CLAlpha
	end
	aoaCommand = math.clamp(aoaCommand, -aoaLimit * 0.6, aoaLimit)

	local vhat = if speed > 1e-3 then velocity / speed else forward
	local liftDir = up - vhat * vhat:Dot(up)
	liftDir = if liftDir.Magnitude > 1e-4 then liftDir.Unit else up
	local flightPathRate = accel:Dot(liftDir) / math.max(speed, 30)

	local maxPitchRate = airframe.MaxPitchRate * RAD * auth * ((mods and mods.pitch) or 1)
	local pitchTarget = flightPathRate + Flight.AOA_TRACKING_GAIN * (aoaCommand - f.aoa)
	pitchTarget = math.clamp(pitchTarget, -maxPitchRate, maxPitchRate)
	local pitchRate = s.pitchRate + (pitchTarget - s.pitchRate) * math.min(1, h * Flight.PITCH_RATE_RESPONSE)

	-- Roll: rate command with a short lag; authority drops when slow and when very fast
	local highSpeedFade = 1 - 0.4 * smoothstep((f.q / Flight.Q_REFERENCE - 3) / 3)
	local rollTarget = math.clamp(input.roll, -1, 1)
		* airframe.MaxRollRate
		* RAD
		* math.clamp(f.q / Flight.Q_REFERENCE, 0.2, 1)
		* highSpeedFade
		* ((mods and mods.roll) or 1)
	-- Damage: a hurt wing makes less lift, so the jet rolls toward it (FLT-10)
	rollTarget += ((mods and mods.rollBias) or 0) * math.clamp(f.q / Flight.Q_REFERENCE, 0.2, 1.5)
	local rollRate = s.rollRate + (rollTarget - s.rollRate) * math.min(1, h * Flight.ROLL_RATE_RESPONSE)

	-- Yaw: rudder plus weathervane stability (nose swings toward the airflow)
	local yawRate = math.clamp(input.yaw, -1, 1) * airframe.MaxYawRate * RAD * auth * ((mods and mods.yaw) or 1)
		+ Flight.SIDESLIP_STABILITY * f.sideslip

	-- Rotate: pitch about right, roll about forward, yaw-right about -up
	local angularVelocity = right * pitchRate + forward * rollRate - up * yawRate
	local rotation = cf.Rotation
	local omega = angularVelocity.Magnitude
	if omega > 1e-9 then
		rotation = CFrame.fromAxisAngle(angularVelocity / omega, omega * h) * rotation
	end
	local position = cf.Position + Units.velocityToStuds(velocity) * h

	-- Fuel
	local burn = if input.afterburner and input.throttle >= 0.999
		then airframe.FuelBurnAB
		else airframe.FuelBurnDry * (0.1 + 0.9 * math.clamp(input.throttle, 0, 1))
	local fuel = math.max(s.fuel - burn * h, 0)

	-- Pilot G tolerance
	local gStress = s.gStress
	if gLoad > Flight.G_STRESS_ONSET then
		gStress += (gLoad - Flight.G_STRESS_ONSET) * Flight.G_STRESS_RATE * h
	else
		gStress -= Flight.G_STRESS_DECAY * h
	end
	local redStress = s.redStress
	if gLoad < Flight.RED_ONSET then
		redStress += (Flight.RED_ONSET - gLoad) * Flight.RED_STRESS_RATE * h
	else
		redStress -= Flight.G_STRESS_DECAY * h
	end

	return {
		cframe = CFrame.new(position) * rotation,
		velocity = velocity,
		angularVelocity = angularVelocity,
		pitchRate = pitchRate,
		rollRate = rollRate,
		yawRate = yawRate,
		fuel = fuel,
		gLoad = gLoad,
		aoa = f.aoa,
		sideslip = f.sideslip,
		stalled = f.stalled,
		gStress = math.clamp(gStress, 0, 1),
		redStress = math.clamp(redStress, 0, 1),
		mach = speed / Atmosphere.speedOfSound(f.altitude),
		altitude = Units.altitudeMetres(position.Y),
		speed = speed,
	}
end

-- Advances the state by dt seconds (split into sub-steps of at most Flight.MAX_SUBSTEP).
function FlightModel.step(
	state: FlightState,
	input: ControlInput,
	airframe: Airframe,
	dt: number,
	mods: Modifiers?
): FlightState
	local steps = math.max(1, math.ceil(dt / Flight.MAX_SUBSTEP - 1e-9))
	local h = dt / steps
	local s = state
	for _ = 1, steps do
		s = substep(s, input, airframe, h, mods)
	end
	return s
end

-- A fresh state for a jet at `cframe` flying straight at `speed` (real m/s).
function FlightModel.newState(cframe: CFrame, speed: number, airframe: Airframe, fuel: number?): FlightState
	local altitude = Units.altitudeMetres(cframe.Position.Y)
	return {
		cframe = cframe,
		velocity = cframe.LookVector * speed,
		angularVelocity = Vector3.zero,
		pitchRate = 0,
		rollRate = 0,
		yawRate = 0,
		fuel = fuel or airframe.Fuel,
		gLoad = 1,
		aoa = 0,
		sideslip = 0,
		stalled = false,
		gStress = 0,
		redStress = 0,
		mach = speed / Atmosphere.speedOfSound(altitude),
		altitude = altitude,
		speed = speed,
	}
end

-- Speed (real m/s) where the G limit and CLMax meet: the best instantaneous turn.
function FlightModel.cornerSpeed(airframe: Airframe, altitude: number, fuel: number?): number
	local mass = totalMass(airframe, fuel or airframe.Fuel)
	local density = Atmosphere.density(altitude)
	return math.sqrt(2 * airframe.MaxG * mass * G / (density * airframe.WingArea * airframe.CLMax))
end

-- Best sustained turn rate (rad/s) at a speed: thrust just balances drag. Full afterburner.
function FlightModel.maxSustainedTurnRate(airframe: Airframe, speed: number, altitude: number, fuel: number?): number
	local mass = totalMass(airframe, fuel or airframe.Fuel)
	local density = Atmosphere.density(altitude)
	local q = 0.5 * density * speed * speed
	local S = airframe.WingArea
	local mach = speed / Atmosphere.speedOfSound(altitude)
	local thrust = airframe.MaxThrust * airframe.AfterburnerMult * (density / Atmosphere.SEA_LEVEL_DENSITY) ^ 0.7
	local cd0 = airframe.CD0 + FlightModel.waveDrag(mach)
	local excess = thrust - q * S * cd0
	if excess <= 0 then
		return 0
	end
	local weight = mass * G
	local n = math.sqrt(excess * q * S / airframe.InducedK) / weight
	n = math.min(n, airframe.MaxG, q * S * airframe.CLMax / weight)
	if n <= 1 then
		return 0
	end
	return G * math.sqrt(n * n - 1) / speed
end

return FlightModel
