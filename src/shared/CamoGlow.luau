--!strict
-- The Galaxy camo's glow (Will): its SurfaceAppearances carry a glow mask (EmissiveMaskContent: the stars and
-- the brightest nebula) and the CamoGlow tag; CamoGlowController eases the glow up and down and drifts its
-- tint between violet and pink, on each player's own screen. Pure: the glow at a moment.

local CamoGlow = {}

CamoGlow.TAG = "CamoGlow"
CamoGlow.PERIOD = 4 -- seconds for one breath, bright to soft and back
CamoGlow.TINT_PERIOD = 11 -- seconds for the tint to drift violet to pink and back
CamoGlow.LOW, CamoGlow.HIGH = 0.6, 2.2 -- EmissiveStrength at the soft and bright ends
CamoGlow.STEADY = 1.2 -- with Reduce Flashing on: no pulse, this glow
CamoGlow.VIOLET = Color3.fromRGB(176, 120, 255)
CamoGlow.PINK = Color3.fromRGB(255, 120, 214)

-- The glow at time t (seconds) for a jet whose pulse is offset by phase (0..1, so a formation doesn't
-- breathe in step). Returns EmissiveStrength and EmissiveTint.
function CamoGlow.at(t: number, phase: number, steady: boolean): (number, Color3)
	local tint =
		CamoGlow.VIOLET:Lerp(CamoGlow.PINK, 0.5 - 0.5 * math.cos(2 * math.pi * (t / CamoGlow.TINT_PERIOD + phase)))
	if steady then
		return CamoGlow.STEADY, tint
	end
	local breath = 0.5 - 0.5 * math.cos(2 * math.pi * (t / CamoGlow.PERIOD + phase))
	return CamoGlow.LOW + (CamoGlow.HIGH - CamoGlow.LOW) * breath, tint
end

return CamoGlow
