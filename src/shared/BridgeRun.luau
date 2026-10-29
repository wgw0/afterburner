--!strict
-- Flying under a bridge (the "Threading the Needle" bonus). Pure: the server feeds it two positions of a jet
-- in a bridge's own frame (Model:GetPivot(), docs/art/BRIDGE.md: x across the bridge, y up from its water
-- line, z along it, 0 at midspan) and asks whether the jet passed under the deck between them.
-- The deck's road runs on a parabola, ROAD_MID above the water at midspan and ROAD_END at the ends of the
-- deck (END_Z); under it there's the girder. The towers stand at TOWER_Z, the anchorages at ANCHOR_Z.

local BridgeRun = {}

BridgeRun.ROAD_MID = 50
BridgeRun.ROAD_END = 18
BridgeRun.END_Z = 945
BridgeRun.GIRDER = 4 -- road surface to the underside of the deck
BridgeRun.TOWER_Z = 494
BridgeRun.TOWER_CLEAR = 15 -- either side of a tower doesn't count (its piers and legs)
BridgeRun.ANCHOR_Z = 780 -- the side spans end at the anchorages (on land)
BridgeRun.WATER_MARGIN = 10 -- below the water line can't be flying

-- Height of the deck's underside above the water line at `z` along the bridge.
function BridgeRun.clearance(z: number): number
	local t = math.clamp(math.abs(z) / BridgeRun.END_Z, 0, 1)
	return BridgeRun.ROAD_END + (BridgeRun.ROAD_MID - BridgeRun.ROAD_END) * (1 - t * t) - BridgeRun.GIRDER
end

-- Did a jet going from `a` to `b` (both in the bridge's frame) pass under the deck?
function BridgeRun.passedUnder(a: Vector3, b: Vector3): boolean
	if (a.X > 0) == (b.X > 0) or a.X == b.X then
		return false -- didn't cross the bridge's line
	end
	local point = a:Lerp(b, a.X / (a.X - b.X))
	local z = math.abs(point.Z)
	if z >= BridgeRun.ANCHOR_Z or math.abs(z - BridgeRun.TOWER_Z) < BridgeRun.TOWER_CLEAR then
		return false
	end
	return point.Y > -BridgeRun.WATER_MARGIN and point.Y < BridgeRun.clearance(point.Z)
end

return BridgeRun
