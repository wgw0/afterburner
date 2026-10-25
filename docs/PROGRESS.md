# Afterburner: Progress Tracker

Every task from [DEVELOPMENT.md](DEVELOPMENT.md), by phase. A box is ticked only when the task's acceptance test has **actually been run and passed** (Definition of Done, DEVELOPMENT.md §0.8). The evidence column says how it was checked.

| Phase | Done | Status |
|---|---|---|
| 0 Foundation | 7 / 9 | 🟡 Waiting on CI's first run on GitHub |
| 1–8 | 0 / 182 | ⚪ Not started |

---

## Phase 0: Foundation

| | Task | Evidence |
|:---:|---|---|
| ✅ | **CORE-01** Folder tree and server/client `Main` boot loaders with Init/Start ordering and per-service error reporting | Play test: output shows `Service started: DiagnosticsService` → `Server ready` → `Controller started: DiagnosticsController` → `Client ready`, with no errors. `Boot.spec`: Priority ordering, a yielding `Init` is refused, a failing `Init` names the module. |
| ✅ | **CORE-02** StyLua, Selene, Wally in `rokit.toml` with config files | `rokit install` gives Rojo 7.7.1, StyLua 2.6.0, Selene 0.32.0, Wally 0.3.2. `stylua --check` and `selene` both clean (0 errors, 0 warnings). |
| ⏳ | **CORE-03** GitHub Actions CI | Workflow written (`.github/workflows/ci.yml`). Same steps pass locally. **Ticked once the first run on GitHub is green.** |
| ✅ | **CORE-04** Util: Signal, Trove, Spring, RingBuffer, Pool, Validate, with unit tests | `Util.spec` and `Validate.spec` pass in Studio. |
| ✅ | **NET-01** `Definitions` format plus `Net` wrapper with type validation | Play test: the client fired a string, NaN, `1.5`, three arguments, and no arguments at an integer remote. All 5 were dropped with the reason logged. A bad RemoteFunction argument returned `nil` without erroring. A valid echo round trip took 91–123 ms in Studio. |
| ✅ | **NET-02** Per-remote token-bucket rate limiting plus a dropped-call counter | Play test: 50 pings in one frame against a 5-call burst gave exactly the burst through and the rest dropped. Logging is summarised every 5 s (`x46`), so spam can't flood the output. |
| ✅ | **MAP-01** Greybox test map: flat area, towers, runway | `Workspace.TestRange` (60 parts): 1,800-stud runway with markings, 6 slalom pylons, height towers at 100/250/500/1000 studs. Saved in `Afterburner.rbxl`. |
| ✅ | **TST-01** Test runner and first specs | `require(game.ServerStorage.Tests.TestRunner).run()` → **28 passed, 0 failed**. A deliberately failing spec was correctly reported as a failure, with file and line. |
| ⏳ | **REL-01** CI workflow | Same as CORE-03. |

**Also done in Phase 0:**
- [x] Rojo CLI and Studio plugin installed. `rojo serve` syncs every file into the open place (checked instance by instance).
- [x] `Shared.Config.Environment`: Studio counts as `Test`, live servers default to `Prod`.

**Known noise (not ours):** Studio prints `ContentId: rbxassetid://203785492 failed…` on play. That asset isn't referenced anywhere in the place or code, so it comes from Roblox's own default content.

---

## Phase 1: Flight model prototype

- [ ] **ACD-01** Airframe schema, registry and startup validator
- [ ] **ACD-02** Greybox models for F-5E and MiG-21 following the model contract
- [ ] **ACD-03** Model-contract validator script (Studio command plus CI check against the built place)
- [ ] **FLT-01** `Atmosphere`, `Units` and `Scale` modules with tests
- [ ] **FLT-02** `FlightModel.step` (steps 1–13), sub-stepping, determinism
- [ ] **FLT-03** Stall model and buffet flag
- [ ] **FLT-04** G limit, corner-speed emergence, G stress
- [ ] **FLT-05** `FlightController` applying the state through `LinearVelocity` and `AngularVelocity`
- [ ] **FLT-06** Debug tuning panel with export
- [ ] **FLT-07** Wave drag and supercruise behaviour
- [ ] **INP-01** InputController with keyboard and mouse, Direct scheme
- [ ] **INP-02** Instructor plus Mouse Aim scheme, with the aim reticle on the HUD
- [ ] **CAM-01** Cockpit camera with free look and G head-shake. Debug chase camera
- [ ] **CAM-02** Greybox analogue cockpit kit with 4 live gauges
- [ ] **CAM-05** G-LOC, grey-out and red-out effects
- [ ] **HUD-01** Core flight HUD: speed, altitude, G, throttle, heading, flight path marker, reticle
- [ ] **AIR-01** Spawn/despawn, network ownership, attributes and the no-character setup
- [ ] **FX-01** Afterburner, contrails, vapour (own jet + others)
- [ ] **AUD-01** Engine and wind (cockpit and external)
- [ ] **TST-03** Playtest template and log folder

## Phase 2: Guns and damage

- [ ] **ACD-04** Weapon schema and registry. Guns for F-5E/MiG-21
- [ ] **FLT-10** Damage modifiers hook (engine, control surfaces)
- [ ] **CAM-03** Snap views, zoom, FOV setting
- [ ] **HUD-02** Gun pipper (simple) and hit markers, kill feed
- [ ] **AIR-02** Crash detection (terrain and mid-air collisions)
- [ ] **AIR-03** Death flow, kill cam trigger, respawn hook for modes
- [ ] **AIR-05** Player leaving mid-flight cleans up correctly, credits kills properly
- [ ] **GUN-01** `Ballistics` module with tests (lead solution accuracy)
- [ ] **GUN-02** Client local tracers (pooled `Beam`s or parts) from seeded spread
- [ ] **GUN-03** Server bullet simulation with rewind and ray–OBB hits
- [ ] **GUN-04** HistoryService ring buffers
- [ ] **GUN-05** Remote fire FX on other clients
- [ ] **GUN-06** Simple pipper (Tier I)
- [ ] **GUN-08** Ammo, spool-up, overheat
- [ ] **DMG-01** Component health, damage application and destruction
- [ ] **DMG-02** Partial damage effects through flight model modifiers
- [ ] **DMG-04** Kill and assist credit, kill feed events
- [ ] **FX-02** Gun, tracer, impact, explosion effects
- [ ] **AUD-02** Guns, hits, explosions
- [ ] **TST-02** Network simulation test checklist
- [ ] **PRF-01** Profiling labels in hot paths

## Phase 3: Missiles, sensors and countermeasures

- [ ] **NET-03** `Pack` helpers for missile state and history snapshots, with round-trip unit tests
- [ ] **ACD-05** Missile data for all Tier I–III missiles
- [ ] **CAM-04** Padlock
- [ ] **HUD-03** Target box, seeker circle, launch zone, missile warning
- [ ] **DMG-03** Fire and smoke
- [ ] **MSL-01** `Guidance` module: PN, gimbal, energy (pure, tested)
- [ ] **MSL-02** MissileService simulation loop and detonation
- [ ] **MSL-03** Fire request validation including server-side lock timing
- [ ] **MSL-04** Packed unreliable replication plus client interpolation
- [ ] **MSL-05** IR rear-aspect and all-aspect seekers
- [ ] **MSL-06** SARH guidance with lock dependency
- [ ] **SNS-01** Visual spotting with LOS and HUD markers
- [ ] **SNS-02** Radar cone detection on the client and the radar MFD page
- [ ] **SNS-03** Server-validated lock state machine with re-checks
- [ ] **SNS-04** Notch filtering
- [ ] **SNS-05** RWR server events plus display and tones
- [ ] **SNS-06** `Signature` module (IR and RCS)
- [ ] **CMS-01** Deploy flow, counts, FX
- [ ] **CMS-02** Flare heat sources and the decoy decision
- [ ] **CMS-03** Chaff decoy for radar missiles and lock breaking
- [ ] **FX-03** Missile, flare, chaff effects
- [ ] **FX-04** Damage smoke and fire
- [ ] **AUD-03** Seeker tone, RWR, missile warning

## Phase 4: Match loop MVP

- [ ] **INP-03** Gamepad support
- [ ] **INP-04** Touch controls (virtual stick, buttons, auto-throttle, aim-assist)
- [ ] **CAM-06** Kill cam and spectate
- [ ] **HUD-04** Warnings system with priorities (stall, terrain, fuel, bounds)
- [ ] **HUD-06** Mobile scaling pass
- [ ] **AIR-04** Out-of-bounds and ceiling handling
- [ ] **SEC-01** Movement checks with strike system and corrections
- [ ] **SEC-02** Exploit test suite: a test-only client script that tries speed hacks, teleports and remote spam, used to check the defences
- [ ] **SEC-03** Logging pipeline for violations (analytics + server-side log)
- [ ] **MCH-01** MatchService state machine and Mode interface
- [ ] **MCH-02** Free Flight and Dogfight FFA
- [ ] **MCH-03** Configurable respawn rules (both types)
- [ ] **MCH-04** Scoreboard and results screen
- [ ] **AI-01** Server-side flight for AI jets (shared FlightModel + Instructor)
- [ ] **AI-02** Patrol/Engage/Attack with gun use
- [ ] **AI-03** Defend state (missile defence, flares, break turn)
- [ ] **MAP-02** "Strait" blockout: terrain shape, airbases, spawns
- [ ] **TUT-01** Lesson framework (steps, prompts, highlights, conditions)
- [ ] **TUT-02** Lessons 1–3
- [ ] **ANL-01** Telemetry wrapper
- [ ] **PRF-02** Full-match stress test (bots fill to 24 jets)

## Phase 5: Progression and saving

- [ ] **MSL-07** ARH with midcourse and active phase
- [ ] **AI-04** Missile use, Extend state
- [ ] **AI-05** Difficulty profiles
- [ ] **DAT-01** DataService with ProfileStore, environment-based names, kick on failure
- [ ] **DAT-02** Schema v1, migrations framework and tests
- [ ] **DAT-03** Client replica with delta updates
- [ ] **DAT-05** Data reset and inspection admin commands (test environment)
- [ ] **PRG-01** Event recording in matches and reward calculation
- [ ] **PRG-02** Research, purchase and lineup rules with server validation
- [ ] **PRG-03** Pilot level curve and level rewards
- [ ] **PRG-04** Upgrade modules feeding flight/loadout modifiers
- [ ] **PRG-05** Anti-farming rules
- [ ] **PRG-06** Economy simulation and pacing check
- [ ] **UI-01** React setup, theme, router, base components
- [ ] **UI-02** Hangar with 3D preview and lineup
- [ ] **UI-03** Tech tree screen
- [ ] **UI-04** Aircraft detail: modules, loadout, camo
- [ ] **UI-06** Results screen with reward animations
- [ ] **MMK-01** In-server BR matching (single place)
- [ ] **SET-01** Settings data, controller, change signal
- [ ] **ANL-03** Economy events
- [ ] **OPS-02** AdminService and commands
- [ ] **REL-02** Test universe setup (separate experience, test products)

## Phase 6: Content and polish for a soft launch

- [ ] **ACD-06** Stat blocks for the 15 launch jets (balancing spreadsheet → data modules)
- [ ] **ACD-07** Final art models for the 15 launch jets (Blender → MeshParts; see §19.4 pipeline)
- [ ] **FLT-08** Variable geometry (F-14)
- [ ] **INP-05** Rebinding UI and persisted bindings
- [ ] **CAM-07** Final art for all four cockpit kits, plus overrides for the launch jets
- [ ] **CAM-08** Third-person chase as a player-facing option (if playtests call for it)
- [ ] **HUD-05** Era variants (analogue vs glass symbology)
- [ ] **GUN-07** LCOS and EEGS sights
- [ ] **DMG-05** Pilot damage diagram on the HUD
- [ ] **MSL-08** Loft profile
- [ ] **MSL-09** Advanced IR (high off-boresight, flare resistance)
- [ ] **SNS-07** TWS
- [ ] **CMS-04** Auto-dispense programmes (Tier V+, for example "2 flares every 0.5 s")
- [ ] **MCH-05** Team Deathmatch, team balancing
- [ ] **MCH-06** Air Superiority with zones
- [ ] **MAP-03** "Strait" final: materials, props, lighting, horizon skirt
- [ ] **MAP-04** Streaming and fog tuning for mobile
- [ ] **FX-05** Quality settings and pooling audit
- [ ] **AUD-04** Warnings and radio barks with subtitles
- [ ] **AUD-05** Music and UI sounds, sound groups and mixer settings
- [ ] **PRG-07** Aircraft mastery stars and rewards
- [ ] **UI-05** Mode select and queue UI
- [ ] **UI-09** Gamepad and touch passes on every screen
- [ ] **MMK-02** Lobby and battle place split, place-specific boot (server knows its role from a place attribute)
- [ ] **MMK-03** MemoryStore queues, lease-based matchmaker, match records
- [ ] **MMK-04** Reserved server teleport flow and return to lobby, with retries
- [ ] **MMK-06** Matchmaking telemetry: wait times, match quality (BR spread)
- [ ] **LIV-01** Daily/weekly challenges with rerolls
- [ ] **LIV-02** Achievements and Roblox badges
- [ ] **LIV-03** Login streak rewards
- [ ] **TUT-03** Lessons 4–6
- [ ] **TUT-04** First-session flow and funnel analytics
- [ ] **SET-02** Settings UI
- [ ] **SET-03** Accessibility options
- [ ] **ANL-02** Onboarding funnel
- [ ] **ANL-04** Combat and balance events
- [ ] **OPS-01** ConfigService with live overrides
- [ ] **CMP-01** Text filtering service for callsigns and squadron names
- [ ] **CMP-03** Report-cheater flow
- [ ] **TST-04** Headless unit tests in CI (if a suitable runner is available)
- [ ] **PRF-03** Mobile performance pass
- [ ] **REL-03** Version module, changelog, tagging process
- [ ] **REL-04** Release checklist and rollback drill

## Phase 7: Monetisation

- [ ] **UI-07** Shop screen
- [ ] **UI-08** Season pass and challenges screens
- [ ] **LIV-04** Season framework and pass progression
- [ ] **SHP-01** Product config (test + prod IDs) and ShopService skeleton
- [ ] **SHP-02** ProcessReceipt with idempotency and failure safety
- [ ] **SHP-03** Game pass ownership checks and benefits
- [ ] **SHP-04** Wings transactions and cosmetics granting
- [ ] **SHP-05** Weekly rotation, bundles, first-purchase offer
- [ ] **SHP-06** Premium jet validator and blocked-category test
- [ ] **SHP-07** Cosmetics system: camos, trails, kill markers, nose art, HUD themes applied to jets
- [ ] **CMP-02** Policy checks wrapper

## Phase 8: Launch and live ops

- [ ] **ACD-08** Remaining tiers (V–VIII) data and models
- [ ] **FLT-09** Thrust vectoring behaviour
- [ ] **SNS-08** Data link
- [ ] **SNS-09** Stealth RCS and weapon bay effect
- [ ] **MCH-07** Strike Escort
- [ ] **MCH-08** PvE wave missions
- [ ] **MCH-09** Ranked Duels with Elo
- [ ] **MCH-10** BVR Battles
- [ ] **AI-06** AI bombers and escort formations (Strike Escort, PvE)
- [ ] **MAP-05** Additional maps (Desert Range, Arctic Fjord, Islands)
- [ ] **DAT-04** Leaderboard stores
- [ ] **MMK-05** Parties
- [ ] **LIV-05** Leaderboards
- [ ] **LIV-06** Squadrons
- [ ] **LIV-07** Test Pilot challenge chain and the Tempest unlock
- [ ] **ANL-05** Dashboards in the Creator Dashboard (custom events) and the weekly balance report process
- [ ] **OPS-03** Event flags (double XP etc.)
- [ ] **OPS-04** Message of the day and announcements
- [ ] **CMP-04** Pre-launch compliance checklist (names, assets, maturity questionnaire, product descriptions)
- [ ] **REL-05** (Optional) Open Cloud publishing from CI
