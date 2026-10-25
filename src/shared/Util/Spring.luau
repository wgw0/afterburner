--!strict
-- Damped spring for cameras, needles and smoothing. Works on numbers and Vector3s.
-- speed: angular frequency (higher = snappier). damping: 1 = critically damped, <1 overshoots.

local Spring = {}
Spring.__index = Spring

export type Spring<T> = {
	position: T,
	velocity: T,
	speed: number,
	damping: number,
	Update: (self: Spring<T>, dt: number, target: T) -> T,
	Reset: (self: Spring<T>, position: T) -> (),
}

local MAX_STEP = 1 / 120

function Spring.new<T>(initial: T, speed: number?, damping: number?): Spring<T>
	local zero: any = if typeof(initial) == "Vector3" then Vector3.zero else 0
	local self = setmetatable({
		position = initial,
		velocity = zero,
		speed = speed or 10,
		damping = damping or 1,
	}, Spring)
	return (self :: any) :: Spring<T>
end

function Spring:Update(dt: number, target: any): any
	-- Fixed sub-steps keep it stable at low frame rates.
	local remaining = math.max(dt, 0)
	local w, z = self.speed, self.damping
	while remaining > 0 do
		local h = math.min(remaining, MAX_STEP)
		local accel = (target - self.position) * (w * w) - self.velocity * (2 * z * w)
		self.velocity += accel * h
		self.position += self.velocity * h
		remaining -= h
	end
	return self.position
end

function Spring:Reset(position: any)
	self.position = position
	self.velocity = if typeof(position) == "Vector3" then Vector3.zero else 0
end

return Spring
