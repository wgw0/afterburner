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
- 15 launch jets (27 airframes in the tech tree) with final models, cockpits and skins, including
  level-reward liveries (Squadron Black, Ace Gold, Legend Chrome).
- Team Deathmatch and Air Superiority (capture zones), alongside Dogfight and Free Flight.
- Matchmaking across servers: lobby servers, a queue for any mode or a chosen one, 6-pilot match servers
  filled with AI pilots after 30 s, and training servers.
- Lessons 4–6 and a first-session flow: new pilots start in training, and can leave it at any time.
- The "Strait" map, finished: materials, props, lighting, bridges.
- Daily and weekly challenges with rerolls, 21 achievements by rarity, a career screen with the level track,
  and titles.
- A daily login streak with weekly rewards.
- Aircraft mastery: 1–5 stars per jet from kills in it, with Credits, kill markers under the canopy and a
  "<jet> Ace" title at 5 stars.
- Settings: controls, key and gamepad rebinding, display, audio levels, and accessibility (subtitles, HUD
  colours, menu size, reduce flashing, shapes on the scopes).
- Radio calls and warnings with subtitles, music, and menu sounds.
- Back to the hangar from the air (hold H).
- Live config: reward multipliers, an event banner, a message of the day and battle ratings, changed on live
  servers without an update.
- Report a cheater: an in-game report with the pilot's anti-cheat data attached for review.
- Analytics: onboarding funnel, progression, economy, combat and balance events.
- The game's version in Settings.

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
