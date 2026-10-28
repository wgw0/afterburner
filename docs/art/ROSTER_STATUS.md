# Roster art status

Where each jet on the roster (DESIGN §6.2) stands in the [art pipeline](AIRCRAFT_PIPELINE.md): its exterior model, skins and cockpit. Built files are in the art branch's worktree under `tools/blender/out/`, which is kept out of git. The **Studio** column lists what's left to do in Studio: import, upload textures, add skin entries, play test.

Jets without flight data in `src/shared/AircraftData/` get the art only, under the Id in this table. Their flight data is separate design work.

| Tier | Jet | Id | Flight data | Branch | Exterior | Skins | Cockpit | Studio |
|---|---|---|---|---|---|---|---|---|
| I | F-5E Tiger II | `F5E` | Yes | master; `art/cockpits` | Done; cockpit well added | Ghost, Desert, Pacific, Lizard (unchanged) | Done | Re-import the exterior; import and install the cockpit |
| I | MiG-21bis | `MiG21bis` | Yes | master; `art/cockpits` | Done; cockpit well added | Silver, Grey, Tactical (unchanged) | Done | Re-import the exterior; import and install the cockpit |
| I | Mirage IIIE | `MirageIII` | Yes | `art/mirage3` (on `art/cockpits`) | Done | Tactical (default), Silver, Desert, Grey | Done | Import, upload textures for 4 skins and the cockpit, play test |
| II | Mirage F1C | `MirageF1` | Yes | `art/miragef1` (on `art/mirage3`) | Done | Interceptor (default), Tactical, Desert, Grey | Done | Import, upload textures for 4 skins and the cockpit, play test |
| II | F-4E Phantom II | `F4E` | Yes | `art/f4e` (on `art/miragef1`) | Done | SEA (default), HillGray, EuroOne, Desert | Done | Import, upload textures for 4 skins and the cockpit, play test |
| II | MiG-23MLD | `MiG23MLD` | Yes | `art/mig23` (on `art/f4e`) | Done (wings at 45°) | Tactical (default), TwoTone, Grey, Desert | Done | Import, upload textures for 4 skins and the cockpit, play test |
| III | F-16A | `F16A` | Yes | `art/f16a` (on `art/mig23`) | Done | Falcon (default), Blue, Desert, Euro | Done | Import, upload textures for 4 skins and the cockpit, play test |
| III | MiG-29A | `MiG29A` | Yes | `art/mig29` (on `art/f16a`) | Done | Grey (default), Euro, BlueGrey, Desert | Done | Import, upload textures for 4 skins and the cockpit, play test |
| III | F-14A Tomcat | `F14A` | No | in `art/f15e` (its own branch was deleted after the rebase onto master) | Done (wings at 35°) | Navy (default), Gull, Ghost, Desert | Done | Import and upload when it gets flight data (the skin entries are already in Config.Skins) |
| III | Mirage 2000C | `Mirage2000C` | No | in `art/f15e` (its own branch was deleted after the rebase onto master) | Done | AirDefence (default), Grey, Tactical, Desert | Done | Import and upload when it gets flight data (the skin entries are already in Config.Skins) |
| IV | F-15C Eagle | `F15C` | No | in `art/f15e` (its own branch was deleted after the rebase onto master) | Done | ModEagle (default), Blue, Aggressor, Desert | Done | Import and upload when it gets flight data (the skin entries are already in Config.Skins) |
| IV | F/A-18C | `FA18C` | No | in `art/f15e` (its own branch was deleted after the rebase onto master) | Done | Navy (default), Gull, Adversary, Ghost | Done | Import and upload when it gets flight data (the skin entries are already in Config.Skins) |
| IV | Su-27S | `Su27S` | No | in `art/f15e` (its own branch was deleted after the rebase onto master) | Done | Flanker (default), Grey, Naval, Desert | Done | Import and upload when it gets flight data (the skin entries are already in Config.Skins) |
| IV | Tornado F3 | `TornadoF3` | No | in `art/f15e` (its own branch was deleted after the rebase onto master) | Done | AirDefence (default), DarkGrey, Splinter, Desert | Done | Import and upload when it gets flight data (the skin entries are already in Config.Skins) |
| V | F-16C Block 50 | `F16C` | No | `art/f16c` (on master, with the art-only jets before it) | Done | Viper (default), Ghost, Arctic, Night | Done | Import and upload when it gets flight data (the skin entries are already in Config.Skins) |
| V | F-15E | `F15E` | No | `art/f15e` (on `art/f16c`) | Done | Strike (default), Ghost, Splinter, Desert | Done | Import and upload when it gets flight data (the skin entries are already in Config.Skins) |
| V | Su-30SM | `Su30SM` | No | `art/su30sm` (on `art/f15e`) | Done | VKS (default), Blue, Naval, Desert | Done | Import and upload when it gets flight data (the skin entries are already in Config.Skins) |
| V | MiG-29SMT | `MiG29SMT` | No | `art/mig29smt` (on `art/su30sm`) | Done | VKS (default), Blue, Splinter, Desert | Done | Import and upload when it gets flight data (the skin entries are already in Config.Skins) |
| V | Gripen C | `GripenC` | No | `art/gripenc` (on `art/mig29smt`) | Done | Grey (default), DarkGrey, Splinter, Arctic | Done | Import and upload when it gets flight data (the skin entries are already in Config.Skins) |
| VI | F/A-18E Super Hornet | `FA18E` | No | `art/fa18e` (on `art/gripenc`) | Done | Navy (default), CAG, Adversary, Ghost | Done | Import and upload when it gets flight data (the skin entries are already in Config.Skins) |
| VI | Su-35S | `Su35S` | No | `art/su35s` (on `art/fa18e`) | Done | VKS (default), Dark, Flanker, Desert | Done | Import and upload when it gets flight data (the skin entries are already in Config.Skins) |
| VI | Eurofighter Typhoon | `Typhoon` | No | `art/typhoon` (on `art/su35s`) | Done | AirDefence (default), TwoTone, DarkGrey, Desert | Done | Import and upload when it gets flight data (the skin entries are already in Config.Skins) |
| VI | Rafale C | `RafaleC` | No | `art/rafalec` (on `art/typhoon`) | Done | AirDefence (default), TwoTone, DarkGrey, Desert | Done | Import and upload when it gets flight data (the skin entries are already in Config.Skins) |
| VII | F-22A Raptor | `F22A` | No | `art/f22a` (on `art/rafalec`) | Done | AirDominance (default), Dark, Ghost, Splinter | Done | Import and upload when it gets flight data (the skin entries are already in Config.Skins) |
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

## Mirage IIIE (`art/mirage3`)

Built on `art/cockpits`, so merge that branch first. This branch also adds the `ElevonL` and `ElevonR` controls to `Shared.ControlSurfaces`, with tests, and the four skin entries to `Shared.Config.Skins`.

Files in `tools/blender/out/`:
- Model: `MirageIII_base.fbx`, plus `MirageIII_manifest.json` and `tools/Manifests/MirageIII.luau`
- Skins: in `textures/`, `MirageIII_<Skin>_<Set>_<Map>.png` for the Tactical, Silver, Desert and Grey skins, 12 PNGs each
- Cockpit: `MirageIII_cockpit.fbx` and `MirageIII_Cockpit_{Color,Normal,Roughness,Metalness}.png`
- Previews: `MirageIII_{side,top,front,threequarter}.png`, `MirageIII_overlay_{side,top}.png`, `textures/MirageIII_<Skin>_paint_*.png` and `MirageIII_cockpit_*.png`

To do in Studio:
1. Import `MirageIII_base.fbx`, then run `AircraftAssembler.install("MirageIII", workspace.MirageIII_base)`. The assembler lines up a single-nozzle import on `Nozzle`.
2. Upload the skins and make `Assets.Skins.MirageIII.<Skin>` with a SurfaceAppearance per set (Body, Wings, Details).
3. Import and install the cockpit, as for the F-5E.
4. Play test. Check that the elevons move with the stick (both up for pitch, opposite for roll), that the rudder works, and the view from the cockpit.

## Mirage F1C (`art/miragef1`)

Built on `art/mirage3` (which is built on `art/cockpits`), so merge those first. This branch also adds the shared skin painter `jet_paint.py`. The Mirage IIIE's paint script now uses it, and its four skins were repainted with it in `tools/blender/out/textures`; the change is only in fine panel lines, but upload these PNGs rather than the earlier ones.

Files in `tools/blender/out/`:
- Model: `MirageF1_base.fbx`, plus `tools/Manifests/MirageF1.luau`
- Skins: `textures/MirageF1_<Skin>_<Set>_<Map>.png` for the Interceptor, Tactical, Desert and Grey skins
- Cockpit: `MirageF1_cockpit.fbx` and `MirageF1_Cockpit_{Color,Normal,Roughness,Metalness}.png`
- Previews: `MirageF1_{side,top,front,threequarter}.png`, `MirageF1_overlay_{side,top}.png`, `textures/MirageF1_<Skin>_paint_*.png` and `MirageF1_cockpit_*.png`

To do in Studio: import, `install("MirageF1", workspace.MirageF1_base)`, make the skin SurfaceAppearances, install the cockpit, then play test. The F1C uses the existing aileron, flap, leading-edge flap, stabilator and rudder controls.

## F-4E Phantom II (`art/f4e`)

Built on `art/miragef1`, so merge the earlier art branches first.

Files in `tools/blender/out/`:
- Model: `F4E_base.fbx`, plus `tools/Manifests/F4E.luau`
- Skins: `textures/F4E_<Skin>_<Set>_<Map>.png` for the SEA, HillGray, EuroOne and Desert skins
- Cockpit: `F4E_cockpit.fbx` and `F4E_Cockpit_{Color,Normal,Roughness,Metalness}.png`
- Previews: `F4E_{side,top,front,threequarter}.png`, `F4E_overlay_{side,top}.png`, `textures/F4E_<Skin>_paint_*.png` and `F4E_cockpit_*.png`

To do in Studio: import the model, run `install("F4E", workspace.F4E_base)` (the assembler lines up twin nozzles on `NozzleL` and `NozzleR`), make the skin SurfaceAppearances, install the cockpit, then play test. The outer wing panels and outer leading-edge flaps are separate parts: `WingOuterL`, `WingOuterR`, `LEFlapOuterL` and `LEFlapOuterR`.

## MiG-23MLD (`art/mig23`)

Built on `art/f4e`, so merge the earlier art branches first.

Files in `tools/blender/out/`:
- Model: `MiG23MLD_base.fbx`, plus `tools/Manifests/MiG23MLD.luau`
- Skins: `textures/MiG23MLD_<Skin>_<Set>_<Map>.png` for the Tactical, TwoTone, Grey and Desert skins
- Cockpit: `MiG23MLD_cockpit.fbx` and `MiG23MLD_Cockpit_{Color,Normal,Roughness,Metalness}.png`
- Previews: `MiG23MLD_{side,top,front,threequarter}.png`, `MiG23MLD_overlay_{side,top}.png` (with the wings spread, to compare with the drawing), `textures/MiG23MLD_<Skin>_paint_*.png` and `MiG23MLD_cockpit_*.png`

To do in Studio: import the model, run `install("MiG23MLD", workspace.MiG23MLD_base)`, make the skin SurfaceAppearances, install the cockpit, then play test. The tailerons use the elevon controls, so check that they move together for pitch and in opposite directions for roll.

## F-16A (`art/f16a`)

Built on `art/mig23`, so merge the earlier art branches first.

Files in `tools/blender/out/`:
- Model: `F16A_base.fbx`, plus `tools/Manifests/F16A.luau`
- Skins: `textures/F16A_<Skin>_<Set>_<Map>.png` for the Falcon, Blue, Desert and Euro skins
- Cockpit: `F16A_cockpit.fbx` and `F16A_Cockpit_{Color,Normal,Roughness,Metalness}.png`
- Previews: `F16A_{side,top,front,threequarter}.png`, `F16A_overlay_{side,top}.png`, `textures/F16A_<Skin>_paint_*.png` and `F16A_cockpit_*.png`

To do in Studio: import the model, run `install("F16A", workspace.F16A_base)`, make the skin SurfaceAppearances, install the cockpit, then play test. The tailerons use the elevon controls.

## MiG-29A (`art/mig29`)

Built on `art/f16a`, so merge the earlier art branches first.

Files in `tools/blender/out/`:
- Model: `MiG29A_base.fbx`, plus `tools/Manifests/MiG29A.luau`
- Skins: `textures/MiG29A_<Skin>_<Set>_<Map>.png` for the Grey, Euro, BlueGrey and Desert skins
- Cockpit: `MiG29A_cockpit.fbx` and `MiG29A_Cockpit_{Color,Normal,Roughness,Metalness}.png`
- Previews: `MiG29A_{side,top,front,threequarter}.png`, `MiG29A_overlay_{side,top}.png`, `textures/MiG29A_<Skin>_paint_*.png` and `MiG29A_cockpit_*.png`

To do in Studio: import the model, run `install("MiG29A", workspace.MiG29A_base)` (twin nozzles, `NozzleL` and `NozzleR`), make the skin SurfaceAppearances, install the cockpit, then play test. Both rudders are on the `Rudder` control, and the stabilators are on the elevon controls.

## F-14A Tomcat (`art/f14a`, art only)

Built on `art/mig29`. This branch also repaints the MiG-29A's Grey skin: its intake mouths were white, and are now dark ducts. Re-upload the 4 `MiG29A_Grey_Body_*.png` maps (only the Color map changed).

Files in `tools/blender/out/`:
- Model: `F14A_base.fbx`, plus `tools/Manifests/F14A.luau`
- Skins: `textures/F14A_<Skin>_<Set>_<Map>.png` for the Navy, Gull, Ghost and Desert skins
- Cockpit: `F14A_cockpit.fbx` and `F14A_Cockpit_{Color,Normal,Roughness,Metalness}.png`
- Previews: `F14A_{side,top,front,threequarter}.png`, `F14A_overlay_{side,top}.png`, `textures/F14A_<Skin>_paint_*.png` and `F14A_cockpit_*.png`

To do in Studio, when the F-14A gets flight data (an `AircraftData/F14A.luau` with `ModelName = "F14A"`): import the model, run `install("F14A", workspace.F14A_base)`, make the skin SurfaceAppearances, install the cockpit, then play test.

## Mirage 2000C (`art/mirage2000`, art only)

Built on `art/f14a`. Files in `tools/blender/out/`: `Mirage2000C_base.fbx` (manifest `tools/Manifests/Mirage2000C.luau`), `textures/Mirage2000C_<Skin>_<Set>_<Map>.png` for the AirDefence, Grey, Tactical and Desert skins, `Mirage2000C_cockpit.fbx` and `Mirage2000C_Cockpit_{Color,Normal,Roughness,Metalness}.png`, and previews (`Mirage2000C_{side,top,front,threequarter,overlay_side,overlay_top}.png`, `textures/Mirage2000C_<Skin>_paint_*.png` and `Mirage2000C_cockpit_*.png`). Install it like the other jets once `AircraftData/Mirage2000C.luau` exists, with `ModelName = "Mirage2000C"`.

## F-15C Eagle (`art/f15c`, art only)

Built on `art/mirage2000`. Files in `tools/blender/out/`: `F15C_base.fbx` (manifest `tools/Manifests/F15C.luau`), `textures/F15C_<Skin>_<Set>_<Map>.png` for the ModEagle, Blue, Aggressor and Desert skins, `F15C_cockpit.fbx` and `F15C_Cockpit_{Color,Normal,Roughness,Metalness}.png`, and previews (`F15C_{side,top,front,threequarter,overlay_side,overlay_top}.png`, `textures/F15C_<Skin>_paint_*.png` and `F15C_cockpit_*.png`). Install it like the other jets once `AircraftData/F15C.luau` exists, with `ModelName = "F15C"`.

## F/A-18C Hornet (`art/fa18c`, art only)

Built on `art/f15c`. Files in `tools/blender/out/`: `FA18C_base.fbx` (manifest `tools/Manifests/FA18C.luau`), `textures/FA18C_<Skin>_<Set>_<Map>.png` for the Navy, Gull, Adversary and Ghost skins, `FA18C_cockpit.fbx` and `FA18C_Cockpit_{Color,Normal,Roughness,Metalness}.png`, and previews (`FA18C_{side,top,front,threequarter,overlay_side,overlay_top}.png`, `textures/FA18C_<Skin>_paint_*.png` and `FA18C_cockpit_*.png`). Install it like the other jets once `AircraftData/FA18C.luau` exists, with `ModelName = "FA18C"`.

## Su-27S Flanker (`art/su27s`, art only)

Built on `art/fa18c`. Files in `tools/blender/out/`: `Su27S_base.fbx` (manifest `tools/Manifests/Su27S.luau`), `textures/Su27S_<Skin>_<Set>_<Map>.png` for the Flanker, Grey, Naval and Desert skins, `Su27S_cockpit.fbx` and `Su27S_Cockpit_{Color,Normal,Roughness,Metalness}.png`, and previews (`Su27S_{side,top,front,threequarter,overlay_side,overlay_top}.png`, `textures/Su27S_<Skin>_paint_*.png` and `Su27S_cockpit_*.png`). Install it like the other jets once `AircraftData/Su27S.luau` exists, with `ModelName = "Su27S"`.

## Tornado F3 (`art/tornadof3`, art only)

Built on `art/su27s`. Files in `tools/blender/out/`: `TornadoF3_base.fbx` (manifest `tools/Manifests/TornadoF3.luau`), `textures/TornadoF3_<Skin>_<Set>_<Map>.png` for the AirDefence, DarkGrey, Splinter and Desert skins, `TornadoF3_cockpit.fbx` and `TornadoF3_Cockpit_{Color,Normal,Roughness,Metalness}.png`, and previews (`TornadoF3_{side,top,front,threequarter,overlay_side,overlay_top}.png`, `textures/TornadoF3_<Skin>_paint_*.png` and `TornadoF3_cockpit_*.png`). Install it like the other jets once `AircraftData/TornadoF3.luau` exists, with `ModelName = "TornadoF3"`.

## F-16C Block 50 (`art/f16c`, art only)

Built on `art/tornadof3`. Files in `tools/blender/out/`: `F16C_base.fbx` (manifest `tools/Manifests/F16C.luau`), `textures/F16C_<Skin>_<Set>_<Map>.png` for the Viper, Ghost, Arctic and Night skins, `F16C_cockpit.fbx` and `F16C_Cockpit_{Color,Normal,Roughness,Metalness}.png`, and previews (`F16C_{side,top,front,threequarter,overlay_side,overlay_top}.png`, `textures/F16C_<Skin>_paint_*.png` and `F16C_cockpit_*.png`). Install it like the other jets once `AircraftData/F16C.luau` exists, with `ModelName = "F16C"`.

## F-15E Strike Eagle (`art/f15e`, art only)

Built on `art/f16c`. Files in `tools/blender/out/`: `F15E_base.fbx` (manifest `tools/Manifests/F15E.luau`), `textures/F15E_<Skin>_<Set>_<Map>.png` for the Strike, Ghost, Splinter and Desert skins, `F15E_cockpit.fbx` and `F15E_Cockpit_{Color,Normal,Roughness,Metalness}.png`, and previews (`F15E_{side,top,front,threequarter,overlay_side,overlay_top}.png`, `textures/F15E_<Skin>_paint_*.png` and `F15E_cockpit_*.png`). Install it like the other jets once `AircraftData/F15E.luau` exists, with `ModelName = "F15E"`.

## Su-30SM (`art/su30sm`, art only)

Built on `art/f15e`. Files in `tools/blender/out/`: `Su30SM_base.fbx` (manifest `tools/Manifests/Su30SM.luau`), `textures/Su30SM_<Skin>_<Set>_<Map>.png` for the VKS, Blue, Naval and Desert skins, `Su30SM_cockpit.fbx` and `Su30SM_Cockpit_{Color,Normal,Roughness,Metalness}.png`, and previews (`Su30SM_{side,top,front,threequarter,overlay_side,overlay_top}.png`, `textures/Su30SM_<Skin>_paint_*.png` and `Su30SM_cockpit_*.png`). Install it like the other jets once `AircraftData/Su30SM.luau` exists, with `ModelName = "Su30SM"`.

## MiG-29SMT (`art/mig29smt`, art only)

Built on `art/su30sm`. Files in `tools/blender/out/`: `MiG29SMT_base.fbx` (manifest `tools/Manifests/MiG29SMT.luau`), `textures/MiG29SMT_<Skin>_<Set>_<Map>.png` for the VKS, Blue, Splinter and Desert skins, `MiG29SMT_cockpit.fbx` and `MiG29SMT_Cockpit_{Color,Normal,Roughness,Metalness}.png`, and previews (`MiG29SMT_{side,top,front,threequarter,overlay_side,overlay_top}.png`, `textures/MiG29SMT_<Skin>_paint_*.png` and `MiG29SMT_cockpit_*.png`). Install it like the other jets once `AircraftData/MiG29SMT.luau` exists, with `ModelName = "MiG29SMT"`.

## Gripen C (`art/gripenc`, art only)

Built on `art/mig29smt`. Files in `tools/blender/out/`: `GripenC_base.fbx` (manifest `tools/Manifests/GripenC.luau`), `textures/GripenC_<Skin>_<Set>_<Map>.png` for the Grey, DarkGrey, Splinter and Arctic skins, `GripenC_cockpit.fbx` and `GripenC_Cockpit_{Color,Normal,Roughness,Metalness}.png`, and previews (`GripenC_{side,top,front,threequarter,overlay_side,overlay_top}.png`, `textures/GripenC_<Skin>_paint_*.png` and `GripenC_cockpit_*.png`). Install it like the other jets once `AircraftData/GripenC.luau` exists, with `ModelName = "GripenC"`.

## F/A-18E Super Hornet (`art/fa18e`, art only)

Built on `art/gripenc`. Files in `tools/blender/out/`: `FA18E_base.fbx` (manifest `tools/Manifests/FA18E.luau`), `textures/FA18E_<Skin>_<Set>_<Map>.png` for the Navy, CAG, Adversary and Ghost skins, `FA18E_cockpit.fbx` and `FA18E_Cockpit_{Color,Normal,Roughness,Metalness}.png`, and previews (`FA18E_{side,top,front,threequarter,overlay_side,overlay_top}.png`, `textures/FA18E_<Skin>_paint_*.png` and `FA18E_cockpit_*.png`). Install it like the other jets once `AircraftData/FA18E.luau` exists, with `ModelName = "FA18E"`.

## Su-35S (`art/su35s`, art only)

Built on `art/fa18e`. Files in `tools/blender/out/`: `Su35S_base.fbx` (manifest `tools/Manifests/Su35S.luau`), `textures/Su35S_<Skin>_<Set>_<Map>.png` for the VKS, Dark, Flanker and Desert skins, `Su35S_cockpit.fbx` and `Su35S_Cockpit_{Color,Normal,Roughness,Metalness}.png`, and previews (`Su35S_{side,top,front,threequarter,overlay_side,overlay_top}.png`, `textures/Su35S_<Skin>_paint_*.png` and `Su35S_cockpit_*.png`). Install it like the other jets once `AircraftData/Su35S.luau` exists, with `ModelName = "Su35S"`.

## Eurofighter Typhoon (`art/typhoon`, art only)

Built on `art/su35s`. Files in `tools/blender/out/`: `Typhoon_base.fbx` (manifest `tools/Manifests/Typhoon.luau`), `textures/Typhoon_<Skin>_<Set>_<Map>.png` for the AirDefence, TwoTone, DarkGrey and Desert skins, `Typhoon_cockpit.fbx` and `Typhoon_Cockpit_{Color,Normal,Roughness,Metalness}.png`, and previews (`Typhoon_{side,top,front,threequarter,overlay_side,overlay_top}.png`, `textures/Typhoon_<Skin>_paint_*.png` and `Typhoon_cockpit_*.png`). Install it like the other jets once `AircraftData/Typhoon.luau` exists, with `ModelName = "Typhoon"`.

## Rafale C (`art/rafalec`, art only)

Built on `art/typhoon`. Files in `tools/blender/out/`: `RafaleC_base.fbx` (manifest `tools/Manifests/RafaleC.luau`), `textures/RafaleC_<Skin>_<Set>_<Map>.png` for the AirDefence, TwoTone, DarkGrey and Desert skins, `RafaleC_cockpit.fbx` and `RafaleC_Cockpit_{Color,Normal,Roughness,Metalness}.png`, and previews (`RafaleC_{side,top,front,threequarter,overlay_side,overlay_top}.png`, `textures/RafaleC_<Skin>_paint_*.png` and `RafaleC_cockpit_*.png`). Install it like the other jets once `AircraftData/RafaleC.luau` exists, with `ModelName = "RafaleC"`.

## F-22A Raptor (`art/f22a`, art only)

Built on `art/rafalec`. Files in `tools/blender/out/`: `F22A_base.fbx` (manifest `tools/Manifests/F22A.luau`), `textures/F22A_<Skin>_<Set>_<Map>.png` for the AirDominance, Dark, Ghost and Splinter skins, `F22A_cockpit.fbx` and `F22A_Cockpit_{Color,Normal,Roughness,Metalness}.png`, and previews (`F22A_{side,top,front,threequarter,overlay_side,overlay_top}.png`, `textures/F22A_<Skin>_paint_*.png` and `F22A_cockpit_*.png`). Install it like the other jets once `AircraftData/F22A.luau` exists, with `ModelName = "F22A"`.
