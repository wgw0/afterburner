# Roster art status

Where each jet on the roster (DESIGN §6.2) stands in the [art pipeline](AIRCRAFT_PIPELINE.md): its exterior model, skins and cockpit. **The whole roster is done:** all 27 jets have flight data in `src/shared/AircraftData/`, a model, four skins and a cockpit, are installed in the place, and have been spawned in play. The Tech Tree runs from Tier I to Tier VIII.

The Blender sources and outputs are in `tools/blender/out/`, in Git LFS (`.fbx`, `.blend` and `.png`). Reference images are in `docs/art/reference/<Id>/`, kept out of git (see each folder's `SOURCES.md`).

| Tier | Jet | Id | Skins (default first) | Cockpit | In game |
|---|---|---|---|---|---|
| I | F-5E Tiger II | `F5E` | Ghost, Desert, Pacific, Lizard | Done | Installed; flown hands-on |
| I | MiG-21bis | `MiG21bis` | Silver, Grey, Tactical | Done | Installed; flown hands-on |
| I | Mirage IIIE | `MirageIII` | Tactical, Silver, Desert, Grey | Done | Installed; spawned in play |
| II | Mirage F1C | `MirageF1` | Interceptor, Tactical, Desert, Grey | Done | Installed; flown hands-on |
| II | F-4E Phantom II | `F4E` | SEA, HillGray, EuroOne, Desert | Done | Installed; spawned in play |
| II | MiG-23MLD | `MiG23MLD` | Tactical, TwoTone, Grey, Desert | Done | Installed; wings sweep in flight (FLT-08) |
| III | F-16A Fighting Falcon | `F16A` | Falcon, Blue, Desert, Euro | Done | Installed; spawned in play |
| III | MiG-29A | `MiG29A` | Grey, Euro, BlueGrey, Desert | Done | Installed; spawned in play |
| III | F-14A Tomcat | `F14A` | Navy, Gull, Ghost, Desert | Done | Installed; model fixed and skins repainted (October 2026); wings sweep in flight |
| III | Mirage 2000C | `Mirage2000C` | AirDefence, Grey, Tactical, Desert | Done | Installed; spawned and flown in play |
| IV | F-15C Eagle | `F15C` | ModEagle, Blue, Aggressor, Desert | Done | Installed; spawned and flown in play |
| IV | F/A-18C Hornet | `FA18C` | Navy, Gull, Adversary, Ghost | Done | Installed; spawned and flown in play |
| IV | Su-27S | `Su27S` | Flanker, Grey, Naval, Desert | Done | Installed; spawned and flown in play |
| IV | Tornado F3 | `TornadoF3` | AirDefence, DarkGrey, Splinter, Desert | Done | Installed; wings sweep in flight |
| V | F-16C Fighting Falcon | `F16C` | Viper, Ghost, Arctic, Night | Done | Installed; spawned and flown in play |
| V | F-15E Strike Eagle | `F15E` | Strike, Ghost, Splinter, Desert | Done | Installed; spawned and flown in play |
| V | Su-30SM | `Su30SM` | VKS, Blue, Naval, Desert | Done | Installed; spawned and flown in play |
| V | MiG-29SMT | `MiG29SMT` | VKS, Blue, Splinter, Desert | Done | Installed; spawned and flown in play |
| V | JAS 39C Gripen | `GripenC` | Grey, DarkGrey, Splinter, Arctic | Done | Installed; spawned and flown in play |
| VI | F/A-18E Super Hornet | `FA18E` | Navy, CAG, Adversary, Ghost | Done | Installed; spawned in play |
| VI | Su-35S | `Su35S` | VKS, Dark, Flanker, Desert | Done | Installed; spawned in play |
| VI | Typhoon | `Typhoon` | AirDefence, TwoTone, DarkGrey, Desert | Done | Installed; wing raised (October 2026) |
| VI | Rafale C | `RafaleC` | AirDefence, TwoTone, DarkGrey, Desert | Done | Installed; wing and canard roots fixed (October 2026) |
| VII | F-22A Raptor | `F22A` | AirDominance, Dark, Ghost, Splinter | Done | Installed; nose fixed (October 2026) |
| VII | F-35A Lightning II | `F35A` | Stealth, Dark, Ghost, Aggressor | Done | Installed; tail booms added, nose fixed (October 2026) |
| VII | Su-57 | `Su57` | VKS, Dark, Grey, Desert | Done | Installed; spawned in play |
| VIII | Tempest-class concept | `Tempest` | Shadow, Storm, Night, Demonstrator | Done | Installed; spawned in play |

The skins are listed in `Shared.Config.Skins`; the default comes with the jet, the others cost 5,000 Credits or 150 Wings. On top of these, every jet has been painted with:
- the three level skins (`Config/LevelRewards`): Squadron Black (level 10), Ace Gold (25) and Legend Chrome (50);
- the six camos (`Config/Cosmetics`, kind `Camo`), which paint every jet you fly once bought: VIP Gold (with the VIP Pilot pass), Arctic Splinter, Tiger Stripe, Midnight Digital, Arachnida and Galaxy (400 Wings each).

All of them live in `ReplicatedStorage.Assets.Skins.<Id>.<SkinId>` (art pipeline §2 and §9).

The jet names follow `DisplayName` in each airframe's data. No manufacturer names are used in game ("Typhoon", not "Eurofighter Typhoon").

## Files per jet

Every jet has the same set of files in `tools/blender/out/`:
- Model: `<Id>_base.blend` and `<Id>_base.fbx`, with the manifest in `tools/Manifests/<Id>.luau`
- Skins: `textures/<Id>_<Skin>_<Set>_<Map>.png` (sets Body, Wings and Details; maps Color, Normal, Roughness and Metalness)
- Cockpit: `<Id>_cockpit.fbx` and `<Id>_Cockpit_{Color,Normal,Roughness,Metalness}.png`, with the manifest in `tools/Manifests/Cockpits/<Id>.luau`
- Previews: `<Id>_{side,top,front,threequarter}.png`, `<Id>_overlay_{side,top}.png`, `textures/<Id>_<Skin>_paint_*.png` and `<Id>_cockpit_*.png`

How a jet is installed in Studio (import, `AircraftAssembler.install`, the skin SurfaceAppearances, `installCockpit`) is in the art pipeline, §4 and §7. To replace a jet's art, follow the same steps: the model it replaces moves to `ServerStorage.ReplacedModels`.

## Things to know per jet

- **Single and twin nozzles:** the assembler lines a single-nozzle import up on `Nozzle`, and twin nozzles on `NozzleL` and `NozzleR`.
- **Elevons and tailerons:** the Mirage IIIE and Mirage 2000C have elevons on the `ElevonL` and `ElevonR` controls. The MiG-23MLD, F-16A, MiG-29A and every later jet with all-moving tailplanes use the same controls for them, so they move together for pitch and in opposite directions for roll. Canards (Su-30SM, Gripen C, Typhoon, Rafale C) are on the elevon controls too.
- **F-4E:** the outer wing panels and outer leading-edge flaps are separate parts (`WingOuterL`, `WingOuterR`, `LEFlapOuterL`, `LEFlapOuterR`).
- **Twin fins:** both rudders are on the `Rudder` control (MiG-29A and the other twin-fin jets).
- **Swing wings:** the MiG-23MLD, F-14A and Tornado F3 wing parts have their origin on the pivot, and the game sweeps them with Mach (FLT-08, DEVELOPMENT.md §6.4).
- **The cockpit well:** the F-5E's and MiG-21bis's skins were painted before the generators opened a cockpit well, so the painters only darken the well when a skin is next repainted (art pipeline §7). The same two jets still have the old dorsal-spine keel under the fuselage (§8).
