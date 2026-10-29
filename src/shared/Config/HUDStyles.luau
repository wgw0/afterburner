--!strict
-- HUD symbology by cockpit era (DEVELOPMENT.md §9.4, HUD-05). Each airframe's Era picks a style:
--   Analogue (Tiers I–II and early jets): a reflector-sight look. Plain speed and altitude numbers instead
--     of tapes, a heading number instead of a tape, a simple pitch ladder (every 10°, no
--     numbers), no flight path marker, and only G and throttle in the corners.
--   EarlyGlass: the full HUD: tapes, numbered ladder every 5°, flight path marker, every readout.
--   FullGlass: as EarlyGlass, plus a bank-angle scale and a speed trend (where your speed will be in 5 s).
--   WAD (Tier VII–VIII: no HUD glass, a helmet display): FullGlass symbology fixed to your view instead of
--     the nose, so it stays in sight while you look around; the gun cross still marks the nose.
-- Every era keeps the same box size: the corner readouts need the room (a smaller analogue box overlapped them).
-- Pure.

export type Style = {
	boxWidth: number, -- degrees
	boxHeight: number,
	tapes: boolean, -- scrolling speed / altitude tapes (false: just the numbers)
	headingTape: boolean, -- false: a heading number
	ladderStep: number, -- degrees between the pitch rungs shown
	ladderNumbers: boolean,
	flightPath: boolean, -- the flight path marker
	fullReadouts: boolean, -- Mach, AoA and vertical speed too (false: G and throttle only)
	bankScale: boolean,
	speedTrend: boolean,
	helmet: boolean, -- drawn on the helmet (fixed to the view), not on the HUD glass (fixed to the nose)
}

local HUDStyles = {}

local EARLY_GLASS: Style = {
	boxWidth = 29.5, -- about 5% roomier than 28 × 22 (Will), so the readouts sit further apart
	boxHeight = 23.2,
	tapes = true,
	headingTape = true,
	ladderStep = 5,
	ladderNumbers = true,
	flightPath = true,
	fullReadouts = true,
	bankScale = false,
	speedTrend = false,
	helmet = false,
}

local function with(base: Style, changes: { [string]: any }): Style
	local style = table.clone(base) :: any
	for key, value in changes do
		style[key] = value
	end
	return table.freeze(style)
end

HUDStyles.STYLES = table.freeze({
	Analogue = with(EARLY_GLASS, {
		tapes = false,
		headingTape = false,
		ladderStep = 10,
		ladderNumbers = false,
		flightPath = false,
		fullReadouts = false,
	}),
	EarlyGlass = table.freeze(EARLY_GLASS),
	FullGlass = with(EARLY_GLASS, { bankScale = true, speedTrend = true }),
	WAD = with(EARLY_GLASS, { bankScale = true, speedTrend = true, helmet = true }),
}) :: { [string]: Style }

HUDStyles.DEFAULT = "EarlyGlass"

-- The style for an airframe's Era (EarlyGlass for an unknown or missing one).
function HUDStyles.forEra(era: string?): Style
	return HUDStyles.STYLES[era or ""] or HUDStyles.STYLES[HUDStyles.DEFAULT]
end

return HUDStyles
