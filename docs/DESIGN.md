# Afterburner: game design document

> A Roblox air-combat game in the spirit of DCS World: energy-based dogfighting, real missile and countermeasure play, and a long progression from 1980s jets up to fifth- and sixth-generation fighters.

Version 0.2 (draft; decisions are logged in §11). Platform: Roblox on PC, console and mobile. Place file: `Afterburner.rbxl`. Current build status is in [PROGRESS.md](PROGRESS.md).

## Contents

1. [Vision and pillars](#1-vision-and-pillars)
2. [Core gameplay](#2-core-gameplay)
3. [Flight model](#3-flight-model)
4. [Weapons, sensors and countermeasures](#4-weapons-sensors-and-countermeasures)
5. [Game modes and matchmaking](#5-game-modes-and-matchmaking)
6. [Aircraft roster and the tech tree](#6-aircraft-roster-and-the-tech-tree)
7. [Player progression](#7-player-progression)
8. [Monetisation strategy](#8-monetisation-strategy)
9. [Technical architecture](#9-technical-architecture)
10. [Build plan: steps to follow](#10-build-plan-steps-to-follow)
11. [Risks and open questions](#11-risks-and-open-questions)

## 1. Vision and pillars

The aim is the most believable dogfighting on Roblox. It won't be a full simulator (no cold starts, no 60-key bindings), but the decisions that make DCS dogfights tense come through: managing energy, timing your shot, defending a missile, and knowing when to run.

Every feature should serve at least one of these design pillars.

| Pillar | What it means in practice |
|---|---|
| **Energy is everything** | Speed and altitude are your resources. Turning bleeds them. Players who manage energy beat players who just pull back on the stick. |
| **Every kill is earned** | Missiles can be defeated. Guns need lead. No lock-and-forget instant kills, even at top tier. |
| **Readable in 3 seconds** | A new player can tell, at a glance: where the enemy is, whether they're locked, and whether a missile is coming. Depth sits underneath, not on top. |
| **The hangar is the dream** | Progression from a 1980s F-5 to an F-22 should feel like a career. Every unlock is something you want to fly. |
| **Fair at every tier** | Matchmaking keeps jets of similar era together. Money buys style and convenience, never a stronger jet than its free equivalent. |

The audience is players aged 13+ who like aviation, military games, or competitive PvP; DCS, War Thunder and Ace Combat fans who play Roblox. Secondary audience: younger players who want to fly cool jets, served by arcade-assist controls and PvE modes.

The tone is grounded and modern-military, but not grim. Clean HUD, radio chatter, satisfying explosions and no gore.

## 2. Core gameplay

### 2.1 The core loop

```
 Hangar ──► Pick jet + loadout ──► Match (8–12 min) ──► Rewards (XP, Credits)
   ▲                                                         │
   └──────── Research / buy / upgrade jets ◄─────────────────┘
```

- Moment to moment (seconds): fly, find a target, manoeuvre for a shot, defend.
- Match (minutes): score kills and assists, take objectives, survive. Respawn with a delay, or limited lives in harder modes.
- Session (an hour): finish 4–6 matches, complete daily challenges, research the next jet.
- Long term (weeks): climb the tech tree, master aircraft, unlock camos, rank up the season pass.

### 2.2 What a good dogfight looks like

1. Detect: radar or RWR shows a contact at 15 km. You climb to gain an energy advantage.
2. Merge: missiles are fired and defended (notch, flare, chaff). Both jets survive and pass head-on.
3. Turn fight: one player goes for a rate fight, the other for a vertical one. The better energy manager gets behind.
4. Kill: an IR missile shot from the rear, or a guns kill as the defender bleeds out of speed.
5. Egress: you're low on fuel and missiles, so you extend away and rejoin.

Every system below exists to make this sequence happen.

### 2.3 Controls

Three control schemes, selectable in settings and reflected in matchmaking stats:

| Scheme | Who it's for | How it works |
|---|---|---|
| **Mouse Aim** (default on PC) | Most players | The mouse points where you want to go; an instructor AI flies the jet there, respecting its limits. Like War Thunder's mouse aim. |
| **Direct** | Experienced players and gamepad | Mouse or stick drives pitch and roll directly, with full control over AoA. More manoeuvrability and more risk (stalls, blackouts). |
| **Touch** | Mobile | A virtual stick plus auto-throttle, aim-assist on guns and big buttons for fire, flares and lock. |

Default PC bindings: W/S for throttle (holding W above 100% engages afterburner), A/D for yaw, Q/E for roll, LMB for guns, Space for missiles, R for the next missile, T for radar lock or unlock, F for flares, C for chaff, V for cockpit or chase view, X to padlock (hold), Z to zoom (hold), Left Shift to override the limiter (hold), M to switch Mouse Aim and Direct, Tab for the scoreboard and H (hold) to go back to the hangar. Every key and gamepad button can be rebound in Settings.

Gamepad and touch layouts are first-class. A large share of Roblox players are on mobile, so mobile must be playable from day one, not patched in later.

### 2.4 Camera: cockpit first (decided)

The **cockpit view is the primary way to play**, in keeping with the DCS feel. A third-person chase camera stays on the table as an option if playtests show the cockpit is too hard for general players.

Modelling a unique cockpit for 30+ jets is the biggest art cost in the project, so cockpits are built from **era kits** rather than one-offs:

| Kit | Used by | Look |
|---|---|---|
| **Analogue** | Tiers I–II (F-5E, MiG-21, F-4E, MiG-23, Mirage) | Round gauges, simple gunsight or early HUD, no MFDs |
| **Early glass** | Tiers III–IV (F-16A/C, MiG-29, F-15C, Su-27, F-14A) | HUD plus one or two monochrome displays, radar scope |
| **Full glass** | Tiers V–VI (Typhoon, Rafale, Su-35, Super Hornet) | Several colour MFDs, helmet-cued sight |
| **Wide-area display** | Tiers VII–VIII (F-22, F-35, Su-57, Tempest) | One large touchscreen-style panel, sensor-fusion view |

Each jet reuses its era kit and changes only the frame, the canopy shape and a few signature details. Instruments are **live** (`SurfaceGui`s driven by the flight model), so a single instrument script serves every cockpit.

*Built, October 2026: it went further than the plan. All 27 jets have their own modelled, textured cockpit with live instruments, so the kits are only the fallback. The HUD symbology also follows the cockpit era.*

Cockpit features:
- Free look: hold right mouse button, or use the right stick, to look around the canopy. Snap-views for checking six and checking above you.
- Padlock (assist): an optional key to lock your view onto the nearest enemy. It's essential for cockpit dogfighting without head-tracking hardware, and it's the main tool for keeping the cockpit accessible.
- Readable HUD: the HUD has to be readable at phone resolution, so the core numbers (speed, altitude, G and lock state) also stay visible in a screen-space overlay that can be turned on or off.
- Third-person fallback: a chase camera behind the jet, the same flight model and HUD overlay. It can be enabled per mode if it tests better with players.

## 3. Flight model

The heart of the game. The goal is a **"simulation-flavoured arcade" model**: built on real physical ideas (lift, drag, thrust, energy), tuned per aircraft from a small table of numbers, and cheap enough to run every frame on a phone.

### 3.1 Scale

Roblox physics loses precision far from the origin, and real jets cover kilometres in seconds. So the game uses a **game scale**:

- 1 stud = 1 m visually, but **speeds are compressed**. The HUD shows real-world numbers (knots, Mach, feet), while the world moves at about **35–40%** of true speed.
- Map size: about 11,200 × 11,200 studs, centred on the origin. That gives roughly 3 to 4 minutes to cross at full afterburner. Keep all action within about ±5,600 studs of the origin. (The world was 1 stud ≈ 0.28 m, the Roblox convention, until the terrain's load time forced the change: 1/12 of the area in studs.)
- Altitude: the ceiling is 5,600 studs, displayed as about 48,000 ft.
- Weapon ranges are scaled with speed. HUD numbers stay authentic-looking (an AIM-120 "50 km" shot), while the world distance is shorter.

These ratios live in one `Config.Scale` module so they can be tuned after playtests.

### 3.2 Forces

Each frame the pilot's client works out:

| Force | Model |
|---|---|
| **Thrust** | `MaxThrust × throttle`, with afterburner adding about 40–60%. Thrust falls off with altitude. Afterburner burns fuel about 3× faster. |
| **Lift** | `½ρv² × WingArea × CL(AoA)`. CL rises roughly linearly to the critical AoA, then drops (stall). |
| **Drag** | Parasitic (`CD0`) plus induced (`k × CL²`, so hard turning costs speed) plus wave drag near Mach 1 (the transonic hump). |
| **Gravity** | Constant. Climbing trades speed for height, diving trades height for speed. This is what makes energy fighting work. |

The result drives the jet's velocity. The orientation response (pitch, roll and yaw rates) is limited by:

- Max instantaneous G, the structural or pilot limit, such as 7.5 G or 9 G.
- Max sustained turn rate, an emergent result: thrust has to beat induced drag.
- Roll rate, which varies with speed. Controls go sluggish when slow and stiffen at very high speed.
- Corner speed, the speed with the best turn rate, which emerges from the G limit plus lift. Learning each jet's corner speed is a skill.

### 3.3 Pilot and aircraft limits

- G-LOC: sustained high G narrows and darkens the screen (grey-out, then blackout). A G-meter on the HUD gives warning. Recovery takes a few seconds.
- Stall: above the critical AoA, lift collapses and the nose drops. The aircraft buffets and a stall-warning tone sounds. Mouse Aim prevents stalls unless the player overrides it.
- Overspeed: above max speed, control authority drops. Extreme overspeed causes damage, rarely.
- Fuel: a soft limit. Running out means gliding. Encourages sensible use of the afterburner.

### 3.4 Per-aircraft stat block

Every jet is defined by about 15 numbers in a shared `AircraftData` module, so a new plane is data plus a model, with no new code:

```lua
-- ReplicatedStorage/Shared/AircraftData/F16C.lua (example shape, values illustrative)
return {
	DisplayName = "F-16C Block 50",
	Tier = 4,
	BattleRating = 9.3,
	Mass = 9200,              -- kg, loaded
	MaxThrust = 76000,        -- N, dry
	AfterburnerMult = 1.65,
	WingArea = 27.9,          -- m^2
	CD0 = 0.021,
	InducedK = 0.11,
	CLMax = 1.6,
	CriticalAoA = 25,         -- degrees
	MaxG = 9.0,
	MaxRollRate = 280,        -- deg/s at corner speed
	MaxMach = 2.0,
	Fuel = 3200,              -- kg
	RadarRange = 70,          -- km (display units)
	RadarType = "Pulse-Doppler",
	Hardpoints = { "Gun", "IR", "IR", "Radar", "Radar", "Radar", "Radar" },
	Countermeasures = { Flares = 60, Chaff = 60 },
}
```

Balancing becomes a spreadsheet job. Real-world figures give the starting point, then values get tuned for gameplay.

## 4. Weapons, sensors and countermeasures

### 4.1 Guns

- Projectiles are simulated as **raycast tracers** (no physical parts). They have travel time and gravity drop, so leading the target matters.
- A **lead indicator (pipper)** appears on the HUD when a target is locked or close. Older jets get a simpler gunsight; newer ones get a predictive LCOS/EEGS-style funnel. That's a meaningful upgrade. *Built: a fixed sight at Tiers I–II, a lead-computing (LCOS) pipper that follows a turning target from Tier III, and the bullet-stream (EEGS) funnel from Tier V.*
- Ammunition is limited (for example, 500 rounds) with spool-up and overheat on rotary cannons.
- **Reloading** (Will, October 2026: running dry shouldn't punish a pilot who's doing well and staying alive). Not realistic, on purpose. When the gun runs dry it refills after 10 s; a missile type refills after 15 s, flares and chaff after 8 s. A bar on the HUD shows the timer.
- **Hit markers** confirm hits from the server, for guns and missiles, with a hit sound and a kill-confirm sound.
- Damage is per hit, with a **component damage model**: wings, engine, tail and pilot. A hit on the tail reduces yaw authority, a hit on the engine reduces thrust, and fire causes damage over time.

### 4.2 Missiles

Missiles must always be **defeatable** (pillar 2). Each missile is a small data block, similar to the aircraft stats.

| Class | Era examples | Guidance | How to defeat it |
|---|---|---|---|
| **Rear-aspect IR** | AIM-9P, R-60 | Locks only on the target's hot rear | Flares, a sharp turn to put the sun or the ground behind you, cutting the afterburner |
| **All-aspect IR** | AIM-9M, R-73 | Locks from any angle; strong off-boresight shots | Flares plus a break turn, throttle back, out-rate the missile |
| **Advanced IR** | AIM-9X, IRIS-T | High off-boresight, flare-resistant | Timed flare bursts plus a hard manoeuvre, or out-range it |
| **SARH radar** | AIM-7M, R-27R | The launching jet must keep a lock until impact | Break the lock: notch (fly 90° to the radar), chaff, or force the shooter to turn away |
| **Active radar** | AIM-120, R-77, Meteor | Fire-and-forget after midcourse; its own radar takes over near the target | Notch plus chaff at the right time, or run (kinematic defeat) |

Each missile has a motor burn time, then coasts on drag, so its energy falls off. A long-range shot at a fleeing target can simply run out of energy. This is the DCS "drag the missile" tactic and it's important to include. Missiles use proportional navigation, with a max G that falls as they slow down. Long-range radar missiles (Tier IV+) loft: they climb on long shots and dive onto the target.

Missiles in flight are drawn at 3× their real length, so players can see them (Will, October 2026: visibility over realism). Jets carry their missiles visibly on the hardpoints, and each one disappears as that type runs out.

Locking on:
- IR: hold the target in a seeker cone for about 1 second until the tone becomes a solid growl.
- Radar: hold T while the target is inside the radar cone and within range.
- An **RWR** (radar warning receiver) tells the target they're being locked, and warns loudly when a missile is launched. Older jets have no missile-launch warning, which makes early tiers tense in a fair way.

### 4.3 Sensors

| Sensor | Gameplay function |
|---|---|
| **Radar** | Shows contacts in a forward cone (wider and longer on newer jets). Pulse-Doppler radars can be **notched**: a target flying perpendicular at low altitude disappears. |
| **RWR** | A 360° indicator of who is painting you, with direction and threat type. |
| **Visual** | Enemy markers appear only within visual range or when spotted by a teammate's radar (data link at higher tiers). Keeps "where is everybody" meaningful. |
| **Data link** | Tier V and up: share radar contacts with teammates whose jets also have it. This is a big part of modern air combat and a reason to want newer jets. *Built, November 2026.* |
| **Stealth** | Tier VII and up (F-22A, F-35A, Su-57, Tempest): shrinks the range at which enemy radar detects you. Stealth is strongest head-on and weaker from the side and behind, and opening the weapon bays to fire shows the jet for a few seconds. Balanced by battle rating. Stealth jets meet other stealth jets or very capable 4.5-gens. *Built, November 2026.* |

### 4.4 Countermeasures

- Flares spoof IR missiles with a chance based on the seeker generation, the angle and the throttle setting.
- Chaff spoofs radar missiles and is most effective while notching.
- Both are limited per life. Each refills on a short timer once it runs out (reloading, §4.1), and on respawn. A rearm-at-base option in larger modes could add a risk/reward choice later.
- Tier V+ jets have flare programmes: one press fires a short burst, and an optional automatic burst fires as a heat-seeker closes in. The most advanced heat-seekers can only be fooled by bursts.

## 5. Game modes and matchmaking

### 5.1 Modes (in rollout order)

| Mode | Players | Description | Phase |
|---|---|---|---|
| **Training** | 1 | Six lessons on a private training server: flight, energy, guns, missiles, defending a missile, and a first fight against an AI pilot. New pilots start here and can leave at any time. The training server also has Vs AI (bots in jets at your jet's level, pilot XP only) and any jet to try. | Built |
| **Free Flight** | 1–12 | Explore the map, practise against AI drones. No rewards, no pressure. | Built |
| **Dogfight (FFA)** | 6 | Spawn in the air, first to 15 kills or 10 minutes. Guns and IR only at low tiers. | Built |
| **Guns Only** | 6 | A free-for-all with no missiles of any kind: guns only, with four times the usual rounds (Will, October 2026). First to 15 kills or 10 minutes. Also on training servers against AI. | Built |
| **Team Deathmatch** | 3v3 | Team score race to 30 kills or 10 minutes. Airborne spawns over each team's coast, no friendly fire. | Built |
| **Air Superiority** | 3v3 | Capture three airspace zones. Holding zones drains enemy tickets, so it rewards teamwork and positioning, not just K/D. 12 minutes. | Built |
| **Duels** (Ranked and Casual) | 1v1 | **The main mode** (Will, November 2026). Best of five rounds. Each round both jets start head-on, level and about 6 km apart, with one life each; the last one flying takes the round. Both down within 2 s of each other (a missile already on its way still counts) is a drawn round, and so is a round still going after 2½ minutes. First to three round wins takes the duel. Ranked moves your duel rating; Casual moves nothing. Fly any jet in your lineup, and change it between rounds. Leaving forfeits the duel. | Built |
| **BVR Battles** | 3v3 | The team match fought at range. Tier IV and up only, with radar missiles only (no heat-seekers; the gun stays for a merge). The teams start about 20 km apart, facing each other, so radar, locks, notching, chaff and the data link decide it. First team to 15 kills or 12 minutes. | Built |
| **Strike Escort** | 3v3 | Every 2½ minutes each team sends two AI bombers at the other team's airbase. Escort yours, shoot theirs down. AI fighters split the jobs: half hunt the enemy bombers, half stay with their own. A bomber that reaches its target scores a strike for its team. First to six strikes, else the most strikes (then team kills) at 12 minutes. Air-to-air only: the bombers are the objective, not ground targets. | Built |
| **PvE Waves** | 1–3 co-op | You and up to two friends hold your airbase against ten waves of AI fighters and bombers, each bigger and sharper than the last. Five bombers through and the base is lost; clear all ten waves to win. A good on-ramp and a mobile-friendly option. Scripted missions with bosses (an AWACS) can come later. | Built |

A match seats 6 pilots (Will, October 2026), so matches fill quickly at low population. AI pilots take any empty seats. Duels seat 2 and PvE Waves 3 players (the waves are the enemy, so no AI fill). Respawns are on a timer (5 s in most modes, 8 s in BVR, 6 s in Strike Escort and PvE; decision log #3); in a duel the round start is the only respawn.

Duels, BVR and PvE Waves are only for players who pick them: ANY never puts you in one, and a long wait never turns them into another mode. Every mode except Free Flight can also be flown against AI on a training server (Vs AI).

**Duel ratings and ranks.** Everyone starts at 1,000. A ranked duel between two players moves both ratings (Elo): beating a higher-rated pilot gains more than beating a lower one, and a win or a loss always moves you at least a point. Your first 10 duels move it faster, so a new pilot finds their level quickly. Ratings fall into six ranks:

| Rank | Rating | First time reached |
|---|---|---|
| Bronze | 0+ | (start) |
| Silver | 1,100+ | "Silver Duelist" title, 2,500 Credits |
| Gold | 1,250+ | "Gold Duelist" title, 5,000 Credits |
| Platinum | 1,400+ | "Platinum Duelist" title, 10,000 Credits |
| Diamond | 1,600+ | "Diamond Duelist" title, 20,000 Credits |
| Ace | 1,800+ | "Ace Duelist" title, 40,000 Credits |

Rank rewards go by your best-ever rating, so dropping back and climbing again doesn't pay twice. The hangar shows your rank, rating, next rank and win–loss record when a duel is picked, and the results screen shows the rating change and any new rank.

**Bombers.** The bomber in Strike Escort and PvE is the **B-1B Lancer**, flown only by AI. It flies straight for its target at about 900 m, at a speed fighters can catch, and never fights back: no gun, no missiles. It throws flares and chaff while a missile is coming, so a clean shot takes work. Shooting one down is a kill as usual. One that gets through drops its bombs and leaves the fight: nobody gets a kill for it, and it isn't in the kill feed.

### 5.2 Matchmaking by battle rating (BR)

Without battle ratings an F-22 would farm F-5s and new players would quit. So:

- Every aircraft has a **Battle Rating** (for example 1.0 to 13.0).
- A player brings a **lineup** of up to three jets (four with the Extra Lineup Slot pass; one at a time, swapped on respawn). The lineup's BR is its highest jet. Matchmaking uses the jet you click PLAY with.
- The matchmaker puts lineups within **±1.0 BR** into the same match. The longer the wait, the looser the rules (Will, November 2026): the spread widens to ±1.7 over the first minute, then to ±3.0 by two and a half minutes, and after two minutes a player who picked a mode takes any mode. A match starts short-handed after 30 s, with AI pilots in the empty seats.
- **Duels** pair two pilots by BR the same way and, for a ranked duel, by duel rating too: within 150 rating points at first, 300 after 30 s and 600 after 45 s. Nobody to duel within 45 s? An AI pilot takes the other seat, as sharp as your rating suggests (Normal, Hard from 1,100, Ace from 1,400), and the duel is unranked (Will, November 2026). Casual duels don't look at rating. Parties can't queue for a duel.
- **BVR** needs a Tier IV or higher jet with radar missiles: PLAY refuses any other, and the matchmaking panel says so before you click.
- The mode picker under PLAY lists RANKED DUEL first (the default), then CASUAL DUEL, DOGFIGHT, TEAMS, ZONES, STRIKE, BVR, GUNS ONLY, PVE and ANY. ANY means Dogfight, Team Deathmatch, Air Superiority, Strike Escort or Guns Only.
- **Parties** of up to 3 queue as one, at the party's highest BR, fly on the same team and go home together. Three is the most so two parties always fit a 6-pilot match.
- BR values are **tuned from live data**: win rate, K/D and average survival time per aircraft, reviewed every patch. Live config can change a jet's BR on live servers without an update.
- Roblox servers are separate instances, so matchmaking uses **reserved servers** plus `MemoryStoreService` queues. See §9.4. *Built, October 2026: lobby servers, a queue for any mode or a chosen one, match servers and training servers; waiting on the live test.*

### 5.3 Maps

Start with **one excellent map**, not five rough ones:

1. "Strait" (launch): coastline, mountains and sea, with two airbases at opposite ends. Valleys for low flying, mountains for terrain masking, and open water for clean BVR. Built with Roblox Terrain plus low-poly props.
2. Later: **"Desert Range"** (flat and open, favours radar), **"Arctic Fjord"** (narrow fjords, knife fights), and **"Islands"** (carrier ops, v1.2+).

Use `StreamingEnabled` and keep detail **low-poly and impostor-friendly**. Players see terrain from 10 km up, so silhouettes matter more than close-up detail.

## 6. Aircraft roster and the tech tree

### 6.1 Structure

One tech tree with **three branches** that share tiers, so players can follow the jets they love:

- NATO / US
- Soviet / Russia
- Europe (France, UK, Sweden, Europe-wide projects)

Cross-branch research is allowed. Every jet needs Research Points (RP) from the previous jet *in any branch at the same or lower tier*, so nobody is locked out of a favourite.

### 6.2 The roster (all 27 jets built)

The plan was about 15 jets at launch, growing to about 30. In the end the whole roster was built in October 2026: all 27 jets have flight data, weapons, a final model, their own cockpit and skins, and all can be researched. BR values are starting points and will be tuned in testing. The B-1B Lancer isn't part of the roster: it's the AI bomber of Strike Escort and PvE (§5.1), and nobody flies it.

| Tier | Era | NATO / US | Soviet / Russia | Europe | BR range | Signature unlock |
|---|---|---|---|---|---|---|
| **I. Starter** | 1960s–80s | **F-5E Tiger II** *(free starter)* | **MiG-21bis** *(free starter)* | Mirage III | 1.0–2.3 | Guns plus rear-aspect IR. Learn energy fighting. |
| **II** | 1970s–80s | F-4E Phantom II | MiG-23MLD | Mirage F1 | 2.7–4.0 | First radar and SARH missiles. RWR. |
| **III** | 1980s | F-14A Tomcat, F-16A | MiG-29A | Mirage 2000C | 4.3–6.0 | All-aspect IR, pulse-Doppler radar, high-G airframes. |
| **IV** | late 80s–90s | F-15C Eagle, F/A-18C | Su-27S | Tornado F3 | 6.3–8.0 | Active radar missiles (early AIM-120 / R-77). |
| **V** | 2000s | F-16C, F-15E | Su-30SM, MiG-29SMT | Gripen C | 8.3–9.7 | Helmet-cued high off-boresight IR, data link. |
| **VI. 4.5-gen** | 2010s | F/A-18E Super Hornet | Su-35S | Typhoon, Rafale | 10.0–11.3 | Supercruise (Typhoon), thrust vectoring (Su-35), long-range missiles. |
| **VII. 5th-gen** | 2010s–20s | **F-22A Raptor**, F-35A | Su-57 | | 11.7–12.7 | Stealth, sensor fusion, the full kit. |
| **VIII. Prestige** | Future | | | **"Tempest" concept** | 13.0 | Sixth-gen capstone. See below. |

The prestige jet is the Tempest. The UK-led Tempest/GCAP programme (with Japan and Italy, and with development work under the Edgewing joint venture) is still in development, and no real performance figures are public. So in Afterburner it's presented clearly as a **"concept" aircraft with fictionalised stats**: extreme sensor range, a deep internal magazine and a smart loadout. Unlock it after researching any two Tier VII jets plus completing a **"Test Pilot" challenge chain**. That way it reads as an achievement, not just a grind. *Built, November 2026: once two Tier VII jets are researched, the Test Pilot trials open as five steps in order, each flown in a Tier VII jet in scored matches (finish 5 matches, shoot down 10 jets, defeat 5 missiles, win 3 matches, then finish a match without being shot down). Each step pays Credits and XP; the last makes the Tempest researchable. A Tier VII jet can also be researched with RP from another Tier VII jet, so the second one doesn't mean flying Tier VI again.* The same "concept" slot can later hold other sixth-gen designs as seasonal headline aircraft.

### 6.3 Making each jet feel different

Jets should play differently, not just have bigger numbers:

- F-5E: a light knife-fighter. Great roll and terrible radar. The perfect teacher.
- MiG-21: fast in a straight line, bleeds speed in turns. Teaches boom-and-zoom.
- F-14A: swing wings change the flight model with speed (built: the sweep follows Mach and changes lift and drag). Long-range missiles at its tier.
- MiG-29 vs F-16: a classic rivalry. The MiG has a better helmet-cued IR missile; the F-16 has better sustained turn and visibility.
- Su-27: huge fuel and missile load, and great at high AoA.
- Typhoon: climb and supercruise monster. Only the Typhoon, F-22A and Tempest stay supersonic on dry thrust.
- Su-35: thrust vectoring allows post-stall manoeuvres (a high-skill gimmick) that bleed energy fast. Built for the Su-30SM, Su-35S, F-22A, Su-57 and Tempest.
- F-22: stealth plus supercruise plus thrust vectoring. The best jet, and players must have earned it.

### 6.4 Naming policy (decided)

Use real names wherever allowed. Otherwise use semi-fictionalised names that are still instantly recognisable.

Real aircraft names, nicknames and designs can belong to manufacturers or programmes, and some of them police trademark use. In practice:

| Name element | Default | Example |
|---|---|---|
| **Military designation** (F-16C, MiG-29A, Su-27S) | Real, where allowed | `F-16C` |
| **Official nickname** (Raptor, Typhoon, Fighting Falcon) | Real if it's clear to use. If not, a semi-fictional nod | `F-22A Raptor`, or `F-22A "Raptor-X"` if needed |
| **Manufacturer names and logos** (Lockheed, Sukhoi, BAE) | **Never** in-game | none |
| **Unreleased or programme names** (Tempest / GCAP) | Semi-fictional concept name | `Tempest-class concept`, `"Project Tempus"` |

Every aircraft data module carries the name and its status, so a rename is a one-line change and we can audit the whole roster at once:

```lua
DisplayName = "F-16C Fighting Falcon",
NameStatus = "Real",            -- "Real" | "SemiFictional"
FallbackName = "F-16C \"Viper-C\"", -- used if a name ever has to change
```

The Eurofighter Typhoon is just "Typhoon" in game, because Eurofighter is the consortium that builds it (Will, November 2026). Every other name is a designation plus, at most, an official nickname.

A semi-fictional name should keep the designation shape and the silhouette, so players still know exactly what they're flying. Before launch, review every `"Real"` name against each manufacturer's published trademark guidance. *This is a design policy, not legal clearance.*

## 7. Player progression

### 7.1 Currencies

| Currency | Earned by | Spent on |
|---|---|---|
| **XP** (per account) | Everything you do in a match | Pilot Level. Unlocks modes, lineup slots and cosmetics. |
| **Research Points (RP)** (per aircraft) | Flying a jet. RP goes toward that branch's next jet. | Researching new aircraft and modules |
| **Credits** | Match rewards, challenges, level-ups, achievements, the login streak, mastery stars, squadron goals, the free spin | Buying researched jets, modules, jet skins (5,000 each) and starting a squadron |
| **Wings** (premium, Robux) | Bought with Robux; small amounts from the season pass, Rare and rarer achievements and the free spin | Cosmetics, jet skins, the season pass and weekly bundles. See §8. |

Use **two earnable currencies plus one premium currency**. More than that confuses players. Research needs RP *and* Credits so that playing and progressing go together.

### 7.2 Match rewards

Rewards come from **contribution**, not just kills, so support players and newer players still progress:

| Action | XP | RP | Credits |
|---|---|---|---|
| Kill | 100 | 100 | 150 |
| Assist (≥25% damage) | 50 | 50 | 75 |
| Missile defeated | 15 | 15 | 20 |
| Zone captured or held | 75 | 75 | 100 |
| Survive to the end | 50 | 50 | 50 |
| Finish the match | 20 | 20 | 30 |
| Win | +30% | +30% | +30% |
| First win of the day | ×2 | ×2 | ×2 |

Tier multiplier: higher-tier jets earn more RP and Credits per action (×1.0 at Tier I up to ×3.5 at Tier VIII) but cost more to buy, so the economy stays balanced. A tenth of every RP award also goes into a free RP pool that can be spent on any jet.

Against farming: kills on AI pilots pay half, and after 3 kills on the same victim in a match each further kill on them pays a quarter. A pilot with no input for the last 60 s gets no survival or win bonus.

### 7.3 Progression pacing (targets to tune)

Retuned November 2026 (Will): Tier II in 20–30 minutes, then scaling up, the way Roblox players expect. The
middle column is the economy simulation's modest player (tools/EconomySim: 1.5 kills a match, mostly AI, a
win 1 in 10, about 2 hours a day, climbing the tree); challenges, the streak, the season pass and squadron
rewards come on top, so most players are quicker.

| Milestone | Target playtime (free player) | Simulated |
|---|---|---|
| First new jet (Tier I sidegrade) | about 10 minutes | 11 min |
| Reach Tier II | 20–30 minutes | 22 min |
| Reach Tier III | about 1½ hours | 1.5 h |
| Reach Tier IV | about 4 hours | 3.7 h |
| Reach Tier V | about 9 hours | 8.6 h |
| Reach Tier VI | about 18 hours | 17 h |
| First Tier VII | about 30–35 hours | 31 h |
| Tempest (prestige) | about 50–60 hours, plus the Test Pilot trials | 57 h (owned) |

Early unlocks come fast to hook players. Late unlocks are aspirational. Paying players get there sooner but not instantly (see §8). These numbers should be revisited with real retention data. If day-7 retention is weak, speed up Tiers I–III first.

### 7.4 Aircraft modules (per-jet upgrades)

After buying a jet, players spend that jet's RP (and Credits) on **modules**. A stock jet should be about **85–90%** as good as a fully upgraded one, so it feels weaker but never helpless. Every jet has **18 modules** (Will, October 2026: more upgrades per jet), some needing another first; owned modules can be taken off and refitted:

- Engine: Engine I–III (thrust +3%, +3%, +2%), Afterburner Tuning, Fuel System (burns less), Extra Fuel
- Airframe: Airframe I–III (max G +0.25 each and faster roll), Aerodynamic Refinement (less drag), High-Lift Devices, Weight Reduction, Flight Controls (pitch and yaw rate)
- Avionics: Avionics I–II (radar range)
- Countermeasures: Countermeasures I–II (more flares and chaff)
- Guns: Ammunition Belt (more rounds)

Not built: weapons modules that unlock better missiles available to that airframe historically (for example, F-16A AIM-9L becomes AIM-9M), better lock speed and a missile-launch warning on older jets.

BR accounts for fully upgraded performance, so stock jets are briefly underpowered rather than upgraded jets being overpowered.

### 7.5 Pilot Level and mastery

- Pilot Level (1–100): XP-driven account level, with 250 Credits for every level. Unlocks: lineup slot 2 (level 5), slot 3 (level 15), titles, HUD colours (Pink, Blue, Violet), Credits and free RP milestones, and the level liveries Squadron Black (10), Ace Gold (25) and Legend Chrome (50), painted for every jet. Duels have no level gate: as the main mode they're open from the start.
- Duel ranks (§5.1): Silver to Ace each give a title ("Gold Duelist") and Credits the first time you reach them. The title shows after your name like any other.
- Aircraft Mastery (per jet, 1–5 stars): stars at 5, 15, 40, 80 and 150 kills in that jet. Each star pays Credits; from 2 stars the jet carries kill markers under the canopy, and 5 stars gives the "<jet> Ace" title. A mastery camo and a cockpit trinket come later with art (Will, November 2026). Rewards loyalty to favourite jets even after moving up.
- Achievements: 104 in all, shown by rarity (Common to Legendary) on the Career screen. 32 are one-offs, such as Ace in a Day (5 kills in one life), Guns Only, Notched (defeat a radar missile), Full Hangar and the secret Threading the Needle (fly under a bridge); these get Roblox badges, good for discoverability. The other 72 are levels of 13 ranked series (Hunter, Dogfighter, Champion, Promotion and so on), so the next one is always in reach. The Duelist series counts duels won: 1, 10, 50, 150 and 500. Every achievement pays by rarity (Will, November 2026): Common 1,000 Credits, Uncommon 2,500, Rare 5,000 + 10 Wings, Epic 10,000 + 25 Wings, Legendary 25,000 + 50 Wings.

### 7.6 Retention systems

- Daily challenges (3 per day, the same for everyone, rerollable once; VIP gets an extra reroll): "Get 2 kills with IR missiles", "Win a match in a Tier II jet". Reward Credits and XP, and all XP counts as season XP.
- Weekly challenges: 2 a week, bigger, new on Monday. They pay Credits and XP.
- Login streak: a 7-day week of Credits (free RP on day 7), repeating, with the title Regular at day 7 and Devoted plus 5,000 Credits at day 30. Never punish a missed day harshly: one missed day is forgiven, and a longer break goes back to the start of that week, never to day 1.
- Free spin: one per 20 minutes played, up to 3 saved, with a prize by rarity (Credits, a free module, Wings or a jet skin). Spins are earned only, never sold, because a paid random prize is gambling (§8.1).
- Seasons (about 8 weeks): a new headline jet, a map or mode, a season pass, and a ranked reset. *Season 1, "First Light", starts on Monday 9 November 2026 and runs 8 weeks: a 30-tier pass with a free and a premium track (§8.2).*
- Squadrons: player groups with a shared tag, weekly squadron goals and a leaderboard. This builds the social retention that keeps Roblox games alive. *Built, November 2026: 10,000 Credits to start one, up to 30 pilots, an owner, officers and members, and the tag before members' names. Members' scored matches earn points (1 per player shot down, 3 per win); at 100 points in a week every member can claim 5,000 Credits.*
- Leaderboards: kills and wins this week, season XP, all-time kills, squadrons this week and duel rating (pilots who've flown at least one duel). Only other players shot down count, not AI pilots (Will, November 2026). Duel ratings don't reset with the season yet.
- Scheduled events (such as a double XP weekend) start and stop on their own, and announcements reach every server at once.

## 8. Monetisation strategy

### 8.1 Principles

1. Never pay-to-win. No Robux item makes you deal more damage, turn harder or see further than a free player in an equivalent jet. This protects the core audience and the game's reputation.
2. Pay for style, speed and convenience. Cosmetics, time-savers within reason, and quality-of-life features.
3. No random paid rewards (loot boxes) at launch. Roblox's rules on paid random items require odds disclosure, and the policy and age-rating landscape keeps changing. Direct purchase is simpler, fairer and safer.
4. Respect younger players. No fake-urgency countdown pressure, clear prices, and every purchase shows exactly what you get.
5. Free players are the content. Matchmaking needs a full population, so the free experience must be genuinely good.

### 8.2 Revenue streams

| Stream | Roblox mechanism | Examples (indicative prices) | Notes |
|---|---|---|---|
| **Wings** | Developer Products | 150 Wings for 149 R$, 550 for 499 R$, 1,200 for 999 R$, 2,500 for 1,999 R$ | The premium currency, about one Wing per Robux. The smallest pack buys at least one jet skin. |
| **Cosmetics** | Bought with Wings | Camos 400 Wings (painted on every jet), contrail colours 200 (Tricolour 300), kill-marker styles 100 (Gold Stars 150), HUD themes 150, wing art 250, a jet's own skins 150 (or 5,000 Credits) | **The core earner.** Planes are huge on-screen billboards, so skins sell. Seasonal and limited-time camos create urgency without randomness. Wing art replaced nose art after Will's test (October 2026). Six camos so far: Arctic Splinter, Tiger Stripe, Midnight Digital, Arachnida, Galaxy, and VIP Gold with the VIP pass. A SHOP CAMOS button sits under each jet's skins. Cockpit trinkets aren't built. |
| **Season Pass** | Developer Product (each season), or Wings | 449 R$ or 900 Wings | Free track plus premium track, 30 tiers. Free: Credits or free RP every tier, a title at 15 and 100 Wings at 30. Premium: double the free Credits or RP, five season-only cosmetics (never sold, kept for good), a title at 30, and 800 Wings back (enough to *almost* buy the next pass when completed, which drives engagement). |
| **Premium jets** | Developer Product / Game Pass | 400–1,200 R$ | Unique variants (for example "F-4E Night Owl", "MiG-29 Display Team") **at the same BR and performance** as a researchable equivalent, plus a unique camo and a +25% RP bonus while flown. Gives a reason to buy without being stronger. *The rule is built (November 2026): a premium jet names its free jet and copies every stat, its tier and BR, or the game won't boot. None are on sale yet, and the RP bonus isn't built.* |
| **Tier Unlock** | Developer Product (one per tier) | Tier IV 299 R$, V 399 R$ | Skips the grind one tier at a time: always the tier directly above your highest owned jet, only Tiers IV and V (Tiers II and III come in under two hours of play, so they aren't sold: Will, November 2026). You pick two jets of that tier and they're researched and owned (stock, no modules); the rest of the tier is researched as usual. A time-saver, not power: the jets are the same ones everyone flies (Will, 30 October 2026). |
| **VIP Pilot** | Game Pass (one-off) | 399 R$ | +25% Credits permanently, a gold VIP tag by your name, an extra daily-challenge reroll, and the VIP Gold camo and contrails. Gentle boost, big perceived value. |
| **Boosters** | Developer Product | 2× RP for 1h: 75 R$; 2× Credits for 1h: 75 R$ | Time-limited; buying another adds an hour. Stacking is capped at 2× total, VIP included, so it can't trivialise the grind. |
| **Convenience** | Game Passes | Extra lineup slot (149 R$, a fourth slot), custom callsign (99 R$, through Roblox's text filter) | Quality of life only. Extra loadout presets (99 R$) aren't built. |
| **Bundles** | Developer Product, or Wings | Starter Bundle 99 R$; weekly bundle in Wings | See §8.4. |
| **Private servers** | Roblox Private Servers | ~100 R$/month | Squads practising, content creators. Good recurring income. |
| **Subscription (optional, later)** | Roblox experience subscriptions, if available | "Squadron Leader": monthly Wings stipend plus a monthly exclusive camo | Only once there's a steady flow of cosmetic content. |
| **Premium Payouts** | Automatic | none | Roblox pays based on Premium players' time in game. Long sessions and good retention earn this for free. |

### 8.3 What not to sell

- No directly purchasable Tier VI–VIII jets. They must be researched; only cosmetic variants of them can be sold. (Tier Unlocks stop at Tier V for the same reason.)
- No buying modules (performance upgrades) with Robux.
- No ammo, missile or countermeasure purchases.
- No "revive" or "skip respawn" in PvP.
- Optional, possibly later: **skip research with Wings** only for jets at or below your highest researched tier (catching up on side branches). Never for skipping up the ladder. Monitor community sentiment.

### 8.4 Store and UX

- The **Hangar** shows the jet in 3D with an equipped camo preview. "Try before you buy" lets players fly a cosmetic in Free Flight before purchase (not built yet).
- A **featured shop rotation** changes weekly with themed bundles. *Built, November 2026: six bundles (Display Team, Arctic Patrol, Tiger Meet, Night Raider, Black Widow, Deep Space), one featured each week from Monday 00:00 UTC, the same for everyone. A bundle costs Wings at 25% off the items you don't own yet, so owning some of it never means paying twice. Nothing in a bundle is random.*
- First-purchase offer: the **Starter Bundle** (99 R$, once per player): a camo you pick, a 3-hour Credits booster and 300 Wings, at a big discount. Converts players who've never paid.
- The top bar shows Credits, free RP and Wings as chips with a hover card (what it is, what it's for, how to get more); Wings + opens the Shop at the packs.
- All purchases go through `MarketplaceService.ProcessReceipt` with **idempotent receipt handling** saved in the DataStore. This is non-negotiable, because a lost purchase means a refund request and an angry player.

### 8.5 KPIs to watch

- D1 / D7 / D30 retention (targets: 30% / 12% / 5% for a solid Roblox title)
- Average session length (target: 25+ minutes)
- Payer conversion (typically 1–3% on Roblox) and ARPPU
- Season pass attach rate among active players
- Per-jet win rate and K/D (balance health, not revenue, but it drives retention)

## 9. Technical architecture

### 9.1 Folder layout

Roblox conventions apply: server logic in ServerScriptService, client logic in StarterPlayerScripts, shared code in ReplicatedStorage. Scripts live as files in the repo and Rojo syncs them into the place; the map, terrain and models live in the place file.

```
src/shared  → ReplicatedStorage.Shared      pure modules used by both sides: FlightModel, Ballistics, Guidance,
                                            DamageModel, Progression, Skins, AircraftData/, WeaponData/, Config/, Net/
src/server  → ServerScriptService.Server    Services/: Data, Aircraft, Combat, Missile, Sensor, Match, Matchmaking,
                                            Party, Progression, Challenge, Season, Shop, Pass, Spin, Leaderboard,
                                            Squadron, Config, Telemetry, Report, Feedback, AI, Drone, History,
                                            AntiCheat, Admin, Diagnostics and others
src/client  → StarterPlayerScripts.Client   Controllers/: Flight, Input, Camera, Cockpit, HUD, Weapon, Sensor, Scopes,
                                            ControlSurface, Effects, Audio, Menu, Tutorial and others; UI/ (React screens)
tests       → ServerStorage.Tests           TestRunner and *.spec modules
tools       → ServerStorage.Tools           Studio tools (AircraftAssembler, map builders, EconomySim); tools/blender has
                                            the Blender scripts that model and paint the jets
```

ReplicatedStorage.Assets holds the jet models, their skins and the effects. The full tree, file by file, is in [DEVELOPMENT.md §1.1](DEVELOPMENT.md#11-source-tree).

### 9.2 Networking model

The key decision: **client-authoritative flight, server-authoritative combat.**

- Flight: each jet is an unanchored assembly whose **network ownership is set to its pilot** (`SetNetworkOwner(player)`). The pilot's client runs `FlightModel` every `RunService.Heartbeat` (or `PreSimulation`) and drives the jet with **`LinearVelocity` + `AngularVelocity` constraints** (or `AlignOrientation`). This gives zero-latency, smooth control for the pilot, and Roblox replicates the motion to everyone else.
- Anti-cheat on flight: the server samples each jet's position and velocity several times a second and checks them against that aircraft's limits (max speed with margin, max acceleration, teleport distance). Violations get logged, then corrected, then kicked if repeated.
- Guns: the client fires a request (`origin`, `direction`, `timestamp`) and shows tracers immediately. The server checks the rate of fire and ammo, re-casts with **lag compensation** (rewinding target positions using a short history buffer, about 250 ms max), and applies damage. Hit markers confirm from the server.
- Missiles: **simulated on the server** (they're few, slow-ish and must be fair). The server replicates missile state at about 10–20 Hz through a single RemoteEvent, and clients interpolate smoothly between updates. Countermeasure spoofing is rolled on the server.
- Remotes: keep the number of RemoteEvents small and typed. Validate *every* argument on the server (types, ranges, rate limits). Never trust a client-sent damage value.

### 9.3 Data and saving

- Use **ProfileStore** (the successor to ProfileService, a widely used community module) or an equivalent with **session locking**, so the same account can't double-load across servers and dupe currency.
- The current schema is version 1. Version it from day one; migrations run on every load. An example save:

```lua
{
	Version = 1,
	PilotXP = 0, PilotLevel = 1, TotalXP = 0,
	Credits = 500, Wings = 0, FreeRP = 0,
	Aircraft = {
		F5E = {
			Owned = true, Researched = true, RP = 0,
			Modules = { Engine1 = true, Airframe1 = false }, -- true = fitted, false = owned but taken off
			Mastery = 0,
			Camo = "Ghost",            -- the skin in use
			Skins = { Desert = true }, -- bought skins (the default skin is always owned)
		},
	},
	Lineup = { "F5E" },
	Cosmetics = { Owned = {}, Equipped = {} }, -- Wings cosmetics: [id] = true; [kind] = id
	Passes = {}, -- cache only; always re-verify with UserOwnsGamePassAsync
	Boosters = { Credits = 0, RP = 0 }, -- unix time each booster runs out
	ProcessedReceipts = {}, -- receipt IDs for idempotent ProcessReceipt (bounded list)
	Settings = { ControlScheme = "MouseAim", Sensitivity = 1.0, Units = "Imperial" },
	Stats = { Kills = 0, AIKills = 0, Deaths = 0, Matches = 0, Wins = 0, Assists = 0 }, -- and more lifetime counts
	Season = { Id = 1, XP = 0, Premium = false, FreeClaimed = 0, PremiumClaimed = 0 },
	Flags = { AllUnlocked = true }, -- only for the game's owner: every jet, module, skin and lineup slot
}
```

- The real template has more: challenges, achievements, titles, the login streak, free spins, the squadron, the Test Pilot trials and this week's leaderboard counts. `src/shared/PlayerData.luau` has every field.
- Save on leave, on a periodic autosave (every few minutes) and right after any purchase.

### 9.4 Server topology

- Lobby place: hangar, shop, tech tree and matchmaking queue. Players spawn here.
- Battle place(s): the same universe, a separate place per map. The lobby sends players to a **reserved server** with `TeleportService`, carrying match settings in teleport data. The battle server re-reads player data from the DataStore (never trust teleport data for currency).
- Queues: `MemoryStoreService` sorted maps keyed by BR band and mode. A queue worker forms matches and fills empty slots with **AI pilots** after a timeout, so matches start quickly even at low population.

For the very first playable build, a **single place** is fine: everyone in one server, picking jets from a simple menu. Split into lobby and battle places once the core loop is fun.

*Built, October 2026: every server works out its role (lobby, match or training) for itself. Matches run on reserved servers of the lobby place until a separate battle place id is set, so a second place is optional. Training servers are private servers with the lessons, Vs AI and any jet. It waits on the live test on the test experience.*

### 9.5 Performance budget

- Target: 60 FPS on mid PCs, 30+ FPS on a three-year-old phone, with 16 jets plus 20 missiles active.
- Jet models: built in Blender by a generator measured from reference drawings, about 35 MeshParts and 5,000–12,000 triangles per jet, with the control surfaces hinged on Motor6Ds and PBR skins as SurfaceAppearances. See the [aircraft art pipeline](art/AIRCRAFT_PIPELINE.md). Each jet has one collision hull (a simple box), and its visual parts have `CanCollide`, `CanTouch` and `CanQuery` off.
- Effects: use pooled `Beam`s and `Trail`s and recycle explosion emitters. Use `ParticleEmitter:Emit()` bursts rather than always-on emitters.
- Remote bandwidth: missile updates batched into one packet per tick. Hit confirmations only.
- Streaming: enable `StreamingEnabled`, and make jets **persistent models** (`ModelStreamingMode = Persistent`) so far-away enemies still exist for radar.

## 10. Build plan: steps to follow

Each phase ends with a **playable build** and a clear exit test. Don't start the next phase until the current one is fun.

### Phase 0: Foundation (week 1)
- [x] Set up the folder layout (§9.1), Config module and a boot order for services and controllers.
- [x] Tooling: a Git repo on GitHub, laid out for Rojo (`default.project.json` → `src/`).
- [x] Install Rojo (CLI plus the Studio plugin) and confirm `rojo serve` syncs into the place.
- [x] Add utility modules (Signal, Trove, Spring, RingBuffer, Pool, Validate) and the typed Net layer.
- [x] Build a greybox map: a test range with a runway, slalom pylons and height towers (`Workspace.TestRange`).

Exit test: the place boots with no errors and the services log that they started. *Passed. Task-level detail is in [PROGRESS.md](PROGRESS.md).*

### Phase 1: Flight model prototype (weeks 2–3) ← **the most important phase**
- [x] Greybox jet (box fuselage plus wings) with network ownership given to the pilot.
- [x] `FlightModel` module: thrust, lift, drag, gravity, AoA, G-limit, stall.
- [x] `FlightController`: Direct controls first (keyboard and mouse), then Mouse Aim.
- [x] Cockpit camera with free look (a greybox cockpit is fine), plus a debug chase camera. Minimal HUD (speed, altitude, G, throttle).
- [x] Two contrasting stat blocks (F-5E, MiG-21) to prove the data-driven approach.
- [x] A tuning panel (a dev-only GUI) to tweak coefficients live.

Exit test: flying is fun on its own, with no weapons. Turning bleeds speed, diving gains it, and the two jets feel different. If this isn't fun, nothing else matters, so iterate here. *Signed off 2026-10-26. Details in [PROGRESS.md](PROGRESS.md).*

### Phase 2: Guns and damage (week 4)
- [x] Raycast bullets with travel time, tracers and a lead pipper.
- [x] Server hit validation with lag compensation, and a component damage model.
- [x] Death, respawn and a kill feed.
- [x] Two players in a Studio test server (Test → Clients and Servers) dogfighting with guns.

Exit test: a 1v1 guns-only fight is tense and the winner feels skill-based. *Signed off 2026-10-26. Details in [PROGRESS.md](PROGRESS.md).*

### Phase 3: Missiles, sensors and countermeasures (weeks 5–6)
- [x] Server-side missile sim (proportional navigation, motor burn, drag).
- [x] IR lock with seeker tone. Flares.
- [x] Radar cone, RWR, SARH missiles, chaff and notching.
- [x] Missile-launch warning and an incoming-missile indicator.

Exit test: a fired missile is dangerous but defeatable, and players can learn *why* they died. *Signed off 2026-10-26. Details in [PROGRESS.md](PROGRESS.md).*

### Phase 4: Match loop, MVP (weeks 7–8)
- [x] Free-for-all mode: spawn in, a score limit and timer, an end screen (rewards arrive with progression in Phase 5).
- [x] Simple AI pilots (pursuit plus basic evasion) to fill servers.
- [x] A first real map ("Strait"), at least a blockout version.
- [x] Tutorial flight (lessons 1–3).
- [x] Mobile touch controls (playable, not polished).

Exit test: 8 players and bots have a full match. Run an internal playtest with friends and write down every complaint. *Signed off 2026-10-26 on solo and 24-bot matches; the multiplayer playtest is still to run. Details in [PROGRESS.md](PROGRESS.md).*

### Phase 5: Progression and saving (weeks 9–10)
- [x] DataService with ProfileStore and the schema (§9.3). Saves persist on the test experience.
- [x] XP, RP, Credits and match rewards (§7.2).
- [x] Hangar UI and a tech tree for Tiers I–III (8 jets).
- [x] Modules (upgrades) and lineup selection.
- [x] Battle rating matchmaking: a basic version inside a single place first.

Exit test: a fresh account can play from F-5E to a Tier II jet, data survives rejoins, and there's no way to dupe currency. *Signed off 2026-10-26; the two-servers session-lock check is carried to the first multiplayer playtest. Details in [PROGRESS.md](PROGRESS.md).*

### Phase 6: Content and polish for a soft launch (weeks 11–14)
- [x] Real jet models for all launch aircraft (about 15). Tiers I–IV plus one or two tasters. *Went further: all 27 jets, Tiers I–VIII, have final models, moving control surfaces, their own cockpits and skins (October 2026).*
- [x] Team Deathmatch and Air Superiority modes. *Guns Only came too (§5.1).*
- [ ] Lobby and battle place split, with reserved-server matchmaking. *Built (§5.2, §9.4), with parties; to tick after the live test on the test experience.*
- [x] Audio pass (engine, RWR, missiles, radio barks), plus effects (vapour, contrails, explosions).
- [x] Settings menu, controller support and key rebinding. *Plus accessibility options and graphics quality settings.*
- [ ] Daily challenges and badges. *Daily and weekly challenges, the login streak, achievements, mastery and the free spin are built. Badges are made on the live experience at launch.*
- [x] Analytics events (`AnalyticsService` funnels: tutorial complete, first kill, first research).

Still to do in this phase: mobile streaming and performance passes, and the release rollback drill. Task-level status is in [PROGRESS.md](PROGRESS.md).

Exit test: a soft launch to a small audience. Measure D1/D7 retention and session length, and fix the biggest drop-off.

### Phase 7: Monetisation (weeks 15–16)
- [x] Wings currency, `ProcessReceipt` with idempotency, and a shop UI.
- [x] The first cosmetics batch (about 20 camos, trails and kill markers). *29 items: six camos, seven contrails, five kill-marker styles, five HUD themes and six wing-art decals, including the VIP and Season 1 ones. Jet skins sell for Credits or Wings.*
- [x] VIP game pass, boosters and the starter bundle. *Plus the Extra Lineup Slot and Custom Callsign passes, Wings packs, Tier Unlocks (IV and V) and the weekly bundle.*
- [x] Season 1 pass with a free and a premium track. *Season 1, "First Light", starts on 9 November 2026.*

Exit test: every purchase path is tested in Studio with test purchases, and a rejoin shows the item granted exactly once.

### Phase 8: Launch and live ops (week 17+)
- [ ] Public launch. Thumbnails and an icon (a jet mid-turn with vapour trails sells the game). First thumbnail: [`docs/art/marketing/thumbnail.jpg`](art/marketing/thumbnail.jpg), uploaded at launch (release checklist step 5).
- [ ] Weekly balance patches from BR data.
- [ ] Season cadence: new jets, maps and modes every about 8 weeks. *Tiers V–VII came early, in October 2026, so seasons start from the full roster.*
- [x] Squadrons, Ranked Duels, BVR mode and PvE missions as post-launch content. *Squadrons are built (November 2026), with parties, leaderboards, scheduled events and announcements. Built early too, in November 2026: Duels (ranked and casual, now the main mode), BVR Battles, Strike Escort and PvE Waves, with the B-1B as the AI bomber (§5.1). All need the live multiplayer test; a seasonal reset for duel ratings is still to do.*
- [x] Tempest prestige unlock as a headline update once Tier VII is live and balanced. *Built early: the Test Pilot trials (§6.2), November 2026.*

Timeline note: the weeks assume one dedicated developer with AI assistance. Phases 1 and 3 are where time overruns are most likely, and that's fine. They're the game.

## 11. Risks and open questions

| Risk | Impact | Mitigation |
|---|---|---|
| Flight model isn't fun, or feels floaty on Roblox | Critical | Phase 1 is dedicated to it, with a live tuning panel and early playtests. Mouse Aim smooths out rough edges. |
| Network jitter makes dogfights feel unfair | High | Client-owned flight, server lag compensation, and interpolated missiles. Test with simulated latency in Studio. |
| Exploiters (speed hacks, teleporting) | High | Server sanity checks on every jet, server-authoritative damage and missiles, and rate-limited remotes. |
| Low player counts split across BR bands | High | 6-pilot matches, AI filler pilots after 30 s, a BR spread and mode choice that loosen the longer a player waits, and fewer modes at launch. Duels need only two players, and an AI duelist steps in after 45 s. |
| Mobile performance and controls | Medium–High | Low-poly assets, a strict performance budget, and touch controls built in Phase 4 rather than at the end. |
| Long grind drives players away | Medium | Fast early tiers, contribution-based rewards, and data-driven pacing adjustments. |
| Trademark complaints over real aircraft names | Medium | Data-driven display names (one-line rename), no manufacturer logos, and fictionalised "concept" jets. |
| Scope creep (carriers, ground attack, helicopters...) | Medium | Air-to-air only until after launch. Everything else goes to a backlog. |

### Decision log

| # | Question | Decision |
|---|---|---|
| 1 | Tooling | Decided. **Git + GitHub** ([wgw0/afterburner](https://github.com/wgw0/afterburner)), with the project laid out for **Rojo** so scripts live as files. |
| 2 | Aircraft names | Decided. **Real names wherever allowed**, otherwise semi-fictionalised but recognisable. See §6.4. |
| 3 | Respawn model | **Deferred.** Decide after playtesting the Phase 4 match loop. Candidates: unlimited respawns on a timer, or one life per jet in the lineup. Every mode uses a 5 s respawn timer meanwhile. |
| 4 | Camera | Decided. **Cockpit view first**, with third person as a fallback if the cockpit proves too hard for general players. See §2.4. |
| 5 | Ground targets | Decided. **Not for now.** Air-to-air only until after launch. Strike Escort keeps to this: the bombers are the targets, and a bomber that reaches the airbase simply scores. |
| 6 | Match size | Decided. **6 pilots a match** (Will, October 2026), with AI in empty seats. See §5.1. |
| 7 | Pacing | Decided. **Tier II in 20–30 minutes**, then scaling up to the Tempest at about 50–60 hours (Will, November 2026). See §7.3. |
| 8 | Tier Unlocks | Decided. **Tiers IV and V only** (Will, November 2026). Tiers II and III come in under two hours of play. See §8.2. |
| 9 | Reloading | Decided. **Stores refill on a timer** when they run dry (Will, October 2026). Not realistic, on purpose. See §4.1. |
| 10 | Main mode | Decided. **Duels are the main mode** (Will, November 2026): first in the mode picker and the default for PLAY. See §5.1. |
| 11 | Duel format | Decided. **Rounds**: best of five, starts in opposite corners heading past each other (Will, 3 November 2026; head-on before), one life a round, with a 2 s grace so trades are drawn rounds (Will, November 2026). See §5.1. |
| 12 | Duel ladder | Decided. **Ranked and Casual**: Ranked moves an Elo rating with six ranks; Casual moves nothing (Will, November 2026). See §5.1. |
| 13 | Nobody to duel | Decided. **An AI duelist after 45 s**, sized to the player's rating and unranked (Will, November 2026). See §5.2. |
| 14 | Strike bomber | Decided. **A real bomber model**, the B-1B Lancer, flown only by AI, rather than a fighter standing in (Will, November 2026). See §5.1. |
