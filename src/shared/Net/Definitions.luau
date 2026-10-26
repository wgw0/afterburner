--!strict
-- Every remote in the game is declared here (DEVELOPMENT.md Appendix A).
--   direction: "ClientToServer" | "ServerToClient" | "Function" (client -> server request/response)
--   reliable:  false = UnreliableRemoteEvent (small, replaceable state only)
--   args:      type specs checked by Validate.matchesSpec ("number", "string?", "Vector3", ...)
--   rate:      client -> server token bucket: `burst` calls, refilling at `perSecond`

export type Definition = {
	direction: "ClientToServer" | "ServerToClient" | "Function",
	reliable: boolean?,
	args: { string },
	rate: { burst: number, perSecond: number }?,
}

local definitions: { [string]: Definition } = {
	-- Aircraft lifecycle (§10)
	RequestSpawn = { direction = "ClientToServer", args = { "string" }, rate = { burst = 2, perSecond = 1 } },
	ReportCrash = { direction = "ClientToServer", args = {}, rate = { burst = 2, perSecond = 1 } },
	-- Pilot's throttle/afterburner/G for other players' effects, 5 Hz: throttle, afterburner, gLoad
	FlightTelemetry = {
		direction = "ClientToServer",
		reliable = false,
		args = { "number", "boolean", "number" },
		rate = { burst = 10, perSecond = 8 },
	},

	-- Guns and damage (§11–12)
	-- Trigger pulled/released: isStart, client serverTime, spread seed
	GunFire = {
		direction = "ClientToServer",
		args = { "boolean", "number", "integer" },
		rate = { burst = 10, perSecond = 8 },
	},
	-- Another jet started/stopped firing, so clients can draw its tracers: jetId, isStart, seed, serverTime
	GunFireFx = { direction = "ServerToClient", args = { "integer", "boolean", "integer", "number" } },
	-- Your round hit something: targetJetId, component
	HitConfirm = { direction = "ServerToClient", args = { "integer", "string" } },
	-- Sparks where a round hit a jet: jetId, world position
	HitFx = { direction = "ServerToClient", reliable = false, args = { "integer", "Vector3" } },
	-- Your jet's component health as fractions (0..1)
	DamageState = { direction = "ServerToClient", args = { "table" } },
	-- A jet was destroyed: jetId, killer's UserId (0 = none or AI), cause, world position, killer's jet (0 = none)
	JetDestroyed = { direction = "ServerToClient", args = { "integer", "integer", "string", "Vector3", "integer" } },
	-- Kill feed line: killer name ("" = none), victim name, weapon or cause, assist names
	KillFeed = { direction = "ServerToClient", args = { "string", "string", "string", "table" } },

	-- Missiles, sensors and countermeasures (§13–15)
	-- Pick which missile type Space fires: index into the airframe's Missiles list
	SelectWeapon = { direction = "ClientToServer", args = { "integer" }, rate = { burst = 6, perSecond = 4 } },
	-- Lock a radar contact (0 = unlock)
	RadarLockRequest = { direction = "ClientToServer", args = { "integer" }, rate = { burst = 6, perSecond = 4 } },
	-- Your radar lock changed: targetJetId (0 = none), state "Locked" | "Lost" | "None"
	LockState = { direction = "ServerToClient", args = { "integer", "string" } },
	-- Who's painting you: { { id = jetId, kind = "Search"|"Lock"|"Launch", position = Vector3 } }
	RWRUpdate = { direction = "ServerToClient", args = { "table" } },
	-- Fire the selected missile at a target (0 = no lock: fires unguided)
	MissileFire = { direction = "ClientToServer", args = { "integer" }, rate = { burst = 3, perSecond = 2 } },
	-- A missile was launched: id, weaponId, ownerJetId (0 = none), position, velocity
	MissileSpawned = { direction = "ServerToClient", args = { "integer", "string", "integer", "Vector3", "Vector3" } },
	-- Packed positions of every missile in flight (Net/Pack), ~15 Hz
	MissileState = { direction = "ServerToClient", reliable = false, args = { "buffer" } },
	-- A missile exploded or expired: id, position, jet it hit (0 = none)
	MissileDetonated = { direction = "ServerToClient", args = { "integer", "Vector3", "integer" } },
	-- Drop a flare or chaff bundle: "Flare" | "Chaff"
	CountermeasureDeploy = { direction = "ClientToServer", args = { "string" }, rate = { burst = 6, perSecond = 6 } },
	-- A jet dropped a flare or chaff: jetId, kind, position, velocity
	CountermeasureFx = { direction = "ServerToClient", args = { "integer", "string", "Vector3", "Vector3" } },

	-- Matches (§17): mode, state, time left, ranking, winner. ~2 Hz and on every change.
	MatchState = { direction = "ServerToClient", args = { "table" } },

	-- Diagnostics (test environment only): exercises the Net layer end to end.
	-- Switch game mode: "FreeFlight" | "Dogfight" | "Stress", or "EndMatch" to end the running match now
	DebugSetMode = { direction = "ClientToServer", args = { "string" }, rate = { burst = 2, perSecond = 0.5 } },
	-- Fire a missile at yourself from 1.8 km behind, to practise defending (weapon id)
	DebugLaunchAtMe = { direction = "ClientToServer", args = { "string" }, rate = { burst = 2, perSecond = 0.5 } },
	-- Spawn a target drone: mode "ahead" (in front of you, same heading) or "circle" (orbits the range)
	DebugSpawnDrone = { direction = "ClientToServer", args = { "string" }, rate = { burst = 3, perSecond = 1 } },
	DebugPing = { direction = "ClientToServer", args = { "integer" }, rate = { burst = 5, perSecond = 2 } },
	DebugPong = { direction = "ServerToClient", args = { "integer", "number" } },
	DebugEcho = { direction = "Function", args = { "string" }, rate = { burst = 3, perSecond = 1 } },
}

return definitions
