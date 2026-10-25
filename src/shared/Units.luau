--!strict
-- Converts between the flight model's real SI units and the world's studs (see Config/Scale).
-- Every HUD number goes through the display helpers here.

local Scale = require(script.Parent.Config.Scale)

local STUDS_PER_REAL_METRE = Scale.STUDS_PER_METRE * Scale.SPEED_SCALE

local Units = {}

Units.STUDS_PER_REAL_METRE = STUDS_PER_REAL_METRE

-- Real m/s (vector or number) -> world studs/s
function Units.velocityToStuds<T>(realMps: T): T
	return (realMps :: any) * STUDS_PER_REAL_METRE
end

-- World studs/s -> real m/s
function Units.velocityFromStuds<T>(studsPerSecond: T): T
	return (studsPerSecond :: any) / STUDS_PER_REAL_METRE
end

-- World studs -> real-equivalent metres (distances and altitudes)
function Units.toMetres(studs: number): number
	return studs / STUDS_PER_REAL_METRE
end

-- Real-equivalent metres -> world studs
function Units.toStuds(metres: number): number
	return metres * STUDS_PER_REAL_METRE
end

function Units.altitudeMetres(worldY: number): number
	return worldY / STUDS_PER_REAL_METRE
end

function Units.knots(mps: number): number
	return mps * 1.943844
end

function Units.kmh(mps: number): number
	return mps * 3.6
end

function Units.feet(metres: number): number
	return metres * 3.280840
end

function Units.km(metres: number): number
	return metres / 1000
end

return Units
