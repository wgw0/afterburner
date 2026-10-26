# Afterburner: Progress Tracker

Every task from [DEVELOPMENT.md](DEVELOPMENT.md), by phase. A box is ticked only when the task's acceptance test has **actually been run and passed** (Definition of Done, DEVELOPMENT.md §0.8). The evidence column says how it was checked.

| Phase | Done | Status |
|---|---|---|
| 0 Foundation | 9 / 9 | ✅ Complete |
| 1 Flight model prototype | 20 / 21 | ✅ Signed off (ACD-03 CI half carried over) |
| 2 Guns and damage | 21 / 21 | ✅ Signed off |
| 3–8 | 0 / 141 | ⚪ Not started |

---

## Phase 0: Foundation

| | Task | Evidence |
|:---:|---|---|
| ✅ | **CORE-01** Folder tree and server/client `Main` boot loaders with Init/Start ordering and per-service error reporting | Play test: output shows `Service started: DiagnosticsService` → `Server ready` → `Controller started: DiagnosticsController` → `Client ready`, with no errors. `Boot.spec`: Priority ordering, a yielding `Init` is refused, a failing `Init` names the module. |
| ✅ | **CORE-02** StyLua, Selene, Wally in `rokit.toml` with config files | `rokit install` gives Rojo 7.7.1, StyLua 2.6.0, Selene 0.32.0, Wally 0.3.2. `stylua --check` and `selene` both clean (0 errors, 0 warnings). |
| ✅ | **CORE-03** GitHub Actions CI | First run on GitHub passed: [run 40242794421](https://github.com/wgw0/afterburner/actions/runs/40242794421) (StyLua check, Selene, Rojo build). |
| ✅ | **CORE-04** Util: Signal, Trove, Spring, RingBuffer, Pool, Validate, with unit tests | `Util.spec` and `Validate.spec` pass in Studio. |
| ✅ | **NET-01** `Definitions` format plus `Net` wrapper with type validation | Play test: the client fired a string, NaN, `1.5`, three arguments, and no arguments at an integer remote. All 5 were dropped with the reason logged. A bad RemoteFunction argument returned `nil` without erroring. A valid echo round trip took 91–123 ms in Studio. |
| ✅ | **NET-02** Per-remote token-bucket rate limiting plus a dropped-call counter | Play test: 50 pings in one frame against a 5-call burst gave exactly the burst through and the rest dropped. Logging is summarised every 5 s (`x46`), so spam can't flood the output. |
| ✅ | **MAP-01** Greybox test map: flat area, towers, runway | `Workspace.TestRange` (60 parts): 1,800-stud runway with markings, 6 slalom pylons, height towers at 100/250/500/1000 studs. Saved in `Afterburner.rbxl`. |
| ✅ | **TST-01** Test runner and first specs | `require(game.ServerStorage.Tests.TestRunner).run()` → **28 passed, 0 failed**. A deliberately failing spec was correctly reported as a failure, with file and line. |
| ✅ | **REL-01** CI workflow | Same as CORE-03. Runs on every push and PR. |

**Also done in Phase 0:**
- [x] Rojo CLI and Studio plugin installed. `rojo serve` syncs every file into the open place (checked instance by instance).
- [x] `Shared.Config.Environment`: Studio counts as `Test`, live servers default to `Prod`.

**Known noise (not ours):** Studio prints `ContentId: rbxassetid://203785492 failed…` on play. That asset isn't referenced anywhere in the place or code, so it comes from Roblox's own default content.

---

## Phase 1: Flight model prototype

**Signed off by Will on 2026-10-26:** "feels good". Fine-tuning can wait for later. Exit test: flying is fun with no weapons, and the two jets feel different. See the [playtest log](playtests/2026-10-25-phase1-first-flight.md).

| | Task | Evidence |
|:---:|---|---|
| ✅ | **ACD-01** Airframe schema, registry and startup validator | `AircraftData.spec`: valid airframes load frozen; missing/out-of-range/NaN/bad-enum fields are named; a broken module stops loading with "Broken: missing WingArea" and doesn't blame the good one. |
| ✅ | **ACD-02** Greybox models for F-5E and MiG-21 following the model contract | `tools/GreyboxBuilder` builds both into `ReplicatedStorage.Assets.Aircraft` (saved in the place). `Model.spec`: both pass the contract. Flown hands-on. |
| 🟡 | **ACD-03** Model-contract validator script (Studio command plus CI check against the built place) | Studio half done: `AircraftModelContract.validate`, run at server boot (AircraftService refuses to start on a bad model) and in `Model.spec`, which catches a deliberately broken model. **CI half carried over:** CI only builds the code, not the place file, so it can't see models yet. Needs a place-reading tool (e.g. Lune) in CI. |
| ✅ | **FLT-01** `Atmosphere`, `Units` and `Scale` modules with tests | `Units.spec`: conversions round-trip, distances agree with velocity scaling, ceiling ≈ 48,000 ft; atmosphere values at sea level and the tropopause. |
| ✅ | **FLT-02** `FlightModel.step`, sub-stepping, determinism | `FlightModel.spec`: level flight holds altitude within 2% over 10 s; deterministic; stable and consistent at 20 vs 60 FPS; input state never mutated. |
| ✅ | **FLT-03** Stall model and buffet flag | Lift falls past critical AoA; slow pull with protections off stalls; the AoA limiter keeps it out of the stall. |
| ✅ | **FLT-04** G limit, corner-speed emergence, G stress | F-5E corner ≈ 348 kt at sea level; holds 7.3 G at its limit; MiG bleeds more in hard turns and the F-5E out-sustains it (11.7 vs 10.8 °/s); G stress builds above 6.5 G and decays. |
| ✅ | **FLT-05** `FlightController` driving `LinearVelocity`/`AngularVelocity` | Play test: client owns the jet (ReceiveAge 0); speed and altitude stable hands-off; flown hands-on in both jets. |
| ✅ | **FLT-06** Debug tuning panel with export | Will tuned roll/pitch/yaw live with the P panel; those values are now the defaults. |
| ✅ | **FLT-07** Wave drag and supercruise behaviour | F-5E stays below Mach 1 on dry thrust at 9 km; MiG-21 goes supersonic in afterburner; wave drag peaks near Mach 1. (Acceleration through Mach 1 is slow; logged for tuning.) |
| ✅ | **INP-01** InputController, keyboard and mouse, Direct scheme | Keys and Direct mode (M) wired and flown; throttle/afterburner hold logic in use. |
| ✅ | **INP-02** Instructor plus Mouse Aim with HUD reticle | `Instructor.spec`: correct roll/pitch direction, no inverted roll for small low targets, G cap unless overridden, settles on 90° and behind-above targets without wobble, holds altitude 30 s. Aim reticle confirmed at screen centre. |
| ✅ | **CAM-01** Cockpit camera with free look and G head-shake; chase camera | Flown hands-on; chase camera reworked to keep the jet centred, with dynamic FOV. |
| ✅ | **CAM-02** Greybox analogue cockpit with 4 live gauges | Airspeed, altimeter, G, RPM live; dials fixed to round and unobstructed after playtest feedback. |
| ✅ | **CAM-05** G-LOC, grey-out and red-out | G stress model unit-tested; grey-out, blackout (with level-hold autopilot) and red-out effects implemented. *Lightest-tested item: the effects weren't specifically checked hands-on; worth a look in Phase 2.* |
| ✅ | **HUD-01** Core flight HUD | Speed, altitude, G, throttle, heading, flight path marker, reticle, warnings. Reticle offset bug found and fixed. |
| ✅ | **HUD-07** HUD visual design pass | Collimated HUD box with tapes, conformal pitch ladder and FPM; ladder clipping bug found in playtest and fixed. |
| ✅ | **AIR-01** Spawn/despawn, network ownership, attributes, no characters | Spawn menu → jet appears, owned by the pilot; respawn and crash → despawn work; runway is the idle streaming focus. |
| ✅ | **FX-01** Afterburner, contrails, vapour | Afterburner flame and light, wingtip vapour above 5 G, contrails above 7 km, driven by telemetry for other jets. *Contrails and other players' effects not yet seen in a multiplayer test.* |
| ✅ | **AUD-01** Engine and wind | Engine pitch follows throttle, muffled in the cockpit; wind rises with speed; volumes cut twice after playtest feedback. Placeholder Creator Store sounds, to review before launch. |
| ✅ | **TST-03** Playtest template and log folder | `docs/playtests/TEMPLATE.md` and the first log with 10 findings. |

**Carried over:** ACD-03 CI half (needs a place-reading tool in CI).

**Also done in Phase 1:** placeholder terrain (`tools/TerrainBuilder`, 70% leaner after `trim()`), streaming tuned (client ready in ~1 s), HUD-07 added to the plan, integrity checks (CI repo checks, module/definition/place specs, startup smoke test). Tests: 49 → 115.

**Tuning backlog (for later):** MiG-21 transonic acceleration; overall roll/pitch feel per jet; sound assets; terrain is a placeholder until MAP-02.

## Phase 2: Guns and damage

**Signed off by Will on 2026-10-26:** "guns feel good". Exit test: a 1v1 guns fight is tense and the winner feels skill-based (tested solo against target drones; real 1v1 between two players still to come).

| | Task | Evidence |
|:---:|---|---|
| ✅ | **ACD-04** Weapon schema and registry; guns for F-5E/MiG-21 | `WeaponData` (2× M39A2 20 mm, GSh-23L 23 mm), validated on load; `Weapons.spec`: every airframe's gun exists, bad weapons are named. AircraftService refuses to boot with an unknown gun. |
| ✅ | **FLT-10** Damage modifiers hook | `FlightModel` takes yaw authority and roll bias; `FlightModel.spec`: a damaged left wing rolls the jet left hands-off, a dead engine gives no thrust. Drones visibly fly worse when hit. |
| ✅ | **CAM-03** Snap views, zoom, FOV | Left Alt + arrows snap left/right/back/up (arrows don't fly the jet while Alt is held); Z zoom; dynamic FOV from Phase 1. FOV *setting* UI comes with SET-02. |
| ✅ | **HUD-02** Gun pipper, hit markers, kill feed | Lead indicator (Ballistics lead solution) in the HUD box, target markers with name/range, ✕ hit marker, ammo/heat/jam readout, kill feed (your lines in amber). |
| ✅ | **AIR-02** Crash detection (terrain and mid-air) | Server checks each jet's path every tick: a drone pointed at the ground was destroyed in 0.45 s. A fake `ReportCrash` while flying at 1,620 studs was ignored. Mid-air collisions despawn both jets. |
| ✅ | **AIR-03** Death flow, kill cam trigger, respawn hook | Explosion, 3.5 s death camera orbiting the wreck, then the menu with "Shot down by X" / "You crashed"; `AircraftService.JetDestroyed` / `CombatService.Kill` signals for match modes. |
| ✅ | **AIR-05** Leaving mid-flight cleans up and credits kills | `DamageModel.spec`: leaving or respawning while damaged still credits the attacker. *Not yet tested with two real players.* |
| ✅ | **GUN-01** `Ballistics` with tests | Seeded spread inside the cone, drop and drag, lead solution hits a crossing target within 3 m, segment-vs-box entry point. |
| ✅ | **GUN-02** Client local tracers from seeded spread | Pooled neon tracers (every 2nd round), dust/splash where they hit the ground. Confirmed hands-on. |
| ✅ | **GUN-03** Server bullet simulation with rewind and ray–OBB hits | Drone shot down in 1.07 s (23 hits); 1.56 s (28 hits) under 150 ms simulated lag. Rewind capped at 250 ms. |
| ✅ | **GUN-04** HistoryService ring buffers | `PoseHistory` interpolation and clamping tested; 1.5 s of poses per jet. |
| ✅ | **GUN-05** Remote fire FX on other clients | `GunFireFx` starts/stops seeded tracer streams for other jets. *Two-client visual check still to do.* |
| ✅ | **GUN-06** Simple pipper (Tier I) | Lead indicator; put the gun cross on it. |
| ✅ | **GUN-08** Ammo, overheat | Server-side ammo, heat per shot, jam at full heat and clears at 40%; the HUD mirrors it via attributes. (Spool-up isn't needed for these guns; it arrives with rotary cannons.) |
| ✅ | **DMG-01** Component health, damage, destruction | `DamageModel.spec`; hits on destroyed parts spill into the fuselage (found in testing: tail shots from dead six could never kill). |
| ✅ | **DMG-02** Partial damage effects | Engine → thrust, tail → pitch/yaw authority, wings → lift and roll bias; applied on the pilot's client from `DamageState`. |
| ✅ | **DMG-04** Kill and assist credit, kill feed | Last damager within 15 s gets the kill, ≥25% damage assists, forced-crash credit within 30 s; kill feed verified in play. |
| ✅ | **FX-02** Gun, tracer, impact, explosion effects | Muzzle flash, tracers, sparks on hits, dust/splash, explosion with fire, smoke, sparks and flash (built-in textures). |
| ✅ | **AUD-02** Guns, hits, explosions | Gun loop (yours non-positional, others 3D), hit tink, damage thud, explosion; Weapons sound group at 0.2. Placeholder Creator Store sounds. |
| ✅ | **TST-02** Network simulation checklist | [docs/testing/NETWORK.md](testing/NETWORK.md) with results. Studio's simulated lag doesn't show up in `GetNetworkPing`, so the compensation amount needs a real server (REL-02). |
| ✅ | **PRF-01** Profiling labels in hot paths | `FlightController.step`, `CombatService.tick`, `AircraftService.collisions`, `WeaponController.tracers`. |

**Also done in Phase 2:** target drones (DroneService, test env only, the base for AI-01), cockpit panel now sits on the fuselage (playtest fix), AI-flown jets supported by AircraftService. Tests: 115 → 157.

**Carried over / to check with two players:** a real 1v1, other players' tracers and effects, leaving mid-fight.

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
