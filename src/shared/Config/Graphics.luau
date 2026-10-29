--!strict
-- Effects quality (DEVELOPMENT.md §20, FX-05). The EffectsQuality setting picks a profile that every
-- client-side effect follows; Auto picks one for the device. Roblox's own graphics level still sets the
-- world's detail: this only scales Afterburner's effects. Pure.

export type Profile = {
	particles: number, -- multiplier on particle rates and burst counts
	jetLights: boolean, -- afterburner, muzzle and missile-motor lights (explosion flashes always light)
	flareLights: boolean, -- each flare lights its surroundings
	flareSmoke: boolean, -- each flare trails smoke
	impactDust: boolean, -- dust or spray where rounds hit the ground or water
}

local Graphics = {}

Graphics.LEVELS = table.freeze({ "Low", "Medium", "High" })

Graphics.PROFILES = table.freeze({
	Low = table.freeze({
		particles = 0.3,
		jetLights = false,
		flareLights = false,
		flareSmoke = false,
		impactDust = false,
	}),
	Medium = table.freeze({
		particles = 0.6,
		jetLights = true,
		flareLights = false,
		flareSmoke = true,
		impactDust = true,
	}),
	High = table.freeze({
		particles = 1,
		jetLights = true,
		flareLights = true,
		flareSmoke = true,
		impactDust = true,
	}),
}) :: { [string]: Profile }

export type Device = {
	touchOnly: boolean, -- a phone or tablet (touch, no keyboard)
	robloxLevel: number, -- Roblox's graphics level, 1–10, or 0 for Automatic
}

-- The level an EffectsQuality setting means on this device. Auto: Low on phones and tablets, or when Roblox's
-- graphics level is set low (1–3); Medium at 4–6; otherwise High.
function Graphics.level(setting: string, device: Device): string
	if Graphics.PROFILES[setting] then
		return setting
	end
	local roblox = device.robloxLevel
	if device.touchOnly or (roblox >= 1 and roblox <= 3) then
		return "Low"
	elseif roblox >= 4 and roblox <= 6 then
		return "Medium"
	end
	return "High"
end

function Graphics.profile(setting: string, device: Device): Profile
	return Graphics.PROFILES[Graphics.level(setting, device)]
end

-- A particle count scaled for a profile, never below 1 for anything that emits at all.
function Graphics.count(profile: Profile, n: number): number
	return if n <= 0 then 0 else math.max(1, math.round(n * profile.particles))
end

return Graphics
