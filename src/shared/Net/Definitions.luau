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
	-- Diagnostics (test environment only): exercises the Net layer end to end.
	DebugPing = { direction = "ClientToServer", args = { "integer" }, rate = { burst = 5, perSecond = 2 } },
	DebugPong = { direction = "ServerToClient", args = { "integer", "number" } },
	DebugEcho = { direction = "Function", args = { "string" }, rate = { burst = 3, perSecond = 1 } },
}

return definitions
