--!strict
-- World scale (DEVELOPMENT.md §3.2). Every value here is a starting point to tune in playtests.

local STUDS_PER_METRE = 1 / 0.28
local SPEED_SCALE = 0.38

return table.freeze({
	STUDS_PER_METRE = STUDS_PER_METRE,
	SPEED_SCALE = SPEED_SCALE, -- world speed = real speed × this
	DISTANCE_DISPLAY_SCALE = 1 / SPEED_SCALE, -- displayed distances are inflated by this
	MAP_HALF_EXTENT = 20000, -- studs from the origin to the edge of the play area
	CEILING = 12000, -- studs
})
