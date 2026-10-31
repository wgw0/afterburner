--!strict
-- Reloading (Will: running dry shouldn't punish a pilot who's doing well and staying alive). Not realistic,
-- on purpose. When the gun, a missile type, flares or chaff run out, a timer starts; when it ends that store
-- is refilled to what the jet spawned with. The server runs it (CombatService for the gun, MissileService
-- for the rest) and sets the jet's Reload_<key> attribute to the server time it finishes, nil when not
-- reloading; the HUD draws a bar from that (keys: "Gun", "Flares", "Chaff", "Msl_<weapon id>"). Pure.

local Reload = {}

Reload.SECONDS = table.freeze({ -- *(tune in playtests)*
	Gun = 10,
	Missile = 15, -- a whole missile type, all its rounds at once
	Flares = 8,
	Chaff = 8,
})
Reload.PREFIX = "Reload_"

-- One step for a store: `count` left of `full`, `doneAt` the running timer's end (nil if none), `now` the
-- server time. Returns the timer's end from now on (nil when not reloading) and whether to refill now.
function Reload.step(count: number, full: number, doneAt: number?, now: number, seconds: number): (number?, boolean)
	if doneAt then
		if now >= doneAt then
			return nil, true
		end
		return doneAt, false
	end
	if count <= 0 and full > 0 then
		return now + seconds, false
	end
	return nil, false
end

-- How far through a reload is, 0..1.
function Reload.progress(doneAt: number, now: number, seconds: number): number
	return math.clamp(1 - (doneAt - now) / seconds, 0, 1)
end

-- The seconds for a key ("Gun", "Flares", "Chaff", or "Msl_<id>").
function Reload.secondsFor(key: string): number
	return (Reload.SECONDS :: any)[key] or Reload.SECONDS.Missile
end

return Reload
