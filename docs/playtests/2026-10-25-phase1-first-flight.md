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

**Pending** Will's verdict.

## Findings

| # | Finding | Severity | Who saw it | Action |
|---|---|---|---|---|
| 1 | Engine sound very loud, fast and harsh | 🟠 major | Will | Fixed: volume ~0.1–0.35, pitch 0.55–0.9, Engine group 0.5 |
| 2 | Boresight, flight-path marker and aim reticle offset toward the top-left | 🟠 major | Will | Fixed: UIScale moved onto a centred frame; projected symbols unscaled |
| 3 | Jet slowly sank with the aim held level (instructor flew the nose, not the flight path) | 🟡 minor | Claude | Fixed: instructor works in the flight-path frame; new 30 s altitude-hold spec |
| 4 | Gunsight glass too big and opaque; canopy bows heavy | 🟡 minor | Will (screenshot) | Fixed: smaller, more transparent glass; thinner bows |
| 5 | MiG-21 takes ~90 s to pass Mach 1 at 9 km in afterburner (too slow) | 🟡 minor | Claude (numbers) | Tune wave drag / per-airframe transonic drag in a later pass |

## Follow-ups

- [ ] Will's hands-on verdict on feel, after the fixes
