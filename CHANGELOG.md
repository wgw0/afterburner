# Changelog

What changed in each release of Afterburner. The newest release is at the top. Versions follow
[semantic versioning](https://semver.org): `0.x` until launch, then `1.0.0`. The number in
`src/shared/Version.luau` must have a section here (CI checks this). How to cut a release is in
[docs/RELEASE.md](docs/RELEASE.md).

A section headed `Unreleased` is a release still being built. `scripts/release.sh` replaces that word with
the release date when the release is tagged.

## [0.6.0] - Unreleased

The soft-launch build: the first version published to the live experience.

### Added
- The whole roster: 27 jets across eight tiers, from the F-5E to the Tempest-class concept, each with a final
  model, moving control surfaces, its own cockpit and skins, plus the level-reward liveries (Squadron Black,
  Ace Gold, Legend Chrome).
- Swing wings on the F-14A, supercruise on the Typhoon, F-22A and Tempest, and thrust vectoring with
  post-stall manoeuvres on the Su-30SM, Su-35S, F-22A, Su-57 and Tempest.
- Stealth on the Tier VII jets and the Tempest: hardest to see head-on, and the weapon bays give a stealth
  jet away for a few seconds after it fires.
- Data link: Tier V+ jets share radar contacts with teammates.
- Team Deathmatch, Air Superiority (capture zones) and Guns Only (no missiles, four times the rounds),
  alongside Dogfight and Free Flight.
- Matchmaking across servers: lobby servers, a queue for any mode or a chosen one by the jet you click PLAY
  with, 6-pilot matches filled with AI pilots after 30 s, and training servers.
- Parties of up to 3: queue together, fly on the same team and come home together.
- Lessons 4–6 and a first-session flow: new pilots get a welcome window and start in training, and can leave
  it at any time.
- Vs AI on training servers, with bots flying jets at your jet's level, in normal or Guns Only matches.
- The "Strait" map, finished: materials, props, lighting, two bridges (fly under one for a secret
  achievement), the world edge and a "Pull up" warning.
- 18 upgrade modules per jet.
- Reloading: an empty gun, missile type, flares or chaff refill after a short timer, with a bar on the HUD.
- Hit markers and a hit sound for missile hits, and a kill-confirm sound.
- The scoreboard shows each pilot's jet and username, and a message says who shot you down.
- Missiles shown on each jet's hardpoints, disappearing as each type runs out, and missile models in flight.
- The HUD changes with the cockpit era.
- Radar lock feedback: the HUD says why a lock failed or broke. A zooming radar and situation display.
- Advanced heat-seekers: helmet-cued shots, and imaging seekers that only bursts of flares can fool.
- Gunsights by tier: a lead-computing pipper that follows a turning target from Tier III, and the
  bullet-stream funnel from Tier V.
- A damage diagram on the HUD: which parts of your jet are hit, and how badly.
- Track-while-scan radar on Tier IV+ jets: fire active radar missiles at a tracked contact without a lock,
  so the target gets no lock warning.
- Long-range radar missiles (Tier IV+) loft: they climb on long shots and dive onto the target, reaching
  further.
- Flare programmes on Tier V+ jets: one press fires a short burst, and an optional automatic burst as a
  heat-seeker closes in.
- Daily and weekly challenges with rerolls, a career screen with the level track, and titles.
- 99 achievements by rarity, each paying Credits (and Wings from Rare up): 32 one-offs and 12 ranked series,
  such as Hunter, Champion and Promotion, so the next one is always in reach.
- A daily login streak with weekly rewards.
- A free spin every 20 minutes played (up to 3 saved), with prizes by rarity. Spins are earned only, never
  sold.
- Aircraft mastery: 1–5 stars per jet from kills in it, with Credits, kill markers under the canopy and a
  "<jet> Ace" title at 5 stars.
- The Test Pilot trials: research two Tier VII jets, then five trials in them unlock the Tempest.
- Squadrons: a tag before your name, owners, officers and members, a weekly goal worth 5,000 Credits each,
  and a squadron leaderboard.
- Leaderboards: kills and wins this week, season XP and all-time kills. Only other players count, not AI
  pilots.
- The season pass: Season 1, "First Light", starts on 9 November 2026. 30 tiers with a free and a premium
  track; the premium track costs Robux or Wings and has season-only cosmetics.
- Wings, the premium currency, in four packs, shown in the top bar with the other currencies.
- The Shop: camos painted on every jet (Arctic Splinter, Tiger Stripe, Midnight Digital, Arachnida, Galaxy),
  contrail colours with display smoke, kill-marker styles, HUD themes and wing art, all for Wings. Each jet's
  own skins can be bought with Credits or Wings, and a SHOP CAMOS button sits under them.
- The Starter Bundle (once per player: a camo you pick, a 3-hour Credits booster and 300 Wings) and a
  themed weekly bundle at 25% off.
- Tier Unlocks for Tiers IV and V: two jets of the tier above your highest, researched and owned.
- 2x Credits and 2x RP boosters, an hour each.
- Game passes: VIP Pilot (+25% Credits, a gold VIP tag, VIP Gold camo and contrails, an extra reroll),
  Extra Lineup Slot and Custom Callsign.
- Settings: controls, key and gamepad rebinding, display, audio levels, and accessibility (subtitles, HUD
  colours, menu size, reduce flashing, shapes on the scopes).
- Graphics settings: effects quality (Auto / Low / Medium / High), contrails and wingtip vapour on or off.
- Radio calls and voice warnings with subtitles, music, and menu sounds.
- Back to the hangar from the air (hold H).
- Live events: an event banner, a message of the day, scheduled events such as double XP weekends, and
  announcements to every server.
- Report a cheater: an in-game report with the pilot's anti-cheat data attached for review.
- Report a bug: a Bug / Lag / Idea / Other window that sends your device details with it.
- The game's version in Settings.

### Changed
- Faster progression: Tier II in about 22 minutes, then scaling up to the Tempest in about 57 hours.
- Matchmaking loosens the longer you wait: the BR spread widens to 3.0, and after two minutes you'll take any
  mode.
- The kill feed is CS:GO style, with your own lines outlined in red.
- Missiles in flight are drawn at three times their real length, so you can see them.
- Shorter missile and radar ranges, to suit the map's size.
- The world is at 1 stud = 1 m, so the map loads in seconds rather than minutes.
- The Eurofighter Typhoon is now just the Typhoon.

## 0.1.0 – 0.5.0 - Internal builds

Not published; built and played in the test experience only, one version per development phase.

- **0.5 Progression and saving:** saves (ProfileStore), research, purchases, lineups, upgrade modules, pilot
  levels, the hangar, tech tree, aircraft detail and results screens, AI missile use and difficulty,
  battle-rating matching, admin commands.
- **0.4 Match loop:** Free Flight and Dogfight, scoreboard and results, AI pilots, lessons 1–3, gamepad and
  touch controls, warnings, movement anti-cheat, the first "Strait" blockout.
- **0.3 Missiles, sensors and countermeasures:** IR, SARH and ARH missiles, radar and RWR, locks, notching,
  flares and chaff.
- **0.2 Guns and damage:** server-checked gunfire with lag compensation, component damage, crashes, kill credit.
- **0.1 Flight model:** the flight model, mouse aim, cockpit and chase cameras, the flight HUD.
