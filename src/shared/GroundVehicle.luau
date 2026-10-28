--!strict
-- Raycast-suspension vehicle model (DEVELOPMENT.md §36). Pure: it reads the body's state, casts each wheel's
-- ray through the `ground` function it is given, and returns the forces to apply this step. The caller (the
-- driver's DriveController) applies them as impulses to the vehicle's root, so Roblox physics integrates the
-- body and handles its collisions; the wheels themselves have no collision.
--
-- Per wheel: a spring and damper along the ground normal, and an anti-roll bar linking each axle's two wheels;
-- drive, brake and rolling resistance along the tyre's
-- heading on the ground; lateral grip against sideways sliding; the tyre force kept within a friction circle
-- (grip x load). All four wheels are driven. Units are metres and seconds (1 stud = 1 m); forces are in the
-- body's own mass units (mass x acceleration), so they work whatever the parts' densities are.

local GroundVehicle = {}

export type Config = {
	Wheels: { { name: string, hub: Vector3, steers: boolean } },
	WheelRadius: number,
	SuspensionFrequency: number,
	SuspensionDamping: number,
	SuspensionTravel: number,
	AntiRoll: number,
	EngineAccel: number,
	TopSpeed: number,
	ReverseSpeed: number,
	BrakeAccel: number,
	HandbrakeAccel: number,
	RollingResistance: number,
	Grip: number,
	LateralStiffness: number,
	AirDrag: number,
	MaxSteer: number,
	MinSteer: number,
	SteerRate: number,
	Gravity: number,
}

-- throttle -1..1 (negative: brake, then reverse), steer -1..1 (positive: right), handbrake
export type Input = { throttle: number, steer: number, handbrake: boolean }

export type Body = {
	cframe: CFrame, -- the vehicle's pivot (on the ground between the axles at rest)
	velocity: Vector3,
	angularVelocity: Vector3,
	centreOfMass: Vector3, -- world
	mass: number,
}

export type State = {
	steer: number, -- radians, current road-wheel angle
	compression: { number }, -- metres, per wheel
	spin: { number }, -- radians, per wheel (for the visuals)
}

export type WheelOut = { compression: number, steer: number, spin: number, grounded: boolean }
export type Step = {
	forces: { { position: Vector3, force: Vector3 } },
	wheels: { WheelOut },
	speed: number, -- m/s along the body's heading (negative: reversing)
	grounded: number, -- wheels on the ground
}

-- ground(origin, direction) -> (hit position, surface normal) or nil
export type GroundFn = (Vector3, Vector3) -> (Vector3?, Vector3?)

function GroundVehicle.newState(config: Config): State
	local n = #config.Wheels
	return { steer = 0, compression = table.create(n, 0), spin = table.create(n, 0) }
end

-- Road-wheel lock at a given forward speed: full lock at walking pace, MinSteer at TopSpeed.
function GroundVehicle.steerLimit(config: Config, speed: number): number
	local t = math.clamp(math.abs(speed) / config.TopSpeed, 0, 1)
	return config.MaxSteer + (config.MinSteer - config.MaxSteer) * t
end

-- Spring rate and damping per unit mass for one corner (each corner carries 1/n of the body).
function GroundVehicle.springRates(config: Config): (number, number)
	local omega = 2 * math.pi * config.SuspensionFrequency
	local k = omega * omega -- per unit corner mass
	local c = 2 * config.SuspensionDamping * omega
	return k, c
end

function GroundVehicle.step(config: Config, state: State, body: Body, input: Input, ground: GroundFn, dt: number): Step
	local cf = body.cframe
	local up = cf.UpVector
	local forward = cf.LookVector
	local right = cf.RightVector
	local n = #config.Wheels
	local cornerMass = body.mass / n
	local k, c = GroundVehicle.springRates(config)
	local travel = config.SuspensionTravel
	local radius = config.WheelRadius

	local speed = body.velocity:Dot(forward)

	-- Steering eases toward the input, limited by speed
	local targetSteer = math.clamp(input.steer, -1, 1) * GroundVehicle.steerLimit(config, speed)
	local maxStep = config.SteerRate * dt
	state.steer += math.clamp(targetSteer - state.steer, -maxStep, maxStep)

	-- Drive: throttle forwards; the opposite of the way you're going brakes, then reverses
	local throttle = math.clamp(input.throttle, -1, 1)
	local driveAccel, brakeAccel = 0, 0
	if throttle > 0 then
		if speed < -0.5 then
			brakeAccel = config.BrakeAccel * throttle
		else
			driveAccel = config.EngineAccel * throttle * math.max(0, 1 - (speed / config.TopSpeed) ^ 3)
		end
	elseif throttle < 0 then
		if speed > 0.5 then
			brakeAccel = config.BrakeAccel * -throttle
		else
			driveAccel = -config.EngineAccel * -throttle * math.max(0, 1 - (-speed / config.ReverseSpeed) ^ 3)
		end
	end

	-- First pass: each wheel's ray and its suspension compression
	local hits: { Vector3? } = table.create(n)
	local normals: { Vector3? } = table.create(n)
	local rates = table.create(n, 0)
	for i, wheel in config.Wheels do
		-- The ray starts `travel` above the rest hub and reaches `travel` below it, plus the tyre radius
		local top = cf:PointToWorldSpace(wheel.hub + Vector3.new(0, travel, 0))
		local hit, normal = ground(top, -up * (2 * travel + radius))
		if hit and normal then
			local hubDistance = (top - hit):Dot(up) - radius -- from the top of travel down to the hub
			local compression = math.clamp(travel - hubDistance, -travel, travel) -- 0 at rest height
			rates[i] = (compression - state.compression[i]) / dt
			state.compression[i] = compression
			hits[i], normals[i] = hit, normal
		else
			state.compression[i] = -travel
		end
	end

	-- Second pass: loads (spring, damper, anti-roll bar) and the tyre forces
	local forces = {}
	local wheels: { WheelOut } = table.create(n)
	local grounded = 0
	for i, wheel in config.Wheels do
		local steer = if wheel.steers then state.steer else 0
		local hit, normal = hits[i], normals[i]
		local compression = state.compression[i]
		local out: WheelOut = { compression = compression, steer = steer, spin = state.spin[i], grounded = false }
		if hit and normal then
			-- The spring holds the corner up at rest (compression 0 carries g), plus the damper; the anti-roll bar
			-- adds load where this wheel is compressed more than the other wheel on its axle
			local partner = 0
			for j, other in config.Wheels do
				if j ~= i and math.abs(other.hub.Z - wheel.hub.Z) < 1e-3 then
					partner = j
				end
			end
			local roll = if partner > 0 then compression - state.compression[partner] else 0
			local load = cornerMass * (config.Gravity + k * compression + c * rates[i] + k * config.AntiRoll * roll)
			load = math.max(load, 0)
			if load > 0 then
				grounded += 1
				out.grounded = true
				local contact = hit
				local heading = (forward * math.cos(steer) + right * math.sin(steer))
				heading = (heading - normal * heading:Dot(normal))
				if heading.Magnitude > 1e-6 then
					heading = heading.Unit
				end
				local side = normal:Cross(heading) -- points left of the heading
				local pointVelocity = body.velocity + body.angularVelocity:Cross(contact - body.centreOfMass)
				local vLong = pointVelocity:Dot(heading)
				local vSide = pointVelocity:Dot(side)

				local long = driveAccel * cornerMass
				local brake = brakeAccel
				if input.handbrake and not wheel.steers then
					brake = math.max(brake, config.HandbrakeAccel)
				end
				brake += config.RollingResistance
				-- Brakes and rolling resistance oppose the tyre's motion, but never push it backwards
				local brakeForce = math.min(brake * cornerMass, math.abs(vLong) * cornerMass / dt)
				long -= brakeForce * (if vLong >= 0 then 1 else -1)
				local lat = -vSide * config.LateralStiffness * cornerMass
				lat = math.clamp(lat, -math.abs(vSide) * cornerMass / dt, math.abs(vSide) * cornerMass / dt)
				-- Friction circle
				local limit = config.Grip * load
				local mag = math.sqrt(long * long + lat * lat)
				if mag > limit and mag > 0 then
					long *= limit / mag
					lat *= limit / mag
				end
				table.insert(forces, { position = contact + normal * radius, force = normal * load })
				table.insert(forces, { position = contact, force = heading * long + side * lat })
				state.spin[i] += vLong / radius * dt
			end
		else
			state.spin[i] += speed / radius * dt * 0.98 -- spinning down in the air
		end
		out.spin = state.spin[i]
		wheels[i] = out
	end

	-- Air drag at the centre of mass
	local v = body.velocity
	if v.Magnitude > 0.1 then
		table.insert(
			forces,
			{ position = body.centreOfMass, force = -v.Unit * config.AirDrag * v.Magnitude ^ 2 * body.mass }
		)
	end

	return { forces = forces, wheels = wheels, speed = speed, grounded = grounded }
end

return GroundVehicle
