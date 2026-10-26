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
	-- A jet was destroyed: jetId, killer's UserId (0 = none or AI), cause, world position
	JetDestroyed = { direction = "ServerToClient", args = { "integer", "integer", "string", "Vector3" } },
	-- Kill feed line: killer name ("" = none), victim name, weapon or cause, assist names
	KillFeed = { direction = "ServerToClient", args = { "string", "string", "string", "table" } },

	-- Diagnostics (test environment only): exercises the Net layer end to end.
	-- Spawn a target drone: mode "ahead" (in front of you, same heading) or "circle" (orbits the range)
	DebugSpawnDrone = { direction = "ClientToServer", args = { "string" }, rate = { burst = 3, perSecond = 1 } },
	DebugPing = { direction = "ClientToServer", args = { "integer" }, rate = { burst = 5, perSecond = 2 } },
	DebugPong = { direction = "ServerToClient", args = { "integer", "number" } },
	DebugEcho = { direction = "Function", args = { "string" }, rate = { burst = 3, perSecond = 1 } },
}

return definitions
