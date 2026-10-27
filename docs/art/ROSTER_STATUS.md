# Roster art status

Where each jet on the roster (DESIGN §6.2) stands in the [art pipeline](AIRCRAFT_PIPELINE.md): its exterior model, skins and cockpit. Built files are in the art branch's worktree under `tools/blender/out/`, which is kept out of git. The **Studio** column lists what's left to do in Studio: import, upload textures, add skin entries, play test.

Jets without flight data in `src/shared/AircraftData/` get the art only, under the Id in this table. Their flight data is separate design work.

| Tier | Jet | Id | Flight data | Branch | Exterior | Skins | Cockpit | Studio |
|---|---|---|---|---|---|---|---|---|
| I | F-5E Tiger II | `F5E` | Yes | master; `art/cockpits` | Done; cockpit well added | Ghost, Desert, Pacific, Lizard (unchanged) | Done | Re-import the exterior; import and install the cockpit |
| I | MiG-21bis | `MiG21bis` | Yes | master; `art/cockpits` | Done; cockpit well added | Silver, Grey, Tactical (unchanged) | Done | Re-import the exterior; import and install the cockpit |
| I | Mirage IIIE | `MirageIII` | Yes | | | | | |
| II | Mirage F1 | `MirageF1` | Yes | | | | | |
| II | F-4E Phantom II | `F4E` | Yes | | | | | |
| II | MiG-23MLD | `MiG23MLD` | Yes | | | | | |
| III | F-16A | `F16A` | Yes | | | | | |
| III | MiG-29A | `MiG29A` | Yes | | | | | |
| III | F-14A Tomcat | `F14A` | No | | | | | |
| III | Mirage 2000C | `Mirage2000C` | No | | | | | |
| IV | F-15C Eagle | `F15C` | No | | | | | |
| IV | F/A-18C | `FA18C` | No | | | | | |
| IV | Su-27S | `Su27S` | No | | | | | |
| IV | Tornado F3 | `TornadoF3` | No | | | | | |
| V | F-16C Block 50 | `F16C` | No | | | | | |
| V | F-15E | `F15E` | No | | | | | |
| V | Su-30SM | `Su30SM` | No | | | | | |
| V | MiG-29SMT | `MiG29SMT` | No | | | | | |
| V | Gripen C | `GripenC` | No | | | | | |
| VI | F/A-18E Super Hornet | `FA18E` | No | | | | | |
| VI | Su-35S | `Su35S` | No | | | | | |
| VI | Eurofighter Typhoon | `Typhoon` | No | | | | | |
| VI | Rafale C | `RafaleC` | No | | | | | |
| VII | F-22A Raptor | `F22A` | No | | | | | |
| VII | F-35A | `F35A` | No | | | | | |
| VII | Su-57 | `Su57` | No | | | | | |
| VIII | Tempest-class concept | `Tempest` | No | | | | | |

## Cockpit system (`art/cockpits`)

The cockpit interiors and the code that shows them (art pipeline §7). The new code is in `tools/AircraftAssembler.luau` (`installCockpit`) and `src/client/Controllers/CockpitController.luau`. Jets without a cockpit model still get the greybox kit, so the branch can be merged before any cockpit is installed.

Files in `tools/blender/out/` (absolute paths are in the hand-over report):

| Jet | Exterior (re-import) | Cockpit | Cockpit textures | Previews |
|---|---|---|---|---|
| F-5E | `F5E_base.fbx` | `F5E_cockpit.fbx` | `F5E_Cockpit_{Color,Normal,Roughness,Metalness}.png` | `F5E_cockpit_{ahead,panel,left,outside}.png` |
| MiG-21bis | `MiG21bis_base.fbx` | `MiG21bis_cockpit.fbx` | `MiG21bis_Cockpit_{Color,Normal,Roughness,Metalness}.png` | `MiG21bis_cockpit_{ahead,panel,left,outside}.png` |

To do in Studio, for each jet:
1. Re-import `<Id>_base.fbx` and run `AircraftAssembler.install("<Id>", ...)`. The fuselage now has the cockpit well. The UVs haven't changed, so the existing skins still apply.
2. Upload the four `<Id>_Cockpit_*.png` maps.
3. Import `<Id>_cockpit.fbx`, then run `AircraftAssembler.installCockpit("<Id>", workspace.<Id>_cockpit, { Color = …, Normal = …, Roughness = …, Metalness = … })`.
4. Play test in the cockpit view. Check that the gauges sit in their bezels, the radar scope sweeps, nothing pokes through the canopy, and the view over the nose is clear.

Optional: repaint and re-upload the skins to paint the inside of the well dark for other players. Without a repaint, other players see the old paint stretched down into the well through the canopy.
