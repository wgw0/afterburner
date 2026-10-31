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
	-- Take out (true, skin) or put away (false) the Ground Roamer (§36): returns (ok, reason)
	RequestGroundRoamer = {
		direction = "Function",
		args = { "boolean", "string?" },
		rate = { burst = 3, perSecond = 0.5 },
	},
	-- Pilot's throttle/afterburner/G for other players' effects, 5 Hz: throttle, afterburner, gLoad
	FlightTelemetry = {
		direction = "ClientToServer",
		reliable = false,
		args = { "number", "boolean", "number" },
		rate = { burst = 10, perSecond = 8 },
	},

	-- The client's frame rate, once a second, so the map warm-up goes as fast as this machine can take it
	StreamPace = {
		direction = "ClientToServer",
		reliable = false,
		args = { "number" },
		rate = { burst = 3, perSecond = 2 },
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
	-- The jet the pilot is looking at, for a helmet-cued heat-seeker (MSL-09; 0 = none)
	IRCue = { direction = "ClientToServer", args = { "integer" }, rate = { burst = 8, perSecond = 6 } },
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
	-- Player data and progression (§22–23). Values never come from the client: only intents.
	-- Your save's replicated fields changed: changes (or the whole replica), isFull
	PlayerDataUpdate = { direction = "ServerToClient", args = { "table", "boolean" } },
	-- Your full replica (asked for when your client starts)
	GetPlayerData = { direction = "Function", args = {}, rate = { burst = 3, perSecond = 0.5 } },
	-- Research / buy a jet, buy a module, set the lineup: each returns (ok, error message)
	ResearchAircraft = { direction = "Function", args = { "string" }, rate = { burst = 4, perSecond = 2 } },
	BuyAircraft = { direction = "Function", args = { "string" }, rate = { burst = 4, perSecond = 2 } },
	BuyModule = { direction = "Function", args = { "string", "string" }, rate = { burst = 4, perSecond = 2 } },
	BuySkin = { direction = "Function", args = { "string", "string", "string?" }, rate = { burst = 4, perSecond = 2 } },
	SetSkin = { direction = "Function", args = { "string", "string" }, rate = { burst = 4, perSecond = 2 } },
	-- Cosmetics (SHP-07): buy one with Wings; equip one in its kind's slot ("" clears it)
	BuyCosmetic = { direction = "Function", args = { "string" }, rate = { burst = 4, perSecond = 2 } },
	EquipCosmetic = { direction = "Function", args = { "string", "string" }, rate = { burst = 6, perSecond = 3 } },
	-- Fit (true) or take off (false) a module the player already owns
	SetModuleFitted = {
		direction = "Function",
		args = { "string", "string", "boolean" },
		rate = { burst = 4, perSecond = 2 },
	},
	SetLineup = { direction = "Function", args = { "table" }, rate = { burst = 4, perSecond = 2 } },
	-- Your spawn request was refused: reason
	SpawnRefused = { direction = "ServerToClient", args = { "string" } },
	-- Settings changed (the server keeps only known keys with valid values)
	SettingsUpdate = { direction = "ClientToServer", args = { "table" }, rate = { burst = 5, perSecond = 1 } },
	-- Your rewards at the end of a match: { XP, Credits, RP = {...}, FreeRP, Lines, Levels, ... }
	MatchRewards = { direction = "ServerToClient", args = { "table" } },
	-- Admin commands (AdminService checks who may use them): command, args -> (ok, message)
	AdminCommand = { direction = "Function", args = { "string", "table?" }, rate = { burst = 5, perSecond = 2 } },

	-- Switch game mode: "FreeFlight" | "Dogfight" | "Stress", or "EndMatch" to end the running match now
	DebugSetMode = { direction = "ClientToServer", args = { "string" }, rate = { burst = 2, perSecond = 0.5 } },
	-- Fire a missile at yourself from 1.8 km behind, to practise defending (weapon id)
	DebugLaunchAtMe = { direction = "ClientToServer", args = { "string" }, rate = { burst = 2, perSecond = 0.5 } },
	-- Spawn a target drone: mode "ahead" (in front of you, same heading) or "circle" (orbits the range)
	DebugSpawnDrone = { direction = "ClientToServer", args = { "string" }, rate = { burst = 3, perSecond = 1 } },
	-- Challenges and achievements (ChallengeService): swap one unfinished daily challenge (once a day), and the
	-- toast when a challenge or achievement completes: { kind, text, detail?, credits?, xp? }
	RerollChallenge = { direction = "Function", args = { "integer" }, rate = { burst = 3, perSecond = 0.5 } },
	ChallengeNotice = { direction = "ServerToClient", args = { "table" } },
	-- A new pilot chose to stay in training after the welcome card (TUT-04): no more first-session flow
	FinishOnboarding = { direction = "ClientToServer", args = {}, rate = { burst = 2, perSecond = 0.2 } },
	-- A new pilot closed the lobby's welcome window instead of going to training: no more first-session flow
	SkipOnboarding = { direction = "ClientToServer", args = {}, rate = { burst = 2, perSecond = 0.2 } },
	-- The daily login reward (LIV-03): claim today's; returns { count, credits, freeRP, title? } or nil
	ClaimDailyReward = { direction = "Function", args = {}, rate = { burst = 3, perSecond = 0.5 } },
	-- A tutorial lesson finished (TutorialController → TelemetryService, ANL-02)
	LessonCompleted = { direction = "ClientToServer", args = { "string" }, rate = { burst = 3, perSecond = 0.2 } },
	-- Pick the title shown next to your name (a Config/LevelRewards title id, or "" for none)
	SetTitle = { direction = "Function", args = { "string" }, rate = { burst = 3, perSecond = 0.5 } },
	-- Use a banked free spin: (prize table, or nil and why not). The server rolls it (Shared/Spin)
	SpinWheel = { direction = "Function", args = {}, rate = { burst = 2, perSecond = 0.5 } },
	-- Pick the two jets for your Tier Unlock and open its purchase (SHP, DESIGN §8.2): (ok, why not)
	ChooseTierUnlock = { direction = "Function", args = { "table" }, rate = { burst = 3, perSecond = 0.5 } },
	-- Your custom callsign ("" = your username); filtered by Roblox before anyone sees it (CMP-01)
	SetCallsign = { direction = "Function", args = { "string" }, rate = { burst = 3, perSecond = 0.2 } },
	-- Leave the current flight for the hangar (HangarButtonController)
	ReturnToHangar = { direction = "ClientToServer", args = {}, rate = { burst = 2, perSecond = 0.5 } },
	-- Matchmaking (MatchmakingService): join the queue for a mode ("Any" or a mode id) with the jet you clicked
	-- PLAY with (it sets your BR), leave it, and its state back to the player:
	-- { state = "Idle" | "Searching" | "Found", mode, waited, message }
	QueueJoin = { direction = "ClientToServer", args = { "string", "string?" }, rate = { burst = 3, perSecond = 0.5 } },
	QueueLeave = { direction = "ClientToServer", args = {}, rate = { burst = 3, perSecond = 0.5 } },
	QueueState = { direction = "ServerToClient", args = { "table" } },
	-- Report a pilot on this server for cheating (ReportService, CMP-03): targetUserId, reason id (Reports) ->
	-- (ok, message). The server also allows one report per 30 s.
	ReportPlayer = { direction = "Function", args = { "integer", "string" }, rate = { burst = 2, perSecond = 1 / 30 } },
	-- Go to a training server ("Training") or back to a lobby ("Lobby") (MatchmakingService)
	Travel = { direction = "ClientToServer", args = { "string" }, rate = { burst = 2, perSecond = 0.2 } },
	-- On a training server: "FreeFlight", or a Vs AI match: mode id, AI difficulty, number of AI pilots
	TrainingSetup = {
		direction = "ClientToServer",
		args = { "string", "string", "integer" },
		rate = { burst = 3, perSecond = 0.5 },
	},
	-- Lesson 6: start (true) or end (false) a training bout against an Easy AI pilot (Free Flight only)
	TrainingBout = { direction = "ClientToServer", args = { "boolean" }, rate = { burst = 2, perSecond = 0.5 } },
	DebugPing = { direction = "ClientToServer", args = { "integer" }, rate = { burst = 5, perSecond = 2 } },
	DebugPong = { direction = "ServerToClient", args = { "integer", "number" } },
	DebugEcho = { direction = "Function", args = { "string" }, rate = { burst = 3, perSecond = 1 } },
}

return definitions
