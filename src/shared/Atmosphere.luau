--!strict
-- Simple standard atmosphere, by real-equivalent altitude in metres.

local Atmosphere = {}

Atmosphere.SEA_LEVEL_DENSITY = 1.225
local SCALE_HEIGHT = 8500
local TROPOPAUSE = 11000

function Atmosphere.density(altitude: number): number
	return Atmosphere.SEA_LEVEL_DENSITY * math.exp(-math.max(altitude, 0) / SCALE_HEIGHT)
end

function Atmosphere.speedOfSound(altitude: number): number
	local h = math.clamp(altitude, 0, TROPOPAUSE)
	return 340.3 - (340.3 - 295.1) * (h / TROPOPAUSE)
end

function Atmosphere.mach(speed: number, altitude: number): number
	return speed / Atmosphere.speedOfSound(altitude)
end

return Atmosphere
