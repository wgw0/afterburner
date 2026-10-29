# Afterburner: progress tracker

Every task from [DEVELOPMENT.md](DEVELOPMENT.md), by phase. A task is marked done only when its acceptance test has actually been run and passed (Definition of Done, DEVELOPMENT.md §0.8). The evidence column says how it was checked.

| Phase | Done | Status |
|---|---|---|
| 0 Foundation | 9 / 9 | Complete |
| 1 Flight model prototype | 21 / 21 | Signed off |
| 2 Guns and damage | 21 / 21 | Signed off |
| 3 Missiles, sensors and countermeasures | 23 / 23 | Signed off |
| 4 Match loop MVP | 21 / 21 | Signed off |
| 5 Progression and saving | 23 / 23 | Signed off |
| 6 Content and polish for a soft launch | 5 / 43 | In progress: content done, launch plumbing not started (see below) |
| 7 Monetisation | 0 / 11 | Not started |
| 8 Launch and live ops | 1 / 20 | ACD-08 done early; three more partly done |

---

## Phase 0: Foundation

| | Task | Evidence |
|:---:|---|---|
| Done | **CORE-01** Folder tree and server/client `Main` boot loaders with Init/Start ordering and per-service error reporting | Play test: output shows `Service started: DiagnosticsService` → `Server ready` → `Controller started: DiagnosticsController` → `Client ready`, with no errors. `Boot.spec`: Priority ordering, a yielding `Init` is refused, a failing `Init` names the module. |
| Done | **CORE-02** StyLua, Selene, Wally in `rokit.toml` with config files | `rokit install` gives Rojo 7.7.1, StyLua 2.6.0, Selene 0.32.0, Wally 0.3.2. `stylua --check` and `selene` both clean (0 errors, 0 warnings). |
| Done | **CORE-03** GitHub Actions CI | First run on GitHub passed: [run 40242794421](https://github.com/wgw0/afterburner/actions/runs/40242794421) (StyLua check, Selene, Rojo build). |
| Done | **CORE-04** Util: Signal, Trove, Spring, RingBuffer, Pool, Validate, with unit tests | `Util.spec` and `Validate.spec` pass in Studio. |
| Done | **NET-01** `Definitions` format plus `Net` wrapper with type validation | Play test: the client fired a string, NaN, `1.5`, three arguments, and no arguments at an integer remote. All 5 were dropped with the reason logged. A bad RemoteFunction argument returned `nil` without erroring. A valid echo round trip took 91–123 ms in Studio. |
| Done | **NET-02** Per-remote token-bucket rate limiting plus a dropped-call counter | Play test: 50 pings in one frame against a 5-call burst gave exactly the burst through and the rest dropped. Logging is summarised every 5 s (`x46`), so spam can't flood the output. |
| Done | **MAP-01** Greybox test map: flat area, towers, runway | `Workspace.TestRange` (60 parts): 1,800-stud runway with markings, 6 slalom pylons, height towers at 100/250/500/1000 studs. Saved in `Afterburner.rbxl`. |
| Done | **TST-01** Test runner and first specs | `require(game.ServerStorage.Tests.TestRunner).run()` → **28 passed, 0 failed**. A deliberately failing spec was correctly reported as a failure, with file and line. |
| Done | **REL-01** CI workflow | Same as CORE-03. Runs on every push and PR. |

**Also done in Phase 0:**
- [x] Rojo CLI and Studio plugin installed. `rojo serve` syncs every file into the open place (checked instance by instance).
- [x] `Shared.Config.Environment`: Studio counts as `Test`, live servers default to `Prod`.

**Known noise (not ours):** Studio prints `ContentId: rbxassetid://203785492 failed…` on play. That asset isn't referenced anywhere in the place or code, so it comes from Roblox's own default content.

---

## Phase 1: Flight model prototype

**Signed off by Will on 2026-10-26:** "feels good". Fine-tuning can wait for later. Exit test: flying is fun with no weapons, and the two jets feel different. See the [playtest log](playtests/2026-10-25-phase1-first-flight.md).

| | Task | Evidence |
|:---:|---|---|
| Done | **ACD-01** Airframe schema, registry and startup validator | `AircraftData.spec`: valid airframes load frozen; missing/out-of-range/NaN/bad-enum fields are named; a broken module stops loading with "Broken: missing WingArea" and doesn't blame the good one. |
| Done | **ACD-02** Greybox models for F-5E and MiG-21 following the model contract | `tools/GreyboxBuilder` builds both into `ReplicatedStorage.Assets.Aircraft` (saved in the place). `Model.spec`: both pass the contract. Flown hands-on. |
| Done | **ACD-03** Model-contract validator script (Studio command plus CI check against the built place) | Studio: `AircraftModelContract.validate`, run at server boot (AircraftService refuses to start on a bad model) and in `Model.spec`, which catches a deliberately broken model. CI (finished before Phase 5): `scripts/validate-models.luau` opens the committed `Afterburner.rbxl` with Lune and runs the same validator on every model, and checks every airframe has one. "Model contract OK: 2 models checked, 2 airframes covered"; a broken copy (missing `CockpitEye`, collidable canopy, MiG model deleted) fails with all three named. |
| Done | **FLT-01** `Atmosphere`, `Units` and `Scale` modules with tests | `Units.spec`: conversions round-trip, distances agree with velocity scaling, ceiling ≈ 48,000 ft; atmosphere values at sea level and the tropopause. |
| Done | **FLT-02** `FlightModel.step`, sub-stepping, determinism | `FlightModel.spec`: level flight holds altitude within 2% over 10 s; deterministic; stable and consistent at 20 vs 60 FPS; input state never mutated. |
| Done | **FLT-03** Stall model and buffet flag | Lift falls past critical AoA; slow pull with protections off stalls; the AoA limiter keeps it out of the stall. |
| Done | **FLT-04** G limit, corner-speed emergence, G stress | F-5E corner ≈ 348 kt at sea level; holds 7.3 G at its limit; MiG bleeds more in hard turns and the F-5E out-sustains it (11.7 vs 10.8 °/s); G stress builds above 6.5 G and decays. |
| Done | **FLT-05** `FlightController` driving `LinearVelocity`/`AngularVelocity` | Play test: client owns the jet (ReceiveAge 0); speed and altitude stable hands-off; flown hands-on in both jets. |
| Done | **FLT-06** Debug tuning panel with export | Will tuned roll/pitch/yaw live with the P panel; those values are now the defaults. |
| Done | **FLT-07** Wave drag and supercruise behaviour | F-5E stays below Mach 1 on dry thrust at 9 km; MiG-21 goes supersonic in afterburner; wave drag peaks near Mach 1. (Acceleration through Mach 1 is slow; logged for tuning.) |
| Done | **INP-01** InputController, keyboard and mouse, Direct scheme | Keys and Direct mode (M) wired and flown; throttle/afterburner hold logic in use. |
| Done | **INP-02** Instructor plus Mouse Aim with HUD reticle | `Instructor.spec`: correct roll/pitch direction, no inverted roll for small low targets, G cap unless overridden, settles on 90° and behind-above targets without wobble, holds altitude 30 s. Aim reticle confirmed at screen centre. |
| Done | **CAM-01** Cockpit camera with free look and G head-shake; chase camera | Flown hands-on; chase camera reworked to keep the jet centred, with dynamic FOV. |
| Done | **CAM-02** Greybox analogue cockpit with 4 live gauges | Airspeed, altimeter, G, RPM live; dials fixed to round and unobstructed after playtest feedback. *Phase 6: the panel finds the cockpit sill from the canopy glass, so it sits below the eye in the new F-5E model.* |
| Done | **CAM-05** G-LOC, grey-out and red-out | G stress model unit-tested; grey-out, blackout (with level-hold autopilot) and red-out effects implemented. *Lightest-tested item: the effects weren't specifically checked hands-on; worth a look in Phase 2.* |
| Done | **HUD-01** Core flight HUD | Speed, altitude, G, throttle, heading, flight path marker, reticle, warnings. Reticle offset bug found and fixed. |
| Done | **HUD-07** HUD visual design pass | Collimated HUD box with tapes, conformal pitch ladder and FPM; ladder clipping bug found in playtest and fixed. |
| Done | **AIR-01** Spawn/despawn, network ownership, attributes, no characters | Spawn menu → jet appears, owned by the pilot; respawn and crash → despawn work; runway is the idle streaming focus. |
| Done | **FX-01** Afterburner, contrails, vapour | Afterburner flame and light, wingtip vapour above 5 G, contrails above 7 km, driven by telemetry for other jets. *Contrails and other players' effects not yet seen in a multiplayer test.* |
| Done | **AUD-01** Engine and wind | Engine pitch follows throttle, muffled in the cockpit; wind rises with speed; volumes cut twice after playtest feedback. Placeholder Creator Store sounds, to review before launch. |
| Done | **TST-03** Playtest template and log folder | `docs/playtests/TEMPLATE.md` and the first log with 10 findings. |

**Also done in Phase 1:** placeholder terrain (`tools/TerrainBuilder`, 70% leaner after `trim()`), streaming tuned (client ready in ~1 s), HUD-07 added to the plan, integrity checks (CI repo checks, module/definition/place specs, startup smoke test). Tests: 49 → 115.

**Tuning backlog (for later):** MiG-21 transonic acceleration; overall roll/pitch feel per jet; sound assets. (The placeholder terrain was replaced by the Strait blockout in Phase 4.)

## Phase 2: Guns and damage

**Signed off by Will on 2026-10-26:** "guns feel good". Exit test: a 1v1 guns fight is tense and the winner feels skill-based (tested solo against target drones; real 1v1 between two players still to come).

| | Task | Evidence |
|:---:|---|---|
| Done | **ACD-04** Weapon schema and registry; guns for F-5E/MiG-21 | `WeaponData` (2× M39A2 20 mm, GSh-23L 23 mm), validated on load; `Weapons.spec`: every airframe's gun exists, bad weapons are named. AircraftService refuses to boot with an unknown gun. |
| Done | **FLT-10** Damage modifiers hook | `FlightModel` takes yaw authority and roll bias; `FlightModel.spec`: a damaged left wing rolls the jet left hands-off, a dead engine gives no thrust. Drones visibly fly worse when hit. |
| Done | **CAM-03** Snap views, zoom, FOV | Left Alt + arrows snap left/right/back/up (arrows don't fly the jet while Alt is held); Z zoom; dynamic FOV from Phase 1. FOV *setting* UI comes with SET-02. |
| Done | **HUD-02** Gun pipper, hit markers, kill feed | Lead indicator (Ballistics lead solution) in the HUD box, target markers with name/range, ✕ hit marker, ammo/heat/jam readout, kill feed (your lines in amber). |
| Done | **AIR-02** Crash detection (terrain and mid-air) | Server checks each jet's path every tick: a drone pointed at the ground was destroyed in 0.45 s. A fake `ReportCrash` while flying at 1,620 studs was ignored. Mid-air collisions despawn both jets. *Phase 6: the paths of the nose, wingtips and tail are checked too, and the hull touching the map counts as a crash (a wingtip clipping a hill, or a shallow belly hit, had gone unnoticed).* |
| Done | **AIR-03** Death flow, kill cam trigger, respawn hook | Explosion, 3.5 s death camera orbiting the wreck, then the menu with "Shot down by X" / "You crashed"; `AircraftService.JetDestroyed` / `CombatService.Kill` signals for match modes. |
| Done | **AIR-05** Leaving mid-flight cleans up and credits kills | `DamageModel.spec`: leaving or respawning while damaged still credits the attacker. *Not yet tested with two real players.* |
| Done | **GUN-01** `Ballistics` with tests | Seeded spread inside the cone, drop and drag, lead solution hits a crossing target within 3 m, segment-vs-box entry point. |
| Done | **GUN-02** Client local tracers from seeded spread | Pooled neon tracers (every 2nd round), dust/splash where they hit the ground. Confirmed hands-on. |
| Done | **GUN-03** Server bullet simulation with rewind and ray–OBB hits | Drone shot down in 1.07 s (23 hits); 1.56 s (28 hits) under 150 ms simulated lag. Rewind capped at 250 ms. |
| Done | **GUN-04** HistoryService ring buffers | `PoseHistory` interpolation and clamping tested; 1.5 s of poses per jet. |
| Done | **GUN-05** Remote fire FX on other clients | `GunFireFx` starts/stops seeded tracer streams for other jets. *Two-client visual check still to do.* |
| Done | **GUN-06** Simple pipper (Tier I) | Lead indicator; put the gun cross on it. |
| Done | **GUN-08** Ammo, overheat | Server-side ammo, heat per shot, jam at full heat and clears at 40%; the HUD mirrors it via attributes. (Spool-up isn't needed for these guns; it arrives with rotary cannons.) |
| Done | **DMG-01** Component health, damage, destruction | `DamageModel.spec`; hits on destroyed parts spill into the fuselage (found in testing: tail shots from dead six could never kill). |
| Done | **DMG-02** Partial damage effects | Engine → thrust, tail → pitch/yaw authority, wings → lift and roll bias; applied on the pilot's client from `DamageState`. |
| Done | **DMG-04** Kill and assist credit, kill feed | Last damager within 15 s gets the kill, ≥25% damage assists, forced-crash credit within 30 s; kill feed verified in play. |
| Done | **FX-02** Gun, tracer, impact, explosion effects | Muzzle flash, tracers, sparks on hits, dust/splash, explosion with fire, smoke, sparks and flash (built-in textures). |
| Done | **AUD-02** Guns, hits, explosions | Gun loop (yours non-positional, others 3D), hit tink, damage thud, explosion; Weapons sound group at 0.2. Placeholder Creator Store sounds. |
| Done | **TST-02** Network simulation checklist | [docs/testing/NETWORK.md](testing/NETWORK.md) with results. Studio's simulated lag doesn't show up in `GetNetworkPing`, so the compensation amount needs a real server (REL-02). |
| Done | **PRF-01** Profiling labels in hot paths | `FlightController.step`, `CombatService.tick`, `AircraftService.collisions`, `WeaponController.tracers`. |

**Also done in Phase 2:** target drones (DroneService, test env only, the base for AI-01), cockpit panel now sits on the fuselage (playtest fix), AI-flown jets supported by AircraftService. Tests: 115 → 157.

**Carried over / to check with two players:** a real 1v1, other players' tracers and effects, leaving mid-fight.

## Phase 3: Missiles, sensors and countermeasures

**Signed off by Will on 2026-10-26.** Exit test: a fired missile is dangerous but defeatable, and players can learn *why* they died. Proven numerically by the engagement simulator and in live tests against debug launches and drones. Hands-on feel (missile handling, HUD symbology, tones) is still to be judged in play.

| | Task | Evidence |
|:---:|---|---|
| Done | **NET-03** `Pack` helpers with round-trip tests | 21-byte missile snapshots; round-trip within precision; a full 40-missile packet < 1 KB; malformed buffers rejected. Live: ~15 packets/s received. |
| Done | **ACD-05** Missile data for Tier I–III | AIM-9P/L, R-13M, R-60, R-73, R-3R, AIM-7F, R-27R with class-specific validation; every airframe's missiles exist, fit its hardpoints, and radar missiles need a radar. |
| Done | **CAM-04** Padlock | Hold X / middle mouse: head follows your lock, IR target or nearest spotted jet, clamped to head limits; mouse aim holds still meanwhile. *Not yet checked hands-on.* |
| Done | **HUD-03** Target box, seeker circle, launch zone, missile warning | Lock box with range/closure, IR seeker circle (flashing → solid at lock), launch-zone bar with Rmin / no-escape / Rmax and caret, SHOOT cue, MISSILE warning with direction arrow, missile and flare/chaff readouts. *Visuals not yet checked hands-on.* |
| Done | **DMG-03** Fire and smoke | Engine below 60% smokes; engine hits below 50% have a 10% fire chance; fire burns the fuselage 6/s for 8 s, credited to whoever started it. |
| Done | **MSL-01** `Guidance` module | PN hits a straight target from 2 km and a 6 G turning target from 1.5 km; a 5.5 km shot at a fleeing target falls short; gimbal loss stops guidance; G falls with speed. (PN sign bug caught by hand-check before testing.) |
| Done | **MSL-02** MissileService simulation and detonation | Live: AIM-9P hit after 5.5 s; proximity fuse and ground impact; blast falloff. Damage raised after testing so a good hit kills (R-60 cripples). |
| Done | **MSL-03** Fire validation incl. server-side lock timing | Server tracks each shooter's IR seeker target and hold time; radar missiles refused without the server's lock; 0.6 s launch cooldown. |
| Done | **MSL-04** Packed unreliable replication + client interpolation | 100 ms interpolation buffer, 200 ms extrapolation; motor flame only while burning. *Phase 6: a new missile starts on the launcher's rail as the client draws it and eases onto the interpolated track over 1 s (launches had appeared tens of metres behind the jet).* |
| Done | **MSL-05** IR rear-aspect and all-aspect seekers | Rear-aspect can't see a jet head-on, all-aspect can; heat by aspect, throttle and afterburner. |
| Done | **MSL-06** SARH with lock dependency | Live: radar-locked a drone and killed it with an R-3R; missiles go dumb permanently if the lock is lost. |
| Done | **SNS-01** Visual spotting with LOS | 3 km (5 km above contrail height) with terrain line of sight; HUD markers. |
| Done | **SNS-02** Radar detection and scope | Client uses the same Signature rules as the server; B-scope with blips and boxed lock. *Visuals not yet checked hands-on.* |
| Done | **SNS-03** Server lock state machine | Validated on request, re-checked 5 Hz (range, cone, clutter/notch, terrain LOS); live: "Locked" then "Lost" when the target died. |
| Done | **SNS-04** Notch filtering | Spec: a pulse-Doppler radar loses a perpendicular target below it; pulse radars are blind looking down. Clutter altitude lowered to 300 m real after testing. |
| Done | **SNS-05** RWR | Search / Lock / Launch threats at 2 Hz; live: radar missile showed "Launch"; IR silent without a missile-approach warner. Ring display with coarse bearings. |
| Done | **SNS-06** `Signature` module | IR and radar detection specs. |
| Done | **CMS-01** Deploy flow, counts, FX | Live: 6 flares deployed, drawn, count 30 → 24. |
| Done | **CMS-02** Flare heat sources and decoy decision | Engagement simulator (40 seeds each): no defence 100% hit; AB + flares 42% defeated; idle + break + flares **82% defeated** (target 70–85%). |
| Done | **CMS-03** Chaff decoy and lock breaking | One roll per bundle per missile/lock; much stronger while notching (chaff spam without notching weakened after review). *Not yet exercised hands-on.* |
| Done | **FX-03** Missile, flare, chaff effects | Missile body, smoke trail, motor light; burning flares with smoke; chaff cloud. |
| Done | **FX-04** Damage smoke and fire | Smoke/fire emitters on engine nozzles driven by the Smoking / OnFire attributes. |
| Done | **AUD-03** Seeker tone, RWR, missile warning | Seeker growl → lock tone, RWR search ping / lock repeat / launch alarm, launch whoosh (placeholder sounds). |

**Also done in Phase 3:** engagement simulator in the test suite; debug "launch at me" buttons; startup smoke test now counts runtime errors after boot (caught a per-frame crash). Tests: 157 → 202.

**To check hands-on later:** padlock, HUD missile symbols, radar scope/RWR display, chaff + notch against an R-27R, tones.

## Phase 4: Match loop MVP

**Signed off by Will on 2026-10-26.** Solo matches against 7 AI pilots and a 24-jet stress match were run in Studio. The full exit test (8 players and bots have a full match, then an internal playtest with friends) is carried over to the first multiplayer playtest.

| | Task | Evidence |
|:---:|---|---|
| Done | **INP-03** Gamepad support | Left stick pitch/roll (deadzone + expo), LB/RB rudder, RT/LT throttle (hold RT at 100% for afterburner), right stick look; A gun, X missile, Y lock, B flare, D-pad chaff/cycle, Select camera, R3 padlock, Start scoreboard; menu selection on the first jet. Simulated buttons in play: flare 30 → 29, chaff 30 → 29, Select switched camera. *Sticks and triggers need a real pad.* |
| Done | **INP-04** Touch controls (virtual stick, buttons, auto-throttle, aim-assist) | Virtual stick, throttle slider with afterburner detent, FIRE/MSL/LOCK/FLR/CHF/WPN/CAM, auto-throttle holding ~420 kt (on by default, AUTO button), gun aim-assist toward the lead when firing near a target. Laid out and checked in play with the debug "Toggle touch UI". *Needs a real phone: multi-touch, feel, aim-assist strength.* |
| Done | **CAM-06** Kill cam and spectate | Live: shot down by an AI → camera follows the killer, "Shot down by Viper [AI]"; menu says "You were shot down by Viper [AI]" (AI names fixed in testing). Spectating other jets with ◀ ▶ while waiting to spawn. |
| Done | **HUD-04** Warnings system with priorities (stall, terrain, fuel, bounds) | Every active warning listed, most urgent first: RETURN TO BATTLE AREA (countdown), PULL UP (terrain on the flight path within 4 s), ENGINE FIRE, STALL, OVER-G, G-LIMIT, ENGINE DAMAGE, BINGO FUEL. Top one flashes red, the rest in amber. *Not yet seen hands-on.* |
| Done | **HUD-06** Mobile scaling pass | On touch: scopes shrink to 70% and move to the top corners (moved below the Roblox top bar after the first look), fuel moves above the stick, key help hidden. |
| Done | **AIR-04** Out-of-bounds and ceiling handling | Outside ±20,000 studs or above the ceiling: 10 s countdown, then despawn. Live: an AI jet moved to x = 20,600 got the warning (9 s left after 1 s) and was despawned after 10 s. |
| Done | **SEC-01** Movement checks with strike system and corrections | `MovementCheck`: speed, teleport and acceleration checks; 3 strikes → reset to the last good position, 3 resets → kick. `MatchRules.spec`: honest max-G flying never flagged, crash stops exempt (found in testing). 24-jet stress match: 0 strikes. |
| Done | **SEC-02** Exploit test suite | `tools/ExploitTest`: CFrame speed hack → 6 strikes, 2 resets; teleport → kicked. Remote spam is covered by the NET-02 rate limits. |
| Done | **SEC-03** Logging pipeline for violations | `AntiCheatStrike` / `AntiCheatKick` telemetry events and `AntiCheatViolations` / `Resets` / `Kicks` counters in ServerStorage; kicks counted once (found in testing). |
| Done | **MCH-01** MatchService state machine and Mode interface | Waiting → Countdown → InProgress → Results, verified live; modes are data in `MatchRules`; the spawn gate follows the state. |
| Done | **MCH-02** Free Flight and Dogfight FFA | Dogfight: 15 kills or 10 minutes, AI fill to 8. Free Flight: no scoring, drones allowed. Switched live with the debug buttons. |
| Done | **MCH-03** Configurable respawn rules (both types) | Timer and Lives rules; `MatchRules.spec`. Dogfight uses a 5 s timer until the respawn decision (DESIGN §11). |
| Done | **MCH-04** Scoreboard and results screen | Banner with mode, time and leader; hold Tab / Start for the scoreboard (Roblox's player list took Tab, now hidden); results screen with winner, ranking and next-match countdown. All checked in play. Rewards on the end screen come with Phase 5. |
| Done | **AI-01** Server-side flight for AI jets (shared FlightModel + Instructor) | AI jets fly the same flight model as players, server-side; 23 at once in the stress test. |
| Done | **AI-02** Patrol/Engage/Attack with gun use | `Dogfight.spec`: a Normal pilot shoots down a target ahead (10/10); an Ace beats an Easy pilot 6–0 (4 draws). Live: AI pilots score kills, including on me. |
| Done | **AI-03** Defend state (missile defence, flares, break turn) | `Dogfight.spec`: break, idle and flares against a heat-seeker after the reaction time; notch and chaff against a radar missile; pull up near the ground. |
| Done | **MAP-02** "Strait" blockout: terrain shape, airbases, spawns | `tools/StraitBuilder`: west landmass with a mountain range (passes cut through), east landmass with lower hills, a north-south channel with the test range on a central island, open sea to the south, islets for masking, airbases west and east (runway, apron, hangars, tower), 12 tagged `SpawnPoint` parts. `Place.spec` checks the spawns are in bounds and clear of terrain. Rebuilt after sign-off as a proper height field (see below). |
| Done | **TUT-01** Lesson framework (steps, prompts, highlights, conditions) | `LessonRunner` (pure, `MatchRules.spec`) plus `TutorialController`: prompt panel with step counter and hint, world props, completion message. Training row on the spawn menu. |
| Done | **TUT-02** Lessons 1–3 | 1 Basic flight (pitch, roll, afterburner, 6 rings), 2 Energy (dive, zoom climb, hard turn, recover), 3 Guns (3 drones). Live: lesson 1 steps 1–3 passed and the rings were laid out; drones spawn in Free Flight. *Runs on Free Flight servers only (reserved training servers are TUT-04). Lessons 2–3 not yet played end to end.* |
| Done | **ANL-01** Telemetry wrapper | `Telemetry.event`: pcall'd, tagged with the environment, recent-event log; `MatchEnded`, `Death` and anti-cheat events seen firing in play. |
| Done | **PRF-02** Full-match stress test (bots fill to 24 jets) | Debug "Stress" mode fills to 24 jets. Once the map had streamed in, the server held **60 Hz**; the services' Heartbeat work cost **1.1 ms average, 4.5 ms peak** per frame (new meter in `Main.server`). Dips to 40–53 Hz only while Studio streamed the new map (server, client and renderer share one process in Studio). |

**After sign-off:**
- The Phase 0 pylons and height towers, Roblox's default Baseplate and the unused SpawnLocation were removed from the island; the runway stays as the menu backdrop.
- Playtest feedback (Will): "the map doesn't actually have height variation" and "flying is still quite hard" from the cockpit.
  - Strait terrain rebuilt as a height field written straight into voxels (`tools/StraitBuilder`): rolling lowland, river valleys and gorges, a ridged western range with passes (peaks ~1,500 studs, snow on top), a lower eastern range, slope- and height-based materials. 383 M cells, half the flat version's 718 M, because only a thin shell under the surface is filled.
  - Cockpit Mouse Aim keeps the horizon mostly level (25% of the jet's roll) like the chase view, so the mouse's directions don't rotate mid-turn; the HUD horizon now follows the camera's roll.
  - AI pilots look ahead along their flight path for terrain, not just straight down.
  - Spawn points offer six slots each: with 23 AI jets they had been spawning on top of each other and colliding (24 collisions in the first seconds of a stress match; none after the fix).
- Second round of playtest feedback (Will): raise the eye, the gunsight goes opaque over water, the RWR's plane emoji is hard to read, the lock-on is confusing, and are there lock sounds?
  - Lock symbology: grey box = contact, green circle = lockable, green square = locking, red square = locked; a big red FIRE above the HUD when locked and in the launch zone (OUT OF RANGE / TOO CLOSE otherwise). Radar locks now build up over a 1 s lock-on like IR locks. Checked in play against a drone: green square → red square → TOO CLOSE → FIRE.
  - The round scope is now a situation display: green jet symbol, the selected missile's lock cone, contact dots (red locked, green lockable), RWR marks on the rim.
  - Tones from one sine (`Assets.Audio.Tone`): IR growl and lock tone, radar lock-on beeps and lock beep, RWR search beep, lock double-beep, missile alarm. Checked through the sound state (pitch and volume switching), not by ear.
  - Cockpit eye 0.2 m higher, panel top lower (about 15° view over the nose), fixed-size dials, canopy hidden from inside, gunsight no longer Glass (Roblox draws Glass opaque over water).
  - Terrain heights rounded to whole studs: the place file went from 80 MB to 25 MB with no visible change.
- Later playtest feedback (Will): the Super 530F and other radar missiles wouldn't lock and nothing said why.
  - The HUD says why a lock failed or broke, for 3 s above the missile: NO LOCK / LOCK BROKEN / LOCK LOST with OUT OF RADAR RANGE, NOT IN RADAR CONE, GROUND CLUTTER, TARGET NOTCHING or TERRAIN IN THE WAY; NO RADAR LOCK when firing a radar missile unlocked.
  - Pulse radars looking down into clutter now see targets within 35% of their range (`Signature.CLUTTER_RANGE`) instead of nothing. Checked in play by Will: locks work much better.
- Supercruise (Will): every jet could hover around Mach 1 on dry thrust, so the Typhoon wasn't special.
  - Stronger transonic drag plus a per-airframe `WaveDrag` factor: only the Typhoon, F-22A and Tempest stay supersonic without afterburner (Mach 1.28 / 1.45 / 1.33 at 10 km); afterburner gains thrust above Mach 0.9. Tests in `FlightModel.spec`. Checked in play by Will.

**Also done in Phase 4:** AI difficulty profiles (Easy/Normal/Hard/Ace) and the Extend state, early parts of AI-04/05; debug panel buttons for mode switching, the stress mode, ending a match and forcing the touch UI; server step-cost meter (`ServerStepMs`, `ServerStepPeakMs`, `ServerHz` attributes). Tests: 202 → 269.

**To check with real devices and players:** gamepad sticks, touch on a phone, HUD warnings hands-on, lessons 2–3 end to end, an 8-player match.

## Phase 5: Progression and saving

**Signed off by Will on 2026-10-26.** Exit test: a fresh account can play from the F-5E to a Tier II jet (simulated: 2.2 h); data survives rejoins (checked on the test experience); no way to dupe currency (every grant and spend is server-side and validated, with ProfileStore session locking). *The two-servers-at-once check needs two live servers: carried to the first multiplayer playtest.*

| | Task | Evidence |
|:---:|---|---|
| Done | **MSL-07** ARH with midcourse and active phase | `Guidance.arhTrack`: data link midcourse (or the last known track, extrapolated, if the launcher's lock drops), active inside `ActiveRange`; outside the gimbal or notched for over 1 s it's lost. Warnings, AI defence and chaff only once active. AIM-120A and R-77 (Tier IV). `Missiles.spec`: 5 ARH tests. Live: a debug AIM-120A from 1.8 km behind went active, the RWR showed the launch, and it hit after 4.4 s. |
| Done | **AI-04** Missile use, Extend state | `AIBrain.chooseMissile`: heat-seekers when the seeker sees the target, radar missiles after a server lock (`SensorService:RequestLock`), through the same launch checks as players. `Dogfight.spec`: 4 tests. Live (24-jet stress): 8 launches in ~30 s (R-60, AIM-9P, R-3R). Extend state from Phase 4 (`Dogfight.spec`). |
| Done | **AI-05** Difficulty profiles | Easy / Normal / Hard / Ace: reaction time, aim error, G use, energy and flare skill, and now missile pacing and launch range. `Dogfight.spec`: an Ace beats an Easy pilot; better pilots fire from further and more often. *Matches still fill with Normal pilots.* |
| Done | **DAT-01** DataService with ProfileStore, environment-based names, kick on failure | `DataService`: `lm-loleris/profilestore` 1.0.3 (the author's own Wally package), store `PlayerData_Test_v1` / `PlayerData_Prod_v1`, kick with a friendly message if a session can't start, migrations on load, `BeforeRelease` before every session ends, `Update()` for all writes. On the test experience: "Roblox API services available - data will be saved"; +1,234 Credits and a new lineup survived stopping and rejoining. A second ProfileStore session on the same save got it and its write was kept (1,734 → 1,735) with nothing lost on the first session's exit. *That ran inside one server, so it can't prove the two-servers case: check in the first multiplayer playtest.* |
| Done | **DAT-02** Schema v1, migrations framework and tests | `PlayerData`: schema v1, `MIGRATIONS` run in order on load, reconcile fills new fields, bounded receipt list, settings sanitised. `PlayerData.spec`: 10 tests (fixtures through a pretend v2→v3 migration, a v0 save, missing fields, bad settings). |
| Done | **DAT-03** Client replica with delta updates | Only changed top-level fields are pushed (`PlayerDataUpdate`); the client asks for the full replica on start (`GetPlayerData`). Delta tests in `PlayerData.spec`; live: the menus updated after every research, purchase and admin grant. |
| Done | **DAT-05** Data reset and inspection admin commands (test environment) | `data.inspect`, `data.reset`, `give.credits` / `give.xp` / `give.rp`, `unlock` (test environment only). Live: give RP and Credits, unlock all 8 jets. |
| Done | **PRG-01** Event recording in matches and reward calculation | `ProgressionService` tallies kills (victim and jet flown), assists, missiles defeated (new `MissileService.MissileDefeated`), survival and activity; rewards at match end (and on leaving mid-match). Live: shooting down a drone paid "Kills (AI)" 50 XP / 50 RP / 75 Cr, plus the win and first-win-of-the-day bonus: 312 XP, 403 Cr in all. *Leaving mid-match not yet tested live (needs a second client or REL-02).* |
| Done | **PRG-02** Research, purchase and lineup rules with server validation | `Progression.research` / `buy` / `setLineup`, used through validated remotes. Live: refused with no RP, out of order (F-16A without a Tier II jet), without Credits, too many lineup slots, a module on an unowned jet; accepted when allowed. `Progression.spec`. |
| Done | **PRG-03** Pilot level curve and level rewards | `xpToNext(level) = 500 + 150 × level^1.35`, 250 Credits per level, lineup slot 2 at level 5 and 3 at level 15. `Progression.spec`; shown in the top bar and the hangar's locked slots. |
| Done | **PRG-04** Upgrade modules feeding flight/loadout modifiers | Engine I/II, Airframe I/II, Avionics I, Countermeasures I; costs scale with tier. Fitted modules ride on the jet (`Modules` attribute) and apply to the pilot's flight model, both radars and the countermeasure counts. Fully upgraded is +6% thrust, +0.5 G: stock is within the 85–90% target. Live: Engine I on a Mirage showed up on the respawned jet. |
| Done | **PRG-05** Anti-farming rules | AI kills pay half; after 3 kills on the same victim each further kill pays a quarter; no input for 60 s means no survival or win bonus. `Progression.spec`; live AI kill paid half. |
| Done | **PRG-06** Economy simulation and pacing check | `tools/EconomySim` runs an average free player on the real code; `Economy.spec` checks the targets. After tuning: first new jet **24 min**, Tier II **2.2 h**, Tier III **8.2 h** (targets 20–30 min, 2–3 h, 8–10 h). |
| Done | **UI-01** React setup, theme, router, base components | react-lua 17.2.1 via Wally (`jsdotlua/react`, `react-roblox`); `UI/Theme`, `UI/Components` (panel, label, button with pending state, bar, pill), `UI/App` with top bar and screen router; `MenuController` owns the state and sends intents. |
| Done | **UI-02** Hangar with 3D preview and lineup | Jet on a turntable, lineup slots (locked until level 5 / 15 with the reason), your jets add / remove, Play with the match status, training lessons. Checked in play. *Phase 6: with every slot full, Add became Swap (a level 1 pilot with one slot could not change jets); the menu backdrop is a slow orbit of the map instead of a followed AI jet; the logo sits clear of Roblox's top-left buttons.* |
| Done | **UI-03** Tech tree screen | Branch columns by tier, node states, RP progress, costs; Research and Buy through the UI live (Mirage IIIE researched, then bought). |
| Done | **UI-04** Aircraft detail: modules, loadout, camo | Stock vs upgraded performance bars, modules with costs or the exact reason they can't be fitted, loadout, camo, lineup. Checked in play. *Phase 6: modules can be unfitted and refitted for free (BUY / FIT / UNFIT), and camo became the skin picker (see ACD-07).* |
| Done | **UI-06** Results screen with reward animations | Winner, reward lines counting up, pilot level bar, scoreboard; replaces the Phase 4 results panel. Checked in play. |
| Done | **MMK-01** In-server BR matching (single place) | `Matchmaking`: match band = top lineup BR down 1.0; AI fly jets in the band; jets above it are refused with the reason; the hangar shows the band. `Matchmaking.spec`: 6 tests. Live: an F-4E lineup gave a BR 2.0–3.0 match with AI in F-4Es, Mirage F1s and IIIs; an F-16A was refused. |
| Done | **SET-01** Settings data, controller, change signal | `Config/Settings` (known keys, ranges, sanitise), `SettingsController` (`Get`, `Set`, `Changed`): control scheme, sensitivity, invert pitch, FOV, default camera, volumes applied at once. Live: FOV 82 and invert saved; an invalid scheme and an unknown key dropped. *The settings screen is SET-02 (Phase 6).* |
| Done | **ANL-03** Economy events | Every Credits source (match rewards) and sink (jets, modules) goes to `AnalyticsService:LogEconomyEvent` and the telemetry log. |
| Done | **OPS-02** AdminService and commands | Admins: the place's creator or group owner, a list, or anyone in Studio; data commands only in the test environment; every command logged. Live through the `AdminCommand` remote. *Phase 6: the owner (creator, group owner or the list, not everyone in Studio) gets full access on joining, in test and live: every jet, module, skin and lineup slot, with currency untouched.* |
| Done | **REL-02** Test universe setup (separate experience, test products) | "Afterburner (TEST)" published by Will (place 72582604278324), Studio API access on; the place carries `Environment = "Test"` (test save store, debug and admin data tools on). The release checklist says to switch it to `Prod` before a production publish. *Test products come with the shop (Phase 7).* |

**Also done in Phase 5:** six new jets with greybox models (Mirage IIIE, F-4E Phantom II, MiG-23MLD, Mirage F1C, F-16A, MiG-29A) and their weapons (DEFA 552, M61A1, GSh-30-1, R.550 Magic, Super 530F, R-24R); a parametric greybox generator; ACD-03's CI half finished before the phase. Tests: 269 → 352.

## Phase 6: Content and polish for a soft launch

In progress. A great deal of late-October work came from playtest feedback rather than the phase order: the whole 27-jet roster, the world-scale rework, the map, audio and radar fixes. Those are recorded on the tasks they belong to below, and work that belongs to no task is under *Done outside the plan* at the end of this phase. DEVELOPMENT.md §37 explains how it was built and the traps found.

**State at 29 October 2026:** the content side of Phase 6 is largely done (every jet, every cockpit, the map). The soft-launch plumbing is not started: matchmaking across servers, team modes, the settings screen, onboarding lessons 4–6, retention features, mobile performance, analytics and the release process. Two exit checks carried over from Phases 4 and 5 still need a real multiplayer session: an 8-player match, and the two-servers-at-once save check. How to run them, and the mobile tests, is in [testing/MULTIPLAYER_AND_MOBILE.md](testing/MULTIPLAYER_AND_MOBILE.md).

Fixes made to earlier systems during Phase 6 are noted on those tasks (AIR-02, CAM-02, MSL-04, UI-02, UI-04, OPS-02).

- [x] **ACD-06** Stat blocks for the 15 launch jets (balancing spreadsheet → data modules)
  - Done for all 27 jets, not 15 (`src/shared/AircraftData/`), with the weapons they need. Starting values from public figures, balanced by measuring each tier's corner speed, sustained turn and thrust-to-weight against the tier below rather than in a spreadsheet. Every jet spawned and flew in play; Tier III–VII loadouts, sizes and skins were checked in a play test per tier. Handling is marked *tune in playtests*.
- [x] **ACD-07** Final art models for the 15 launch jets (Blender → MeshParts; see §19.4 pipeline)
  - **Done for the whole roster (27 jets), October 2026.** Every jet has a model, four PBR skins and a cockpit, installed with `AircraftAssembler` and spawned in play (sizes within a metre or two of the real jets). The F-35A got tail booms after Will spotted its fins floating. The routine is in DEVELOPMENT.md §37.3. The notes below are the early history.
  - Pipeline built ([art pipeline](art/AIRCRAFT_PIPELINE.md)): a Blender generator measured from reference drawings, a check that overlays the model on the drawing, `AircraftAssembler`, a model contract that allows Motor6D hinges, and `ControlSurfaceController`.
  - 1 of 15 done. The F-5E model is in the game: 35 parts, 10.7k triangles, moving ailerons, stabilators, rudder and flaps. It passes the contract in Studio and CI. Flown hands-on, with the cockpit view and missile launches checked.
  - Four PBR skins painted by `tools/blender/f5e_paint.py`: Ghost Grey (the free default) and the Desert, Pacific and Lizard aggressor schemes at 5,000 Credits each.
  - The skin picker is on the aircraft details screen (BUY / USE / IN USE), and the preview shows the skin in use. Ownership is saved per jet. The server paints each jet as it spawns, and AI jets get random skins. Checked in play: skins switched, previewed and kept across sessions; AI F-5Es spawned in mixed skins.
  - 2 of 15: the MiG-21bis, from `tools/blender/mig21_generate.py`. It is measured from the MiG-21PF three-view, scaled to the bis's 7.154 m span, with the bis's larger dorsal spine taken from photos. 29 parts, 10.4k triangles. Three skins from `tools/blender/mig21_paint.py`: Natural Metal (the free default), Interceptor Grey and Tactical Camouflage at 5,000 Credits. Checked in play: AI MiGs spawned in the skins, and their ailerons, flaps, stabilators and rudder moved.
  - Next: the Mirage IIIE, then the rest of the launch roster.
- [ ] **FLT-08** Variable geometry (F-14)
  - Not started. The F-14A and Tornado F3 fly with fixed mid-sweep figures and models posed at a fixed sweep.
- [ ] **INP-05** Rebinding UI and persisted bindings
- [x] **CAM-07** Final art for all four cockpit kits, plus overrides for the launch jets
  - Went further than planned: every one of the 27 jets has its own modelled, textured cockpit with live instrument faces (`AircraftAssembler.installCockpit`, `CockpitController`), so the shared kits are only the fallback. Flown hands-on in several jets by Will (MiG-21, Mirage F1, Typhoon, the Tier IV jets).
- [ ] **CAM-08** Third-person chase as a player-facing option (if playtests call for it)
- [ ] **HUD-05** Era variants (analogue vs glass symbology)
- [ ] **GUN-07** LCOS and EEGS sights
- [ ] **DMG-05** Pilot damage diagram on the HUD
- [ ] **MSL-08** Loft profile
- [ ] **MSL-09** Advanced IR (high off-boresight, flare resistance)
  - Partly done: the `IR_Adv` missiles (AIM-9X, IRIS-T, ASRAAM, MICA IR, R-74M) have wide seeker cones and gimbals and strong flare resistance. Helmet cueing (locking where the pilot looks) is not built.
- [ ] **SNS-07** TWS
  - Not started. Related radar work done: lock failure reasons on the HUD, pulse radars that see close targets in clutter, zooming cone and situation scopes (DEVELOPMENT.md §14.2).
- [ ] **CMS-04** Auto-dispense programmes (Tier V+, for example "2 flares every 0.5 s")
- [x] **MCH-05** Team Deathmatch, team balancing
  - West v East, 30 team kills or 10 minutes. Players join the side with fewer players, AI evens the numbers (and leaves the bigger side when a player joins), teams spawn over their own coast. No friendly fire: guns, missile blasts and fuses, seekers, radar locks, the RWR and AI targeting all skip teammates (`Lib/Teams`). Teammates are blue on the HUD and scopes; banner, scoreboard and results show the teams; the winning team gets the win reward. `MatchRules.spec` covers the rules. Checked in play (4v4 with AI: every kill cross-team, scores matched deaths) and by Will. *Two humans on one team still to see in a multiplayer test.*
  - Servers alternate Dogfight and Team Deathmatch each match (`MatchRules.ROTATION`) until mode select (UI-05). Checked in play and by Will.
- [ ] **MCH-06** Air Superiority with zones
- [x] **MAP-03** "Strait" final: materials, props, lighting, horizon skirt
  - Props done. A low-poly kit from Blender (`scenery_generate.py`: three trees, house, barn, flats, shop, warehouse, church, hangar, shelter, tower, ops block, fuel tank; 32–264 triangles each) is placed by `tools/SceneryBuilder`. It lays 12 towns on street grids, farms along the roads, about 15,000 trees in 760 woods, and roads between the towns and airbases on each coast. The roads are routed round the sea and the steep ground and textured with one repeating 128×256 image. The airbases get arched hangars facing the runway, a tower with a glass cab, an ops block, shelters and fuel tanks in place of the old boxes. Towns and woods are StreamingMesh models; flying over them holds 60 fps in Studio once streamed in.
  - Horizon skirt done. Past the terrain the world carries on as a flat plain to the haze: eight client-side slabs (`WorldEdgeController`) whose SpecialMeshes are scaled out to ±150 km, grass where the coasts run on and sea elsewhere. The outer 2,500 studs of terrain ease down to the plain's height (`WorldEdge`, `StraitBuilder.edges`), so the mountains on the north and west edges slope away instead of ending in cliffs. Roads and towns keep back from that band.
  - The play-area edge and the ceiling show a Minecraft-style border: drifting red diagonal stripes in a patch around the point nearest you, fading in from 3,000 studs. It doesn't block anyone; the RETURN TO BATTLE AREA countdown does.
  - Sky and light done, after Constable (`tools/SkyBuilder.luau`). An English afternoon: latitude 51.5°, 15:45, a warm low sun from the west-south-west. The skybox is painted by `tools/blender/sky_paint.py`: heaped cumulus built from round puffs merged into one smooth surface and lit from the real sun direction (warm lit sides, grey-violet bases, bright rims against the sun, some heavier slate clouds), thin cirrus overhead, a warm hazy horizon and faint brushwork. Roblox's volumetric clouds sit in front, tinted to match; light haze, a slight warm grade, bloom and sun rays. Clouds cost nothing measurable (60 fps either way).
  - Grass from the air: `tools/blender/terrain_paint.py` paints a patchwork of fields with mowing stripes and hedgerows, used as MaterialVariants on Grass and LeafyGrass at 2,048 studs per tile. Terrain only draws variants with the Regular pattern. The grass decoration is off.
  - Signed off by Will ("happy with the sky").
- [ ] **MAP-04** Streaming and fog tuning for mobile
  - Streaming was turned off for a while (it unloaded the map on death and under memory pressure), then back on after the world-scale rework: the map is a twentieth of its old size in cells, loads in about 10 s, PLAY waits for `MapReady`, and it stays loaded through deaths (60 fps in Studio). Still to do: mobile memory, join time and fog on a real phone.
- [ ] **FX-05** Quality settings and pooling audit
- [ ] **AUD-04** Warnings and radio barks with subtitles
  - Betty voice warnings from Will's recordings (`Assets.Audio`): PULL UP (cuts in, back to back), ENGINE FIRE, BINGO FUEL, ENGINE DAMAGE ("Caution"); the master warning chime for STALL, OVER-G, G-LIMIT and RETURN TO BATTLE AREA. RWR contact, lock and launch use his RWR recordings. Every missile guiding on you now warns, heat-seekers included, and a heat-seeker lock shows LOCKED like a radar lock.
  - Still to do: radio barks and subtitles.
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

**Done outside the plan (October 2026).** Work Will asked for that belongs to no task; how it was built is in DEVELOPMENT.md §37.

- World scale 1 stud = 1 m: terrain load from 133 s to about 10 s, 60 fps (§37.1). Checked in play.
- Supercruise: stronger transonic drag and a per-airframe `WaveDrag` factor, so only the Typhoon, F-22A and Tempest stay supersonic on dry thrust; afterburner gains thrust above Mach 0.9 (§6.4). Tests in `FlightModel.spec`; checked in play by Will.
- Radar: lock failure reasons on the HUD, pulse radars see close targets in clutter, stealth now shrinks detection range, zooming scopes (§14.2, §14.5). Locks checked in play by Will.
- The island raised above the sea so it doesn't look flooded from afar (§37.5). Checked from the air.
- Tech tree rows size to their tallest branch; the RP note sits below everything.
- Two Severn Bridges to the island (§37.5). Placed and checked in play; roads to them still to do.
- The Ground Roamer, a drivable 4x4 (§36). Driven in play; airbase spawn spots, other players' wheel spin and touch controls still to do.
- Betty voice warnings and RWR recordings (AUD-04 above).

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

- [x] **ACD-08** Remaining tiers (V–VIII) data and models
  - Done early, with Phase 6's roster work: the F-16C, F-15E, Su-30SM, MiG-29SMT, Gripen C, F/A-18E, Su-35S, Typhoon, Rafale C, F-22A, F-35A, Su-57 and the Tempest-class concept, each spawned in play with its loadout and skin. Tech tree runs to Tier VIII.
- [ ] **FLT-09** Thrust vectoring behaviour
  - Partly done: `ThrustVectoring` jets (Su-30SM, Su-35S, F-22A, Su-57, Tempest) keep more control authority at low speed. Post-stall rotation and the faster energy bleed are not built.
- [ ] **SNS-08** Data link
- [ ] **SNS-09** Stealth RCS and weapon bay effect
  - Partly done: the airframe `Stealth` factor shrinks radar detection range on both server and client (`Missiles.spec` checks it). Aspect-dependent RCS and the weapon-bay effect are not built.
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
  - Partly done: the Tempest is in the tech tree, researched from any one Tier VII jet. The two-jet rule and the challenge chain are not built.
- [ ] **ANL-05** Dashboards in the Creator Dashboard (custom events) and the weekly balance report process
- [ ] **OPS-03** Event flags (double XP etc.)
- [ ] **OPS-04** Message of the day and announcements
- [ ] **CMP-04** Pre-launch compliance checklist (names, assets, maturity questionnaire, product descriptions)
- [ ] **REL-05** (Optional) Open Cloud publishing from CI
