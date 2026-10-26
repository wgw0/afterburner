# Playtest: 2026-10-25 · Phase 1 first flight

| | |
|---|---|
| **Build** | `phase-1/flight-model` @ 5f432a9 (fixes applied during the session) |
| **Phase / exit test** | Phase 1: "flying is fun with no weapons; the two jets feel different" |
| **Testers** | Will (hands-on), Claude (automated checks) |
| **Setup** | Studio solo play, keyboard and mouse, ~1100×700 viewport |
| **Duration** | in progress |

## What we tested

- [x] Boot: all services and controllers start, smoke test passes
- [x] Spawn an F-5E and MiG-21 from the menu; client owns the jet's physics
- [x] Cockpit view, HUD, gauges visible
- [ ] Mouse Aim feel
- [ ] Direct mode feel
- [ ] Stall, G-LOC, crash and respawn
- [ ] The two jets feel different

## Results against the exit test

**Pass** (2026-10-26). After the HUD pass, chase camera, audio and load-time fixes, Will: "feels good, sign off phase 1". Fine-tuning deferred.

## Findings

| # | Finding | Severity | Who saw it | Action |
|---|---|---|---|---|
| 1 | Engine sound very loud, fast and harsh | 🟠 major | Will | Fixed: volume ~0.1–0.35, pitch 0.55–0.9, Engine group 0.5 |
| 2 | Boresight, flight-path marker and aim reticle offset toward the top-left | 🟠 major | Will | Fixed: UIScale moved onto a centred frame; projected symbols unscaled |
| 3 | Jet slowly sank with the aim held level (instructor flew the nose, not the flight path) | 🟡 minor | Claude | Fixed: instructor works in the flight-path frame; new 30 s altitude-hold spec |
| 4 | Gunsight glass too big and opaque; canopy bows heavy | 🟡 minor | Will (screenshot) | Fixed: smaller, more transparent glass; thinner bows |
| 5 | MiG-21 takes ~90 s to pass Mach 1 at 9 km in afterburner (too slow) | 🟡 minor | Claude (numbers) | Tune wave drag / per-airframe transonic drag in a later pass |
| 6 | Roll felt too fast and not jet-like | 🟠 major | Will | Fixed: roll inertia (~0.4 s), then Will tuned F-5E roll 80 / pitch 20 / yaw 10 °/s in the P panel; MiG-21 scaled to 65 / 17 / 8 |
| 7 | Spawned too high to see the ground; haze hid it | 🟡 minor | Will | Fixed: spawn 3000 → 1200 studs, Atmosphere density 0.3 → 0.1 |
| 8 | No ground to judge height and speed | 🟠 major | Will | Fixed: placeholder terrain (tools/TerrainBuilder), streaming off for Phase 1 |
| 9 | "Test" from F5 once hung with only the server booted | 🟡 minor | Will | Not reproduced; likely overlapped with a session Claude had started. Watch for it |
| 10 | HUD looks awful: loose screen text, clashes with canopy frame, no tapes or pitch ladder; cockpit gauge dials squashed with ticks outside | 🟠 major | Will | New task HUD-07 (HUD design pass); gauge fix under CAM-02 |

## Follow-ups

- [x] Will's hands-on verdict: signed off
