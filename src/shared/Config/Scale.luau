--!strict
-- World scale (DEVELOPMENT.md §3.2). Every value here is a starting point to tune in playtests.
--
-- The flight model runs in real-world SI units. Only the world is compressed: a jet doing a real
-- 250 m/s moves 250 × SPEED_SCALE "visual metres" per second in the world. Because positions come
-- from those scaled velocities, real-equivalent distances and altitudes are world distances divided
-- by SPEED_SCALE, so climbs, turn rates and energy all stay true to life.

local STUDS_PER_METRE = 1 -- 1 stud = 1 visual metre (it was 0.28 m: the terrain took over 2 minutes to load)
local SPEED_SCALE = 0.38

return table.freeze({
	STUDS_PER_METRE = STUDS_PER_METRE,
	SPEED_SCALE = SPEED_SCALE,
	DISTANCE_DISPLAY_SCALE = 1 / SPEED_SCALE,
	MAP_HALF_EXTENT = 5600, -- studs from the origin to the edge of the play area (~14.7 km real)
	CEILING = 5600, -- studs (~48,000 ft real-equivalent)
})
